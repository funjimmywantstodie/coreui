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
--   Asset.resolve("uranium/logo.png")                -- local file (getcustomasset)
--   Asset.resolve("https://example.com/logo.png")    -- downloaded, cached, loaded
--   Asset.headshot(userId)                           -- avatar thumbnail
--
-- Local files and URL downloads need executor globals (`getcustomasset`,
-- `writefile`, …). They're feature-detected and pcall-guarded exactly like
-- util/Config.lua, so in Studio (or an executor missing them) the call returns
-- "" and the caller shows its placeholder instead of erroring.

local Services = require(script.Parent.Services)

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
Asset.CacheFolder = "uranium/images"

-- Base URL for art hosted in the public asset repo. init.lua points this at
-- `Theme.Brand.assets`; `Asset.url("logo.png")` then builds the full URL, so
-- adding a new image is "commit the file, reference it by name".
Asset.Base = ""

function Asset.url(name: string): string
	if type(name) ~= "string" or name == "" then
		return ""
	end
	if name:match("^https?://") then
		return name -- already absolute — pass it through untouched
	end
	return Asset.Base .. name
end

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
		-- Walk the path so a nested default like "uranium/images" creates both
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

-- Magic bytes for the formats Roblox will actually render, so a downloaded body
-- can be checked before it's committed to the disk cache.
local function looksLikeImage(body: string): boolean
	local head = body:sub(1, 12)
	return head:sub(1, 8) == "\137PNG\r\n\26\n"       -- png
		or head:sub(1, 2) == "\255\216"                -- jpeg
		or head:sub(1, 6) == "GIF89a" or head:sub(1, 6) == "GIF87a"
		or (head:sub(1, 4) == "RIFF" and head:sub(9, 12) == "WEBP")
		or head:sub(1, 2) == "BM"                      -- bmp
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
	-- Refuse to cache a body that isn't actually an image. A 404 page or a rate
	-- limit notice would otherwise be written to <name>.png and cached on disk
	-- forever, so one bad fetch would permanently break that image.
	if not looksLikeImage(body) then
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

-- The body of Asset.resolve (below), plus the chain-depth counter.
--
-- The counter lives here rather than as a second parameter of `Asset.resolve`
-- itself, because that one is public (`Uranium.Asset.resolve`) and an optional
-- trailing argument is exactly what a caller feeds an array index to by
-- accident: `for i, v in list do Asset.resolve(v, i) end` would silently start
-- at depth i and refuse a chain. Nothing outside this file can reach it.
local resolveValue: (any, number) -> string

resolveValue = function(value: any, depth: number): string
	if value == nil then
		return ""
	end

	if type(value) == "table" then
		-- A chain of chains is legal (a caller composing `{ Theme.Brand.logo, myId }`
		-- nests one without thinking about it), so the recursion is real — but a
		-- table that contains itself would spin here forever, and this runs on the
		-- render path for every image in the UI. Four levels is far past any honest
		-- fallback chain.
		if depth >= 4 then
			return ""
		end
		for _, candidate in value do
			local resolved = resolveValue(candidate, depth + 1)
			if resolved ~= "" then
				return resolved
			end
		end
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

-- The one every component calls. Accepts an id, a content url, a file path, an
-- http(s) url, or nil. Always returns a string — "" means "nothing to show", so
-- callers can assign it straight to `Image` and fall back on their placeholder.
--
-- It also accepts an ARRAY of any of those: a fallback chain, tried in order,
-- first one that resolves wins. That's how you survive Roblox's asset rules —
-- put a `https://…/logo.png` first (downloaded to disk, loaded via
-- getcustomasset, so moderation / Asset Privacy / decal-vs-image ids never
-- apply) and a plain asset id after it for executors with no file access.
--
-- One argument, exactly as before.
function Asset.resolve(value: any): string
	return resolveValue(value, 0)
end

-- ── Actually loading it ──────────────────────────────────────────────────────
-- `resolve` only proves the *shape* of a source is usable — it can't know the
-- asset renders. So `Asset.load` sets the image and reports back whether it
-- really arrived, letting callers keep a placeholder up.
--
-- Two hard rules here, both learned the painful way:
--
--   1. **Never use ContentProvider:PreloadAsync to decide.** It doesn't work on
--      ImageLabels (a documented engine limitation) and fails constantly on
--      content strings, so it reports Failure for images that render fine.
--      `ImageLabel.IsLoaded` is the only signal that tells the truth.
--   2. **Never clear or hide the image based on that check.** Detection is
--      advisory. The image is assigned immediately and stays assigned; a
--      negative result only means "keep the placeholder", never "erase the art".
--      Anything else risks blanking a picture that was about to appear.
--
-- The engine also only fetches textures for instances it's *rendering*, so an
-- unparented or hidden ImageLabel never loads at all. Callers must keep the
-- image visible while it loads — which the no-hiding rule above already gives.

local LOAD_TIMEOUT = 8

-- `alive` lets a superseded load give up mid-wait instead of holding the label
-- hostage for the rest of its timeout (see `generation` below).
local function whenLoaded(image: ImageLabel, timeout: number?, alive: (() -> boolean)?): boolean
	if image.IsLoaded then
		return true
	end
	local deadline = os.clock() + (timeout or LOAD_TIMEOUT)
	while not image.IsLoaded and os.clock() < deadline do
		if alive and not alive() then
			return false
		end
		task.wait(0.15)
	end
	return image.IsLoaded
end

-- Put `content` on the image and wait for it. Also tries the decal→image id
-- shuffle: a Decal asset and the Image it wraps live at adjacent ids, and the
-- decals that don't render directly need the underlying image (decalId - 1).
local function tryContent(image: ImageLabel, content: string, timeout: number, alive: (() -> boolean)?): boolean
	if alive and not alive() then
		return false
	end
	image.Image = content
	if whenLoaded(image, timeout, alive) then
		return true
	end
	local id = tonumber(content:match("rbxassetid://(%d+)$"))
	if id and id > 1 then
		if alive and not alive() then
			return false
		end
		image.Image = "rbxassetid://" .. tostring(id - 1)
		if whenLoaded(image, timeout, alive) then
			return true
		end
	end
	return false
end

-- Which load is the live one for a given ImageLabel. A walk can sit in
-- `whenLoaded` for 8s per candidate (plus a download), so two calls on the same
-- label overlap freely — and the loser used to keep writing: it painted its own
-- content over the winner's and then called `onDone(false)`, putting the
-- placeholder back on top of art that had already arrived. That's `Window:SetLogo`
-- during the default logo's chain, or `Image:Set` twice in a row. Weak keys so a
-- destroyed label doesn't pin an entry here.
local generation: { [ImageLabel]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Point `image` at `source`; `onDone(loaded)` reports whether it rendered.
-- `source` may be a single value or a fallback chain (see Asset.resolve) — each
-- candidate gets a short window, the last gets the full timeout.
--
-- `onDone` can fire twice — false on timeout, then true if the asset shows up
-- late — so keep it idempotent (toggling a placeholder is the ideal shape).
function Asset.load(image: ImageLabel, source: any, onDone: ((boolean) -> ())?)
	local chain: { any } = (type(source) == "table") and source or { source }
	local token = (generation[image] or 0) + 1
	generation[image] = token
	local function current(): boolean
		return generation[image] == token
	end

	task.spawn(function()
		local firstContent = ""
		for i, candidate in chain do
			-- Resolving can download (an https candidate is fetched to disk on
			-- first use), which is why the whole walk lives on this thread.
			local content = Asset.resolve(candidate)
			if not current() then
				return -- a newer load owns this label now
			end
			if content ~= "" then
				if firstContent == "" then
					firstContent = content
				end
				-- Don't spend the full budget on early candidates — there's
				-- another source waiting behind them.
				local budget = (i < #chain) and 3 or LOAD_TIMEOUT
				if tryContent(image, content, budget, current) then
					if onDone then
						onDone(true)
					end
					return
				end
			end
		end

		if not current() then
			return
		end
		-- Nothing loaded. Leave the best candidate assigned rather than blanking
		-- it, so a slow asset can still paint itself in later.
		image.Image = firstContent
		if onDone then
			onDone(false)
			if firstContent ~= "" then
				image:GetPropertyChangedSignal("IsLoaded"):Once(function()
					if image.IsLoaded and current() then
						onDone(true)
					end
				end)
			end
		end
	end)
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
			Services.ContentProvider:PreloadAsync(contents)
		end)
		for _, holder in contents do
			holder:Destroy()
		end
	end)
end

return Asset
