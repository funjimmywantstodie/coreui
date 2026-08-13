--!strict
-- util/Asset.lua — turn "whatever the caller has" into something an ImageLabel
-- can actually render.
--
-- Roblox's `Image` property only accepts content URLs (`rbxassetid://…`,
-- `rbxthumb://…`, `rbxasset://…`). Everything else people naturally have — a
-- bare decal id copied off the creator dashboard, a PNG on disk, an https URL to
-- an image — has to be converted first. That conversion is the whole point of
-- this module, so a caller can write any of these and it just works:
--
--   Asset.resolve(91296376944710)                    -- number / numeric string
--   Asset.resolve("rbxassetid://91296376944710")     -- already a content url
--   Asset.resolve("krypton/logo.png")                -- local file (getcustomasset)
--   Asset.resolve("https://example.com/logo.png")    -- downloaded, cached, loaded
--   Asset.headshot(userId)                           -- avatar thumbnail
--
-- Local files and URL downloads need executor globals (`getcustomasset`,
-- `writefile`, …). They're feature-detected and pcall-guarded exactly like
-- util/Config.lua, so in Studio (or an executor missing them) the call returns
-- "" and the caller shows its placeholder instead of erroring.

local Asset = {}

-- Executor globals live on the SHARED env (getgenv), not the chunk env. Some
-- sandboxes throw merely on touching getgenv/_G, so every lookup is guarded —
-- this module is required at load time and a raw error would kill the library.
local genv: any = nil
pcall(function()
	if type(getgenv) == "function" then
		genv = getgenv()
	end
end)

local function g(name: string): any
	if type(genv) == "table" then
		local ok, v = pcall(function()
			return genv[name]
		end)
		if ok and v ~= nil then
			return v
		end
	end
	local ok2, v2 = pcall(function()
		return (_G :: any)[name]
	end)
	if ok2 and v2 ~= nil then
		return v2
	end
	return nil
end

local g_getcustomasset = g("getcustomasset") or g("getsynasset") or g("get_custom_asset")
local g_writefile = g("writefile")
local g_isfile = g("isfile")
local g_isfolder = g("isfolder")
local g_makefolder = g("makefolder")

-- Can we hand a *local file* to Roblox as an image? (asset ids always work)
Asset.supported = type(g_getcustomasset) == "function"
-- Can we additionally fetch a remote image and cache it on disk?
Asset.canDownload = Asset.supported and type(g_writefile) == "function"

-- Where downloaded images are cached. Set once at startup if you want them
-- somewhere other than the default (e.g. alongside your configs).
Asset.CacheFolder = "krypton/images"

local IMAGE_EXT = { png = true, jpg = true, jpeg = true, webp = true, tga = true, bmp = true }

local function extensionOf(path: string): string?
	local ext = tostring(path):match("%.([%a%d]+)$")
	return ext and IMAGE_EXT[ext:lower()] and ext:lower() or nil
end

local function ensureFolder()
	if type(g_isfolder) ~= "function" or type(g_makefolder) ~= "function" then
		return
	end
	pcall(function()
		-- Walk the path so a nested default like "krypton/images" creates both
		-- levels — makefolder doesn't do parents.
		local built = ""
		for segment in tostring(Asset.CacheFolder):gmatch("[^/\\]+") do
			built = built == "" and segment or (built .. "/" .. segment)
			if not g_isfolder(built) then
				g_makefolder(built)
			end
		end
	end)
end

-- getcustomasset for a path already on disk. Returns nil (never throws) when the
-- global is missing or the file isn't there.
function Asset.fromFile(path: string): string?
	if not Asset.supported or type(path) ~= "string" or path == "" then
		return nil
	end
	if type(g_isfile) == "function" then
		local okExists, exists = pcall(g_isfile, path)
		if okExists and not exists then
			return nil
		end
	end
	local ok, content = pcall(g_getcustomasset, path)
	if ok and type(content) == "string" and content ~= "" then
		return content
	end
	return nil
end

-- url → disk → content id. Cached twice: in memory for the session, and on disk
-- across sessions (a re-run reuses the file instead of re-downloading).
local urlCache: { [string]: string } = {}

function Asset.fromUrl(url: string, filename: string?): string?
	if type(url) ~= "string" or url == "" then
		return nil
	end
	local hit = urlCache[url]
	if hit then
		return hit
	end
	if not Asset.canDownload then
		return nil
	end

	-- Name the cache file after the url so repeat calls land on the same file.
	local name = filename
	if not name then
		local hash = 5381
		for i = 1, #url do
			hash = (hash * 33 + string.byte(url, i)) % 4294967296
		end
		name = ("%010d.%s"):format(hash, extensionOf(url) or "png")
	end
	local path = Asset.CacheFolder .. "/" .. name

	local cached = Asset.fromFile(path)
	if cached then
		urlCache[url] = cached
		return cached
	end

	ensureFolder()
	-- HttpGet hands back the body as a Lua string, which is binary-safe — so a
	-- PNG survives the round trip to writefile intact.
	local okGet, body = pcall(function()
		return game:HttpGet(url)
	end)
	if not okGet or type(body) ~= "string" or body == "" then
		return nil
	end
	if not (pcall(g_writefile, path, body)) then
		return nil
	end
	local content = Asset.fromFile(path)
	if content then
		urlCache[url] = content
	end
	return content
end

-- The one every component calls. Accepts an id, a content url, a file path, an
-- http(s) url, or nil. Always returns a string — "" means "nothing to show", so
-- callers can assign it straight to `Image` and fall back on their placeholder.
function Asset.resolve(value: any): string
	if value == nil then
		return ""
	end

	if type(value) == "number" then
		return "rbxassetid://" .. tostring(math.floor(value))
	end
	if type(value) ~= "string" or value == "" then
		return ""
	end

	-- already a content url
	if value:match("^rbxassetid://") or value:match("^rbxthumb://")
		or value:match("^rbxasset://") or value:match("^rbxgameasset://") then
		return value
	end
	-- bare id, with or without stray whitespace
	local digits = value:match("^%s*(%d+)%s*$")
	if digits then
		return "rbxassetid://" .. digits
	end
	-- a roblox catalog/library link — pull the id out of it
	local libraryId = value:match("roblox%.com/[^%s]-/(%d+)")
	if libraryId then
		return "rbxassetid://" .. libraryId
	end
	-- remote image → download + cache
	if value:match("^https?://") then
		return Asset.fromUrl(value) or ""
	end
	-- otherwise treat it as a path on disk
	return Asset.fromFile(value) or ""
end

-- Avatar thumbnails without an API round-trip. `kind` is "head" (default),
-- "bust" or "body"; rbxthumb only accepts a fixed set of sizes.
function Asset.headshot(userId: number, size: number?, kind: string?): string
	local kinds = {
		head = "AvatarHeadShot",
		bust = "AvatarBust",
		body = "Avatar",
	}
	local thumbType = kinds[kind or "head"] or "AvatarHeadShot"
	local px = size or 150
	-- snap to the sizes rbxthumb actually serves
	local allowed = { 48, 60, 75, 100, 150, 180, 352, 420 }
	local best = allowed[1]
	for _, candidate in allowed do
		if math.abs(candidate - px) < math.abs(best - px) then
			best = candidate
		end
	end
	return ("rbxthumb://type=%s&id=%d&w=%d&h=%d"):format(thumbType, math.floor(userId), best, best)
end

-- Pre-warm a set of images (ids, paths or urls) off the caller's thread, so the
-- first frame that shows them isn't the one that downloads them.
function Asset.preload(list: { any })
	task.spawn(function()
		local contents = {}
		for _, item in list do
			local resolved = Asset.resolve(item)
			if resolved ~= "" then
				local holder = Instance.new("ImageLabel")
				holder.Image = resolved
				table.insert(contents, holder)
			end
		end
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(contents)
		end)
		for _, holder in contents do
			holder:Destroy()
		end
	end)
end

return Asset
