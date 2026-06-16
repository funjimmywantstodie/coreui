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

-- Pull the globals through the environment so --!strict doesn't flag unknowns.
local env: any = getfenv and getfenv() or (_G :: any)
local g_writefile = env.writefile
local g_readfile = env.readfile
local g_isfile = env.isfile
local g_delfile = env.delfile
local g_isfolder = env.isfolder
local g_makefolder = env.makefolder
local g_listfiles = env.listfiles

Config.supported = type(g_writefile) == "function"
	and type(g_readfile) == "function"
	and type(g_isfile) == "function"

-- Strip path separators so a config name can't escape its folder.
local function sanitize(name: string): string
	return (tostring(name):gsub("[^%w%-_ ]", "")):gsub("^%s*(.-)%s*$", "%1")
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
		return raw
	end
	return nil
end

return Config
