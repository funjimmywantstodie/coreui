--!strict
-- util/Bind.lua — the keybind router + mode machine behind every bindable
-- control.
--
-- One pair of UserInputService listeners (created with the Window, torn down
-- with it) fans every press out to the registered bindings, so N bound controls
-- cost 2 connections instead of 2N — and every binding gets the same
-- gameProcessed / key-capture gating for free.
--
-- A binding is a key + a MODE, and the mode is the point:
--
--   Toggle   press flips the value (the default)
--   Hold     value is true only while the key is held down
--   Press    fires once per press, carries no state (commands: rejoin, respawn)
--   Always   value is forced on; the key does nothing while it's selected
--   None     no activation at all — the control is only a key picker
--
-- Bindings never poll input themselves; the router pushes to them. Mouse
-- buttons are routed as well as keyboard keys (pass
-- `Enum.UserInputType.MouseButton2` as the key); components/BindChip.lua binds
-- MB2/MB3 from a click on the armed chip, and leaves MB1 to the caller.
--
-- The router is also the *registry* every binding is already in, which is what
-- components/Hud.lua reads: `Bind:Observe(fn)` fires on any change (a bind
-- registered, re-keyed, mode-cycled, activated, destroyed) and `Bind:List()`
-- hands back the live entries. A binding carries a `Label` so it has something
-- to be called in that list — an unlabeled one is internal plumbing and stays
-- out of it (`Binding:IsListed`).

local UserInputService = game:GetService("UserInputService")

local Log = require(script.Parent.Log)

local Bind = {}
Bind.__index = Bind

local Binding = {}
Binding.__index = Binding

-- ── keys ────────────────────────────────────────────────────────────────────
-- A "key" is an Enum.KeyCode, or one of the mouse UserInputTypes below.
local MOUSE_NAME: { [Enum.UserInputType]: string } = {
	[Enum.UserInputType.MouseButton1] = "MB1",
	[Enum.UserInputType.MouseButton2] = "MB2",
	[Enum.UserInputType.MouseButton3] = "MB3",
}
local NAME_MOUSE: { [string]: Enum.UserInputType } = {}
for input, name in MOUSE_NAME do
	NAME_MOUSE[name] = input
end

-- The chip is ~44px wide in a toggle row, and "RightControl" is not going to
-- fit. Shorten the ones people actually bind; everything else keeps its name.
local SHORT: { [string]: string } = {
	LeftShift = "LShift",
	RightShift = "RShift",
	LeftControl = "LCtrl",
	RightControl = "RCtrl",
	LeftAlt = "LAlt",
	RightAlt = "RAlt",
	LeftSuper = "LSuper",
	RightSuper = "RSuper",
	Backspace = "Bksp",
	CapsLock = "Caps",
	PageDown = "PgDn",
	PageUp = "PgUp",
	Insert = "Ins",
	Delete = "Del",
	Escape = "Esc",
	Return = "Enter",
}
local LONG: { [string]: string } = {}
for long, short in SHORT do
	LONG[short] = long
end

-- Is `v` something the router can bind? (KeyCode, or a mouse button.)
function Bind.isKey(v: any): boolean
	if typeof(v) ~= "EnumItem" then
		return false
	end
	return (v :: any).EnumType == Enum.KeyCode or MOUSE_NAME[v :: any] ~= nil
end

-- Display name for a key. `nil` / Unknown reads as "None" — an unbound control.
function Bind.name(key: any): string
	if not Bind.isKey(key) or key == Enum.KeyCode.Unknown then
		return "None"
	end
	local mouse = MOUSE_NAME[key]
	if mouse then
		return mouse
	end
	return SHORT[key.Name] or key.Name
end

-- Inverse of Bind.name, for config load. Accepts both the short display name
-- and the raw enum name, so hand-written configs work either way.
function Bind.parse(name: any): any
	if Bind.isKey(name) then
		return name
	end
	if type(name) ~= "string" or name == "" then
		return Enum.KeyCode.Unknown
	end
	local mouse = NAME_MOUSE[name]
	if mouse then
		return mouse
	end
	local ok, key = pcall(function()
		return (Enum.KeyCode :: any)[LONG[name] or name]
	end)
	return (ok and key) or Enum.KeyCode.Unknown
end

-- ── modes ───────────────────────────────────────────────────────────────────
local CANON: { [string]: string } = {
	none = "None",
	toggle = "Toggle",
	hold = "Hold",
	press = "Press",
	always = "Always",
}
-- What right-clicking a chip cycles through when the caller doesn't say.
Bind.DefaultModes = { "Toggle", "Hold", "Always" }

-- Normalize a caller-supplied mode. Case-insensitive; an unknown value warns
-- and falls back rather than killing the build over a typo.
function Bind.mode(value: any, where: string?, fallback: string?): string
	if value == nil then
		return fallback or "Toggle"
	end
	local canon = type(value) == "string" and CANON[(value :: string):lower()] or nil
	if not canon then
		Log.warn(where or "Keybind", ('Mode "%s" is not one of Toggle / Hold / Press / Always / None — using %s.')
			:format(tostring(value), fallback or "Toggle"))
		return fallback or "Toggle"
	end
	return canon
end

-- ── manager ─────────────────────────────────────────────────────────────────
function Bind.new(ctx: any): any
	local self = setmetatable({
		ctx = ctx,
		entries = {} :: { any },
		connections = {} :: { RBXScriptConnection },
		observers = {} :: { () -> () },
	}, Bind)

	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		self:_dispatch(input, gameProcessed, true)
	end))
	-- Releases are NOT gated on gameProcessed / capture: a Hold binding that went
	-- down legitimately must come back up even if focus moved to a textbox in
	-- between, or the feature sticks on with no key to turn it off.
	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		self:_dispatch(input, false, false)
	end))

	return self
end

-- The manager lives on the Context so every component can reach it. Window
-- creates it up front (and tracks its connections for teardown); this lazy
-- accessor is just so a control built outside a Window still works.
function Bind.get(ctx: any): any
	local existing = rawget(ctx, "_binds")
	if not existing then
		existing = Bind.new(ctx)
		rawset(ctx, "_binds", existing)
	end
	return existing
end

-- ── registry observers ──────────────────────────────────────────────────────
-- Anything that draws the bind list (components/Hud.lua) subscribes here rather
-- than hooking each binding's `onState` — which is already spoken for by the
-- chip that owns it. Returns an unsubscribe function; a consumer that outlives
-- nothing (a HUD is destroyed with the window) must still call it, or its dead
-- closure runs on every keypress forever.
function Bind:Observe(fn: () -> ()): () -> ()
	table.insert(self.observers, fn)
	return function()
		local list = self.observers
		for i = #list, 1, -1 do
			if list[i] == fn then
				table.remove(list, i)
				break
			end
		end
	end
end

-- Every registered binding, in registration order. A snapshot: callers are free
-- to add or drop bindings while walking it.
function Bind:List(): { any }
	return table.clone(self.entries)
end

-- Called synchronously on every change, so a HUD repaints in the same frame as
-- the key that moved it (the same reason Binding:_set paints before it spawns
-- the user callback).
function Bind:_changed()
	for _, fn in table.clone(self.observers) do
		fn()
	end
end

-- Unknown is NOT a key: it's what an unbound binding stores (a fresh chip, one
-- cleared with Backspace, a config whose key name didn't parse). The engine also
-- reports KeyCode.Unknown for keys it has no mapping for, and without this every
-- unbound binding in the window would fire on one of them at once.
-- Exported as `Bind.of` because the router isn't the only listener that has to
-- turn an InputObject into a key: Window's toggle-key listener compares against
-- one too, and comparing `input.KeyCode` alone silently ignored every mouse
-- binding (a mouse press reports KeyCode.Unknown).
function Bind.of(input: InputObject): any?
	if input.UserInputType == Enum.UserInputType.Keyboard then
		return input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode or nil
	end
	return MOUSE_NAME[input.UserInputType] and input.UserInputType or nil
end
local keyOf = Bind.of

function Bind:_dispatch(input: InputObject, gameProcessed: boolean, began: boolean)
	local key = keyOf(input)
	if not key then
		return
	end
	if began and (gameProcessed or self.ctx:IsCapturing()) then
		return -- typing into a textbox, or a chip is listening for this very press
	end
	-- A callback is free to add or destroy bindings, so walk a snapshot.
	for _, entry in table.clone(self.entries) do
		if began then
			if entry.key == key then
				entry:_press()
			end
		elseif entry._downKey == key then
			entry:_release()
		end
	end
end

-- Register a binding.
--   Key        Enum.KeyCode | mouse Enum.UserInputType   (Unknown = unbound)
--   Mode       "Toggle" | "Hold" | "Press" | "Always" | "None"
--   Modes      the cycle list a UI chip offers (defaults to Bind.DefaultModes)
--   Default    starting state for Toggle/Hold
--   Label      what to call this bind in a bind list / HUD (unnamed = hidden)
--   Hud        true / false to force it into or out of that list
--   Callback   fn(active, info) — info = { Key, Mode, KeyName }
--   OnChanged  fn(key, mode) — the bind itself changed
--   OnState    internal, synchronous paint hook (used by the chip)
--   GetState   external source of truth for Toggle mode (a Toggle's own value)
function Bind:Register(opts: any): any
	opts = opts or {}
	local where = opts.Where or "Keybind"
	local entry = setmetatable({
		manager = self,
		key = Bind.isKey(opts.Key) and opts.Key or Enum.KeyCode.Unknown,
		mode = Bind.mode(opts.Mode, where),
		modes = opts.Modes or Bind.DefaultModes,
		state = opts.Default == true,
		enabled = true,
		label = (type(opts.Label) == "string" and opts.Label ~= "") and opts.Label or nil,
		hud = opts.Hud,
		callback = opts.Callback,
		onChanged = opts.OnChanged,
		onState = opts.OnState,
		getState = opts.GetState,
		_downKey = nil :: any,
	}, Binding)
	table.insert(self.entries, entry)
	self:_changed()

	-- "Always" means on, so a control that loads in Always mode is on from the
	-- first frame without anyone touching a key. Deferred so the caller has its
	-- handle back before the callback runs.
	if entry.mode == "Always" and not entry.state then
		task.defer(function()
			if entry.mode == "Always" then
				entry:_set(true)
			end
		end)
	end
	return entry
end

function Bind:Destroy()
	for _, conn in self.connections do
		conn:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.entries)
	table.clear(self.observers)
end

-- ── binding ─────────────────────────────────────────────────────────────────
function Binding:_info(): any
	return { Key = self.key, Mode = self.mode, KeyName = Bind.name(self.key) }
end

-- The binding's idea of the current value. `getState` (a Toggle handing over its
-- own value) wins when it's there — written out rather than `getState() or state`
-- because that idiom falls through to `state` on a legitimate `false`.
function Binding:_value(): boolean
	if self.getState then
		return self.getState() == true
	end
	return self.state
end

-- Push a new activation state out: paint first (synchronous, so the UI never
-- lags a frame behind the key), then the user callback on its own thread so a
-- slow or erroring callback can't stall input dispatch.
function Binding:_set(active: boolean)
	self.state = active
	if self.onState then
		self.onState(active)
	end
	self.manager:_changed()
	if self.callback then
		task.spawn(self.callback, active, self:_info())
	end
end

-- A "Press" bind carries no state, so it blinks instead: on for a beat, then
-- back off. Same signal the chip already showed, now visible to the registry
-- too, so a HUD row flashes when a one-shot command fires.
function Binding:_pulse()
	self.state = true
	if self.onState then
		self.onState(true)
	end
	self.manager:_changed()
	task.delay(0.12, function()
		self.state = false
		if self.onState then
			self.onState(false)
		end
		self.manager:_changed()
	end)
end

function Binding:_press()
	if not self.enabled then
		return
	end
	local mode = self.mode
	if mode == "None" or mode == "Always" then
		return -- Always is on regardless of the key; None never activates
	end
	self._downKey = self.key
	if mode == "Hold" then
		self:_set(true)
	elseif mode == "Press" then
		-- Fire-and-forget command: no state to carry, so both edges read true.
		if self.callback then
			task.spawn(self.callback, true, self:_info())
		end
		self:_pulse()
	else -- Toggle
		self:_set(not self:_value())
	end
end

function Binding:_release()
	self._downKey = nil
	-- Deliberately NOT gated on `enabled`: a Hold bind that was disabled while its
	-- key was down still has to come back up, or it sticks on with `_press` now
	-- gated too — nothing left that could ever turn it off. Same reasoning as the
	-- gameProcessed exemption in the header.
	if self.mode == "Hold" and self.state then
		self:_set(false)
	end
end

function Binding:GetKey(): any
	return self.key
end

function Binding:SetKey(key: any, silent: boolean?)
	-- Re-keying with a press still outstanding strands the feature ON: _downKey is
	-- cleared below, so the old key's release matches nothing and there is no
	-- longer anything that turns it off. Drop it first. Gated on `_downKey` rather
	-- than on `state` alone — a Hold bind whose key isn't down but whose value is
	-- true is a config being restored, and that value is the caller's to keep.
	if self._downKey ~= nil and self.mode == "Hold" and self.state then
		self:_set(false)
	end
	self.key = Bind.isKey(key) and key or Enum.KeyCode.Unknown
	self._downKey = nil
	self.manager:_changed()
	if not silent and self.onChanged then
		self.onChanged(self.key, self.mode)
	end
end

function Binding:GetMode(): string
	return self.mode
end

function Binding:SetMode(mode: string, silent: boolean?)
	local previous = self.mode
	self.mode = Bind.mode(mode, "Keybind", previous)
	if self.mode == previous then
		-- _downKey deliberately untouched on a no-op: clearing it mid-hold would
		-- strand a Hold bind on. Config load calls this unconditionally whenever the
		-- saved record carries a Mode, so the no-op path is the common one.
		return
	end
	self._downKey = nil
	self.manager:_changed()
	if self.mode == "Always" then
		self:_set(true)
	elseif (self.mode == "Hold" or self.mode == "Press" or self.mode == "None") and not silent then
		-- ENTERING a mode that can't hold a value on its own. Hold's value exists
		-- only while the key is down, Press carries no value at all, and None never
		-- activates — so anything the previous mode left ON is now on with nothing
		-- holding it there and no key that can turn it off (worse for None, which
		-- also drops out of the HUD while the feature is still running). Drop it the
		-- moment the mode changes rather than making the user tap the key once just
		-- to clear it. `_downKey` was cleared just above, so there's no hold in
		-- progress to fight.
		--
		-- `silent` (only ever set by the config-restore path in BindChip:SetFlag) opts
		-- out: a saved Hold bind that was on is a value the caller chose to persist,
		-- and the load pass isn't a user flipping the mode.
		if self:_value() then
			self:_set(false)
		end
	elseif previous == "Hold" and self:_value() then
		-- Leaving Hold with the key down would strand the feature on.
		self:_set(false)
	end
	-- Leaving Always deliberately keeps whatever value it left behind — dropping
	-- straight to off would kill a feature the user only meant to re-key.
	if not silent and self.onChanged then
		self.onChanged(self.key, self.mode)
	end
end

function Binding:GetModes(): { string }
	return self.modes
end

function Binding:GetState(): boolean
	return self.state
end

function Binding:GetLabel(): string?
	return self.label
end

function Binding:SetLabel(label: string?)
	self.label = (type(label) == "string" and label ~= "") and label or nil
	self.manager:_changed()
end

-- Does this bind belong in a bind list / HUD? It needs a name — an unlabeled
-- binding is internal plumbing, and a row reading "None" tells nobody anything —
-- and a mode that can actually go live: "None" is a pure key picker (the
-- Settings tab's Toggle-UI bind), which never activates. `Hud = true/false` at
-- registration overrides both.
function Binding:IsListed(): boolean
	if self.hud ~= nil then
		return self.hud == true
	end
	return self.label ~= nil and self.mode ~= "None"
end

-- Sync the binding's idea of the value without firing the callback — used when
-- something else (a click on the toggle, a config load) moved it.
function Binding:SetState(active: boolean, fire: boolean?)
	if fire then
		self:_set(active == true)
		return
	end
	self.state = active == true
	if self.onState then
		self.onState(self.state)
	end
	self.manager:_changed()
end

function Binding:SetEnabled(enabled: boolean)
	self.enabled = enabled ~= false
	self.manager:_changed()
end

function Binding:Destroy()
	local list = self.manager.entries
	for i = #list, 1, -1 do
		if list[i] == self then
			table.remove(list, i)
			break
		end
	end
	self.callback = nil
	self.onChanged = nil
	self.onState = nil
	self.manager:_changed()
end

return Bind
