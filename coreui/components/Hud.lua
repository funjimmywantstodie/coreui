--!strict
-- components/Hud.lua — the floating bind HUD: a small draggable panel that
-- answers "what's on right now?" without opening the menu.
--
-- It reads util/Bind.lua's registry directly (`Bind:Observe` → `Bind:Entries`),
-- so it isn't a second list anyone has to maintain. The panel is exactly:
--
--     everything you asked for by name  +  every top-level feature running
--
-- "Asked for by name" is a KEY on a desktop and a PIN on a phone — the chip's
-- key half becomes a pin there (components/BindChip.lua) — and the panel treats
-- the two identically: listed while off, so the row is how you switch it on.
-- The rule itself lives in `Binding:IsListed`; the roll-up (`Parent`, `+n`) in
-- the same file. Nothing else is listed. A phone used to get every idle toggle
-- in the menu on the theory that the rows were the only way to fire one; they
-- were, and the panel was an inventory of the hub with nothing to say which
-- rows the user cared about.
--
-- A ROW IS ONE NAME AND ONE CHIP, and the chip is the row's one accent element:
--
--     desktop   Auto Parry              [ F ]        the key (and the mode, when
--               Aim Assist              [ E hold ]   it isn't a plain toggle)
--               ESP                     [ always ]
--               Infinite Jump           [ on ]       running, never keyed
--     phone     Auto Parry              [ ON  ]      the STATE, because there
--               Aim Assist              [ HOLD ]     the row is the control
--
-- Lit accent while the bind is live, exactly like the chip on the control it
-- came from. A row does what its mode says — tap flips a Toggle, tap fires a
-- Press, holding a Hold row holds it — on both devices; a desktop row is just
-- also a readout of which key does that.
--
-- Three shapes worth knowing before touching this:
--
--  * It's a SIBLING of the window frame, not a child. Minimizing the window (or
--    the toggle key) has to leave the HUD up — reading your binds with the menu
--    closed is the entire point — but it still lives in the window's ScreenGui,
--    so it dies with it.
--  * The FPS / ping readout is its OWN card under the panel: it isn't a bind
--    and it survives the collapse, which is the state you most want numbers in.
--  * Rows are POOLED and repainted in place. The registry notifies on every
--    press, so a Hold key down/up must not churn instances.

local Services = require(script.Parent.Parent.util.Services)

local RunService = Services.RunService
local UserInputService = Services.UserInputService
local Stats = Services.Stats

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Fade = require(script.Parent.Parent.util.Fade)
local Icons = require(script.Parent.Parent.Icons)
local Bind = require(script.Parent.Parent.util.Bind)
local Collapse = require(script.Parent.Parent.util.Collapse)
local Log = require(script.Parent.Parent.util.Log)
local Gui = require(script.Parent.Parent.util.Gui)

-- ── desktop ──────────────────────────────────────────────────────────────────
local WIDTH = 256
local HEADER_H = 32
local ROW_H = 26
local CHIP_H = 20
local CHIP_MIN_W = 32 -- a one-letter key still reads as a chip, not a dot
local KEY_W = 104 -- the column the chip is right-aligned in: "RShift hold" plus air
local STATS_H = 24 -- the readout bar, which is its own card under the panel
local GAP = 4      -- ...and the air between the two: close enough to read as one unit
local PAD_X = 12   -- where text starts, in the header, the rows AND the stat bar
-- A row is a tile with air around it, not a stripe that runs into the panel's
-- border: the list is inset by this, and a row pads its own text by the rest
-- (PAD_X - INSET), so the names still line up under the title.
local INSET = 6
-- One radius for the panel and the stat bar (they're one unit), a smaller one
-- for what sits inside them. The old mix (10 / 8 / 7 / 5) was four different
-- curves in a 256px box, which is a lot of what "looks off" was.
local RADIUS = 10
local ROW_RADIUS = 6
local CHIP_RADIUS = 6
local MARGIN = 8   -- keep-on-screen inset
-- ...but only for a panel that has never been dragged. Once the user grabs it
-- they may shove it OFF the edge and leave a strip behind — see `place`.
local PEEK = 28       -- the strip that must stay reachable on a desktop
local PEEK_TOUCH = 44 -- ...and on a phone, where the strip is a thumb target
local SUB_X = 12   -- a sub-option's row steps in this far under its parent
local HEAD_H = 18  -- a section header ("GLOBAL", "THIS GAME")
local MORE_H = 16  -- the "+N more" line, which sits BELOW the scroll area
local LIST_PAD = 5 -- the list's own top/bottom inset
-- ── phone ────────────────────────────────────────────────────────────────────
-- The rows are the hotbar — the only way to fire a bind at all — so they're
-- thumb-sized tiles with air between them, and the chip says the STATE rather
-- than a key nothing can press. The panel is narrower: it's on top of the game
-- the whole time it's up.
local WIDTH_TOUCH = 226
local HEADER_H_TOUCH = 44 -- the caret is the panel's only button; 32px is a mouse target
local ROW_H_TOUCH = 44
local ROW_GAP_TOUCH = 6
local PAD_X_TOUCH = 14
local INSET_TOUCH = 8
local ROW_RADIUS_TOUCH = 8
local PILL_W = 50
local PILL_H = 24
local HEAD_H_TOUCH = 26
local MORE_H_TOUCH = 24
local STATS_H_TOUCH = 32
-- The panel is a readout, not the screen. `root` is `Active`, so every pixel of
-- panel is a pixel that stops handing presses through to the game under it.
local TOUCH_SHARE = 0.62
-- How far a press may travel and still be a tap. Beyond it the gesture is a
-- drag of the panel (or, inside a phone's list, a scroll) and a Hold it started
-- is let go.
local SLOP = 8

-- One pooled row. `entry` is what it was last painted with — the press handler
-- is bound once per row and looks up what it's bound to at press time.
type Row = {
	frame: Frame,
	name: TextLabel,
	chip: TextLabel,
	chipStroke: UIStroke,
	stroke: UIStroke, -- the tile's edge; drawn on touch, where every row is a button
	corner: UICorner,
	entry: any,
	hover: boolean,
	active: boolean,
}

-- One pooled section header. The padding is held onto because the indent is
-- device-dependent and this is a plain label in a UIListLayout.
type Head = { label: TextLabel, pad: UIPadding, line: Frame }

-- The name label is RichText (for the dim "+2" roll-up count), and a label is
-- whatever the menu author called their feature — so it has to be escaped, or a
-- toggle named "HP < 50%" eats the rest of the row.
local function escape(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local SCHEMA: Log.Schema = {
	{ "Title", "string" },
	{ "X", "number" },
	{ "Y", "number" },
	{ "MaxRows", "number" },
	{ "Visible", "boolean" },
	{ "Collapsed", "boolean" },
	{ "Stats", "boolean" },
	{ "Fps", "boolean" },
	{ "Ping", "boolean" },
}

return function(ctx: any, parent: Instance, opts: any): any
	opts = opts or {}
	local colors = Theme.Colors
	Log.check("Hud", opts, SCHEMA)

	local maxRows = math.max(1, math.floor(tonumber(opts.MaxRows) or 10))
	-- `Stats = false` drops the whole readout row; Fps/Ping drop one each. The row
	-- also hides itself when nothing is in it.
	local showStats = opts.Stats ~= false
	local showFps = showStats and opts.Fps ~= false
	local showPing = showStats and opts.Ping ~= false

	local binds = Bind.get(ctx)
	local connections: { RBXScriptConnection } = {}
	local destroyed = false

	-- Built up front (its methods are filled in at the bottom) so the drag and
	-- collapse handlers can reach `handle.OnChange` — the hook Window fans out to
	-- `Window:OnHudChanged`, which is how the HUD's flag gets a change
	-- notification: everything the HUD persists moves without a control callback
	-- anywhere in sight.
	local handle: any = {}
	local function changed()
		if handle.OnChange then
			handle.OnChange()
		end
	end

	-- ── root ─────────────────────────────────────────────────────────────────
	-- Two cards stacked in one draggable unit. `root` is transparent — it owns
	-- the position, the drag, the fade and the entrance scale for both at once.
	local root = Create("Frame", {
		-- Neutral name: a direct child of the ScreenGui is as visible to a walk of
		-- the tree as the window itself (util/Gui.lua).
		Name = Gui.rname(),
		Position = UDim2.fromOffset(tonumber(opts.X) or 16, tonumber(opts.Y) or 140),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false, -- revealed below, so the fade snapshots a finished panel
		ZIndex = 10,
		-- Floats over the window and the game, so it swallows the presses that
		-- land on it. See the drag-priority registration further down, which is
		-- the half of this the window consults explicitly.
		Active = true,
		Parent = parent,
	}, {
		Create.listLayout({ Padding = UDim.new(0, GAP) }),
		Create("UIScale", {}),
	})
	local panelScale = root:FindFirstChildOfClass("UIScale") :: UIScale
	local fade = Fade.new(root)

	-- ── panel ────────────────────────────────────────────────────────────────
	-- A miniature of the window: chrome header over a bg body, one border, same
	-- radius.
	local panel = Create("Frame", {
		Name = "Panel",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.bg,
		ClipsDescendants = true,
		LayoutOrder = 1,
		Parent = root,
	}, {
		Create.corner(RADIUS),
		Create.stroke(colors.border),
		Create.listLayout(),
	})

	local header = Create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, HEADER_H),
		BackgroundColor3 = colors.chrome,
		LayoutOrder = 1,
		Parent = panel,
	}, {
		-- Round the top corners with the panel, then square off the bottom —
		-- same trick as the window titlebar.
		Create.corner(RADIUS),
	})
	local squareFill = Create("Frame", {
		Name = "SquareFill",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, RADIUS),
		BackgroundColor3 = colors.chrome,
		BorderSizePixel = 0,
		Parent = header,
	})
	local headerBorder = Create("Frame", {
		Name = "Border",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = colors.border_soft,
		BorderSizePixel = 0,
		Parent = header,
	})
	-- The header's mark is a glyph, not the accent rail it used to be. The rail
	-- was a 3×11 stub of green that belonged to nothing else on screen (the
	-- window's rail is the sidebar's active-tab mark, in a gutter); a keyboard
	-- glyph says what the panel is. It is dim at rest and LIT while anything
	-- listed is live — so a collapsed panel, which is only this header, still
	-- answers the question the panel exists for.
	local glyph = Icons.new("keyboard", 14, colors.text_dim)
	glyph.AnchorPoint = Vector2.new(0, 0.5)
	glyph.Position = UDim2.new(0, PAD_X, 0.5, 0)
	glyph.ZIndex = 2;
	(glyph :: any).Parent = header
	local title = Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PAD_X + 20, 0),
		Size = UDim2.new(1, -(PAD_X + 20 + 30), 1, 0),
		Text = opts.Title or "Keybinds",
		TextColor3 = colors.text,
		TextSize = 12,
		FontFace = Theme.Font.Bold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
		Parent = header,
	})
	-- Positioned by hand, not laid out: a UIListLayout suppresses child Rotation,
	-- and the caret spins 180° when the panel collapses.
	local caretBtn = Create("TextButton", {
		Name = "Caret",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		Text = "",
		ZIndex = 2,
		Parent = header,
	})
	local caret = Icons.new("chev", 14, colors.text_dim)
	caret.AnchorPoint = Vector2.new(0.5, 0.5)
	caret.Position = UDim2.fromScale(0.5, 0.5);
	(caret :: any).Parent = caretBtn
	caretBtn.MouseEnter:Connect(function()
		Icons.tint(caret, colors.text)
	end)
	caretBtn.MouseLeave:Connect(function()
		Icons.tint(caret, colors.text_dim)
	end)

	-- ── body (collapsible) ───────────────────────────────────────────────────
	local body = Create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Create.listLayout(),
	})

	-- The list SCROLLS, and it is capped by HEIGHT rather than by row count —
	-- ten 44px phone rows are 528px against a 360px landscape viewport, and the
	-- panel would otherwise pin to the top with its tail off the screen.
	--
	-- Sized by hand: `AutomaticSize` and `AutomaticCanvasSize` on the SAME axis
	-- of a ScrollingFrame is a documented conflict and draws nothing. `refresh`
	-- placed every row itself, so `fitList` writes the frame and canvas heights
	-- from that sum; nothing is measured, so nothing can disagree. `MaxRows`
	-- still means how many rows EXIST (what "+N more" counts); the height only
	-- decides how many you see at once.
	local listLayout = Create.listLayout()
	local listPad = Create.padding(LIST_PAD, INSET)
	local list = Create("ScrollingFrame", {
		Name = "Binds",
		Size = UDim2.new(1, 0, 0, 0),
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollingEnabled = false, -- turned on by fitList only when it overflows
		ScrollBarThickness = 0,
		ScrollBarImageColor3 = colors.scroll,
		ScrollBarImageTransparency = 0.4,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = body,
	}, {
		listPad,
		listLayout,
	})

	-- What the panel says with nothing in it — and, since the list is now only
	-- what the user asked for, HOW to put something in it. Per device, because
	-- the answer is a key on one and a pin on the other.
	local emptyPad = Create.padding(0, PAD_X - INSET)
	local empty = Create("TextLabel", {
		Name = "Empty",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, ROW_H * 2),
		Text = "",
		TextColor3 = colors.text_dim,
		TextSize = 11,
		TextWrapped = true,
		FontFace = Theme.Font.Regular,
		LayoutOrder = 1000,
		Parent = list,
	}, {
		emptyPad,
	})
	-- OUTSIDE the scroll area, pinned under it: the line that says there's more
	-- than you can see must never itself be the part you can't see.
	local more = Create("TextLabel", {
		Name = "More",
		Visible = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, MORE_H),
		Text = "",
		TextColor3 = colors.text_dim,
		TextSize = 10,
		FontFace = Theme.Font.Regular,
		LayoutOrder = 2,
		Parent = body,
	})

	local holder, setCollapsedHeight = Collapse.wrap(body, opts.Collapsed == true)
	holder.LayoutOrder = 2
	holder.Parent = panel

	-- Collapsed, the header IS the whole panel, so its bottom corners have to
	-- round with it. ClipsDescendants clips to a RECTANGLE, not to the UICorner,
	-- so the square chrome fill would poke past the panel's rounded bottom as two
	-- nubs. Hiding it hands the corners back to the header's own UICorner. The
	-- hide waits out the collapse tween; the show is immediate.
	local squareToken = 0
	local function setHeaderSquared(square: boolean, after: number?)
		squareToken += 1
		local token = squareToken
		local function apply()
			if destroyed or token ~= squareToken then
				return
			end
			squareFill.Visible = square
			headerBorder.Visible = square
		end
		if after and after > 0 then
			task.delay(after, apply)
		else
			apply()
		end
	end
	setHeaderSquared(opts.Collapsed ~= true)

	-- ── stat bar ─────────────────────────────────────────────────────────────
	-- Its own card below the panel, a sibling rather than a child, so collapsing
	-- the binds leaves the readout up.
	local statsPad = Create.padding(0, PAD_X)
	local statsBar = Create("Frame", {
		Name = "Stats",
		Visible = false,
		Size = UDim2.new(1, 0, 0, STATS_H),
		BackgroundColor3 = colors.chrome,
		LayoutOrder = 2,
		Parent = root,
	}, {
		Create.corner(RADIUS),
		Create.stroke(colors.border),
		statsPad,
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 12),
		}),
	})

	-- `key` is the trailing unit label AND the identity, so SetStat("FPS", …)
	-- updates the same pill every tick and SetStat("Coins", "1.2k") appends one.
	local statLabels: { [string]: TextLabel } = {}
	local statOrder = 0
	-- An empty bar is no bar at all — the root's list layout skips invisible
	-- children, so the gap under the panel goes with it.
	local function syncStatsRow()
		statsBar.Visible = showStats and next(statLabels) ~= nil
	end
	local function setStat(key: string, value: string?)
		local label = statLabels[key]
		if value == nil then
			if label then
				label:Destroy()
				statLabels[key] = nil
				syncStatsRow()
			end
			return
		end
		if not label then
			statOrder += 1
			label = Create("TextLabel", {
				Name = key,
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				RichText = true,
				Text = "",
				TextColor3 = colors.text,
				TextSize = ctx:IsTouch() and 12 or 11,
				FontFace = Theme.Font.Mono,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = statOrder,
				Parent = statsBar,
			}) :: TextLabel
			statLabels[key] = label
			syncStatsRow()
		end
		label.Text = ('%s<font color="#%s"> %s</font>'):format(value, colors.text_dim:ToHex(), key)
	end
	-- Seeded with dashes so FPS/MS hold the first two slots (and the row has its
	-- final height) before the first sample lands half a second later.
	if showFps then
		setStat("FPS", "—")
	end
	if showPing then
		setStat("MS", "—")
	end

	-- ── device layout ────────────────────────────────────────────────────────
	-- Everything that isn't a row, re-laid out when the device answer moves
	-- (Context:OnTouch). Rows re-lay themselves out in `paintRow`.
	local function fitChrome()
		local touch = ctx:IsTouch()
		local padX = touch and PAD_X_TOUCH or PAD_X
		local inset = touch and INSET_TOUCH or INSET
		local mark = touch and 16 or 14
		root.Size = UDim2.fromOffset(touch and WIDTH_TOUCH or WIDTH, 0)
		listLayout.Padding = UDim.new(0, touch and ROW_GAP_TOUCH or 0)
		-- Right-aligned on touch so an inset (sub-option) tile steps in from the
		-- LEFT — see paintRow. Every full-width row is `(1, 0)` either way.
		listLayout.HorizontalAlignment = touch and Enum.HorizontalAlignment.Right
			or Enum.HorizontalAlignment.Left
		header.Size = UDim2.new(1, 0, 0, touch and HEADER_H_TOUCH or HEADER_H)
		caretBtn.Size = UDim2.fromOffset(touch and 40 or 16, touch and 40 or 16)
		caretBtn.Position = UDim2.new(1, touch and -4 or -10, 0.5, 0)
		glyph.Size = UDim2.fromOffset(mark, mark)
		glyph.Position = UDim2.new(0, padX, 0.5, 0)
		title.Position = UDim2.fromOffset(padX + mark + 6, 0)
		title.TextSize = touch and 13 or 12
		title.Size = UDim2.new(1, -(padX + mark + 6 + (touch and 48 or 30)), 1, 0)
		listPad.PaddingLeft = UDim.new(0, inset)
		listPad.PaddingRight = UDim.new(0, inset)
		statsBar.Size = UDim2.new(1, 0, 0, touch and STATS_H_TOUCH or STATS_H)
		statsPad.PaddingLeft = UDim.new(0, padX)
		statsPad.PaddingRight = UDim.new(0, padX)
		for _, label in statLabels do
			label.TextSize = touch and 12 or 11
		end
		empty.Text = touch and "Nothing pinned yet.\nPin a feature from the menu to list it here."
			or "Nothing bound yet.\nBind a key to a feature to list it here."
		empty.TextSize = touch and 12 or 11
		emptyPad.PaddingLeft = UDim.new(0, padX - inset)
		emptyPad.PaddingRight = UDim.new(0, padX - inset)
		empty.Size = UDim2.new(1, 0, 0, touch and ROW_H_TOUCH + 16 or ROW_H * 2)
		more.Size = UDim2.new(1, 0, 0, touch and MORE_H_TOUCH or MORE_H)
		more.TextSize = touch and 12 or 10
	end
	fitChrome()

	-- ── rows ─────────────────────────────────────────────────────────────────
	local rows: { Row } = {}
	-- ...and the section headers between them, pooled for the same reason.
	local heads: { Head } = {}

	-- The height the list gets, and whether that means it scrolls. `content` is
	-- what `refresh` just laid out, in pixels. The budget is the viewport minus
	-- everything the panel is obliged to draw around the list, read off the same
	-- `parent.AbsoluteSize` that `place` clamps against.
	local latchDefault: () -> () = function() end -- assigned once positioning exists
	local lastContent = 0
	local function fitList(content: number?)
		if destroyed then
			return
		end
		lastContent = content or lastContent
		local touch = ctx:IsTouch()
		local vp = (parent :: any).AbsoluteSize
		-- No viewport yet (an executor can run before one reports) means no budget
		-- to clamp to: draw the whole list rather than one row of it.
		local budget = lastContent
		if vp and vp.Y > 0 then
			budget = vp.Y - MARGIN * 2 - (touch and HEADER_H_TOUCH or HEADER_H)
			if more.Visible then
				budget -= touch and MORE_H_TOUCH or MORE_H
			end
			if statsBar.Visible then
				budget -= GAP + (touch and STATS_H_TOUCH or STATS_H)
			end
			if touch then
				budget = math.min(budget, vp.Y * TOUCH_SHARE)
			end
			-- One row plus the inset is the floor: a zero-height list would leave a
			-- header with nothing under it.
			budget = math.max(budget, (touch and ROW_H_TOUCH or ROW_H) + LIST_PAD * 2)
		end
		local height = math.floor(math.min(lastContent, budget))
		list.Size = UDim2.new(1, 0, 0, height)
		list.CanvasSize = UDim2.new(0, 0, 0, math.ceil(lastContent))
		-- Scrolling only when there's something to scroll to. Off, a swipe inside
		-- the list does nothing and the press stays a tap.
		local overflow = lastContent > height + 0.5
		list.ScrollingEnabled = overflow
		list.ScrollBarThickness = overflow and 3 or 0
	end

	-- ── operating a row ──────────────────────────────────────────────────────
	-- A row is a plain Frame, deliberately: a TextButton would sink the press and
	-- the panel could no longer be dragged from its rows on a desktop. So the row
	-- only records that it was pressed, and the gesture machinery below (which
	-- sees every press on `root`) decides on release whether that was a tap.
	--
	--   Toggle   tap flips it          Press   tap fires it once
	--   Hold     down = key down, lift = key up — including a lift that slid off
	--            the row (the release listener is UserInputService's) and a press
	--            that became a drag or a scroll
	--   Always   inert — it's on; change the mode from the menu
	--
	-- Every activation goes through `ctx:User`, so a host watching OnFlagChanged
	-- sees a row tap as `source = "user"`, exactly like the key.
	local pressedRow: Row? = nil
	local holdRow: Row? = nil
	local function endHold()
		local row = holdRow
		holdRow = nil
		if row and row.entry then
			local entry = row.entry
			ctx:User(function()
				entry:Activate(false)
			end)
		end
	end
	local function rowPressed(row: Row)
		pressedRow = row
		local entry = row.entry
		if entry and entry.GetMode and entry:GetMode() == "Hold" then
			holdRow = row
			ctx:User(function()
				entry:Activate(true)
			end)
		end
	end
	local function rowTapped(row: Row)
		local entry = row.entry
		if not entry then
			return
		end
		if entry:GetMode() == "Hold" then
			endHold() -- the lift is the whole tap for a Hold
			return
		end
		ctx:User(function()
			entry:Activate(true)
		end)
	end

	-- Only the row's background moves on hover, so it isn't a full repaint. A
	-- live row keeps its fill either way; an idle one lifts to `card` under the
	-- pointer, which is what says the row is something you can click.
	local function paintHover(row: Row)
		if ctx:IsTouch() then
			return
		end
		row.frame.BackgroundTransparency = (row.hover or row.active) and 0 or 1
	end

	local function newRow(index: number): Row
		local frame = Create("Frame", {
			Name = "Bind",
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundColor3 = colors.card,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
			LayoutOrder = index,
			Parent = list,
		})
		local corner = Create.corner(ROW_RADIUS)
		corner.Parent = frame
		-- Off on a desktop (a readout row has no edge until it's hovered, and then
		-- the fill is the edge); on a phone every row is a button and the edge is
		-- what says so.
		local stroke = Create.stroke(colors.border_soft)
		stroke.Enabled = false
		stroke.Parent = frame
		local name = Create("TextLabel", {
			Name = "Name",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(PAD_X - INSET, 0),
			Size = UDim2.new(1, -((PAD_X - INSET) * 2 + KEY_W), 1, 0),
			RichText = true,
			Text = "",
			TextColor3 = colors.text_muted,
			TextSize = 12,
			FontFace = Theme.Font.Medium,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = frame,
		}) :: TextLabel
		-- The chip is ONE instance — a label with a fill — and it's the same chip
		-- on both devices: a mono key on a desktop, a bold state word on a phone.
		-- It is the row's one accent element, and it lights the way the control's
		-- own BindChip does, so the panel and the menu agree about what "live"
		-- looks like.
		local chip = Create("TextLabel", {
			Name = "Chip",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -(PAD_X - INSET), 0.5, 0),
			Size = UDim2.fromOffset(0, CHIP_H),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = colors.control,
			BorderSizePixel = 0,
			RichText = true,
			Text = "",
			TextColor3 = colors.text,
			TextSize = 11,
			FontFace = Theme.Font.Mono,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = frame,
		}, {
			Create.corner(CHIP_RADIUS),
			Create.padding(0, 8),
			Create("UISizeConstraint", { MinSize = Vector2.new(CHIP_MIN_W, CHIP_H) }),
		}) :: TextLabel
		local chipStroke = Create.stroke(colors.border)
		chipStroke.Parent = chip
		local row: Row = {
			frame = frame,
			name = name,
			chip = chip,
			chipStroke = chipStroke,
			stroke = stroke,
			corner = corner,
			entry = nil,
			hover = false,
			active = false,
		}
		frame.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				rowPressed(row)
			end
		end)
		frame.MouseEnter:Connect(function()
			row.hover = true
			paintHover(row)
		end)
		frame.MouseLeave:Connect(function()
			row.hover = false
			paintHover(row)
		end)
		return row
	end

	local function newHead(): Head
		local pad = Create.padding(0, 0, 3, PAD_X - INSET)
		local label = Create("TextLabel", {
			Name = "Section",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, HEAD_H),
			Text = "",
			TextColor3 = colors.text_dim,
			TextSize = 9,
			FontFace = Theme.Font.Bold,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Bottom, -- sits ON the rows below it
			TextTruncate = Enum.TextTruncate.AtEnd,
			Visible = false,
			Parent = list,
		}, {
			pad,
		}) :: TextLabel
		-- A hairline under the caption, so a header reads as the LID of the block
		-- below it rather than as another row of words.
		local line = Create("Frame", {
			Name = "Line",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = colors.border_soft,
			BorderSizePixel = 0,
			Parent = label,
		})
		return { label = label, pad = pad, line = line }
	end

	-- Not RichText, unlike a row's name: a section is a tab's name with nothing
	-- interpolated into it. Upper-cased because at 9px dim it has to read as a
	-- divider and not as another bind.
	local function paintHead(head: Head, text: string, order: number, first: boolean)
		local touch = ctx:IsTouch()
		head.label.Text = string.upper(text)
		head.label.Size = UDim2.new(1, 0, 0, (touch and HEAD_H_TOUCH or HEAD_H) + (first and 0 or 6))
		head.label.TextSize = touch and 10 or 9
		head.pad.PaddingLeft = UDim.new(0, touch and (PAD_X_TOUCH - INSET_TOUCH) or (PAD_X - INSET))
		head.label.LayoutOrder = order
		-- Touch rows are tiles with air between them, so a hairline there lands
		-- as a stray line in a gap; the caption alone reads as a divider.
		head.line.Visible = not touch
		head.label.Visible = true
	end

	-- What the desktop chip says. The key, first; the mode after it only when
	-- the mode changes what the key does (a plain toggle needs no word); and for
	-- a row listed without a key, the state — it's there because it's running,
	-- or because it was pinned or forced in, and "on"/"off" is the honest label.
	local dimHex = colors.text_dim:ToHex()
	local function chipTextDesktop(keyName: string, hasKey: boolean, mode: string, active: boolean): string
		if mode == "Always" then
			return "always"
		end
		local word = if mode == "Hold" then "hold" elseif mode == "Press" then "tap" else nil
		if not hasKey then
			if active then
				return "on"
			end
			return word or "off"
		end
		if not word then
			return keyName
		end
		if active then
			return keyName .. " " .. word -- all accent on the lit chip
		end
		return ('%s<font color="#%s"> %s</font>'):format(keyName, dimHex, word)
	end

	-- `sub` = this row's parent is on screen right above it, so it draws stepped
	-- in: a bound sub-option reads as belonging to the feature over it rather
	-- than as another top-level thing that's running.
	local function paintRow(row: Row, entry: any, sub: boolean)
		row.entry = entry
		local touch = ctx:IsTouch()
		-- The list is inset from the panel's edge; the row pads its text by the
		-- rest, so a name lands at PAD_X exactly like the title above it.
		local inner = (touch and PAD_X_TOUCH or PAD_X) - (touch and INSET_TOUCH or INSET)
		local rowH = touch and ROW_H_TOUCH or ROW_H
		local active = entry:GetState() == true
		local mode = entry:GetMode()
		local keyName = Bind.name(entry:GetKey())
		local hasKey = keyName ~= "None"
		local indent = sub and SUB_X or 0
		row.active = active

		local text = escape(entry:GetLabel() or "Bind")
		-- Sub-options that are on but rolled up into this row: "Aimbot +3" says
		-- the feature is running with more than its bare minimum on, without
		-- spending three rows saying it.
		local extra = entry.CountActive and entry:CountActive() or 0
		if extra > 0 then
			text ..= ('<font color="#%s"> +%d</font>'):format(dimHex, extra)
		end
		row.name.Text = text
		row.name.TextColor3 = active and colors.text or colors.text_muted

		-- Lit = live, on both devices, and lit the way the menu's own BindChip
		-- and the active nav tile are: accent text and an accent edge on an
		-- accent-TINTED fill (`ctx.AccentSoft`). Never a solid accent slab — at
		-- chip size that was the brightest thing on the screen, and a single
		-- letter sitting in it read as a warning light, not a key.
		row.chip.BackgroundColor3 = active and ctx.AccentSoft or colors.control
		row.chipStroke.Color = active and ctx.Accent or colors.border
		row.chip.Position = UDim2.new(1, -inner, 0.5, 0)

		if touch then
			-- The chip says the STATE, because here the row is the control and the
			-- question is "is this on, and what happens if I tap it?":
			--   Toggle   ON / OFF       Hold   HOLD       Press   TAP
			--   Always   ALWAYS — on, and the row can't change that
			local word = if mode == "Hold" then "HOLD"
				elseif mode == "Press" then "TAP"
				elseif mode == "Always" then "ALWAYS"
				elseif active then "ON"
				else "OFF"
			row.chip.Text = word
			row.chip.TextColor3 = active and ctx.Accent or colors.text_muted
			row.chip.TextSize = 11
			row.chip.FontFace = Theme.Font.Bold
			row.chip.AutomaticSize = Enum.AutomaticSize.None
			row.chip.Size = UDim2.fromOffset(PILL_W, PILL_H)
			row.name.Position = UDim2.fromOffset(inner, 0)
			row.name.Size = UDim2.new(1, -(inner + PILL_W + inner + 8), 1, 0)
			row.name.TextSize = 13
			-- Every row is a tile, so the list reads as a column of buttons; a
			-- running one lifts a surface step and firms its edge. A sub-option's
			-- tile is inset from the left (the list is right-aligned — fitChrome)
			-- rather than its text, because at tile sizes a text indent is invisible.
			row.frame.Size = UDim2.new(1, -indent, 0, rowH)
			row.frame.BackgroundColor3 = active and colors.pop or colors.card
			row.frame.BackgroundTransparency = 0
			row.stroke.Enabled = true
			row.stroke.Color = active and colors.border or colors.border_soft
			row.corner.CornerRadius = UDim.new(0, ROW_RADIUS_TOUCH)
		else
			row.chip.Text = chipTextDesktop(keyName, hasKey, mode, active)
			row.chip.TextColor3 = active and ctx.Accent or colors.text
			row.chip.TextSize = 11
			row.chip.FontFace = Theme.Font.Mono
			row.chip.AutomaticSize = Enum.AutomaticSize.X
			row.chip.Size = UDim2.fromOffset(0, CHIP_H)
			row.name.Position = UDim2.fromOffset(inner + indent, 0)
			row.name.Size = UDim2.new(1, -(inner + indent + KEY_W + inner), 1, 0)
			row.name.TextSize = sub and 11 or 12
			row.frame.Size = UDim2.new(1, 0, 0, rowH)
			row.frame.BackgroundColor3 = colors.card
			row.stroke.Enabled = false
			row.corner.CornerRadius = UDim.new(0, ROW_RADIUS)
			paintHover(row)
		end
		row.frame.Visible = true
	end

	-- ── refresh ──────────────────────────────────────────────────────────────
	-- Scratch state, cleared and refilled rather than reallocated: the repaint
	-- runs on every registry edge, on the input thread.
	local sListed: { any } = {}
	local sIsListed: { [any]: boolean } = {}
	local sBlocks: { any } = {}
	local sBlockOf: { [any]: any } = {}
	local sOrder: { any } = {}
	local sSubRow: { [any]: boolean } = {}
	local sActive: { any } = {}
	local sIdle: { any } = {}
	-- Section grouping: keys in first-appearance order (registration order,
	-- which is tab-build order), the reverse lookup, one bucket of blocks per
	-- key. `""` is the unheaded bucket.
	local sSecKeys: { string } = {}
	local sSecIndex: { [string]: number } = {}
	local sSecBuckets: { { any } } = {}
	local sHeadAt: { [number]: string } = {} -- the section that STARTS at row i
	-- A block is `{ entries, active, section }` — a parent and the sub-options
	-- drawn under it, kept together through the sort so an indented row can
	-- never land under an unrelated bind. Pooled; `blockUsed` is the high-water
	-- mark for this pass.
	local blockPool: { any } = {}
	local blockUsed = 0
	local function takeBlock(entry: any): any
		blockUsed += 1
		local block = blockPool[blockUsed]
		if not block then
			block = { entries = {}, active = false, pinned = false }
			blockPool[blockUsed] = block
		end
		table.clear(block.entries)
		block.entries[1] = entry
		block.active = entry:GetState() == true
		-- ROOT only, unlike `active`: a feature with a running sub-option IS
		-- running, but a pin is something the user put on one specific control,
		-- and a pinned sub-option is drawn under its parent regardless.
		block.pinned = entry.IsPinned and entry:IsPinned() == true
		-- A block's section is its ROOT's, so a pair can't split across one.
		block.section = (entry.GetSection and entry:GetSection()) or ""
		return block
	end

	-- The parent of `entry`, but only if that parent is itself on screen — a
	-- bound sub-option whose feature isn't listed has nothing to sit under.
	local function parentOf(entry: any): any?
		local parent = entry.GetParent and entry:GetParent() or nil
		return (parent and sIsListed[parent]) and parent or nil
	end

	local function refresh()
		if destroyed then
			return
		end
		local listed, isListed = sListed, sIsListed
		table.clear(listed)
		table.clear(isListed)
		table.clear(sBlockOf)
		table.clear(sOrder)
		table.clear(sSubRow)
		table.clear(sSecKeys)
		table.clear(sSecIndex)
		table.clear(sHeadAt)
		blockUsed = 0
		-- `Entries`, not `List`: nothing in this walk mutates the registry.
		for _, entry in binds:Entries() do
			if entry:IsListed() then
				table.insert(listed, entry)
				isListed[entry] = true
			end
		end

		-- Gather each listed bind under its parent, if that parent is listed too.
		-- TWO passes, because one pass silently depended on registration order: a
		-- child seen before its parent opened its own block, then the parent
		-- opened a second one, and the pair drew as two unrelated rows.
		local blocks, blockOf = sBlocks, sBlockOf
		table.clear(blocks)
		for _, entry in listed do
			if not parentOf(entry) then
				local block = takeBlock(entry)
				blockOf[entry] = block
				table.insert(blocks, block)
			end
		end
		-- ...then everything under one of them, attached to its nearest ancestor
		-- that owns a block. The hop bound is the cycle guard: `Parent` is matched
		-- by name, so nothing stops a menu from pointing two binds at each other.
		for _, entry in listed do
			if not blockOf[entry] then
				local block: any = nil
				local node, hops = parentOf(entry), 0
				while node and hops <= #listed do
					block = blockOf[node]
					if block then
						break
					end
					node = parentOf(node)
					hops += 1
				end
				if block then
					table.insert(block.entries, entry)
				else
					block = takeBlock(entry)
					table.insert(blocks, block)
				end
				blockOf[entry] = block
				block.active = block.active or entry:GetState() == true
			end
		end

		-- Filed under the part of the menu each came from (`Binding:GetSection`
		-- — the tab's name, so no menu author declares a thing).
		for _, block in blocks do
			local key: string = block.section or ""
			local index = sSecIndex[key]
			if not index then
				index = #sSecKeys + 1
				sSecKeys[index] = key
				sSecIndex[key] = index
				local bucket = sSecBuckets[index]
				if not bucket then
					bucket = {}
					sSecBuckets[index] = bucket
				end
				table.clear(bucket)
			end
			table.insert(sSecBuckets[index], block)
		end

		local touch = ctx:IsTouch()
		-- Under the cap, rows stay in registration order so nothing jumps around
		-- while you read it. Over the cap, what's LIVE has to be the part you can
		-- see, so active blocks float to the top of their section.
		--
		-- NOT ON TOUCH. There the rows are buttons the user is aiming a thumb at,
		-- and the tap that switches a feature on is exactly the event that would
		-- sort it to the top and slide everything else under the finger. A phone
		-- list scrolls instead (fitList), so nothing is unreachable for want of it.
		--
		-- On touch the float is by PIN instead, always — the panel is the hotbar
		-- and the pin is how a user puts a button on it, so what they placed has
		-- to be the part that's there without scrolling for it. Safe where the
		-- active float isn't: nothing in the HUD moves a pin (only the chip's pin
		-- half, in the menu — components/BindChip.lua), so a tap on a row changes
		-- `active` and never `pinned`, and the list under the thumb holds still.
		local floatPinned, floatActive = touch, (not touch) and #listed > maxRows
		if floatPinned or floatActive then
			for i = 1, #sSecKeys do
				-- Within a section's own bucket, never across one: `sHeadAt` is
				-- built from bucket order below and a block that moved between
				-- buckets would draw under the wrong header. Stable both halves
				-- (a two-bucket partition, not `table.sort`, which is unstable),
				-- so registration order survives inside each.
				local bucket = sSecBuckets[i]
				table.clear(sActive)
				table.clear(sIdle)
				for _, block in bucket do
					local first = if floatPinned then block.pinned else block.active
					table.insert(first and sActive or sIdle, block)
				end
				table.clear(bucket)
				for _, block in sActive do
					table.insert(bucket, block)
				end
				for _, block in sIdle do
					table.insert(bucket, block)
				end
			end
		end

		local order, subRow = sOrder, sSubRow
		for i = 1, #sSecKeys do
			local first = true
			for _, block in sSecBuckets[i] do
				for j, entry in block.entries do
					table.insert(order, entry)
					subRow[entry] = j > 1
					if first then
						sHeadAt[#order] = sSecKeys[i]
						first = false
					end
				end
			end
		end

		-- One section on screen is no grouping at all — the common case.
		local showHeads = #sSecKeys > 1
		local rowH = touch and ROW_H_TOUCH or ROW_H
		local headH = touch and HEAD_H_TOUCH or HEAD_H
		local gap = touch and ROW_GAP_TOUCH or 0
		-- `MaxRows` is a DESKTOP cap: past ten rows a readout stops being one. On
		-- a phone a row that isn't drawn is a feature the user cannot reach, so
		-- every listed bind is drawn and the height budget turns the rest into a
		-- scroll.
		local shown = touch and #order or math.min(#order, maxRows)
		-- `content` is summed as we go: it's what `fitList` sizes the frame and
		-- canvas from, and every number in it is one this loop just wrote.
		local slot, headsUsed, content = 0, 0, LIST_PAD * 2
		for i = 1, shown do
			local section = showHeads and sHeadAt[i] or nil
			if section ~= nil and section ~= "" then
				headsUsed += 1
				local head = heads[headsUsed]
				if not head then
					head = newHead()
					heads[headsUsed] = head
				end
				slot += 1
				local isFirst = headsUsed == 1 and i == 1
				paintHead(head, section, slot, isFirst)
				content += headH + (isFirst and 0 or 6)
				if slot > 1 then
					content += gap
				end
			end
			local row = rows[i]
			if not row then
				row = newRow(i)
				rows[i] = row
			end
			paintRow(row, order[i], subRow[order[i]] == true)
			slot += 1
			row.frame.LayoutOrder = slot
			content += rowH
			if slot > 1 then
				content += gap
			end
		end
		for i = shown + 1, #rows do
			rows[i].frame.Visible = false
			rows[i].entry = nil -- a hidden row can't be tapped into a stale bind
		end
		for i = headsUsed + 1, #heads do
			heads[i].label.Visible = false
		end
		empty.Visible = shown == 0
		if shown == 0 then
			content += empty.Size.Y.Offset
		end
		-- The header glyph lights while anything listed is live — the whole
		-- answer, readable even with the list folded away.
		local live = false
		for _, entry in listed do
			if entry:GetState() == true then
				live = true
				break
			end
		end
		Icons.tint(glyph, live and ctx.Accent or colors.text_dim)
		local rest = #order - shown
		more.Visible = rest > 0
		if rest > 0 then
			more.Text = ("+%d more"):format(rest)
		end
		fitList(content)
		if shown > 0 then
			latchDefault()
		end
	end

	local unsubscribeBinds = binds:Observe(refresh)
	local unsubscribeAccent = ctx:RegisterAccent(function()
		refresh() -- the lit chips (and the lit glyph) are the panel's only accent
	end)

	-- ── position ─────────────────────────────────────────────────────────────
	-- Offset-only, whole pixels: the panel is small and full of 11px text, and a
	-- half-pixel origin is what makes that text look soft.
	--
	-- Until someone puts it somewhere (an `X`/`Y` option, a drag, SetPosition, a
	-- restored flag) the panel rests at a DEFAULT that depends on the device: the
	-- desktop's (16, 140), or on a phone the right edge near the top — the
	-- desktop spot lands on the left thumbstick. Near the TOP, not centred: the
	-- panel's height is whatever the registry lists, and a centred panel slides
	-- every time that changes, under the thumb that caused it.
	local hasPos = tonumber(opts.X) ~= nil or tonumber(opts.Y) ~= nil
	local pos = Vector2.new(tonumber(opts.X) or 16, tonumber(opts.Y) or 140)
	local function defaultPos(): Vector2
		local vp = (parent :: any).AbsoluteSize
		local size = root.AbsoluteSize
		if ctx:IsTouch() and vp and vp.X > 0 then
			return Vector2.new(vp.X - size.X - MARGIN, math.round(vp.Y * 0.14))
		end
		return Vector2.new(tonumber(opts.X) or 16, tonumber(opts.Y) or 140)
	end
	-- Once derived against a panel with rows in it the default is frozen — it
	-- becomes a position like any other, and `place`'s clamp still applies.
	local defaultLatched = false
	-- The panel may be TUCKED off the edge, and on a phone that's the point of
	-- being able to move it at all: a 226px hotbar over a 360px landscape
	-- viewport is a third of the screen, and the only thing a user could do
	-- about it was collapse it (which takes the rows away — the rows ARE the
	-- feature there). So the clamp keeps a `peek` strip on screen instead of the
	-- whole panel: push it out to the left or right and a grab strip stays
	-- behind, wide enough to be a thumb target, to pull it back with.
	--
	-- Two rules, both of them about being able to get it back:
	--  * The strip is only conceded to a panel someone has PLACED (`hasPos`) —
	--    a drag, `SetPosition`, `X`/`Y`, or a restored record, which is what
	--    makes a tuck survive a reload. A panel that has never been placed
	--    lands whole on screen, so no default and no rotation can tuck one on
	--    the user's behalf.
	--  * The top edge concedes nothing, so the ceiling is unchanged. The header
	--    is the only part of a phone's panel that drags (a moving press in the
	--    list is the list's scroll), and tucking UP takes the header off first
	--    — the strip left behind would be rows, which scroll instead of
	--    dragging, and the panel could not be pulled back. Tucking down leads
	--    with the header, so it's safe, and it's the direction a hotbar in the
	--    way actually wants to go.
	local function place(p: Vector2?)
		local target: Vector2 = p or defaultPos()
		local vp = (parent :: any).AbsoluteSize
		local size = root.AbsoluteSize
		if vp and vp.X > 0 and size.X > 0 then
			local peek = if ctx:IsTouch() then PEEK_TOUCH else PEEK
			local loX, hiX = MARGIN, math.max(MARGIN, vp.X - size.X - MARGIN)
			local loY, hiY = MARGIN, math.max(MARGIN, vp.Y - size.Y - MARGIN)
			if hasPos then
				local head = if ctx:IsTouch() then HEADER_H_TOUCH else HEADER_H
				local strip = math.min(peek, size.X)
				loX = math.min(loX, strip - size.X)
				hiX = math.max(hiX, vp.X - strip)
				-- Down to a header, never past it: that's the handle back.
				hiY = math.max(hiY, vp.Y - math.min(head, size.Y))
			end
			target = Vector2.new(math.clamp(target.X, loX, hiX), math.clamp(target.Y, loY, hiY))
		end
		pos = Vector2.new(math.round(target.X), math.round(target.Y))
		root.Position = UDim2.fromOffset(pos.X, pos.Y)
	end
	-- Re-fit first: the list's ceiling comes off the viewport too, and the clamp
	-- would otherwise run against the size the panel had before the screen moved.
	local function replace()
		fitList()
		place((hasPos or defaultLatched) and pos or nil)
	end
	replace()
	-- Deferred: the default reads `root.AbsoluteSize`, and the rows the caller is
	-- still building haven't been measured on this frame.
	local latchToken = 0
	latchDefault = function()
		if hasPos or defaultLatched then
			return
		end
		latchToken += 1
		local token = latchToken
		task.defer(function()
			if destroyed or hasPos or defaultLatched or token ~= latchToken then
				return
			end
			if root.AbsoluteSize.Y <= 0 then
				return
			end
			place(nil)
			defaultLatched = true
		end)
	end
	-- A viewport change (rotation, resized window) invalidates a latched default:
	-- the edge and the fraction it was derived from both moved.
	table.insert(connections, (parent :: any):GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		defaultLatched = false
		replace()
		latchDefault()
	end))
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(replace)
	-- The device answer moving (Context:OnTouch): chrome and rows re-lay out, the
	-- listing rule's meaning changes, and an unplaced panel moves to the other
	-- default.
	local unsubscribeTouch = ctx:OnTouch(function()
		fitChrome()
		defaultLatched = false
		refresh()
		replace()
		latchDefault()
	end)

	-- ── drag + tap ───────────────────────────────────────────────────────────
	-- The HUD is on top, so a press on it is the HUD's and nothing else's. The
	-- window's titlebar asks this before it starts its own drag: `Active` is the
	-- engine's half, but the titlebar is a plain Frame dragging off `InputBegan`,
	-- and two drags fighting over one mouse is not worth leaving to hit-test
	-- order (util/Context.lua).
	local unsubscribeDrag = ctx:RegisterDragPriority(function(point: Vector2): boolean
		if not root.Visible then
			return false
		end
		local origin, size = root.AbsolutePosition, root.AbsoluteSize
		return point.X >= origin.X and point.X <= origin.X + size.X
			and point.Y >= origin.Y and point.Y <= origin.Y + size.Y
	end)

	-- One rule, and it is the same rule the window has: a press that stays put
	-- is a tap on whatever it landed on, a press that moves is a drag of the
	-- panel. The one exception is a phone's list, where a press that moves is
	-- the ScrollingFrame's scroll — the panel moves by its header and stat bar
	-- there, which are always on screen and never scroll. Nothing waits on a
	-- timer: a long press used to grab the panel, and a thumb resting on a
	-- toggle for a third of a second was dragging the hotbar instead of flipping
	-- the switch.
	local dragging = false
	local dragStart = Vector2.zero
	local dragOrigin = pos
	local dragMoved = false
	local gestureInput: InputObject? = nil
	local gestureInList = false
	local scrolling = false
	local function grab()
		dragMoved = true
		hasPos = true -- the user has an opinion about where it goes now
		pressedRow = nil
	end
	local function beginGesture(input: InputObject, inList: boolean)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		-- The list is inside `root`, so one press reaches both handlers. Whichever
		-- lands first opens the gesture; the other only adds what it knows.
		if gestureInput == input then
			gestureInList = gestureInList or inList
			return
		end
		gestureInput = input
		gestureInList = inList
		dragging = true
		dragMoved = false
		scrolling = false
		dragStart = Vector2.new(input.Position.X, input.Position.Y)
		dragOrigin = pos
	end
	root.InputBegan:Connect(function(input)
		beginGesture(input, false)
	end)
	list.InputBegan:Connect(function(input)
		beginGesture(input, true)
	end)

	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
			if not dragMoved and not scrolling and math.abs(delta.X) + math.abs(delta.Y) > SLOP then
				-- A press that moved was never a tap — and a Hold it started has to
				-- let go, or the feature runs for as long as the panel is held.
				pressedRow = nil
				endHold()
				if gestureInList and ctx:IsTouch() then
					scrolling = true -- the ScrollingFrame's, not ours
				else
					grab()
				end
			end
			-- The panel only moves once the gesture is a drag: a thumb that wobbles
			-- 3px on a tap must not nudge the hotbar it's tapping.
			if dragMoved then
				place(dragOrigin + delta)
			end
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			local wasDragging = dragging
			dragging = false
			if gestureInput == input then
				gestureInput = nil
			end
			gestureInList = false
			scrolling = false
			-- Announced on RELEASE, not per frame: the position is part of the HUD's
			-- persisted record, and a host writing on every change would write
			-- sixty times a second across a drag.
			if wasDragging and dragMoved then
				ctx:User(changed)
			end
			-- A press that stayed put is a tap on whatever row it landed on. Every
			-- release ends a Hold, including one whose finger slid off the row.
			local tapped = pressedRow
			pressedRow = nil
			if wasDragging and not dragMoved and tapped then
				rowTapped(tapped)
			else
				endHold()
			end
			-- The caret is a TextButton and sinks input, so a click on it never
			-- reaches root.InputBegan to reset the flag — after any drag, the NEXT
			-- caret click would be swallowed as "that was a drag". Deferred because
			-- Activated fires on this same release and has to still see it.
			task.defer(function()
				dragMoved = false
			end)
		end
	end))

	-- ── FPS / ping ───────────────────────────────────────────────────────────
	-- One connection, sampled twice a second: a per-frame label write costs more
	-- than the whole rest of the HUD, and a jittering number is unreadable.
	-- Skipped while hidden — but NOT while collapsed: the bar stays on screen.
	local visible = opts.Visible ~= false
	local collapsed = opts.Collapsed == true
	if showFps or showPing then
		local frames, elapsed = 0, 0
		table.insert(connections, RunService.Heartbeat:Connect(function(dt)
			frames += 1
			elapsed += dt
			if elapsed < 0.5 then
				return
			end
			local fps = math.floor(frames / elapsed + 0.5)
			frames, elapsed = 0, 0
			if not visible then
				return
			end
			if showFps then
				setStat("FPS", tostring(fps))
			end
			if showPing then
				-- Not every executor/place exposes the network stats item.
				local ok, ms = pcall(function()
					return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
				end)
				setStat("MS", (ok and type(ms) == "number") and tostring(math.floor(ms + 0.5)) or "—")
			end
		end))
	end

	-- ── handle ───────────────────────────────────────────────────────────────
	handle.Frame = root  -- the whole unit: panel + stat bar
	handle.Panel = panel
	handle.OnVisible = nil :: ((boolean) -> ())? -- Window syncs its settings toggle through this

	function handle:IsVisible(): boolean
		return visible
	end

	-- `animate = false` snaps (used by config load, which shouldn't play an
	-- animation for state the user set in a previous session).
	function handle:SetVisible(value: boolean, animate: boolean?)
		if destroyed then
			return
		end
		value = value ~= false
		-- Already there, and the panel agrees — nothing to do. `root.Visible` is
		-- part of the test on purpose: the deferred first reveal at the bottom of
		-- this file calls SetVisible(true) precisely when `visible` is already
		-- true and the panel is still hidden, and that call has to go through.
		if value == visible and root.Visible == value then
			return
		end
		visible = value
		if value then
			root.Visible = true
			-- Repaint once the fade lands: rows that changed state while the panel
			-- was hidden were driven by the fade's snapshot, not by their own paint.
			if animate == false then
				fade:Set(0)
				panelScale.Scale = 1
				refresh()
			else
				-- Back to rest FIRST, which releases the snapshot the hide left held:
				-- rows registered while hidden aren't in it and would sit fully
				-- opaque while everything around them fades in.
				fade:Set(0)
				fade:Set(1)
				panelScale.Scale = 0.94
				Tween.play(panelScale, Tween.Pop, { Scale = 1 })
				fade:To(Tween.Normal, 0, refresh)
			end
			replace()
		elseif animate == false then
			root.Visible = false
		else
			Tween.play(panelScale, Tween.MenuOut, { Scale = 0.94 })
			fade:To(Tween.MenuOut, 1, function()
				if not visible then
					root.Visible = false
				end
			end)
		end
		if handle.OnVisible then
			handle.OnVisible(visible)
		end
		changed()
	end

	function handle:Show()
		handle:SetVisible(true)
	end
	function handle:Hide()
		handle:SetVisible(false)
	end

	function handle:IsCollapsed(): boolean
		return collapsed
	end

	function handle:SetCollapsed(value: boolean, animate: boolean?)
		value = value == true
		if value == collapsed then
			return
		end
		collapsed = value
		setCollapsedHeight(collapsed, animate ~= false)
		setHeaderSquared(not collapsed, (collapsed and animate ~= false) and Tween.Slide.Time or 0)
		-- `animate = false` (a config load) has to snap the caret too.
		if animate == false then
			caret.Rotation = collapsed and 180 or 0
		else
			Tween.play(caret, Tween.Spin, { Rotation = collapsed and 180 or 0 })
		end
		changed()
	end

	function handle:SetTitle(text: string)
		title.Text = tostring(text)
	end

	-- Add / update / remove a stat pill next to FPS and MS. `SetStat("Coins",
	-- nil)` drops it again.
	function handle:SetStat(key: string, value: any)
		if type(key) ~= "string" or key == "" then
			return
		end
		setStat(key, value ~= nil and tostring(value) or nil)
	end

	function handle:GetPosition(): Vector2
		return pos
	end
	function handle:SetPosition(x: number, y: number)
		hasPos = true
		place(Vector2.new(tonumber(x) or pos.X, tonumber(y) or pos.Y))
		changed()
	end

	function handle:Refresh()
		refresh()
	end

	-- Config: the HUD persists as a small record rather than a bare value, so a
	-- saved config restores where you put it and whether it was up at all
	-- (util/Context.lua `hud` codec).
	function handle:GetFlag(): any
		return { Visible = visible, Collapsed = collapsed, X = pos.X, Y = pos.Y }
	end
	function handle:SetFlag(value: any)
		if type(value) ~= "table" then
			return
		end
		if tonumber(value.X) and tonumber(value.Y) then
			hasPos = true -- a saved spot beats the device default
			place(Vector2.new(tonumber(value.X) :: number, tonumber(value.Y) :: number))
		end
		if value.Collapsed ~= nil then
			handle:SetCollapsed(value.Collapsed == true, false)
		end
		if value.Visible ~= nil then
			handle:SetVisible(value.Visible == true, false)
		end
		-- A record that only moved the panel gets no notification from the setters
		-- above, and a host mirroring the HUD needs to hear about a restore either
		-- way. Deduped downstream by value.
		changed()
	end

	function handle:Destroy()
		if destroyed then
			return
		end
		destroyed = true
		for _, conn in connections do
			conn:Disconnect()
		end
		table.clear(connections)
		unsubscribeBinds()
		unsubscribeAccent()
		unsubscribeDrag()
		unsubscribeTouch()
		endHold() -- a Hold the finger still has down must not outlive the panel
		root:Destroy()
	end

	-- The caret is inside the drag surface, so a drag that happens to start on it
	-- must not also collapse the panel when the button comes back up.
	caretBtn.Activated:Connect(function()
		if dragMoved then
			dragMoved = false
			return
		end
		ctx:User(function()
			handle:SetCollapsed(not collapsed)
		end)
	end)

	refresh()
	if collapsed then
		caret.Rotation = 180
	end
	-- Reveal on a deferred pass: the fade has to snapshot a finished panel, and
	-- the caller's controls (and therefore its binds) are usually still being
	-- built at this point. `not root.Visible` so a caller that already showed it
	-- on this frame doesn't get the entrance played twice.
	if visible then
		task.defer(function()
			if not destroyed and visible and not root.Visible then
				handle:SetVisible(true)
			end
		end)
	end

	return handle
end
