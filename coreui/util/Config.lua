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

local Services = require(script.Parent.Services)

local HttpService = Services.HttpService

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

-- What was detected, so executor file-API gaps are diagnosable. Built as a
-- string rather than printed: this module is required at load time, long before
-- `CreateWindow{ Verbose = ... }` can be read, and an unconditional branded line
-- on every load is a free fingerprint for a game scraping LogService. Window
-- logs it through `Log.info` once it knows whether the host wants output.
Config.report = ("config: supported=%s  writefile=%s readfile=%s isfile=%s listfiles=%s delfile=%s")
	:format(
		tostring(Config.supported),
		type(g_writefile), type(g_readfile), type(g_isfile),
		type(g_listfiles), type(g_delfile)
	)

-- The reserved key a config file carries its metadata under. It sits alongside
-- the flags in the same JSON object, and nothing registers a flag by that name,
-- so `Context:LoadConfig` skips it (see the note there — the skip is a promise,
-- not an accident). `Window:SaveConfig(name, meta)` writes it and
-- `Window:ConfigInfo(name)` reads it back without applying anything.
Config.MetaKey = "__uranium"

-- Strip path separators so a config name can't escape its folder. Wrapped in
-- parens: gsub returns (string, count), and letting that second value escape made
-- `sanitize(name)` in an argument list expand to two arguments.
--
-- Spelled out in ASCII rather than `%w` on purpose. `%w` is whatever the host
-- Lua's isalnum() says, which on some builds counts high bytes as alphanumeric —
-- there, half the bytes of a multi-byte glyph survive the strip and the name no
-- longer round-trips (save writes one filename, the list reads back another).
--
-- This is a CONTRACT, not an implementation detail: every name a caller shows in
-- a config list has to survive it unchanged, because the filename and the
-- autoload pointer are matched by string equality later. It's exported as
-- `Uranium.Config.sanitize` so a host can check a name it builds
-- (`Config.sanitize(n) == n`) instead of reverse-engineering the pattern.
local function sanitize(name: string): string
	local cleaned = (tostring(name):gsub("[^A-Za-z0-9%-_ ]", ""))
	return (cleaned:gsub("^%s*(.-)%s*$", "%1"))
end
Config.sanitize = sanitize

local function configsDir(folder: string): string
	return folder .. "/configs"
end

local function pathFor(folder: string, name: string): string
	return configsDir(folder) .. "/" .. sanitize(name) .. ".json"
end

-- Create `path` and every folder above it. ConfigFolder is documented as
-- free-form, so a host that scopes its configs ("uranium/games/12345" — one
-- folder per place) hands us a path several levels deep. This used to be two
-- flat makefolder calls, which is fine only on executors whose makefolder is
-- itself recursive; on the others the folder was never created and every save
-- silently failed.
local function makeFolders(path: string)
	local parts = {}
	for segment in tostring(path):gmatch("[^/\\]+") do
		table.insert(parts, segment)
	end
	local walked = ""
	for _, segment in parts do
		walked = walked == "" and segment or (walked .. "/" .. segment)
		if not g_isfolder(walked) then
			g_makefolder(walked)
		end
	end
end

local function ensureFolders(folder: string)
	if type(g_isfolder) ~= "function" or type(g_makefolder) ~= "function" then
		return
	end
	pcall(function()
		makeFolders(configsDir(folder)) -- walks `folder` on the way down
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

-- Every entry point below returns `(result, reason)`. The library already knew
-- which of "no file access" / "no such config" / "corrupt JSON" happened — it
-- just threw the answer away and handed back a bare `false`, which is the
-- difference between a useful toast and "Couldn't load". Reasons are short
-- lowercase phrases meant to be pasted straight into a message.

-- Serialize `data` to JSON and write it. Returns true on success.
function Config.save(folder: string, name: string, data: any): (boolean, string?)
	if not Config.supported then
		return false, "no file access"
	end
	name = sanitize(name)
	if name == "" then
		return false, "invalid name"
	end
	ensureFolders(folder)
	local ok, json = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	if not ok then
		return false, "couldn't encode"
	end
	local wrote = pcall(g_writefile, pathFor(folder, name), json)
	return wrote, wrote and nil or "write failed"
end

-- Read + decode a config. Returns the table, or nil + why not.
function Config.load(folder: string, name: string): (any?, string?)
	if not Config.supported then
		return nil, "no file access"
	end
	local path = pathFor(folder, name)
	local okExists, exists = pcall(g_isfile, path)
	if not okExists or not exists then
		return nil, "no such config"
	end
	local okRead, raw = pcall(g_readfile, path)
	if not okRead then
		return nil, "unreadable"
	end
	local okDecode, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not okDecode or type(data) ~= "table" then
		return nil, "corrupt JSON"
	end
	return data
end

-- The metadata a config was stamped with (Config.MetaKey), without touching a
-- single control. This is what "which game does this config belong to?" actually
-- wants to ask — decoding the whole file to read four fields, then discarding it,
-- is the shape every host would otherwise write.
function Config.info(folder: string, name: string): (any?, string?)
	local data, reason = Config.load(folder, name)
	if not data then
		return nil, reason
	end
	local meta = (data :: any)[Config.MetaKey]
	if type(meta) ~= "table" then
		return nil, "no metadata"
	end
	return meta
end

function Config.delete(folder: string, name: string): (boolean, string?)
	if not Config.supported then
		return false, "no file access"
	end
	if type(g_delfile) ~= "function" then
		return false, "executor can't delete files"
	end
	local path = pathFor(folder, name)
	local okExists, exists = pcall(g_isfile, path)
	if not okExists or not exists then
		return false, "no such config"
	end
	local removed = pcall(g_delfile, path)
	return removed, removed and nil or "delete failed"
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
		-- Trim ONLY. A stray newline from an editor (or another tool writing the
		-- file) would never match a name in the saved-config dropdown — but running
		-- the full sanitize on the way out was worse: the pointer is already written
		-- sanitized, so a second pass could only ever mangle a name that had round-
		-- tripped fine, and did exactly that wherever `%w` disagreed between the
		-- writing session and the reading one. Store verbatim, read verbatim.
		local name = (raw:gsub("^%s*(.-)%s*$", "%1"))
		return name ~= "" and name or nil
	end
	return nil
end

return Config
