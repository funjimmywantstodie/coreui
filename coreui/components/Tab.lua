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

	local icon = Icons.new(opts.Icon or "gear", M.navIcon, colors.text_dim)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5);
	(icon :: any).Parent = button
	local iconScale = Create("UIScale", { Parent = icon })

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
		buildTip()
		local frame = tip :: Frame
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
		if not frame or not frame.Visible then
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
			Icons.tint(icon, style == "solid" and colors.knockout or accent)
			railGoal = { Size = UDim2.fromOffset(3, 18), BackgroundTransparency = 0 }
		else
			goal = {
				-- idle (transparency 1) keeps the tint colour so the fade-out is a
				-- pure fade; hover is one step lighter than the chrome.
				BackgroundColor3 = hovering and colors.control_hi
					or (style == "solid" and accentFill or accentSoft),
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
	-- A tab with its own Color is pinned to it and ignores SetAccent; everything
	-- else re-themes live.
	ctx:RegisterAccent(function()
		if not tabColor then
			paint(false)
		end
	end)

	local tab = {
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
		iconScale = Create("UIScale", { Parent = icon })
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

	paint(false)
	return tab
end
