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
local Log = require(script.Parent.Log)

local Context = {}
Context.__index = Context

export type Context = typeof(setmetatable(
	{} :: {
		Theme: any,
		Accent: Color3,
		AccentHover: Color3,
		AccentFill: Color3,
		AccentSoft: Color3,
		overlay: Frame,
		Flags: { [string]: { handle: any, kind: string } },
		_consumers: { (Color3, Color3) -> () },
		_popover: { menu: Instance, catcher: Instance, conns: { RBXScriptConnection }, onClose: (() -> ())? }?,
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
		overlay = overlay,
		Flags = {},
		_consumers = {},
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

function Context:SetAccent(color: Color3)
	self.Accent = color
	self.AccentHover = hover(color)
	self.AccentFill = fill(color)
	self.AccentSoft = soft(self.Theme, color)
	for _, fn in self._consumers do
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
		encode = function(v) return v end, -- string | { string } — both JSON-safe
		decode = function(v) return v end,
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
			return nil
		end,
		decode = function(v) return v end, -- number | { number } — handle:Set resolves ids live
	},
}

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
	self.Flags[name] = { handle = handle, kind = kind }
end

-- Snapshot every flagged control into a JSON-safe table.
function Context:GetConfig(): { [string]: any }
	local data = {}
	for name, entry in self.Flags do
		local codec = Codec[entry.kind]
		local ok, value = pcall(function()
			return entry.handle:Get()
		end)
		if ok and codec then
			data[name] = codec.encode(value)
		end
	end
	return data
end

-- Apply a saved table back onto the flagged controls (fires their callbacks).
function Context:LoadConfig(data: { [string]: any })
	if type(data) ~= "table" then
		return
	end
	for name, raw in data do
		local entry = self.Flags[name]
		if entry then
			local codec = Codec[entry.kind]
			if codec then
				local okDecode, value = pcall(codec.decode, raw)
				if okDecode then
					pcall(function()
						entry.handle:Set(value)
					end)
				end
			end
		end
	end
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

	-- Fade the menu in. CanvasGroup renders its descendants to one buffer, so a
	-- single GroupTransparency tween brings the whole popover up together.
	if menu:IsA("CanvasGroup") then
		menu.GroupTransparency = 1
		Tween.play(menu, Tween.Pop, { GroupTransparency = 0 })
	end

	-- Re-place when the anchor moves, when the menu's auto-size settles, or when
	-- the window resizes.
	local conns = {
		anchor:GetPropertyChangedSignal("AbsolutePosition"):Connect(place),
		menu:GetPropertyChangedSignal("AbsoluteSize"):Connect(place),
		self.overlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(place),
	}
	self._popover = { menu = menu, catcher = catcher, conns = conns, onClose = onClose }
	catcher.Activated:Connect(function()
		self:ClosePopover()
	end)
end

function Context:IsOpen(menu: GuiObject): boolean
	return self._popover ~= nil and self._popover.menu == menu
end

return Context
