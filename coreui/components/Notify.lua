--!strict
-- components/Notify.lua — bottom-right toast. Slides + fades in (0.22s), holds
-- for `Duration` (default 3.2s), slides out (0.25s), then destroys itself.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Fade = require(script.Parent.Parent.util.Fade)
local Icons = require(script.Parent.Parent.Icons)

-- Semantic notification kinds. Each colors the accent bar + adds a matching
-- icon. Anything else (incl. nil / "default") keeps the original accent-themed
-- toast with no icon. Keys are matched case-insensitively; "warn" aliases
-- "warning".
local C = Theme.Colors
local TYPES: { [string]: { color: Color3, icon: string } } = {
	success = { color = C.success, icon = "success" },
	info    = { color = C.info,    icon = "info" },
	warning = { color = C.warning, icon = "warning" },
	error   = { color = C.danger,  icon = "error" },
}

return function(ctx: any, container: Frame, opts: any)
	local colors = Theme.Colors
	opts = opts or {}

	-- Resolve the requested Type → semantic color + icon (nil = default look).
	local kind: { color: Color3, icon: string }? = nil
	if type(opts.Type) == "string" then
		local key = opts.Type:lower()
		kind = TYPES[key == "warn" and "warning" or key]
	end
	local barColor = kind and kind.color or ctx.Accent

	-- The toast is a clipping shell: the card slides horizontally inside it and
	-- is cut at the edge (no layout reflow), and the whole thing fades as a unit
	-- through util/Fade.lua. It was a CanvasGroup, which did both for free but
	-- rasterized the title and body text into a buffer and blurred them.
	local order = (container:GetAttribute("count") or 0) + 1
	container:SetAttribute("count", order)

	-- Cap the visible stack: the container grows upward with AutomaticSize, so a
	-- burst of notifications used to run off the top of the window and sit there
	-- clipped. Retire the oldest instead.
	local MAX_TOASTS = 4
	local live: { GuiObject } = {}
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") and child.Name == "Toast" then
			table.insert(live, child)
		end
	end
	if #live >= MAX_TOASTS then
		table.sort(live, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #live - MAX_TOASTS + 1 do
			live[i]:Destroy()
		end
	end

	local toast = Create("Frame", {
		Name = "Toast",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ClipsDescendants = true, -- the card slides in from off its right edge
		LayoutOrder = order,
		Parent = container,
	})

	local card = Create("Frame", {
		Name = "Card",
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.pop,
		ClipsDescendants = true,
		Parent = toast,
	}, {
		Create.corner(9),
		Create.stroke(colors.border),
	})

	-- content holds the vertical text stack; the card sizes to it. The accent
	-- bar is positioned absolutely (height tracked) so it never feeds the
	-- card's AutomaticSize — otherwise its (1,0) height would run away.
	-- A typed toast reserves a left gutter for its icon; the default keeps the
	-- original snug padding.
	local leftPad = kind and 40 or 16
	local content = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	}, {
		Create.padding(10, 13, 10, leftPad),
		Create.listLayout({ Padding = UDim.new(0, 3) }),
	})

	-- Type icon, tinted to match the bar, pinned top-left inside the gutter.
	-- Positioned absolutely so it never feeds the card's AutomaticSize.
	if kind then
		local icon = Icons.new(kind.icon, 18, kind.color)
		icon.Position = UDim2.fromOffset(13, 11)
		icon.ZIndex = 2
		icon.Parent = card
	end

	-- Scale height (1,0 on Y) fills the card natively. Scale-sized children are
	-- excluded from AutomaticSize, so the bar never feeds the card's height and
	-- can't trigger AbsoluteSizeChanged re-entrancy.
	local bar = Create("Frame", {
		Name = "AccentBar",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = barColor,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = card,
	})
	-- Only the default (accent-themed) toast tracks live accent changes; typed
	-- toasts have a fixed semantic color. A toast is transient, so drop the
	-- subscription when it dies — otherwise the registry grows by one dead
	-- closure per notification.
	local unsubscribeAccent: (() -> ())? = nil
	if not kind then
		unsubscribeAccent = ctx:RegisterAccent(function(accent)
			bar.BackgroundColor3 = accent
		end)
	end

	if opts.Title then
		Create("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = opts.Title,
			TextColor3 = colors.text,
			TextSize = 13,
			FontFace = Theme.Font.Medium,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			LayoutOrder = 1,
			Parent = content,
		})
	end

	Create("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = opts.Text or "",
		TextColor3 = colors.text_muted,
		TextSize = 12,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		LayoutOrder = 2,
		Parent = content,
	})

	-- in — the fade is built last, so its snapshot covers the finished toast.
	local fade = Fade.new(toast)
	fade:Set(1)
	fade:To(Tween.Toast, 0)
	Tween.play(card, Tween.Toast, { Position = UDim2.fromOffset(0, 0) })

	-- A toast doesn't always live to its own timer: the MAX_TOASTS cap above
	-- destroys the oldest ones outright, and the window can be unloaded at any
	-- point. Both used to leave this toast's accent subscription in the registry
	-- and its exit animation still queued — a quarter-second of tweening a
	-- destroyed subtree, and a dead closure firing on every SetAccent until the
	-- timer that was going to clean it up finally came round. Destroying is the
	-- one signal that covers every way it can go.
	local finished = false
	local function retire()
		if finished then
			return
		end
		finished = true
		if unsubscribeAccent then
			unsubscribeAccent()
			unsubscribeAccent = nil
		end
		fade:Destroy()
	end
	toast.Destroying:Connect(retire)

	-- out → destroy. Reached by the timer below, or early by a tap on the card:
	-- on a phone the stack sits where the window's buttons are, and a toast that
	-- can only wait out its timer is one more thing in the way. `leaving` makes
	-- the two paths meet once.
	local leaving = false
	local function dismiss()
		if finished or leaving then
			return -- already retired (capped out, or the window went away)
		end
		leaving = true
		Tween.play(card, Tween.ToastOut, { Position = UDim2.fromOffset(20, 0) })
		fade:To(Tween.ToastOut, 1, function()
			retire()
			toast:Destroy()
		end)
	end
	-- An invisible full-card button rather than making the card one: the card is
	-- a Frame the fade snapshots and the bar/icon sit in, and a button's own
	-- AutoButtonColor/press states have no business in it.
	local tap = Create("TextButton", {
		Name = "Dismiss",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = card,
	})
	tap.Activated:Connect(dismiss)

	-- hold → out → destroy
	task.delay(opts.Duration or 3.2, dismiss)
end
