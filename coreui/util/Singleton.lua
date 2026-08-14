--!strict
-- util/Singleton.lua — the "only one Uranium at a time" guard.
--
-- Every loadstring run is a brand new chunk with brand new module state, so the
-- ONLY place a previous run can leave a note for the next one is the shared
-- executor env (getgenv). We stash a small record there:
--
--   getgenv()._URANIUM_LOADED = { Name = "Uranium", Window = <handle>, Unload = fn }
--
-- Re-running the loader finds that record, unloads the old window, then builds a
-- fresh one — so the loadstring refreshes the UI in place instead of stacking a
-- second copy on top of the first. Consumers can also test the key themselves
-- (`if getgenv()._URANIUM_LOADED then ... end`) since a table is truthy.
--
-- Everything is feature-detected + pcall-guarded exactly like util/Config.lua:
-- Studio has no getgenv, and some sandboxes throw merely on touching it.

local Players = game:GetService("Players")

local Singleton = {}

Singleton.Key = "_URANIUM_LOADED"

-- Pre-rebrand slots. A build older than the Uranium rename is still a live
-- window on screen, but it parked its record (and named its ScreenGui) under the
-- old brand — so unloadExisting has to look there too, or re-running the loader
-- stacks a Uranium window on top of a Krypton one instead of replacing it.
Singleton.LegacyKeys = { "_KRYPTON_LOADED" }
Singleton.LegacyNames = { "Krypton" }

-- Shared env, with a fallback chain: getgenv() (executors) → _G (Studio and
-- anywhere getgenv is missing — same cross-run persistence, different table).
local env: any = nil
pcall(function()
	if type(getgenv) == "function" then
		env = getgenv()
	end
end)
if type(env) ~= "table" then
	pcall(function()
		env = _G
	end)
end

Singleton.supported = type(env) == "table"

-- The record left by whichever run is currently live, or nil.
function Singleton.get(): any
	if type(env) ~= "table" then
		return nil
	end
	local ok, v = pcall(function()
		return env[Singleton.Key]
	end)
	if ok and type(v) == "table" then
		return v
	end
	return nil
end

local function setKey(value: any)
	if type(env) ~= "table" then
		return
	end
	pcall(function()
		env[Singleton.Key] = value
	end)
end

-- Publish `record` as the live instance. Returns it so the caller can hold on to
-- it for the matching release().
function Singleton.claim(record: any): any
	setKey(record)
	return record
end

-- Clear the key, but only if it still points at OUR record — a window torn down
-- late (after a newer run already claimed the slot) must not evict the new one.
function Singleton.release(record: any)
	-- A nil record is a window that never claimed the slot (AllowMultiple), not a
	-- wildcard: letting it fall through to setKey(nil) had a secondary window's
	-- close wipe the *primary* window's record, after which IsLoaded read false and
	-- a loader re-run couldn't find the live window to unload it.
	if record == nil or Singleton.get() ~= record then
		return
	end
	setKey(nil)
end

-- Last-resort sweep: destroy any leftover ScreenGui with our name. Covers the
-- cases the record can't — the flag was cleared by hand, the previous chunk's
-- Unload closure errored, or an older build that predates this guard is still on
-- screen. Destroying the ScreenGui is always safe; a live window that survives
-- this would be an orphan nobody can see anyway.
local function sweep(guiName: string): number
	local removed = 0
	local roots: { Instance } = {}
	local lp = Players.LocalPlayer
	if lp then
		local pg = lp:FindFirstChildOfClass("PlayerGui")
		if pg then
			table.insert(roots, pg)
		end
	end
	pcall(function()
		table.insert(roots, game:GetService("CoreGui"))
	end)
	for _, root in roots do
		pcall(function()
			for _, child in root:GetChildren() do
				if child:IsA("ScreenGui") and child.Name == guiName then
					child:Destroy()
					removed += 1
				end
			end
		end)
	end
	return removed
end

-- Tear down whatever Uranium is already on screen. Returns true if something was
-- actually unloaded, so the caller can log a refresh instead of a fresh load.
function Singleton.unloadExisting(guiName: string): boolean
	local record = Singleton.get()
	local unloaded = false
	if record then
		if type(record.Unload) == "function" then
			-- pcall: the old chunk may be half-dead (executor unloaded, error
			-- mid-teardown). Either way we still clear the key + sweep below.
			pcall(record.Unload)
		end
		setKey(nil)
		unloaded = true
	end
	-- Same treatment for anything a pre-rebrand build left behind.
	if type(env) == "table" then
		for _, key in Singleton.LegacyKeys do
			local ok, old = pcall(function()
				return env[key]
			end)
			if ok and type(old) == "table" then
				if type(old.Unload) == "function" then
					pcall(old.Unload)
				end
				pcall(function()
					env[key] = nil
				end)
				unloaded = true
			end
		end
	end
	if sweep(guiName) > 0 then
		unloaded = true
	end
	for _, name in Singleton.LegacyNames do
		if name ~= guiName and sweep(name) > 0 then
			unloaded = true
		end
	end
	return unloaded
end

return Singleton
