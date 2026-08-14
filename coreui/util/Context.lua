--!strict
-- util/Context.lua — the object threaded through every component.
--
-- Carries the live accent color (themeable via Window:SetAccent), an accent
-- subscription registry, the single-popover manager used by dropdowns and
-- color pickers (menus mount into a high-ZIndex overlay so they escape the
-- scrolling content's clipping), and the flag registry that backs config
-- save / load (any control given a `Flag` is captured by GetConfig/LoadConfig).

local Create = require(script.Parent.Create)
local Tween = require(script.Parent.Tween)
local Fade = require(script.Parent.Fade)
local Log = require(script.Parent.Log)
local Bind = require(script.Parent.Bind)

local Context = {}
Context.__index = Context

export type Context = typeof(setmetatable(
	{} :: {
		Theme: any,
		Accent: Color3,
		AccentHover: Color3,
		AccentFill: Color3,
		AccentSoft: Color3,
		Keybinds: boolean,
		overlay: Frame,
		Flags: { [string]: { handle: any, kind: string } },
		Groups: { { key: string, handle: any } },
		_groupKeys: { [string]: boolean },
		_consumers: { (Color3, Color3) -> () },
		_flagWatchers: { (string, string) -> () },
		_valueWatchers: { (string, any, string, string) -> () },
		_lastEncoded: { [string]: any },
		_source: string,
		_windowState: { () -> () },
		_popover: {
			menu: Instance,
			catcher: Instance,
			conns: { RBXScriptConnection },
			onClose: (() -> ())?,
			fade: any,
		}?,
		_capturing: number,
	},
	Context
))

-- The hover shade of an accent. Lerping toward white washed the color out (the
-- Uranium accent went pastel-mint); brightening in HSV instead keeps the hue and
-- most of the saturation, so #00C46A hovers to ~#1FE087 like the palette says.
local function hover(accent: Color3): Color3
	local h, s, v = accent:ToHSV()
	return Color3.fromHSV(h, math.max(0, s - 0.12), math.min(1, v + 0.12))
end

-- The accent, deepened, for LARGE solid fills (primary buttons). The accent is
-- sized for small marks — a 6px slider fill, a 23px toggle track. The same
-- colour across a 36px full-width button is a searing slab that drowns
-- everything around it, so big fills sit ~18% darker and *hover up* to the full
-- accent, which also gives the press somewhere to go.
local function fill(accent: Color3): Color3
	local h, s, v = accent:ToHSV()
	return Color3.fromHSV(h, math.min(1, s + 0.06), v * 0.82)
end

-- The accent laid *into* a surface — a tinted tile rather than a painted one.
-- Used where something needs to read as accent-coloured across an area too big
-- for the real accent (active nav tile, avatar placeholders, badges): the icon
-- or text on top carries the actual colour, the tile just tints under it.
local function soft(theme: any, accent: Color3): Color3
	return theme.Colors.card:Lerp(accent, 0.13)
end

function Context.new(theme: any, overlay: Frame, accent: Color3): Context
	return setmetatable({
		Theme = theme,
		Accent = accent,
		AccentHover = hover(accent),
		AccentFill = fill(accent),
		AccentSoft = soft(theme, accent),
		-- Are controls bindable unless they say otherwise? Window flips this from
		-- `CreateWindow{ Keybinds = false }`; a control built without a Window (a
		-- test harness) gets the default. Read it as `ctx.Keybinds ~= false` so a
		-- context predating the field still means "yes".
		Keybinds = true,
		overlay = overlay,
		Flags = {},
		-- Every collapsible group in the window, in build order, each under a
		-- stable key — see RegisterGroup. Window snapshots this for the
		-- `uranium_window` flag; nothing else reads it.
		Groups = {},
		_groupKeys = {},
		_consumers = {},
		_flagWatchers = {},
		_valueWatchers = {},
		_lastEncoded = {},
		-- Where the change currently being applied came from. "code" is the
		-- resting state (a programmatic :Set); the two interesting cases push
		-- their own over it — see WithSource.
		_source = "code",
		_windowState = {},
		_popover = nil,
		_capturing = 0,
	}, Context)
end

-- ── Key capture ─────────────────────────────────────────────────────────────
-- A control that's listening for a raw keypress (Keybind) claims capture for the
-- duration. The window's toggle-key listener sits on UserInputService, which
-- doesn't know a control is mid-bind, so without this, binding a key also
-- toggled the window on the very keystroke being bound.
function Context:BeginCapture()
	self._capturing += 1
end

function Context:EndCapture()
	self._capturing = math.max(0, self._capturing - 1)
end

function Context:IsCapturing(): boolean
	return self._capturing > 0
end

-- Register a function recolored whenever the accent changes. Called once now
-- with the current accent so callers don't duplicate the initial paint. The
-- derived shades (`ctx.AccentFill` / `ctx.AccentSoft`) are refreshed *before*
-- consumers run, so a callback can read them straight off ctx. Returns
-- an unsubscribe function — transient consumers (e.g. toasts) must call it on
-- teardown or their dead closures pile up in the registry and fire on every
-- SetAccent forever.
function Context:RegisterAccent(fn: (Color3, Color3) -> ()): () -> ()
	table.insert(self._consumers, fn)
	fn(self.Accent, self.AccentHover)
	return function()
		local list = self._consumers
		for i = #list, 1, -1 do
			if list[i] == fn then
				table.remove(list, i)
				break
			end
		end
	end
end

-- The three derived weights for an ARBITRARY colour, in the same order the live
-- ones sit on ctx: hover / large-fill / tinted-tile. For anything that paints a
-- colour the window accent doesn't own — a per-tab accent (components/Tab.lua) —
-- so it ramps exactly like SetAccent ramps the global one instead of growing a
-- second, hand-rolled set of shades. Keep reading ctx.AccentFill / ctx.AccentSoft
-- for the live accent; this is only for the exceptions.
function Context:Shades(color: Color3): (Color3, Color3, Color3)
	return hover(color), fill(color), soft(self.Theme, color)
end

function Context:SetAccent(color: Color3)
	self.Accent = color
	self.AccentHover = hover(color)
	self.AccentFill = fill(color)
	self.AccentSoft = soft(self.Theme, color)
	-- Walk a snapshot: RegisterAccent's unsubscriber does a table.remove, and a
	-- consumer that drops (or adds) one mid-broadcast would shift the array out
	-- from under the loop and skip the next control's re-theme. Same reason
	-- util/Bind.lua clones before notifying its observers.
	for _, fn in table.clone(self._consumers) do
		fn(self.Accent, self.AccentHover)
	end
end

-- ── Flags / config ──────────────────────────────────────────────────────────
-- Each control kind serializes its value to a JSON-safe form and back. Color3 /
-- Enum.KeyCode aren't JSON-encodable, so they round-trip through hex / name.
local Codec: { [string]: { encode: (any) -> any, decode: (any) -> any } } = {
	toggle = {
		encode = function(v) return v == true end,
		decode = function(v) return v == true end,
	},
	slider = {
		encode = function(v) return v end,
		decode = function(v) return tonumber(v) or 0 end,
	},
	input = {
		encode = function(v) return tostring(v) end,
		decode = function(v) return tostring(v) end,
	},
	code = { -- raw editor text; stored verbatim like input
		encode = function(v) return tostring(v) end,
		decode = function(v) return tostring(v) end,
	},
	dropdown = {
		-- string | { string } — both JSON-safe. "Nothing selected" is `nil`, and a
		-- nil assignment leaves the key out of the table entirely, so the flag never
		-- reached the file: saving with no selection and loading it back left
		-- whatever had been picked since. `false` is the stand-in that survives the
		-- JSON round trip; decode hands nil back.
		encode = function(v) if v == nil then return false end return v end,
		decode = function(v) if v == false then return nil end return v end,
	},
	keybind = {
		encode = function(v) return (typeof(v) == "EnumItem" and v.Name) or "Unknown" end,
		decode = function(v)
			local ok, key = pcall(function()
				return (Enum.KeyCode :: any)[v]
			end)
			return (ok and key) or Enum.KeyCode.Unknown
		end,
	},
	-- A bind is a key AND a mode (Toggle / Hold / Press / Always / None), so it
	-- persists as a pair via the handle's GetFlag/SetFlag. Configs written before
	-- modes existed hold a bare key name, so decode still accepts a plain string.
	bind = {
		encode = function(v)
			if typeof(v) == "EnumItem" then
				return { key = Bind.name(v), mode = "None" }
			elseif type(v) == "table" then
				return { key = Bind.name(v.Key), mode = v.Mode or "None" }
			end
			return { key = "None", mode = "None" }
		end,
		decode = function(v)
			if type(v) == "string" then
				return { Key = Bind.parse(v) }
			elseif type(v) == "table" then
				return { Key = Bind.parse(v.key), Mode = v.mode }
			end
			return { Key = Bind.parse(v) } -- anything unrecognized parses to Unknown
		end,
	},
	-- The bind HUD (components/Hud.lua) isn't a control and has no single value —
	-- it persists as where you put it and whether it was up, through the same
	-- GetFlag/SetFlag pair the bind codec uses.
	hud = {
		encode = function(v)
			if type(v) ~= "table" then
				return { visible = false }
			end
			local record: any = {
				visible = v.Visible == true,
				collapsed = v.Collapsed == true,
			}
			-- Coordinates only when there actually are some. A window whose HUD was
			-- never built reports `{ Visible = false }` and nothing else, and
			-- `floor(nil or 0)` wrote that down as a real position of (0, 0) — loading
			-- the config in a session where the HUD *is* up teleported it into the
			-- corner instead of leaving it where the user put it.
			local x, y = tonumber(v.X), tonumber(v.Y)
			if x and y then
				record.x = math.floor(x)
				record.y = math.floor(y)
			end
			return record
		end,
		decode = function(v)
			if type(v) ~= "table" then
				return { Visible = v == true }
			end
			return {
				Visible = v.visible == true,
				Collapsed = v.collapsed == true,
				X = tonumber(v.x),
				Y = tonumber(v.y),
			}
		end,
	},
	-- The window's own UI state — where it sits, whether it's maximized, which tab
	-- is open and which groups are folded. Like `hud` it isn't a control and has no
	-- single value, so it goes through the same GetFlag/SetFlag pair;
	-- components/Window.lua registers it itself unless
	-- `CreateWindow{ PersistWindow = false }`.
	--
	-- Every field is optional on the way back in: a config written by a build with
	-- different tabs (or on a machine with a different viewport) has to restore the
	-- parts that still make sense and drop the rest, which is Window's job in
	-- `applyWindowState` — the codec only gets it there and back.
	window = {
		encode = function(v)
			if type(v) ~= "table" then
				return {}
			end
			local record: any = { maximized = v.Maximized == true }
			-- Paired, and only when both are real numbers: half a coordinate is not
			-- a position, and `floor(nil or 0)` would write the corner of the screen
			-- down as if the user had put the window there (the bug the `hud` codec
			-- above already had once).
			local x, y = tonumber(v.X), tonumber(v.Y)
			if x and y then
				record.x = math.floor(x)
				record.y = math.floor(y)
			end
			local w, h = tonumber(v.Width), tonumber(v.Height)
			if w and h then
				record.w = math.floor(w)
				record.h = math.floor(h)
			end
			local tab = tonumber(v.Tab)
			if tab then
				record.tab = math.floor(tab)
			end
			if type(v.Groups) == "table" then
				local groups: any = {}
				local any = false
				for key, collapsed in v.Groups :: any do
					groups[key] = collapsed == true
					any = true
				end
				-- Omitted rather than written empty: HttpService encodes an empty
				-- table as `[]`, which reads as a corrupt record rather than "no
				-- groups" when a human opens the file.
				if any then
					record.groups = groups
				end
			end
			return record
		end,
		decode = function(v)
			if type(v) ~= "table" then
				return {}
			end
			return {
				X = tonumber(v.x),
				Y = tonumber(v.y),
				Width = tonumber(v.w),
				Height = tonumber(v.h),
				Maximized = v.maximized == true,
				Tab = tonumber(v.tab),
				Groups = type(v.groups) == "table" and v.groups or nil,
			}
		end,
	},
	colorpicker = {
		encode = function(v) return typeof(v) == "Color3" and v:ToHex() or tostring(v) end,
		decode = function(v)
			local ok, color = pcall(Color3.fromHex, v)
			return (ok and color) or Color3.new(1, 1, 1)
		end,
	},
	playerselect = { -- handle:Get() returns Player(s); persist as UserId(s), :Set resolves back
		encode = function(v)
			if type(v) == "table" then
				local ids = {}
				for _, p in v do
					if typeof(p) == "Instance" and p:IsA("Player") then
						table.insert(ids, p.UserId)
					end
				end
				return ids
			elseif typeof(v) == "Instance" and v:IsA("Player") then
				return v.UserId
			end
			return false -- nobody picked — see the dropdown codec for why not nil
		end,
		-- number | { number } — handle:Set resolves ids live
		decode = function(v) if v == false then return nil end return v end,
	},
}

-- Read a flag's *persisted* value and encode it, exactly as GetConfig would.
-- Shared so a single flag's notification and a whole-config snapshot can never
-- disagree about what a control's value is; `where` names the caller in the
-- warnings, since a failure means something different in each ("save skipped it"
-- vs "the change notification was dropped").
local function encodeFlag(name: string, entry: { handle: any, kind: string }, where: string): (boolean, any)
	local codec = Codec[entry.kind]
	if not codec then
		return false, nil
	end
	local okRead, value = pcall(function()
		if entry.handle.GetFlag then
			return entry.handle:GetFlag()
		end
		return entry.handle:Get()
	end)
	if not okRead then
		-- Silence here is what makes "save did nothing" impossible to debug: the
		-- flag just goes missing from the file. Name it and carry on with the rest.
		Log.warn(where, ('flag "%s" (%s) failed to read — skipped: %s')
			:format(name, entry.kind, tostring(value)))
		return false, nil
	end
	local okEncode, encoded = pcall(codec.encode, value)
	if not okEncode then
		Log.warn(where, ('flag "%s" (%s) failed to encode — skipped: %s')
			:format(name, entry.kind, tostring(encoded)))
		return false, nil
	end
	return true, encoded
end

-- Value equality over encoded (JSON-safe) values, which is what "did this flag
-- actually change?" means. Tables here are small and acyclic by construction —
-- a bind is `{ key, mode }`, the window record is a handful of numbers plus a
-- map of booleans — so a plain recursive walk is both correct and cheap.
local function sameValue(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not sameValue(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- The dedupe baseline has to be OURS. Codecs build fresh tables today, but a
-- codec (or a host's `GetFlag`) that ever handed back the live table it reads
-- from would mutate the baseline along with the value, and every subsequent
-- change would compare equal and go unreported — a silent, near-undebuggable
-- failure of the whole feature. A copy costs nothing at this size.
local function freeze(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, v in value do
		out[key] = freeze(v)
	end
	return out
end

-- ── Flag change notifications ───────────────────────────────────────────────
-- `OnFlag` above answers "which flags exist"; this answers "which one just
-- moved", which is what a host that persists continuously needs. Without it the
-- only way to notice a change is to poll `GetConfig()` and diff, so everything
-- since the last poll is lost whenever the client dies without a clean unload.
--
-- `fn(name, value, kind, source)`:
--   name    the flag
--   value   the ENCODED value — byte-for-byte what `GetConfig()` would put in
--           the file for it, so a host can patch its snapshot in place instead
--           of re-reading every flag to find the one that moved
--   kind    the codec kind, as `GetFlags()` reports it
--   source  "user" (a control the user operated) · "code" (a programmatic
--           `:Set`) · "config" (inside ApplyConfig / LoadConfig)
--
-- `source` is the load-bearing one: a config landing 40 flags must not look like
-- 40 edits worth writing back, and the alternative — the host guessing with a
-- re-entrancy flag around its own ApplyConfig call — can't see an autoload the
-- library ran itself.
--
-- Fires SYNCHRONOUSLY, like OnFlag. Note that most controls hand their callback
-- to `task.spawn`, so a watcher usually runs on that spawned thread rather than
-- on the one that caused the change — fine to yield in, never a reason to
-- assume you're still inside the click handler.
function Context:OnFlagChanged(fn: (string, any, string, string) -> ()): () -> ()
	table.insert(self._valueWatchers, fn)
	return function()
		local list = self._valueWatchers
		for i = #list, 1, -1 do
			if list[i] == fn then
				table.remove(list, i)
				break
			end
		end
	end
end

-- Run `fn` with changes attributed to `source`. The tag is dynamically scoped
-- rather than passed down because the notification is raised several frames of
-- call stack below the thing that knows the answer — a click handler calls
-- `handle:Set`, which spawns the control's callback, which is where the notify
-- lands. `task.spawn` resumes immediately, so that spawned thread is still
-- inside this scope.
--
-- pcall'd so a throwing handler can't strand the tag and mislabel every change
-- after it; the error is re-raised untouched.
function Context:WithSource(source: string, fn: (...any) -> ...any, ...): ...any
	local previous = self._source
	self._source = source
	local results = table.pack(pcall(fn, ...))
	self._source = previous
	if not results[1] then
		error(results[2], 0)
	end
	return table.unpack(results, 2, results.n)
end

-- Sugar for the common one: a control's own input handler. Every place a
-- control turns a click / drag / keystroke into a value change wraps it, so
-- "the user did this" is a fact rather than an inference.
function Context:User(fn: (...any) -> ...any, ...): ...any
	return self:WithSource("user", fn, ...)
end

-- Announce that `name`'s value may have moved. Cheap to over-call: it re-reads
-- and re-encodes the flag and stays silent unless the result actually differs
-- from the last value it reported, which is what keeps a `:Set` that lands on
-- the value already held — a config restoring what's already on screen, a
-- toggle re-asserted every frame — from looking like an edit.
--
-- `source` overrides the ambient tag for this one notification; almost nothing
-- needs it, since WithSource already covers the paths that know better.
function Context:NotifyFlag(name: string, source: string?)
	local entry = self.Flags[name]
	if not entry then
		return
	end
	-- Nobody listening: skip the read + encode entirely. The baseline going stale
	-- is harmless — it holds the last value we *reported*, so the first
	-- notification after a watcher appears compares against that and fires iff
	-- something really did change in between, which is the honest answer.
	if #self._valueWatchers == 0 then
		return
	end
	local ok, encoded = encodeFlag(name, entry, "OnFlagChanged")
	if not ok then
		return
	end
	if sameValue(self._lastEncoded[name], encoded) then
		return
	end
	self._lastEncoded[name] = freeze(encoded)
	local from = source or self._source
	for _, fn in table.clone(self._valueWatchers) do
		local okWatcher, err = pcall(fn, name, encoded, entry.kind, from)
		if not okWatcher then
			-- Same rule as OnFlag: a host's bookkeeping blowing up must not take the
			-- control that moved down with it.
			Log.warn("OnFlagChanged", ('watcher errored for flag "%s" (%s): %s')
				:format(name, entry.kind, tostring(err)))
		end
	end
end

-- ── Group registry ──────────────────────────────────────────────────────────
-- Collapsible groups register themselves so the window can persist which ones
-- are folded. The key is `"<tab>::<group>"` — the tab's name at creation and the
-- group's `Id` (or its Title), which is the most stable identity available
-- without making every caller invent one. Same key twice gets a `#n` suffix, so
-- two identically-titled groups in one tab still round-trip as long as the menu
-- builds in the same order.
function Context:RegisterGroup(scope: string, id: string, handle: any): string
	local base = ("%s::%s"):format(scope, id)
	local key = base
	local n = 1
	while self._groupKeys[key] do
		n += 1
		key = ("%s#%d"):format(base, n)
	end
	self._groupKeys[key] = true
	table.insert(self.Groups, { key = key, handle = handle })
	return key
end

-- Window subscribes; groups and tabs raise it. The window's own geometry is
-- Window's business, but "a group was folded" and "a tab was selected" happen
-- in components that have no idea the flag exists.
function Context:OnWindowState(fn: () -> ()): () -> ()
	table.insert(self._windowState, fn)
	return function()
		local list = self._windowState
		for i = #list, 1, -1 do
			if list[i] == fn then
				table.remove(list, i)
				break
			end
		end
	end
end

function Context:WindowStateChanged()
	for _, fn in table.clone(self._windowState) do
		fn()
	end
end

-- Watch flag registration. `fn(name, kind)` fires SYNCHRONOUSLY from inside
-- RegisterFlag, which is the whole point: a loader that wants to know which
-- module (or which boot phase) a flag came from tags it against whatever it is
-- currently building, and that only works if the notification lands before the
-- next line of the builder runs. A BindableEvent would not do — Roblox's
-- deferred signal behaviour hands the callback back at the end of the
-- resumption cycle, by which time "what are we building right now?" has moved
-- on. Same shape as RegisterAccent: returns an unsubscribe.
--
-- Unlike RegisterAccent this does NOT replay the flags already registered —
-- Context:GetFlags() is there for that, and a watcher installed at CreateWindow
-- time (the `OnFlag` option) has missed nothing.
function Context:OnFlag(fn: (string, string) -> ()): () -> ()
	table.insert(self._flagWatchers, fn)
	return function()
		local list = self._flagWatchers
		for i = #list, 1, -1 do
			if list[i] == fn then
				table.remove(list, i)
				break
			end
		end
	end
end

-- Every registered flag as `{ [name] = kind }` — a copy, so a caller can't edit
-- the live registry through it. Enumerating at two points in time is what lets a
-- host split flags into groups it registered before and after some milestone
-- (a per-place module, a profile), which is the difference between a config that
-- scopes and one that has to be all-or-nothing.
function Context:GetFlags(): { [string]: string }
	local out = {}
	for name, entry in self.Flags do
		out[name] = entry.kind
	end
	return out
end

-- Register a stateful control's handle under `name` so config save/load can
-- read (:Get) and write (:Set) it. `kind` selects the codec. No-op without both.
function Context:RegisterFlag(name: string?, handle: any, kind: string?)
	if not name or not kind or not Codec[kind] or not handle then
		return
	end
	-- Two controls sharing a Flag silently overwrite each other in config
	-- save/load — the second wins and the first never persists. That's almost
	-- always a copy-paste slip, so surface it rather than let configs go stale.
	if self.Flags[name] then
		Log.warn("Flag", ('"%s" is registered twice — both controls share one config '
			.. "slot, so only the last will save/load. Give each a unique Flag."):format(name))
	end
	local entry = { handle = handle, kind = kind }
	self.Flags[name] = entry
	-- Seed the change-notification baseline with the value the control was BUILT
	-- with, so a control taking its `Default` is never reported as a change (see
	-- OnFlagChanged). A handle that can't be read at all is a malformed handle and
	-- encodeFlag says so; the flag still registers, and saving it will fail the
	-- same way later.
	-- Explicit branch, not `ok and freeze(...) or nil`: a legitimately falsy
	-- baseline (the `dropdown` and `playerselect` codecs both encode "nothing
	-- selected" as `false`) would fall through to nil, and the first real
	-- notification would then report a change that never happened.
	local ok, encoded = encodeFlag(name, entry, "OnFlagChanged")
	if ok then
		self._lastEncoded[name] = freeze(encoded)
	else
		self._lastEncoded[name] = nil
	end
	-- Clone before notifying: a watcher is allowed to unsubscribe itself (or add
	-- another) from inside the callback, and mutating the array mid-walk would
	-- skip the next one. Same reason SetAccent and util/Bind.lua clone.
	for _, fn in table.clone(self._flagWatchers) do
		local ok, err = pcall(fn, name, kind)
		if not ok then
			-- A host's bookkeeping blowing up must not take the control down with
			-- it — the flag is registered either way.
			Log.warn("OnFlag", ('watcher errored for flag "%s" (%s): %s')
				:format(name, kind, tostring(err)))
		end
	end
end

-- Snapshot every flagged control into a JSON-safe table.
--
-- A control whose persisted value isn't its primary value — a keybind, which is
-- a key *and* a mode, while `:Get()` is just the key — exposes `:GetFlag()` /
-- `:SetFlag()` and those win. Everything else round-trips through `:Get()`/`:Set()`.
function Context:GetConfig(): { [string]: any }
	local data = {}
	for name, entry in self.Flags do
		local ok, encoded = encodeFlag(name, entry, "SaveConfig")
		if ok then
			data[name] = encoded
		end
	end
	return data
end

-- Apply a saved table back onto the flagged controls (fires their callbacks).
-- Returns how many flags were applied and how many keys were skipped.
--
-- **A key with no registered flag is skipped, quietly and on purpose** — that's
-- a promised part of the format, not an accident of the loop. It's what lets a
-- config carry data that isn't a control value: `Config.MetaKey` ("__uranium")
-- is the library's own reserved slot for the metadata `Window:SaveConfig(name,
-- meta)` stamps, and a host is free to keep its own bookkeeping keys alongside
-- it. It also means a config written by a build with more controls than this one
-- still loads the flags this build does have.
--
-- `opts.Filter = function(name, kind) -> boolean` decides, per flag, whether it
-- is applied at all — for a host that scopes its registry (a portable half and a
-- per-place half) and wants to land only one of them. It's a *predicate*, not a
-- list of names, because that classification is computed rather than enumerable.
-- Three things it promises:
--   • It only ever sees keys that resolved to a registered flag, so `kind` is
--     always a real codec kind and `Config.MetaKey` (and any other bookkeeping
--     key) never reaches it — those are skipped before the filter is consulted.
--   • A filtered-out key counts as **skipped**, never applied, so LoadConfig's
--     "applied nothing" still means nothing matched.
--   • It's called inside a pcall; a filter that errors skips its flag rather
--     than half-applying a config the host couldn't classify.
export type LoadOpts = { Filter: ((string, string) -> boolean)? }

function Context:LoadConfig(data: { [string]: any }, opts: LoadOpts?): (number, number)
	if type(data) ~= "table" then
		return 0, 0
	end
	local filter: ((string, string) -> boolean)? = nil
	if opts ~= nil then
		if type(opts) ~= "table" then
			Log.warn("LoadConfig", ("options must be a table, got %s — ignoring.")
				:format(typeof(opts)))
		elseif opts.Filter ~= nil then
			if type(opts.Filter) ~= "function" then
				Log.warn("LoadConfig", ("Filter must be a function, got %s — ignoring.")
					:format(typeof(opts.Filter)))
			else
				filter = opts.Filter
			end
		end
	end
	local applied, skipped = 0, 0
	for name, raw in data do
		local entry = self.Flags[name]
		local codec = entry and Codec[entry.kind]
		local wanted = true
		if codec and filter then
			local okFilter, verdict = pcall(filter, name, entry.kind)
			if not okFilter then
				Log.warn("LoadConfig", ('filter errored for flag "%s" (%s) — skipped: %s')
					:format(name, entry.kind, tostring(verdict)))
				wanted = false
			else
				wanted = verdict and true or false
			end
		end
		if not codec or not wanted then
			skipped += 1
		else
			-- Every failure below used to be swallowed by a bare pcall, so one broken
			-- control read as "the whole config didn't load". Skip the bad flag, say
			-- which one, and keep applying the rest.
			local okDecode, value = pcall(codec.decode, raw)
			if not okDecode then
				Log.warn("LoadConfig", ('flag "%s" (%s) failed to decode — skipped: %s')
					:format(name, entry.kind, tostring(value)))
				skipped += 1
			else
				-- Tagged for the whole apply, so a host persisting on change can tell
				-- 40 flags landing from a config apart from 40 edits worth writing
				-- back (see OnFlagChanged). The control's own callback fires from
				-- inside here, which is where most of the notifications come from.
				local okSet, err = pcall(function()
					self:WithSource("config", function()
						if entry.handle.SetFlag then
							entry.handle:SetFlag(value)
						else
							entry.handle:Set(value)
						end
					end)
				end)
				if okSet then
					applied += 1
					-- Backstop for handles with no callback of their own — the HUD, the
					-- window record, a host's own registered state. Deduped against
					-- whatever the control already reported, so the common case is a
					-- comparison and nothing else.
					self:NotifyFlag(name, "config")
				else
					Log.warn("LoadConfig", ('flag "%s" (%s) failed to apply — skipped: %s')
						:format(name, entry.kind, tostring(err)))
					skipped += 1
				end
			end
		end
	end
	return applied, skipped
end

-- ── Popovers ───────────────────────────────────────────────────────────────
function Context:ClosePopover()
	local p = self._popover
	if not p then
		return
	end
	self._popover = nil
	for _, conn in p.conns do
		conn:Disconnect()
	end
	p.catcher:Destroy()
	-- Land the open-fade back on its resting values before hiding. Closing
	-- mid-fade and immediately reopening would otherwise snapshot the half-faded
	-- tree as the new baseline and leave the menu permanently washed out.
	p.fade:Set(0)
	p.menu.Visible = false
	if p.onClose then
		p.onClose()
	end
end

-- Open `menu` directly under `anchor`, closing any other open popover first.
-- A full-overlay catcher button dismisses it on any outside click.
function Context:OpenPopover(menu: GuiObject, anchor: GuiObject, onClose: (() -> ())?)
	self:ClosePopover()

	local catcher = Create("TextButton", {
		Name = "Catcher",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 50,
		Parent = self.overlay,
	})
	menu.ZIndex = 60
	menu.Parent = self.overlay

	-- Place the menu under the anchor, but keep it inside the overlay (= window)
	-- bounds: clamp horizontally, and flip above the anchor when there isn't
	-- enough room below. The window clips descendants, so a menu that spilled
	-- off the edge would be cut off — this keeps it fully visible.
	local MARGIN = 8
	local GAP = 6
	local function place()
		local o = self.overlay.AbsolutePosition
		local os = self.overlay.AbsoluteSize
		local a = anchor.AbsolutePosition
		local asz = anchor.AbsoluteSize
		local msz = menu.AbsoluteSize

		local x = a.X - o.X
		x = math.clamp(x, MARGIN, math.max(MARGIN, os.X - msz.X - MARGIN))

		local below = (a.Y - o.Y) + asz.Y + GAP
		local above = (a.Y - o.Y) - msz.Y - GAP
		local y = below
		if below + msz.Y > os.Y - MARGIN and above >= MARGIN then
			y = above -- not enough room below → open upward
		end
		y = math.clamp(y, MARGIN, math.max(MARGIN, os.Y - msz.Y - MARGIN))

		menu.Position = UDim2.fromOffset(x, y)
	end
	place()
	menu.Visible = true

	-- Fade the menu in as a unit. This used to be a CanvasGroup + one
	-- GroupTransparency tween, which rasterized every option label into a buffer
	-- and blurred it — util/Fade.lua does the same job on the real properties.
	-- Snapshotting here (not at build time) is deliberate: menus rebuild their
	-- rows, so each open re-reads the tree it's actually about to show.
	local fade = Fade.new(menu)
	fade:Set(1)
	fade:To(Tween.Pop, 0)

	-- Re-place when the anchor moves, when the menu's auto-size settles, or when
	-- the window resizes.
	local conns = {
		anchor:GetPropertyChangedSignal("AbsolutePosition"):Connect(place),
		menu:GetPropertyChangedSignal("AbsoluteSize"):Connect(place),
		self.overlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(place),
	}
	self._popover = { menu = menu, catcher = catcher, conns = conns, onClose = onClose, fade = fade }
	catcher.Activated:Connect(function()
		self:ClosePopover()
	end)
end

function Context:IsOpen(menu: GuiObject): boolean
	return self._popover ~= nil and self._popover.menu == menu
end

return Context
