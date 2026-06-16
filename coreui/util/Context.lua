--!strict
-- util/Context.lua — the object threaded through every component.
--
-- Carries the live accent color (themeable via Window:SetAccent), an accent
-- subscription registry, and the single-popover manager used by dropdowns and
-- color pickers (menus mount into a high-ZIndex overlay so they escape the
-- scrolling content's clipping).

local Create = require(script.Parent.Create)
local Tween = require(script.Parent.Tween)

local Context = {}
Context.__index = Context

export type Context = typeof(setmetatable(
	{} :: {
		Theme: any,
		Accent: Color3,
		AccentHover: Color3,
		overlay: Frame,
		_consumers: { (Color3, Color3) -> () },
		_popover: { menu: Instance, catcher: Instance, conns: { RBXScriptConnection }, onClose: (() -> ())? }?,
	},
	Context
))

local function hover(accent: Color3): Color3
	return accent:Lerp(Color3.new(1, 1, 1), 0.3)
end

function Context.new(theme: any, overlay: Frame, accent: Color3): Context
	return setmetatable({
		Theme = theme,
		Accent = accent,
		AccentHover = hover(accent),
		overlay = overlay,
		_consumers = {},
		_popover = nil,
	}, Context)
end

-- Register a function recolored whenever the accent changes. Called once now
-- with the current accent so callers don't duplicate the initial paint.
function Context:RegisterAccent(fn: (Color3, Color3) -> ())
	table.insert(self._consumers, fn)
	fn(self.Accent, self.AccentHover)
end

function Context:SetAccent(color: Color3)
	self.Accent = color
	self.AccentHover = hover(color)
	for _, fn in self._consumers do
		fn(self.Accent, self.AccentHover)
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
