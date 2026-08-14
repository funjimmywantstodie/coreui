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
-- `Enum.UserInputType.MouseButton2` as the key), though the click-to-rebind UI
-- only captures keyboard keys — a click there means "cancel".

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

local function keyOf(input: InputObject): any?
	if input.UserInputType == Enum.UserInputType.Keyboard then
		return input.KeyCode
	end
	return MOUSE_NAME[input.UserInputType] and input.UserInputType or nil
end

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
		callback = opts.Callback,
		onChanged = opts.OnChanged,
		onState = opts.OnState,
		getState = opts.GetState,
		_downKey = nil :: any,
	}, Binding)
	table.insert(self.entries, entry)

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
end

-- ── binding ─────────────────────────────────────────────────────────────────
function Binding:_info(): any
	return { Key = self.key, Mode = self.mode, KeyName = Bind.name(self.key) }
end

-- Push a new activation state out: paint first (synchronous, so the UI never
-- lags a frame behind the key), then the user callback on its own thread so a
-- slow or erroring callback can't stall input dispatch.
function Binding:_set(active: boolean)
	self.state = active
	if self.onState then
		self.onState(active)
	end
	if self.callback then
		task.spawn(self.callback, active, self:_info())
	end
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
		if self.onState then
			self.onState(true)
			task.delay(0.12, function()
				if self.onState then
					self.onState(false)
				end
			end)
		end
	else -- Toggle
		local current = self.getState and self.getState() or self.state
		self:_set(not current)
	end
end

function Binding:_release()
	self._downKey = nil
	if self.mode == "Hold" and self.enabled and self.state then
		self:_set(false)
	end
end

function Binding:GetKey(): any
	return self.key
end

function Binding:SetKey(key: any, silent: boolean?)
	self.key = Bind.isKey(key) and key or Enum.KeyCode.Unknown
	self._downKey = nil
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
	self._downKey = nil
	if self.mode == previous then
		return
	end
	if self.mode == "Always" then
		self:_set(true)
	elseif previous == "Hold" and self.state then
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
end

function Binding:SetEnabled(enabled: boolean)
	self.enabled = enabled ~= false
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
end

return Bind
