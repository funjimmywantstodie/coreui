--!strict
-- components/Tab.lua — a sidebar nav button + a two-column content page.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)
local Group = require(script.Parent.Group)

local M = Theme.Metrics

local function newColumn(order: number): Frame
	return Create("Frame", {
		Name = "Column",
		BackgroundTransparency = 1,
		AnchorPoint = order == 2 and Vector2.new(1, 0) or Vector2.new(0, 0),
		Position = order == 2 and UDim2.fromScale(1, 0) or UDim2.fromScale(0, 0),
		Size = UDim2.new(0.5, -(M.columnGap / 2), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Create.listLayout({ Padding = UDim.new(0, M.groupGap) }),
	})
end

return function(ctx: any, opts: any)
	local colors = Theme.Colors

	-- nav button ──────────────────────────────────────────────────────────
	local button = Create("TextButton", {
		Name = "Nav_" .. (opts.Name or "Tab"),
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(M.navButton, M.navButton),
		BackgroundColor3 = colors.accent,
		BackgroundTransparency = 1,
	}, {
		Create.corner(M.navRadius),
	})

	-- Accent glow under the active button — the CSS `box-shadow: 0 6px 16px -4px
	-- accent`. A soft accent-tinted shadow image sitting behind the button
	-- (ZIndex 0, so the overflow haloes out past the button's rounded fill).
	local glow = Create("ImageLabel", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(M.navButton + 26, M.navButton + 26),
		BackgroundTransparency = 1,
		Image = "rbxassetid://6014261993",
		ImageColor3 = ctx.Accent,
		ImageTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(49, 49, 450, 450),
		ZIndex = 0,
		Parent = button,
	})

	local icon = Icons.new(opts.Icon or "gear", M.navIcon, colors.text_dim)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5);
	(icon :: any).Parent = button
	local iconScale = Create("UIScale", { Parent = icon })

	-- content page ────────────────────────────────────────────────────────
	local page = Create("Frame", {
		Name = "Page_" .. (opts.Name or "Tab"),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
	})
	local columns = Create("Frame", {
		Name = "Columns",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = page,
	})
	local col1 = newColumn(1)
	col1.Parent = columns
	local col2 = newColumn(2)
	col2.Parent = columns

	local divider = Create("Frame", {
		Name = "ColDivider",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(1, 0),
		BackgroundColor3 = colors.border_soft,
		BorderSizePixel = 0,
		Parent = columns,
	})
	columns:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		divider.Size = UDim2.fromOffset(1, columns.AbsoluteSize.Y)
	end)

	-- nav state ──────────────────────────────────────────────────────────
	local active = false
	local hovering = false
	-- Crossfade both colour and transparency in a single tween. The old code
	-- snapped BackgroundColor3 to white instantly while the fill was still
	-- opaque (and snapped transparency to 0 on activate), so a switched-off tab
	-- showed a solid flash for one frame before fading. Keeping the colour on
	-- the accent while the fill fades out means there's no intermediate solid
	-- colour to flash — the accent simply fades in / out.
	local function paint(animate: boolean?)
		local goal
		local glowGoal = { ImageTransparency = active and 0.45 or 1 }
		if active then
			goal = { BackgroundColor3 = ctx.Accent, BackgroundTransparency = 0 }
			Icons.tint(icon, colors.white)
		else
			goal = {
				-- idle (transparency 1) keeps the accent so the fade-out is a
				-- pure accent fade; only the faint hover fill uses white.
				BackgroundColor3 = hovering and colors.white or ctx.Accent,
				BackgroundTransparency = hovering and 0.92 or 1,
			}
			Icons.tint(icon, hovering and colors.text_muted or colors.text_dim)
		end
		if animate == false then
			for key, value in goal do
				(button :: any)[key] = value
			end
			glow.ImageTransparency = glowGoal.ImageTransparency
		else
			Tween.play(button, Tween.Fast, goal)
			Tween.play(glow, Tween.Fast, glowGoal)
		end
	end
	button.MouseEnter:Connect(function()
		hovering = true
		if not active then
			paint()
		end
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		if not active then
			paint()
		end
	end)
	ctx:RegisterAccent(function()
		glow.ImageColor3 = ctx.Accent
		if active then
			button.BackgroundColor3 = ctx.Accent
		end
	end)

	local tab = {
		button = button,
		page = page,
	}
	function tab:_setActive(value: boolean)
		local becameActive = value and not active
		active = value
		page.Visible = value
		paint()
		if becameActive then
			iconScale.Scale = 0.8
			Tween.play(iconScale, Tween.Spring, { Scale = 1 }) -- pop on select
		end
	end
	function tab:CreateGroup(groupOpts: any)
		local target = (groupOpts and groupOpts.Column == 2) and col2 or col1
		return Group(ctx, target, groupOpts or {})
	end

	return tab
end
