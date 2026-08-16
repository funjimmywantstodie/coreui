--!strict
-- components/Hud.lua — the floating bind HUD: a small draggable panel that
-- answers "what's on right now?" without opening the menu.
--
-- It reads util/Bind.lua's registry directly (`Bind:Observe` → `Bind:List`), so
-- it isn't a second list anyone has to maintain: every Toggle, every
-- activation-mode `Keybind` control and every `Window:Bind` shows up the moment
-- it has a key on it *or* is switched on, and lights while it's live. The
-- controls pass the `Label` from their own `Name`, so nothing has to be declared
-- twice.
--
-- What it deliberately does NOT show is every bindable feature in the menu:
-- that's a wall of unbound, idle rows that buries the few you actually use. The
-- inclusion rule lives in `Binding:IsListed` — a key, or currently active and
-- not a sub-option of something else — so the panel is "everything bound, plus
-- every top-level feature running".
--
-- That last clause is the roll-up. Bindings form a shallow tree (a control
-- declares `Parent = "<feature>"`, or inherits one from its Group / Section),
-- because turning Aimbot on means turning on the handful of sub-options that
-- make it work — and listing each of those as its own row said nothing the
-- "Aimbot" row above them didn't. A rolled-up sub-option shows as a `+n` count
-- on its parent instead; one the user put a key on is listed anyway, indented
-- under that parent, because a key is them asking for it by name.
--
-- Three deliberate shapes here:
--
--  * It's a SIBLING of the window frame, not a child. Minimizing the window (or
--    the toggle key) has to leave the HUD up — being able to read your binds
--    with the menu closed is the entire point — but it still lives in the
--    window's ScreenGui, so it dies with it and needs no teardown of its own
--    beyond its input connections.
--  * The FPS / ping readout is its OWN card under the panel, not a row inside
--    it — it isn't a bind and it doesn't come from the registry. Being outside
--    the collapsing body is the point: fold the binds away and the numbers stay.
--  * Rows are POOLED and repainted in place. The registry notifies on every
--    press, so a Hold key down/up must not churn instances.
--  * One accent element per row (the live dot). An active row lifts to `card`
--    instead of tinting accent, so a screen full of active binds still reads as
--    a list rather than a wall of green.

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

local WIDTH = 248
local HEADER_H = 30
local ROW_H = 22
local STATS_H = 26 -- the readout bar, which is its own card under the panel
local GAP = 6      -- ...and the air between the two
local PAD_X = 12
local NAME_X = 26
local KEY_W = 110 -- right column: "RShift · always" in 11px mono, with room to spare
local MARGIN = 8  -- keep-on-screen inset
local SUB_X = 12  -- how far a sub-option's row is indented under its parent

-- One pooled bind row: dot (live marker) · name · "KEY · mode".
type Row = { frame: Frame, dot: Frame, name: TextLabel, key: TextLabel }

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
	-- also hides itself when nothing is in it, so turning both off (and never
	-- calling SetStat) doesn't leave an empty strip and a hairline behind.
	local showStats = opts.Stats ~= false
	local showFps = showStats and opts.Fps ~= false
	local showPing = showStats and opts.Ping ~= false

	local binds = Bind.get(ctx)
	local connections: { RBXScriptConnection } = {}
	local destroyed = false

	-- Built up front (its methods are filled in at the bottom) so the drag and
	-- collapse handlers below can reach `handle.OnChange` — the hook Window fans
	-- out to `Window:OnHudChanged`, which is how the HUD's flag gets a change
	-- notification. Everything the HUD persists (where it is, whether it's folded,
	-- whether it's up) moves without a control callback anywhere in sight, so
	-- there'd otherwise be nothing to hang one on.
	local handle: any = {}
	local function changed()
		if handle.OnChange then
			handle.OnChange()
		end
	end

	-- ── root ─────────────────────────────────────────────────────────────────
	-- Two cards stacked in one draggable unit: the bind panel, and the FPS/ping
	-- readout as its own bar beneath it. `root` is transparent — it exists to own
	-- the position, the drag, the fade and the entrance scale for both at once.
	local root = Create("Frame", {
		-- Neutral name: the HUD is a direct child of the ScreenGui, so it's as
		-- visible to a walk of the tree as the window itself (util/Gui.lua).
		Name = Gui.rname(),
		Position = UDim2.fromOffset(tonumber(opts.X) or 16, tonumber(opts.Y) or 140),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false, -- revealed below, so the fade snapshots a finished panel
		ZIndex = 10,
		Parent = parent,
	}, {
		Create.listLayout({ Padding = UDim.new(0, GAP) }),
		Create("UIScale", {}),
	})
	local panelScale = root:FindFirstChildOfClass("UIScale") :: UIScale
	local fade = Fade.new(root)

	-- ── panel ────────────────────────────────────────────────────────────────
	-- A miniature of the window: chrome header over a bg body, one border, same
	-- radius. It reads as part of the same UI without being a second window.
	local panel = Create("Frame", {
		Name = "Panel",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.bg,
		ClipsDescendants = true,
		LayoutOrder = 1,
		Parent = root,
	}, {
		Create.corner(10),
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
		-- same trick as the window titlebar (util note in Window.lua).
		Create.corner(10),
	})

	local squareFill = Create("Frame", {
		Name = "SquareFill",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 10),
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

	local rail = Create("Frame", {
		Name = "Rail",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, PAD_X, 0.5, 0),
		Size = UDim2.fromOffset(3, 11),
		BackgroundColor3 = ctx.Accent,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = header,
	}, {
		Create.corner(2),
	})

	local title = Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(NAME_X - 4, 0),
		Size = UDim2.new(1, -(NAME_X + 26), 1, 0),
		Text = opts.Title or "Active Binds",
		TextColor3 = colors.text,
		TextSize = 11,
		FontFace = Theme.Font.Bold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
		Parent = header,
	})

	-- The caret is positioned by hand, not laid out: a UIListLayout suppresses
	-- child Rotation, and this one spins 180° when the panel collapses.
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
	-- "chev" (up) at rest, spun 180° when collapsed — the same direction and the
	-- same Tween.Spin the group / section headers use.
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

	local list = Create("Frame", {
		Name = "Binds",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = body,
	}, {
		Create.padding(5, 0),
		Create.listLayout(),
	})

	local empty = Create("TextLabel", {
		Name = "Empty",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, ROW_H),
		Text = "Nothing bound yet",
		TextColor3 = colors.text_dim,
		TextSize = 11,
		FontFace = Theme.Font.Regular,
		LayoutOrder = 1000,
		Parent = list,
	})
	local more = Create("TextLabel", {
		Name = "More",
		Visible = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Text = "",
		TextColor3 = colors.text_dim,
		TextSize = 10,
		FontFace = Theme.Font.Regular,
		LayoutOrder = 1001,
		Parent = list,
	})

	local holder, setCollapsedHeight = Collapse.wrap(body, opts.Collapsed == true)
	holder.LayoutOrder = 2
	holder.Parent = panel

	-- Collapsed, the header IS the whole panel, so its bottom corners have to
	-- round with it. ClipsDescendants clips to a RECTANGLE, not to the UICorner
	-- shape (see the same note in Window.lua), so the square chrome fill would
	-- otherwise poke past the panel's rounded bottom corners as two little nubs
	-- with the divider hairline drawn straight across them. Hiding both hands the
	-- corners back to the header's own UICorner, which matches the panel's radius.
	-- The hide waits out the collapse tween (the header's bottom isn't the panel's
	-- bottom until then); the show has to be immediate, before the body slides in
	-- behind it.
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
	-- FPS / ping is NOT a row inside the bind list: it isn't a bind, it doesn't
	-- come from the registry, and stuffing it above the rows behind a hairline
	-- made it read as a strange first entry. It's its own card below the panel —
	-- a sibling of it, not a child — which also means COLLAPSING the panel leaves
	-- the readout up. That's the state you want it in most: binds folded away,
	-- frames and ping still on screen.
	local statsBar = Create("Frame", {
		Name = "Stats",
		Visible = false,
		Size = UDim2.new(1, 0, 0, STATS_H),
		BackgroundColor3 = colors.chrome,
		LayoutOrder = 2,
		Parent = root,
	}, {
		Create.corner(8),
		Create.stroke(colors.border),
		Create.padding(0, PAD_X),
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 14),
		}),
	})

	-- `key` is the trailing unit label AND the identity, so SetStat("FPS", …)
	-- updates the same pill every tick and a caller's SetStat("Coins", "1.2k")
	-- just appends another one.
	local statLabels: { [string]: TextLabel } = {}
	local statOrder = 0
	-- An empty bar is no bar at all: `Stats = false`, or both readouts off and
	-- nothing added by hand, and it disappears — the root's list layout skips
	-- invisible children, so the gap under the panel goes with it.
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
				TextSize = 11,
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

	-- ── rows ─────────────────────────────────────────────────────────────────
	local rows: { Row } = {}

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
		}, {
			Create.corner(6),
		})
		local dot = Create("Frame", {
			Name = "Dot",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, PAD_X, 0.5, 0),
			Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = colors.border,
			BorderSizePixel = 0,
			Parent = frame,
		}, {
			Create.corner(999),
		})
		local name = Create("TextLabel", {
			Name = "Name",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(NAME_X, 0),
			Size = UDim2.new(1, -(NAME_X + KEY_W + PAD_X), 1, 0),
			RichText = true,
			Text = "",
			TextColor3 = colors.text_muted,
			TextSize = 12,
			FontFace = Theme.Font.Medium,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = frame,
		}) :: TextLabel
		local key = Create("TextLabel", {
			Name = "Key",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -PAD_X, 0.5, 0),
			Size = UDim2.new(0, KEY_W, 1, 0),
			RichText = true,
			Text = "",
			TextColor3 = colors.text_dim,
			TextSize = 11,
			FontFace = Theme.Font.Mono,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = frame,
		}) :: TextLabel
		return { frame = frame, dot = dot, name = name, key = key }
	end

	-- `sub` = this row's parent is on screen right above it, so it draws indented
	-- with a smaller dot: a bound sub-option reads as belonging to the feature
	-- over it rather than as another top-level thing that's running.
	local function paintRow(row: Row, entry: any, sub: boolean)
		local active = entry:GetState() == true
		local keyName = Bind.name(entry:GetKey())
		if keyName == "None" then
			-- Idle unbound rows are filtered out by Binding:IsListed, so this is a
			-- keyless bind that's currently ON (an "Always", or a toggle switched on
			-- from the menu) or a `Hud = true` override. The em dash is the honest
			-- answer to "what key?" — there isn't one, it's running anyway.
			keyName = "—"
		end
		local indent = sub and SUB_X or 0
		local text = escape(entry:GetLabel() or "Bind")
		-- Sub-options that are on but rolled up into this row. The count is the
		-- whole point of the roll-up: "Aimbot +3" says the feature is running with
		-- more than its bare minimum on, without spending three rows saying it.
		local extra = entry.CountActive and entry:CountActive() or 0
		if extra > 0 then
			text ..= ('<font color="#%s"> +%d</font>'):format(colors.text_dim:ToHex(), extra)
		end
		row.name.Text = text
		row.name.Position = UDim2.fromOffset(NAME_X + indent, 0)
		row.name.Size = UDim2.new(1, -(NAME_X + indent + KEY_W + PAD_X), 1, 0)
		row.name.TextColor3 = active and colors.text or colors.text_muted
		row.key.Text = ('%s<font color="#%s"> · %s</font>')
			:format(keyName, colors.text_dim:ToHex(), entry:GetMode():lower())
		row.key.TextColor3 = active and colors.text or colors.text_dim
		row.dot.Position = UDim2.new(0, PAD_X + indent, 0.5, 0)
		row.dot.Size = sub and UDim2.fromOffset(4, 4) or UDim2.fromOffset(6, 6)
		row.dot.BackgroundColor3 = active and ctx.Accent or colors.border
		row.frame.BackgroundTransparency = active and 0 or 1
		row.frame.Visible = true
	end

	-- Scratch state for `refresh`, cleared and refilled rather than reallocated.
	-- The repaint runs on every registry edge — a Hold key down and up is two, and
	-- a re-key, a mode cycle, a register and a destroy each raise one — so six
	-- fresh tables plus one per block was garbage produced on the input thread, in
	-- a function whose entire premise is that it doesn't churn instances.
	local sListed: { any } = {}
	local sIsListed: { [any]: boolean } = {}
	local sBlocks: { any } = {}
	local sBlockOf: { [any]: any } = {}
	local sOrder: { any } = {}
	local sSubRow: { [any]: boolean } = {}
	local sActive: { any } = {}
	local sIdle: { any } = {}
	-- ...and the blocks with them. A block is `{ entries, active }`; the pool hands
	-- back the same tables every repaint and `blockUsed` is the high-water mark for
	-- this pass, so nothing beyond it is read.
	local blockPool: { any } = {}
	local blockUsed = 0
	local function takeBlock(entry: any): any
		blockUsed += 1
		local block = blockPool[blockUsed]
		if not block then
			block = { entries = {}, active = false }
			blockPool[blockUsed] = block
		end
		table.clear(block.entries)
		block.entries[1] = entry
		block.active = entry:GetState() == true
		return block
	end

	-- The parent of `entry`, but only if that parent is itself on screen — a bound
	-- sub-option whose feature isn't listed has nothing to sit under. Hoisted out
	-- of `refresh` because it closes over `sIsListed`, which is now stable: built
	-- inside, it was one more closure allocated per activation edge.
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
		blockUsed = 0
		-- `Entries`, not `List`: nothing in this walk registers or destroys a
		-- binding, so the copy `List` makes is pure garbage here.
		for _, entry in binds:Entries() do
			if entry:IsListed() then
				table.insert(listed, entry)
				isListed[entry] = true
			end
		end

		-- Gather each listed bind under its parent, if that parent made the list
		-- too. A bound sub-option whose feature isn't on screen (nothing switched
		-- on, no key on the parent) is its own top-level row — there's nothing for
		-- it to sit under, and hiding it would lose a key the user chose.
		--
		-- Blocks keep parent and children together through the cap sort below, so
		-- an indented row can never end up under an unrelated bind (or, worse, be
		-- the row that got cut).
		--
		-- TWO passes, because one pass silently depended on registration order: a
		-- child seen before its parent found no block to join, opened its own, and
		-- then the parent opened a second one — so the two drew as unrelated
		-- top-level rows and the roll-up count went missing. Parent-first is what
		-- `Parent = true` on a card produces, but an explicit `Parent = "aimbot"`
		-- is free to name a feature built in a later group, and did.
		local blocks, blockOf = sBlocks, sBlockOf
		table.clear(blocks)
		-- Roots first, in registration order — that's the order of the panel.
		for _, entry in listed do
			if not parentOf(entry) then
				local block = takeBlock(entry)
				blockOf[entry] = block
				table.insert(blocks, block)
			end
		end
		-- ...then everything that sits under one of them, attached to its nearest
		-- ancestor that owns a block. The tree is documented as shallow, so that
		-- ancestor is normally just the parent — but walking up rather than reading
		-- `blockOf[parent]` once keeps this independent of the order pass 2 happens
		-- to visit a deeper chain in, and flattening a deep chain into its root's
		-- block is what the renderer draws anyway (one level of indent). The hop
		-- bound is the cycle guard: `Parent` is matched by name, so nothing stops a
		-- menu from pointing two binds at each other.
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

		-- Under the cap, rows stay in registration order so nothing jumps around
		-- while you read it. Over the cap, what's LIVE has to be the part you can
		-- see, so active binds float to the top (relative order preserved).
		--
		-- Partitioned through two scratch lists and written back into `blocks`
		-- rather than rebound to a fresh array: `blocks` IS the scratch table, and
		-- pointing the local somewhere else would leave it holding the pooled
		-- blocks from the previous repaint.
		if #listed > maxRows then
			table.clear(sActive)
			table.clear(sIdle)
			for _, block in blocks do
				table.insert(block.active and sActive or sIdle, block)
			end
			table.clear(blocks)
			for _, block in sActive do
				table.insert(blocks, block)
			end
			for _, block in sIdle do
				table.insert(blocks, block)
			end
		end

		local order, subRow = sOrder, sSubRow
		for _, block in blocks do
			for i, entry in block.entries do
				table.insert(order, entry)
				subRow[entry] = i > 1
			end
		end

		local shown = math.min(#order, maxRows)
		for i = 1, shown do
			local row = rows[i]
			if not row then
				row = newRow(i)
				rows[i] = row
			end
			paintRow(row, order[i], subRow[order[i]] == true)
		end
		for i = shown + 1, #rows do
			rows[i].frame.Visible = false
		end
		empty.Visible = shown == 0
		local rest = #order - shown
		more.Visible = rest > 0
		-- Only formatted when it's actually on screen: the overflow line is empty
		-- in the overwhelmingly common case, and this runs on every key edge.
		if rest > 0 then
			more.Text = ("+%d more"):format(rest)
		end
	end

	local unsubscribeBinds = binds:Observe(refresh)
	local unsubscribeAccent = ctx:RegisterAccent(function(accent)
		rail.BackgroundColor3 = accent
		refresh() -- the live dots are the only accent inside the list
	end)

	-- ── position + drag ──────────────────────────────────────────────────────
	-- Offset-only position, rounded to whole pixels: the panel is small and full
	-- of 11px text, and a half-pixel origin is exactly what makes that text look
	-- soft (see Window.lua's snapToPixels).
	local pos = Vector2.new(tonumber(opts.X) or 16, tonumber(opts.Y) or 140)
	local function place(p: Vector2)
		local vp = (parent :: any).AbsoluteSize
		local size = root.AbsoluteSize
		if vp and vp.X > 0 and size.X > 0 then
			p = Vector2.new(
				math.clamp(p.X, MARGIN, math.max(MARGIN, vp.X - size.X - MARGIN)),
				math.clamp(p.Y, MARGIN, math.max(MARGIN, vp.Y - size.Y - MARGIN))
			)
		end
		pos = Vector2.new(math.round(p.X), math.round(p.Y))
		root.Position = UDim2.fromOffset(pos.X, pos.Y)
	end
	place(pos)
	-- A viewport (or a collapse) that shrinks under the panel would otherwise
	-- leave it hanging off an edge with nothing to grab.
	table.insert(connections, (parent :: any):GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		place(pos)
	end))
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		place(pos)
	end)

	-- Both cards drag as one unit — the handle is `root`, so the stat bar and the
	-- gap between them are grabbable too (the rows and pills are plain labels, so
	-- input reaches it through them). Only the caret button is a click target.
	local dragging = false
	local dragStart = Vector2.zero
	local dragOrigin = pos
	local dragMoved = false
	root.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragMoved = false
			dragStart = Vector2.new(input.Position.X, input.Position.Y)
			dragOrigin = pos
		end
	end)
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
			if math.abs(delta.X) + math.abs(delta.Y) > 4 then
				dragMoved = true
			end
			place(dragOrigin + delta)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			local wasDragging = dragging
			dragging = false
			-- Announced on RELEASE, not per frame: `place` runs on every mouse move
			-- and the position is part of the HUD's persisted record, so a host
			-- writing on every change would write sixty times a second across a drag.
			if wasDragging and dragMoved then
				ctx:User(changed)
			end
			-- Clear the drag flag here rather than only in the caret's handler. The
			-- caret is a TextButton and sinks input, so a click on it never reaches
			-- root.InputBegan to reset the flag — after any drag of the panel, the
			-- NEXT caret click would be swallowed as "that was a drag". Deferred
			-- because Activated fires on this same release and has to still see it.
			task.defer(function()
				dragMoved = false
			end)
		end
	end))

	-- ── FPS / ping ───────────────────────────────────────────────────────────
	-- One connection, sampled twice a second: a per-frame label write would cost
	-- more than the whole rest of the HUD, and a jittering number is unreadable
	-- anyway. Skipped entirely while hidden — but NOT while collapsed: the bar is
	-- its own card outside the collapsing body and stays on screen, so it has to
	-- keep counting.
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
				-- Not every executor/place exposes the network stats item, so this
				-- degrades to a dash rather than erroring every half second.
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
		-- Already there, and the panel agrees — nothing to do. Without this,
		-- `Window:SetHudVisible(true)` on a HUD that's already up replayed the whole
		-- entrance (fade to invisible, scale to 0.94, pop back) and announced a
		-- visibility change that hadn't happened, which the settings switch and any
		-- host watching OnHudVisible both had to filter out on their own.
		--
		-- `root.Visible` is part of the test on purpose rather than `value ==
		-- visible` alone: the deferred first reveal at the bottom of this file calls
		-- SetVisible(true) precisely when `visible` is *already* true (it comes from
		-- the options) and the panel is still hidden, and that call has to go through.
		if value == visible and root.Visible == value then
			return
		end
		visible = value
		if value then
			root.Visible = true
			-- Repaint once the fade lands: rows that changed state while the panel
			-- was hidden were driven by the fade's snapshot, not by their own paint,
			-- so their fill is stale until the snapshot is released at alpha 0.
			if animate == false then
				fade:Set(0)
				panelScale.Scale = 1
				refresh()
			else
				-- Back to rest FIRST, which releases the snapshot the hide left held.
				-- Rows registered while the panel was hidden aren't in that snapshot, so
				-- without this they sit fully opaque while everything around them fades
				-- in. Set(0) restores the old rows to their own resting transparencies
				-- and drops the cache; the Set(1) below then re-reads a tree that
				-- includes the new rows.
				fade:Set(0)
				fade:Set(1)
				panelScale.Scale = 0.94
				Tween.play(panelScale, Tween.Pop, { Scale = 1 })
				fade:To(Tween.Normal, 0, refresh)
			end
			place(pos)
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
		-- `animate = false` (a config load) has to snap the caret too, or the panel
		-- restores collapsed while its arrow spins into place a beat later.
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
			place(Vector2.new(tonumber(value.X) :: number, tonumber(value.Y) :: number))
		end
		if value.Collapsed ~= nil then
			handle:SetCollapsed(value.Collapsed == true, false)
		end
		if value.Visible ~= nil then
			handle:SetVisible(value.Visible == true, false)
		end
		-- A record that only moved the panel gets no notification from the setters
		-- above (`place` isn't one of them), and a host mirroring the HUD needs to
		-- hear about a restore either way. Deduped downstream by value.
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
	-- built at this point.
	-- `not root.Visible` so a caller that already showed it on this frame
	-- (Window:SetHudVisible, which builds and shows in one go) doesn't get the
	-- entrance played twice.
	if visible then
		task.defer(function()
			if not destroyed and visible and not root.Visible then
				handle:SetVisible(true)
			end
		end)
	end

	return handle
end
