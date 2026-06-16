--!strict
-- components/Notify.lua — bottom-right toast. Slides + fades in (0.22s), holds
-- for `Duration` (default 3.2s), slides out (0.25s), then destroys itself.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)

return function(ctx: any, container: Frame, opts: any)
	local colors = Theme.Colors
	opts = opts or {}

	-- CanvasGroup → fade every descendant at once; renders to its own buffer
	-- so the inner card's horizontal slide is clipped (no layout reflow).
	local order = (container:GetAttribute("count") or 0) + 1
	container:SetAttribute("count", order)

	local toast = Create("CanvasGroup", {
		Name = "Toast",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		GroupTransparency = 1,
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
	local content = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	}, {
		Create.padding(10, 13, 10, 16),
		Create.listLayout({ Padding = UDim.new(0, 3) }),
	})

	-- Scale height (1,0 on Y) fills the card natively. Scale-sized children are
	-- excluded from AutomaticSize, so the bar never feeds the card's height and
	-- can't trigger AbsoluteSizeChanged re-entrancy.
	local bar = Create("Frame", {
		Name = "AccentBar",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = ctx.Accent,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = card,
	})
	ctx:RegisterAccent(function(accent)
		bar.BackgroundColor3 = accent
	end)

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

	-- in
	Tween.play(toast, Tween.Toast, { GroupTransparency = 0 })
	Tween.play(card, Tween.Toast, { Position = UDim2.fromOffset(0, 0) })

	-- hold → out → destroy
	task.delay(opts.Duration or 3.2, function()
		Tween.play(card, Tween.ToastOut, { Position = UDim2.fromOffset(20, 0) })
		local out = Tween.play(toast, Tween.ToastOut, { GroupTransparency = 1 })
		out.Completed:Once(function()
			toast:Destroy()
		end)
	end)
end
