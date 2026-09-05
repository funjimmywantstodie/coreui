--!strict
-- components/Tab.lua — a sidebar nav button + a two-column content page.
--
-- The nav is icon-only (a 64px sidebar, 40px tiles), so everything that tells
-- one tab from another has to fit in that tile. The knobs, all optional:
--
--   Pin       "top" (default) / "bottom" — which end of the rail it sits at.
--   Color     a per-tab accent for the active tile / rail / dot / badge.
--   Style     "tile" (default) / "solid" / "plain" — how the active state draws.
--   Rail      false drops the accent rail in the gutter.
--   Dot       a small always-on marker (true = the tab colour, or a Color3).
--   Separator a hairline above the button, to break the rail into clusters.
--   Name/Desc/Badge  the hover flyout's three lines.
--
-- That set exists for the case the sidebar is actually bad at: one tab is
-- "universal player mods" and the next is specific to the game you're in, and
-- as a stack of grey glyphs they look like the same kind of thing. Give the two
-- clusters different colours, pin the global one to the other end, separate
-- them with a hairline, and the rail reads as two groups.
--
-- The flyout is also the tab's *name*, which the port never showed anywhere:
-- the reference mock carried it as a `data-tip` attribute on the nav button
-- (`.coreui-navbtn[data-tip]:hover::after`) and DOCS.md has always described
-- `Name` as the "sidebar label / tooltip". It mounts into `ctx.overlay`, not the
-- sidebar — the sidebar is inside `body`, and a flyout parented there would be
-- drawn under the content it has to overlap.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)
local Fade = require(script.Parent.Parent.util.Fade)
local Log = require(script.Parent.Parent.util.Log)
local Group = require(script.Parent.Group)

local M = Theme.Metrics

local PINS: { [string]: boolean } = { top = true, bottom = true }
local STYLES: { [string]: boolean } = { tile = true, solid = true, plain = true }

-- Everything `CreateTab` accepts, declared where it's read.
--
-- This list used to live in components/Window.lua as fifteen consecutive
-- `Log.field` calls, while the two normalizers below sat here — so one option's
-- contract was spread across two files and adding a knob meant editing both,
-- with nothing to notice if you only did one. Window forwards its options and
-- says nothing about their shape now.
--
-- `Pin`/`Style` are typed `string` here and *valued* by the normalizers, which
-- warn-and-default rather than fail: a wrong type is a mistake about the API, a
-- wrong string is a typo, and only the first is worth refusing to build over.
local SCHEMA: Log.Schema = {
	{ "Name", "string" },
	{ "Id", "string" },
	{ "Icon", "string" },
	{ "Desc", "string" },
	{ "Badge", "string" },
	{ "Pin", "string" },
	{ "Style", "string" },
	{ "Color", "Color3" },
	{ "Dot", { "boolean", "Color3" } },
	{ "Rail", "boolean" },
	{ "Separator", "boolean" },
	{ "Order", "number" },
	{ "Visible", "boolean" },
	{ "Callback", "function" },
}

-- Both of these are spelling-tolerant on case only ("Bottom" is a reasonable
-- thing to type) and warn-and-default on anything else, like Group's Column.
local function normalizePin(value: any, where: string): string
	if value == nil then
		return "top"
	end
	local text = type(value) == "string" and string.lower(value) or nil
	if text and PINS[text] then
		return text
	end
	Log.warn(where, ('Pin must be "top" or "bottom", got %s — pinning to the top.')
		:format(tostring(value)))
	return "top"
end

local function normalizeStyle(value: any, where: string): string
	if value == nil then
		return "tile"
	end
	local text = type(value) == "string" and string.lower(value) or nil
	if text and STYLES[text] then
		return text
	end
	Log.warn(where, ('Style must be "tile", "solid" or "plain", got %s — using "tile".')
		:format(tostring(value)))
	return "tile"
end

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
	local where = Log.where("CreateTab", opts.Name)
	Log.check(where, opts, SCHEMA)

	local label: string = opts.Name or "Tab"
	local desc: string? = opts.Desc
	local badge: string? = opts.Badge
	local pin = normalizePin(opts.Pin, where)
	local style = normalizeStyle(opts.Style, where)
	local showRail = opts.Rail ~= false
	-- `Color` overrides the window accent for this tab alone; nil follows it live.
	local tabColor: Color3? = opts.Color
	-- `Dot = true` uses the tab's colour, `Dot = Color3` picks its own.
	local dotColor: Color3? = typeof(opts.Dot) == "Color3" and opts.Dot or nil
	local showDot = opts.Dot ~= nil and opts.Dot ~= false

	-- The tab's accent weights (mark / large fill / tinted tile): its own colour
	-- if it has one, otherwise the window's live accent. A per-tab colour is
	-- derived through ctx:Shades, so it gets exactly the same treatment SetAccent
	-- gives the global one instead of a second, hand-rolled ramp.
	local function shades(): (Color3, Color3, Color3)
		if tabColor then
			local _, f, s = ctx:Shades(tabColor)
			return tabColor, f, s
		end
		return ctx.Accent, ctx.AccentFill, ctx.AccentSoft
	end

	-- nav button ──────────────────────────────────────────────────────────
	local button = Create("TextButton", {
		Name = "Nav_" .. label,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(M.navButton, M.navButton),
		BackgroundColor3 = colors.accent_soft,
		BackgroundTransparency = 1,
	}, {
		Create.corner(M.navRadius),
	})

	-- A hairline above the button, for breaking the rail into clusters. It's a
	-- sibling of the button in the nav frame (Window parents it and orders it
	-- just above), so the nav's UIListLayout spaces it like any other item.
	local separator: Frame? = nil
	if opts.Separator == true then
		separator = Create("Frame", {
			Name = "NavSeparator",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 9),
		}, {
			Create("Frame", {
				Name = "Line",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(24, 1),
				BackgroundColor3 = colors.border,
				BorderSizePixel = 0,
			}),
		})
	end

	-- No glow behind the active button: the Uranium palette is flat fills only.
	-- The active state is a *tinted* tile (accent_soft) with an accent icon on
	-- it, plus the rail below — a solid accent tile put a neon block in the
	-- sidebar of every screenshot, and it fought the primary button for the eye.
	-- (`Style = "solid"` opts back into a filled tile per tab: as one tab out of
	-- six, marking a different *class* of tab, it earns the area it takes.)
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
		Visible = showRail,
		Parent = button,
	}, {
		Create.corner(999),
	})

	-- The always-on marker. Unlike the tile and the rail it doesn't wait for the
	-- tab to be active, which is the whole point: you can tell the clusters apart
	-- without hovering or clicking. It hides *while* active, because by then the
	-- tile is already carrying the colour (and on a solid tile a same-coloured
	-- dot would simply disappear).
	local dot = Create("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -3, 0, 3),
		Size = UDim2.fromOffset(7, 7),
		BackgroundColor3 = colors.accent,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = button,
	}, {
		Create.corner(999),
		-- A chrome-coloured ring so the dot reads as a marker on the tile rather
		-- than a stray pixel touching the icon.
		Create.stroke(colors.chrome, 2),
	})

	-- The icon is a spritesheet slice, so it's pinned square: the compact sidebar
	-- (see `_layout`) resizes it, and a slice drawn into a non-square box smears.
	local function squareIcon(inst: GuiObject)
		Create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = inst })
	end
	local icon = Icons.new(opts.Icon or "gear", M.navIcon, colors.text_dim)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5);
	(icon :: any).Parent = button
	squareIcon(icon)
	local iconScale = Create("UIScale", { Parent = icon })

	-- The tab's NAME, under the icon — drawn on touch only. The sidebar is
	-- icon-only and the flyout below is the label, but touch has no hover, so on a
	-- phone every tab was an unlabeled glyph: Home, Global, Games, Settings and the
	-- game tab were five grey shapes. It's 9px and dim, wider than the tile (the
	-- sidebar clips it at its own edge), and the tile grows by LABEL_H to hold it.
	local LABEL_H = 12
	local navLabel = Create("TextLabel", {
		Name = "Label",
		Visible = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.fromOffset(M.sidebar - 4, LABEL_H),
		Text = label,
		TextColor3 = colors.text_dim,
		TextSize = 9,
		FontFace = Theme.Font.Medium,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
		Parent = button,
	})
	-- What the sidebar last asked for (Window drives it — see `_layout`).
	local layoutSpec = { size = M.navButton, icon = M.navIcon, label = false }

	-- hover flyout ────────────────────────────────────────────────────────
	-- Built on first hover, not up front: a tab that's never hovered never pays
	-- for it, and the tree it snapshots for the fade is the one it's about to
	-- show. Lives in ctx.overlay so it draws over the content, not under it.
	local TIP_GAP = 10
	local TIP_MARGIN = 4
	local TIP_MAX_W = 200
	local tip: Frame? = nil
	local tipFade: any = nil
	local tipName: TextLabel? = nil
	local tipDesc: TextLabel? = nil
	local tipBadge: Frame? = nil
	local tipBadgeText: TextLabel? = nil
	local tipSizeConn: RBXScriptConnection? = nil -- permanent (auto-size settles late)
	local tipMoveConn: RBXScriptConnection? = nil -- only while the flyout is up
	local hovering = false
	local active = false

	local function placeTip()
		local frame = tip
		if not frame or not frame.Visible then
			return
		end
		local overlay = ctx.overlay
		local o, os = overlay.AbsolutePosition, overlay.AbsoluteSize
		local b, bs = button.AbsolutePosition, button.AbsoluteSize
		local ts = frame.AbsoluteSize
		if os.X <= 0 then
			return
		end
		local x = (b.X - o.X) + bs.X + TIP_GAP
		local y = (b.Y - o.Y) + bs.Y / 2 - ts.Y / 2
		x = math.min(x, math.max(TIP_MARGIN, os.X - ts.X - TIP_MARGIN))
		y = math.clamp(y, TIP_MARGIN, math.max(TIP_MARGIN, os.Y - ts.Y - TIP_MARGIN))
		-- Whole pixels, same reason as the window itself: a flyout landing on a
		-- half pixel rasterizes its label half a pixel off the display grid.
		frame.Position = UDim2.fromOffset(math.round(x), math.round(y))
	end

	local function paintTip()
		if not (tipBadge and tipBadgeText) then
			return
		end
		local accent, _, accentSoft = shades()
		tipBadge.BackgroundColor3 = accentSoft
		tipBadgeText.TextColor3 = accent
	end

	local function buildTip()
		if tip then
			return
		end
		local frame = Create("Frame", {
			Name = "NavTip",
			Visible = false,
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = colors.pop,
			ZIndex = 70,
		}, {
			Create.corner(7),
			Create.stroke(colors.border),
			Create.padding(7, 9),
			Create.listLayout({ Padding = UDim.new(0, 3) }),
		})
		tipName = Create("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Text = label,
			TextColor3 = colors.text,
			TextSize = 12,
			FontFace = Theme.Font.Medium,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			LayoutOrder = 1,
			Parent = frame,
		}, {
			-- AutomaticSize grows the label to its text; the constraint caps the
			-- width and TextWrapped then takes over, so a long line wraps instead
			-- of running a flyout off the side of the window.
			Create("UISizeConstraint", { MaxSize = Vector2.new(TIP_MAX_W, math.huge) }),
		})
		if desc and desc ~= "" then
			tipDesc = Create("TextLabel", {
				Name = "Desc",
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				Text = desc,
				TextColor3 = colors.text_muted,
				TextSize = 11,
				FontFace = Theme.Font.Regular,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				LayoutOrder = 2,
				Parent = frame,
			}, {
				Create("UISizeConstraint", { MaxSize = Vector2.new(TIP_MAX_W, math.huge) }),
			})
		end
		if badge and badge ~= "" then
			tipBadge = Create("Frame", {
				Name = "Badge",
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundColor3 = colors.accent_soft,
				LayoutOrder = 3,
				Parent = frame,
			}, {
				Create.corner(4),
				Create.padding(2, 5),
			})
			tipBadgeText = Create("TextLabel", {
				Name = "Text",
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				Text = string.upper(badge),
				TextColor3 = colors.accent,
				TextSize = 10,
				FontFace = Theme.Font.Bold,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = tipBadge,
			})
		end
		frame.Parent = ctx.overlay
		tip = frame
		tipFade = Fade.new(frame)
		-- AutomaticSize settles a frame late, so the first place() ran against a
		-- zero size — re-place whenever it changes (which is also what covers
		-- SetName / SetDesc growing the flyout while it's up).
		tipSizeConn = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTip)
		paintTip()
	end

	local function showTip()
		if label == "" then
			return
		end
		-- With the name drawn under the icon (touch), the flyout only has a job if
		-- there's a description or a badge to carry — the name line is redundant,
		-- and a flyout that repeats what's already on the tile is noise.
		local labelled = layoutSpec.label
		if labelled and not ((desc and desc ~= "") or (badge and badge ~= "")) then
			return
		end
		buildTip()
		local frame = tip :: Frame
		if tipName then
			tipName.Visible = not labelled
		end
		frame.Visible = true
		placeTip()
		tipFade:Set(1)
		tipFade:To(Tween.Fast, 0)
		-- Only tracked while it's up: dragging the window fires this every frame
		-- and there's no reason for a hidden flyout to listen.
		if not tipMoveConn then
			tipMoveConn = button:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeTip)
		end
	end

	local function hideTip(immediate: boolean?)
		local frame = tip
		if not frame then
			return
		end
		-- The visibility read is only a "is there anything to do?" guard, and every
		-- way it can fail (the instance already destroyed, a container that refuses
		-- the read) means the answer is no. Worth a pcall because the callers are
		-- teardown paths â `tab:_hideFlyout` runs inside `Window:Destroy` â where
		-- throwing out of a no-op would be the expensive half of this function.
		local ok, visible = pcall(function()
			return frame.Visible
		end)
		if not ok or not visible then
			return
		end
		if tipMoveConn then
			tipMoveConn:Disconnect()
			tipMoveConn = nil
		end
		local function done()
			if not hovering and tip then
				tip.Visible = false
				-- Land the fade back on its resting values before hiding, exactly
				-- like Context:ClosePopover — reopening mid-fade would otherwise
				-- snapshot the half-faded labels as the new baseline.
				tipFade:Set(0)
			end
		end
		if immediate then
			tipFade:Set(1)
			done()
			return
		end
		tipFade:To(Tween.MenuOut, 1, done)
	end

	-- content page ────────────────────────────────────────────────────────
	local page = Create("Frame", {
		Name = "Page_" .. label,
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
	-- Crossfade both colour and transparency in a single tween. The old code
	-- snapped BackgroundColor3 to white instantly while the fill was still
	-- opaque (and snapped transparency to 0 on activate), so a switched-off tab
	-- showed a solid flash for one frame before fading. Idle keeps the *tint*
	-- colour and only fades the transparency, so there's no intermediate solid
	-- colour to flash — the tile simply fades in / out.
	local function paint(animate: boolean?)
		local accent, accentFill, accentSoft = shades()
		local goal, railGoal
		rail.BackgroundColor3 = accent
		dot.BackgroundColor3 = dotColor or accent
		dot.Visible = showDot and not active
		if active then
			-- "solid" fills the tile and knocks the icon out of it; "plain" drops
			-- the tile entirely and lets the icon + rail carry the state.
			local fill = style == "solid" and accentFill or accentSoft
			goal = {
				BackgroundColor3 = fill,
				BackgroundTransparency = style == "plain" and 1 or 0,
			}
			local ink = style == "solid" and colors.knockout or accent
			Icons.tint(icon, ink)
			navLabel.TextColor3 = ink
			railGoal = { Size = UDim2.fromOffset(3, 18), BackgroundTransparency = 0 }
		else
			goal = {
				-- idle (transparency 1) keeps the tint colour so the fade-out is a
				-- pure fade; hover is one step lighter than the chrome.
				BackgroundColor3 = hovering and colors.control_hi
					or (style == "solid" and accentFill or accentSoft),
				BackgroundTransparency = hovering and 0 or 1,
			}
			local ink = hovering and colors.text_muted or colors.text_dim
			Icons.tint(icon, ink)
			navLabel.TextColor3 = ink
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
		paintTip()
	end
	button.MouseEnter:Connect(function()
		hovering = true
		showTip()
		if not active then
			paint()
		end
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		hideTip()
		if not active then
			paint()
		end
	end)
	-- Touch has no hover, so the flyout shows on PRESS: up from the finger landing
	-- until it lifts or TOUCH_TIP_HOLD has passed, whichever is later. The tap
	-- still switches the tab (Activated fires on the same release). `hovering` is
	-- reused as the "keep it up" flag, so hideTip's own `done` guard holds.
	local TOUCH_TIP_HOLD = 1.2
	local touchTipToken = 0
	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		touchTipToken += 1
		local token = touchTipToken
		hovering = true
		showTip()
		local released = false
		local expired = false
		local function settle()
			if token == touchTipToken and released and expired then
				hovering = false
				hideTip()
			end
		end
		local conn: RBXScriptConnection? = nil
		conn = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
			if input.UserInputState == Enum.UserInputState.End
				or input.UserInputState == Enum.UserInputState.Cancel then
				if conn then
					conn:Disconnect()
				end
				released = true
				settle()
			end
		end)
		task.delay(TOUCH_TIP_HOLD, function()
			expired = true
			settle()
		end)
	end)
	-- A tab with its own Color is pinned to it and ignores SetAccent; everything
	-- else re-themes live.
	ctx:RegisterAccent(function()
		if not tabColor then
			paint(false)
		end
	end)

	-- Every group on this page, in build order, so the titlebar search can filter
	-- them from direct references instead of re-deriving the page's shape from
	-- instance names (see tab:Filter).
	local groups: { any } = {}

	local tab: any = {
		button = button,
		page = page,
		separator = separator,
		pin = pin,
		order = tonumber(opts.Order),
		-- Installed by Window, which owns the nav frames and the selection: one
		-- fires when this tab is hidden/shown (it may have to select another), the
		-- other when it moves between the top and bottom clusters.
		_onVisible = (nil :: any),
		_onPin = (nil :: any),
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
			-- Spawned: a Callback that errors (or yields) is the caller's problem,
			-- not something that should take the tab switch down with it.
			if opts.Callback then
				task.spawn(opts.Callback, tab)
			end
		end
	end

	function tab:IsActive(): boolean
		return active
	end

	-- ── sidebar geometry, driven by Window ───────────────────────────────────
	-- `spec = { size, icon, label }`: the tile's width (and its height without a
	-- label), the icon's size, and whether the name is drawn under the icon. The
	-- sidebar picks these per level when its clusters would overlap on a short
	-- viewport (Window.lua `fitNav`), and on touch, where the label is the only
	-- place the name exists. Idempotent: the sidebar re-runs it on every fit.
	function tab:_layout(spec: any)
		local size = tonumber(spec.size) or M.navButton
		local iconSize = tonumber(spec.icon) or M.navIcon
		local labelled = spec.label == true
		layoutSpec = { size = size, icon = iconSize, label = labelled }
		local height = size + (labelled and LABEL_H or 0)
		button.Size = UDim2.fromOffset(size, height)
		-- The icon sits in the top `size` square; the label takes the strip below.
		icon.Position = if labelled then UDim2.new(0.5, 0, 0, size / 2 + 1) else UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromOffset(iconSize, iconSize)
		if icon:IsA("TextLabel") then
			icon.TextSize = iconSize
		end
		navLabel.Visible = labelled
		if tipName then
			tipName.Visible = not labelled
		end
	end

	-- The tile's height for a given spec, for the sidebar's overflow arithmetic —
	-- computed here so the label strip's height isn't a second constant elsewhere.
	function tab:_tileHeight(spec: any): number
		return (tonumber(spec.size) or M.navButton) + (spec.label == true and LABEL_H or 0)
	end

	-- ── single column ─────────────────────────────────────────────────────────
	-- Below a content width the two columns stop being a layout (each is ~150px
	-- on a phone and every control is crushed), so column 2 stacks UNDER column 1
	-- in build order. A layout-time reflow, not a change to `Column`: the groups
	-- stay where they were built, only the column frames move. Driven by Window's
	-- per-page fit, which is the one place the content width is known.
	local stackLayout: UIListLayout? = nil
	local stacked = false
	function tab:_setStacked(value: boolean)
		value = value == true
		if value == stacked then
			return
		end
		stacked = value
		if value then
			-- A UIListLayout owns its children's Position, so the columns' anchors
			-- and scale positions have to be neutralized for it, and restored after.
			col1.AnchorPoint = Vector2.zero
			col2.AnchorPoint = Vector2.zero
			col1.Position = UDim2.new()
			col2.Position = UDim2.new()
			col1.Size = UDim2.new(1, 0, 0, 0)
			col2.Size = UDim2.new(1, 0, 0, 0)
			col1.LayoutOrder = 1
			col2.LayoutOrder = 2
			local layout = stackLayout
			if not layout then
				layout = Create.listLayout({ Padding = UDim.new(0, M.groupGap) })
				stackLayout = layout
			end
			layout.Parent = columns
		else
			if stackLayout then
				stackLayout.Parent = nil
			end
			col1.AnchorPoint = Vector2.new(0, 0)
			col1.Position = UDim2.fromScale(0, 0)
			col2.AnchorPoint = Vector2.new(1, 0)
			col2.Position = UDim2.fromScale(1, 0)
			col1.Size = UDim2.new(0.5, -(M.columnGap / 2), 0, 0)
			col2.Size = UDim2.new(0.5, -(M.columnGap / 2), 0, 0)
		end
		-- The divider only means something between two columns.
		local divider = columns:FindFirstChild("ColDivider")
		if divider then
			divider.Visible = not value
		end
	end

	function tab:_isStacked(): boolean
		return stacked
	end

	-- ── runtime customization ────────────────────────────────────────────────
	-- Everything the options table sets is also settable later, so a menu can
	-- react to what it finds (mark the game tab red when the game isn't
	-- supported, dot the tab that has features running, …).
	function tab:SetColor(color: Color3?)
		if color ~= nil and typeof(color) ~= "Color3" then
			Log.fail("SetColor", ("expects a Color3 or nil, got %s"):format(typeof(color)))
		end
		tabColor = color
		paint(false)
	end

	function tab:GetColor(): Color3
		return tabColor or ctx.Accent
	end

	function tab:SetStyle(value: string?)
		style = normalizeStyle(value, "SetStyle")
		paint(false)
	end

	function tab:SetRail(enabled: boolean)
		showRail = enabled ~= false
		rail.Visible = showRail
	end

	function tab:SetDot(value: any)
		showDot = value ~= nil and value ~= false
		dotColor = typeof(value) == "Color3" and value or nil
		paint(false)
	end

	function tab:SetIcon(name: string)
		if type(name) ~= "string" then
			Log.fail("SetIcon", ('expects an icon name, got %s (try tab:SetIcon("gear"))')
				:format(typeof(name)))
		end
		-- Icons.apply only works on an ImageLabel, and a name with no Lucide entry
		-- builds a glyph TextLabel instead — so swap the instance rather than
		-- branching on which of the two we happen to be holding.
		local fresh = Icons.new(name, M.navIcon, colors.text_dim)
		fresh.AnchorPoint = Vector2.new(0.5, 0.5)
		fresh.Position = UDim2.fromScale(0.5, 0.5)
		icon:Destroy()
		icon = fresh;
		(icon :: any).Parent = button
		squareIcon(icon)
		iconScale = Create("UIScale", { Parent = icon })
		tab:_layout(layoutSpec) -- the fresh icon takes the sidebar's current size
		paint(false)
	end

	-- Tear the flyout down so the next hover rebuilds it. Needed when a line it
	-- wasn't built with appears (a desc/badge set at runtime): the rows are only
	-- created for the lines that had content.
	local function rebuildTip()
		hideTip(true)
		if tipSizeConn then
			tipSizeConn:Disconnect()
			tipSizeConn = nil
		end
		if tipFade then
			tipFade:Destroy()
			tipFade = nil
		end
		if tip then
			tip:Destroy()
		end
		tip, tipName, tipDesc, tipBadge, tipBadgeText = nil, nil, nil, nil, nil
		if hovering then
			showTip()
		end
	end

	-- The flyout's three lines. Name is also what the button/page instances are
	-- named after, but renaming those buys nothing — the flyout is the label.
	function tab:SetName(text: string)
		Log.field("SetName", "text", text, "string")
		label = text or ""
		navLabel.Text = label
		if tipName then
			tipName.Text = label
		end
	end

	function tab:SetDesc(text: string?)
		local had = desc ~= nil and desc ~= ""
		desc = text
		if tipDesc then
			tipDesc.Text = text or ""
			tipDesc.Visible = (text ~= nil and text ~= "")
		elseif not had and text and text ~= "" then
			rebuildTip()
		end
	end

	function tab:SetBadge(text: string?)
		local had = badge ~= nil and badge ~= ""
		badge = text
		if tipBadge and tipBadgeText then
			tipBadgeText.Text = string.upper(text or "")
			tipBadge.Visible = (text ~= nil and text ~= "")
		elseif not had and text and text ~= "" then
			rebuildTip()
		end
	end

	-- Drop the flyout without waiting for a MouseLeave that may never come: the
	-- window minimizing or unloading takes the button off screen under the cursor,
	-- and a flyout left visible would still be in the window fade's snapshot —
	-- two fades writing the same transparencies (see util/Fade.lua).
	function tab:_hideFlyout()
		hovering = false
		hideTip(true)
	end

	function tab:IsVisible(): boolean
		return button.Visible
	end

	-- Hiding a tab hides its nav button (and its separator), not its page —
	-- Window decides what to select instead through `_onVisible`.
	function tab:SetVisible(value: boolean)
		local visible = value ~= false
		if button.Visible == visible then
			return
		end
		button.Visible = visible
		if separator then
			separator.Visible = visible
		end
		if not visible then
			hovering = false
			hideTip(true)
		end
		if tab._onVisible then
			tab._onVisible(visible)
		end
	end

	-- Moving between the two clusters is a reparent, which only Window can do
	-- (it owns the nav frames) — it installs `_onPin` when it mounts the tab.
	function tab:SetPin(value: string?)
		local target = normalizePin(value, "SetPin")
		if target == tab.pin then
			return
		end
		tab.pin = target
		if tab._onPin then
			tab._onPin(target)
		end
	end

	-- The tab's identity for the window's persisted group-collapse map, fixed at
	-- creation: `SetName` renames the flyout, and letting that re-key every group
	-- underneath it would quietly orphan them in configs already on disk.
	local scope: string = opts.Id or label or "Tab"

	function tab:CreateGroup(groupOpts: any)
		if groupOpts ~= nil and type(groupOpts) ~= "table" then
			Log.fail("CreateGroup", ("options must be a table like { Title = ..., Column = 1 }, got %s")
				:format(typeof(groupOpts)))
		end
		Log.field("CreateGroup", "Id", groupOpts and groupOpts.Id, "string")
		-- `Parent` scopes every bindable control in the card to one feature for the
		-- bind HUD: a name, or `true` to mean "the first bindable control here".
		Log.field("CreateGroup", "Parent", groupOpts and groupOpts.Parent, { "string", "boolean", "table" })
		-- `Section` overrides which HUD header this card's binds sit under; by
		-- default they inherit the tab's own name.
		Log.field("CreateGroup", "Section", groupOpts and groupOpts.Section, "string")
		-- Column is 1 (left) or 2 (right). A stray value (e.g. Column = 3, or a
		-- string) would silently land the group in the left column — warn and
		-- fall back so the author knows their column choice was ignored.
		local column = groupOpts and groupOpts.Column
		if column ~= nil and column ~= 1 and column ~= 2 then
			Log.warn(Log.where("CreateGroup", groupOpts and groupOpts.Title),
				("Column must be 1 (left) or 2 (right), got %s — using column 1."):format(tostring(column)))
		end
		local target = (column == 2) and col2 or col1
		-- `label`, not `scope`: the HUD header is a thing the user reads, so it's
		-- the tab's display name (and it follows `SetName`'s *initial* value the
		-- same way the flyout does — see the note on `scope` above for why the two
		-- identities aren't the same one).
		local handle = Group(ctx, target, groupOpts or {}, scope, label)
		table.insert(groups, handle)
		return handle
	end

	-- ── titlebar search ───────────────────────────────────────────────────────
	-- Show a group if its title matches; otherwise show only the fields whose text
	-- matches, and hide a group left with nothing. An empty query restores
	-- everything.
	--
	-- This lives here rather than in components/Window.lua, where it used to, for
	-- the reason spelled out on `handle._search` in Group.lua: it is entirely a
	-- statement about the page's layout, and the page is this file's. Window now
	-- asks the active tab to filter itself and knows none of it.
	--
	-- The per-field text is collected once per search SESSION, not per keystroke —
	-- `ResetFilter` is the invalidation, called when the search box is opened,
	-- which is the only moment the menu can have grown or lost controls since the
	-- last one. Caching also means the filter matches the labels a field was BUILT
	-- with rather than whatever a live value reads at this instant, which is what
	-- people are typing at. Weak keys, so a destroyed control doesn't pin its
	-- strings until the next reset.
	local searchText: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any

	local function collectText(inst: Instance): string
		local hit = searchText[inst]
		if hit then
			return hit
		end
		local parts = {}
		for _, d in inst:GetDescendants() do
			if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and d.Text ~= "" then
				table.insert(parts, d.Text)
			end
		end
		local text = string.lower(table.concat(parts, " "))
		searchText[inst] = text
		return text
	end

	function tab:ResetFilter()
		table.clear(searchText)
	end

	function tab:Filter(query: string?)
		local q = string.lower(query or "")
		for _, handle in groups do
			local entry = handle._search
			if entry then
				local groupMatch = q == "" or string.find(entry.title, q, 1, true) ~= nil
				local anyVisible = false

				-- Fields and their trailing hairlines are siblings ordered field,
				-- separator, field, separator… so filter the fields first, then
				-- re-derive each separator: visible only when the field above it
				-- survived AND some field still follows it. (Leaving separators alone
				-- stranded hairlines wherever a field was hidden; showing them all put
				-- one under the last row.)
				local ordered: { GuiObject } = {}
				for _, child in entry.card:GetChildren() do
					if child:IsA("GuiObject") then -- skip UICorner/UIStroke/UIPadding/UIListLayout
						table.insert(ordered, child)
					end
				end
				table.sort(ordered, function(a, b)
					return a.LayoutOrder < b.LayoutOrder
				end)
				for _, item in ordered do
					if item.Name ~= "Separator" then
						local matches = groupMatch
							or string.find(collectText(item), q, 1, true) ~= nil
						item.Visible = matches
						if matches then
							anyVisible = true
						end
					end
				end
				local previousVisible = false
				local lastSeparator: GuiObject? = nil
				for _, item in ordered do
					if item.Name == "Separator" then
						item.Visible = previousVisible
						if previousVisible then
							lastSeparator = item
						end
					else
						if item.Visible and lastSeparator then
							lastSeparator = nil -- a field follows it, so it stays
						end
						previousVisible = item.Visible
					end
				end
				if lastSeparator then
					lastSeparator.Visible = false -- trailing hairline, nothing below
				end

				entry.group.Visible = q == "" or groupMatch or anyVisible
			end
		end
	end

	paint(false)
	return tab
end
