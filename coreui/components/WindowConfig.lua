--!strict
-- components/WindowConfig.lua — the window's flag + config surface.
--
-- Split out of components/Window.lua. Everything here is either a pass-through
-- to util/Context.lua's flag registry or that registry plus util/Config.lua's
-- file layer; not one method in the file touches an Instance, which is what made
-- it ~240 lines of the window shell that had nothing to do with the shell.
--
-- The split it draws is the same one the API draws: `GetConfig`/`ApplyConfig`
-- are the primitives, and `SaveConfig`/`LoadConfig` are those plus a file. A host
-- that wants its own layout on disk uses the first pair and never comes here.

local Config = require(script.Parent.Parent.util.Config)
local Log = require(script.Parent.Parent.util.Log)
local Signal = require(script.Parent.Parent.util.Signal)

-- Options for ApplyConfig / LoadConfig. `Filter(name, kind) -> boolean` decides
-- per flag whether it's applied; see Context:LoadConfig for the contract.
export type LoadOpts = { Filter: ((string, string) -> boolean)? }

return function(window: any, ctx: any, opts: any)
	-- Where configs are saved on disk. No longer fixed at CreateWindow — see
	-- window:SetConfigFolder — so anything showing a config list has to be told
	-- when the list it's showing became a different folder's.
	local configFolder = opts.ConfigFolder or "uranium"
	local folderWatchers = Signal.new() :: any

	-- ── settings: the flag registry ───────────────────────────────────────────
	-- The two primitives everything else here is built on. The named-file methods
	-- below are just these plus util/Config.lua — which is the point: a host that
	-- wants its own layout on disk, remote or shared configs, in-memory profiles
	-- or a "reset to defaults" button needs the snapshot/apply pair WITHOUT the
	-- library's file path in the middle, and previously the only way to apply a
	-- table of flags was to write it to <ConfigFolder>/configs/<name>.json first.
	--
	--   local snapshot = Window:GetConfig()      -- exactly what SaveConfig serializes
	--   Window:ApplyConfig(snapshot)             -- exactly what LoadConfig applies
	--
	-- GetConfig returns flags only — no `Config.MetaKey` stamp; that's SaveConfig's
	-- doing, and a host composing its own file adds whatever metadata it wants.
	function window:GetConfig(): { [string]: any }
		return ctx:GetConfig()
	end

	-- Apply a table of flags. Returns how many were applied and how many keys were
	-- skipped (unknown flag, failed decode, control refused the value, or filtered
	-- out). Keys with no registered flag are skipped rather than erroring — see
	-- Context:LoadConfig, where that promise is spelled out.
	--
	-- `opts.Filter = function(name, kind) -> boolean` applies only the flags it
	-- says yes to, for a host whose registry is split (a portable half, a per-place
	-- half). One predicate rather than a list of names, because that split is
	-- computed, not enumerable; `Config.MetaKey` and every other unregistered key
	-- is skipped before the filter is consulted, so it never sees one.
	function window:ApplyConfig(data: { [string]: any }, loadOpts: LoadOpts?): (number, number)
		if type(data) ~= "table" then
			Log.warn("ApplyConfig", ("expects a table of flags, got %s — ignoring.")
				:format(typeof(data)))
			return 0, 0
		end
		return ctx:LoadConfig(data, loadOpts)
	end

	-- Every registered flag as `{ [name] = kind }`. Snapshot it at two moments —
	-- before and after a per-place module builds its controls — and the difference
	-- is that module's flags, which is how a config gets scoped (apply the portable
	-- half anywhere, the game-specific half only in the right game) instead of
	-- being all-or-nothing.
	function window:GetFlags(): { [string]: string }
		return ctx:GetFlags()
	end

	-- Register a flag by hand. `handle` needs `:Get()`/`:Set(v)` (or `:GetFlag()`/
	-- `:SetFlag(v)` when the persisted value isn't the primary one), `kind` names
	-- the codec — the same contract every control satisfies. This is how the
	-- built-in Settings tab persists the bind HUD, which isn't a control at all,
	-- and it's how a host puts its own non-control state in the same config file.
	function window:RegisterFlag(name: string, handle: any, kind: string)
		ctx:RegisterFlag(name, handle, kind)
	end

	-- Watch flags as they're registered — `fn(name, kind)`, synchronously, so the
	-- callback can attribute the flag to whatever is being built at that instant.
	-- Returns an unsubscribe. `CreateWindow{ OnFlag = fn }` is the same hook,
	-- installed early enough to catch every flag in the menu.
	function window:OnFlag(fn: (string, string) -> ()): () -> ()
		return ctx:OnFlag(fn)
	end

	-- Watch flag VALUES as they move — `fn(name, value, kind, source)`, where
	-- `value` is the encoded value (what `GetConfig()` would file under that name)
	-- and `source` is `"user"` / `"code"` / `"config"`. Fires synchronously, and
	-- never for a control taking its default or for a `:Set` that lands on the
	-- value already held. Returns an unsubscribe.
	--
	-- This is what a host persisting continuously hangs off: without it the only
	-- way to notice a change is to poll `GetConfig()` and diff it, which loses
	-- everything since the last poll whenever the client script dies without a
	-- clean unload. `source` is what keeps a config landing 40 flags from looking
	-- like 40 edits worth writing back.
	function window:OnFlagChanged(fn: (string, any, string, string) -> ()): () -> ()
		if type(fn) ~= "function" then
			Log.fail("OnFlagChanged", ("expects a function fn(name, value, kind, source), got %s")
				:format(typeof(fn)))
		end
		return ctx:OnFlagChanged(fn)
	end

	-- Tell the watchers a flag's value moved. Only needed for state YOU registered
	-- with `RegisterFlag` — every control notifies for itself. Re-reads and
	-- re-encodes the flag and stays silent unless the value actually differs from
	-- the last one reported, so it's safe to call on any suspicion of a change.
	function window:NotifyFlag(name: string, source: string?)
		if type(name) ~= "string" or name == "" then
			Log.warn("NotifyFlag", ("expects a flag name, got %s — ignoring.")
				:format(name == "" and '""' or typeof(name)))
			return
		end
		if not ctx.Flags[name] then
			Log.warn("NotifyFlag", ('no flag named "%s" is registered — ignoring.'):format(name))
			return
		end
		ctx:NotifyFlag(name, source)
	end

	-- ── settings: config persistence ──────────────────────────────────────────
	-- These are the flag registry (above) plus a file on disk. Every one of them
	-- returns `(result, reason)`: the library always knew whether it was a missing
	-- file, corrupt JSON or an executor with no file access, and a bare `false`
	-- threw that away — leaving a host with nothing to say but "Couldn't load".
	window.ConfigSupported = Config.supported

	local function badConfigName(where: string, name: any): boolean
		if type(name) ~= "string" or name == "" then
			Log.warn(where, ("config name must be a non-empty string, got %s — ignoring.")
				:format(name == "" and '""' or typeof(name)))
			return true
		end
		return false
	end

	-- `meta` is stamped into the file under `Config.MetaKey` alongside the flags,
	-- and read back by ConfigInfo without applying anything — provenance
	-- ("which game / profile / build wrote this?") without a second file to keep
	-- in sync. It's skipped on load like any unregistered key.
	function window:SaveConfig(name: string, meta: any?): (boolean, string?)
		if badConfigName("SaveConfig", name) then
			return false, "invalid name"
		end
		if meta ~= nil and type(meta) ~= "table" then
			Log.warn("SaveConfig", ("meta must be a table, got %s — saving without it.")
				:format(typeof(meta)))
			meta = nil
		end
		local snapshot = ctx:GetConfig()
		local n = 0
		for _ in snapshot do
			n += 1
		end
		if meta then
			snapshot[Config.MetaKey] = meta
		end
		local ok, reason = Config.save(configFolder, name, snapshot)
		Log.infof("SaveConfig(%q) -> %s  (%d flags%s)",
			tostring(name), tostring(ok), n, ok and "" or ", " .. tostring(reason))
		return ok, reason
	end

	-- `opts` is ApplyConfig's, and it's here for the same reason: a host that
	-- scopes its registry — a portable half applied anywhere, a per-place half
	-- only in the right game — could otherwise only land *part* of a file by
	-- abandoning this method entirely and rebuilding it out of `Uranium.Config` +
	-- ApplyConfig, losing the name validation, the log line and the (ok, reason)
	-- shape in the process. A filtered-out flag counts as skipped, so "applied
	-- nothing" still means what it says.
	function window:LoadConfig(name: string, loadOpts: LoadOpts?): (boolean, string?)
		if badConfigName("LoadConfig", name) then
			return false, "invalid name"
		end
		local data, reason = Config.load(configFolder, name)
		Log.infof("LoadConfig(%q) -> %s%s",
			tostring(name), tostring(data ~= nil), data and "" or " (" .. tostring(reason) .. ")")
		if not data then
			return false, reason
		end
		local applied = ctx:LoadConfig(data, loadOpts)
		if applied == 0 then
			-- The file was fine and nothing in it matched a control we have (or the
			-- caller's filter wanted none of what did). That's a different failure
			-- from "no such config" and it used to read as success.
			return false, "applied nothing"
		end
		return true
	end

	function window:DeleteConfig(name: string): (boolean, string?)
		if badConfigName("DeleteConfig", name) then
			return false, "invalid name"
		end
		return Config.delete(configFolder, name)
	end

	function window:ListConfigs(): { string }
		return Config.list(configFolder)
	end

	-- The metadata a config was saved with, without touching a single control —
	-- the read a "does this config belong to this game?" check actually wants.
	function window:ConfigInfo(name: string): (any?, string?)
		if badConfigName("ConfigInfo", name) then
			return nil, "invalid name"
		end
		return Config.info(configFolder, name)
	end

	-- ── settings: auto-load pointer ───────────────────────────────────────────
	-- The Settings tab used to call Config.setAutoload/getAutoload directly, which
	-- made it the one config path a host couldn't intercept — every other one goes
	-- through a window: method. Now it goes through these too.
	function window:SetAutoload(name: string?)
		if name ~= nil and type(name) ~= "string" then
			Log.warn("SetAutoload", ("expects a config name or nil, got %s — ignoring.")
				:format(typeof(name)))
			return
		end
		Config.setAutoload(configFolder, name)
	end

	function window:GetAutoload(): string?
		return Config.getAutoload(configFolder)
	end

	-- ── settings: where configs live ──────────────────────────────────────────
	function window:GetConfigFolder(): string
		return configFolder
	end

	-- Re-scope persistence at runtime — per-place config folders, user profiles,
	-- an account switch. Anything already showing a config list is notified
	-- (window:OnConfigFolder) because its contents just became a different
	-- folder's; the built-in Settings tab refreshes its dropdown from that.
	function window:SetConfigFolder(path: string)
		if type(path) ~= "string" or path == "" then
			Log.warn("SetConfigFolder", ("expects a non-empty path, got %s — ignoring.")
				:format(path == "" and '""' or typeof(path)))
			return
		end
		if path == configFolder then
			return
		end
		configFolder = path
		folderWatchers:Fire(configFolder)
	end

	-- Fires immediately with the current folder, then on every change; returns an
	-- unsubscribe.
	function window:OnConfigFolder(fn: (string) -> ()): () -> ()
		local unsubscribe = folderWatchers:Connect(fn)
		fn(configFolder) -- the current folder; Signal never replays
		return unsubscribe
	end

	-- The folder moves at runtime, so anything else that needs it gets a getter
	-- rather than a value captured at build time.
	return {
		folder = function(): string
			return configFolder
		end,
	}
end
