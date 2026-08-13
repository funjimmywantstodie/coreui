--!strict
-- util/Config.lua — executor filesystem layer for saving / loading configs.
--
-- Exploit executors expose global file functions (writefile / readfile / …) that
-- don't exist in Studio or live game clients. Everything here is feature-detected
-- and pcall-guarded so the library degrades gracefully (Config.supported = false)
-- instead of erroring where those globals are absent.
--
-- Layout on disk:  <folder>/configs/<name>.json   (one JSON blob per config)
--                  <folder>/autoload.txt          (name of the config to auto-load)

local HttpService = game:GetService("HttpService")

local Config = {}

-- Resolve executor file globals. Executors put these on the SHARED global env
-- (getgenv) — not the chunk env — so prefer that, then fall back to the ambient
-- global / _G. Everything is pcall-guarded: some sandboxes throw merely on
-- touching getgenv/getfenv, and a raw error here would kill the whole library at
-- require time (this module is required by Window).
local genv: any = nil
pcall(function()
	if type(getgenv) == "function" then
		genv = getgenv()
	end
end)

local function g(name: string): any
	-- 1) shared global env (getgenv)
	if type(genv) == "table" then
		local ok, v = pcall(function()
			return genv[name]
		end)
		if ok and v ~= nil then
			return v
		end
	end
	-- 2) ambient global identifier (works when funcs are plain globals)
	local ok2, v2 = pcall(function()
		return (_G :: any)[name]
	end)
	if ok2 and v2 ~= nil then
		return v2
	end
	return nil
end

local g_writefile = g("writefile")
local g_readfile = g("readfile")
local g_isfile = g("isfile")
local g_delfile = g("delfile")
local g_isfolder = g("isfolder")
local g_makefolder = g("makefolder")
local g_listfiles = g("listfiles")

Config.supported = type(g_writefile) == "function"
	and type(g_readfile) == "function"
	and type(g_isfile) == "function"

-- Surface what was detected so executor file-API gaps are obvious in the console.
print(("[Krypton] config: supported=%s  writefile=%s readfile=%s isfile=%s listfiles=%s delfile=%s")
	:format(
		tostring(Config.supported),
		type(g_writefile), type(g_readfile), type(g_isfile),
		type(g_listfiles), type(g_delfile)
	))

-- Strip path separators so a config name can't escape its folder. Wrapped in
-- parens: gsub returns (string, count), and letting that second value escape made
-- `sanitize(name)` in an argument list expand to two arguments.
local function sanitize(name: string): string
	local cleaned = (tostring(name):gsub("[^%w%-_ ]", ""))
	return (cleaned:gsub("^%s*(.-)%s*$", "%1"))
end

local function configsDir(folder: string): string
	return folder .. "/configs"
end

local function pathFor(folder: string, name: string): string
	return configsDir(folder) .. "/" .. sanitize(name) .. ".json"
end

local function ensureFolders(folder: string)
	if type(g_isfolder) ~= "function" or type(g_makefolder) ~= "function" then
		return
	end
	pcall(function()
		if not g_isfolder(folder) then
			g_makefolder(folder)
		end
		local cfg = configsDir(folder)
		if not g_isfolder(cfg) then
			g_makefolder(cfg)
		end
	end)
end

-- List saved config names (no path, no extension), sorted.
function Config.list(folder: string): { string }
	local names = {}
	if not Config.supported or type(g_listfiles) ~= "function" then
		return names
	end
	ensureFolders(folder)
	local ok, files = pcall(g_listfiles, configsDir(folder))
	if ok and type(files) == "table" then
		for _, path in files do
			local name = tostring(path):match("([^/\\]+)%.json$")
			if name then
				table.insert(names, name)
			end
		end
	end
	table.sort(names)
	return names
end

-- Serialize `data` to JSON and write it. Returns true on success.
function Config.save(folder: string, name: string, data: any): boolean
	if not Config.supported then
		return false
	end
	name = sanitize(name)
	if name == "" then
		return false
	end
	ensureFolders(folder)
	local ok, json = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	if not ok then
		return false
	end
	return (pcall(g_writefile, pathFor(folder, name), json))
end

-- Read + decode a config. Returns the table, or nil if missing / corrupt.
function Config.load(folder: string, name: string): any?
	if not Config.supported then
		return nil
	end
	local path = pathFor(folder, name)
	local okExists, exists = pcall(g_isfile, path)
	if not okExists or not exists then
		return nil
	end
	local okRead, raw = pcall(g_readfile, path)
	if not okRead then
		return nil
	end
	local okDecode, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not okDecode then
		return nil
	end
	return data
end

function Config.delete(folder: string, name: string): boolean
	if not Config.supported or type(g_delfile) ~= "function" then
		return false
	end
	local path = pathFor(folder, name)
	local okExists, exists = pcall(g_isfile, path)
	if not okExists or not exists then
		return false
	end
	return (pcall(g_delfile, path))
end

-- Auto-load pointer: which config (if any) to apply on launch.
function Config.setAutoload(folder: string, name: string?)
	if not Config.supported then
		return
	end
	ensureFolders(folder)
	local path = folder .. "/autoload.txt"
	if name and sanitize(name) ~= "" then
		pcall(g_writefile, path, sanitize(name))
	elseif type(g_delfile) == "function" then
		local okExists, exists = pcall(g_isfile, path)
		if okExists and exists then
			pcall(g_delfile, path)
		end
	end
end

function Config.getAutoload(folder: string): string?
	if not Config.supported then
		return nil
	end
	local path = folder .. "/autoload.txt"
	local okExists, exists = pcall(g_isfile, path)
	if not okExists or not exists then
		return nil
	end
	local okRead, raw = pcall(g_readfile, path)
	if okRead and type(raw) == "string" and raw ~= "" then
		-- Trim: a stray newline from an editor (or another tool writing the file)
		-- would never match a name in the saved-config dropdown.
		local name = sanitize(raw)
		return name ~= "" and name or nil
	end
	return nil
end

return Config
