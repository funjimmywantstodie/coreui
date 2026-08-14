--!strict
-- components/Tab.lua — a sidebar nav button + a two-column content page.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)
local Log = require(script.Parent.Parent.util.Log)
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
		BackgroundColor3 = colors.accent_soft,
		BackgroundTransparency = 1,
	}, {
		Create.corner(M.navRadius),
	})

	-- No glow behind the active button: the Uranium palette is flat fills only.
	-- The active state is a *tinted* tile (accent_soft) with an accent icon on
	-- it, plus the rail below — a solid accent tile put a neon block in the
	-- sidebar of every screenshot, and it fought the primary button for the eye.
	--
	-- The rail is the loud half of the active state, and it can afford to be:
	-- it's 3×18px. It lives in the sidebar gutter left of the button (the nav
	-- frame doesn't clip), and grows out of nothing on select.
	local rail = Create("Frame", {
		Name = "Rail",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, -9, 0.5, 0),
		Size = UDim2.fromOffset(3, 0),
		BackgroundColor3 = colors.accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = button,
	}, {
		Create.corner(999),
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

	-- Scale height (1,0 on Y) so the divider fills the column block natively.
	-- Roblox excludes scale-sized children from a parent's AutomaticSize, so this
	-- can't feed back into `columns` and trigger AbsoluteSizeChanged re-entrancy
	-- (the old signal-driven offset height oscillated on subpixel rounding).
	Create("Frame", {
		Name = "ColDivider",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = colors.border_soft,
		BorderSizePixel = 0,
		Parent = columns,
	})

	-- nav state ──────────────────────────────────────────────────────────
	local active = false
	local hovering = false
	-- Crossfade both colour and transparency in a single tween. The old code
	-- snapped BackgroundColor3 to white instantly while the fill was still
	-- opaque (and snapped transparency to 0 on activate), so a switched-off tab
	-- showed a solid flash for one frame before fading. Idle keeps the *tint*
	-- colour and only fades the transparency, so there's no intermediate solid
	-- colour to flash — the tile simply fades in / out.
	local function paint(animate: boolean?)
		local goal, railGoal
		rail.BackgroundColor3 = ctx.Accent
		if active then
			goal = { BackgroundColor3 = ctx.AccentSoft, BackgroundTransparency = 0 }
			Icons.tint(icon, ctx.Accent) -- the icon carries the colour, not the tile
			railGoal = { Size = UDim2.fromOffset(3, 18), BackgroundTransparency = 0 }
		else
			goal = {
				-- idle (transparency 1) keeps the tint colour so the fade-out is a
				-- pure fade; hover is one step lighter than the chrome.
				BackgroundColor3 = hovering and colors.control_hi or ctx.AccentSoft,
				BackgroundTransparency = hovering and 0 or 1,
			}
			Icons.tint(icon, hovering and colors.text_muted or colors.text_dim)
			railGoal = { Size = UDim2.fromOffset(3, 0), BackgroundTransparency = 1 }
		end
		if animate == false then
			for key, value in goal do
				(button :: any)[key] = value
			end
			for key, value in railGoal do
				(rail :: any)[key] = value
			end
		else
			Tween.play(button, Tween.Fast, goal)
			-- Overshoot on the way in only: Back easing on the way *out* would
			-- pull the height below zero before settling.
			Tween.play(rail, active and Tween.Spring or Tween.Fast, railGoal)
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
		rail.BackgroundColor3 = ctx.Accent
		if active then
			button.BackgroundColor3 = ctx.AccentSoft
			Icons.tint(icon, ctx.Accent)
		end
	end)

	local tab = {
		button = button,
		page = page,
	}

	-- The page's resting position is captured once, on first activation (Window
	-- sets it before selecting the first tab). Re-reading page.Position on every
	-- activation meant a fast tab switch sampled a mid-tween value and adopted it
	-- as "rest", so the page crept further down the screen with each switch.
	local restPos: UDim2? = nil
	local slideTween: Tween? = nil

	function tab:_setActive(value: boolean)
		local becameActive = value and not active
		active = value
		page.Visible = value
		paint()
		if becameActive then
			iconScale.Scale = 0.8
			Tween.play(iconScale, Tween.Spring, { Scale = 1 }) -- pop on select
			-- ease the page up into place so switching tabs settles instead of
			-- hard-cutting (rest position is set by Window; nudge down, slide back)
			local rest = restPos or page.Position
			restPos = rest
			if slideTween then
				slideTween:Cancel()
			end
			page.Position = rest + UDim2.fromOffset(0, 10)
			slideTween = Tween.play(page, Tween.Normal, { Position = rest })
		end
	end
	function tab:CreateGroup(groupOpts: any)
		if groupOpts ~= nil and type(groupOpts) ~= "table" then
			Log.fail("CreateGroup", ("options must be a table like { Title = ..., Column = 1 }, got %s")
				:format(typeof(groupOpts)))
		end
		-- Column is 1 (left) or 2 (right). A stray value (e.g. Column = 3, or a
		-- string) would silently land the group in the left column — warn and
		-- fall back so the author knows their column choice was ignored.
		local column = groupOpts and groupOpts.Column
		if column ~= nil and column ~= 1 and column ~= 2 then
			Log.warn(Log.where("CreateGroup", groupOpts and groupOpts.Title),
				("Column must be 1 (left) or 2 (right), got %s — using column 1."):format(tostring(column)))
		end
		local target = (column == 2) and col2 or col1
		return Group(ctx, target, groupOpts or {})
	end

	return tab
end
