--!strict
-- components/Hud.lua — the floating bind HUD: a small draggable panel that
-- answers "what's on right now?" without opening the menu.
--
-- It reads util/Bind.lua's registry directly (`Bind:Observe` → `Bind:List`), so
-- it isn't a second list anyone has to maintain: every Toggle with a `Keybind`,
-- every activation-mode `Keybind` control and every `Window:Bind` shows up the
-- moment it's registered and lights while it's live. A binding only needs a
-- `Label` to appear — which the controls pass from their own `Name` — so nothing
-- has to be declared twice.
--
-- Three deliberate shapes here:
--
--  * It's a SIBLING of the window frame, not a child. Minimizing the window (or
--    the toggle key) has to leave the HUD up — being able to read your binds
--    with the menu closed is the entire point — but it still lives in the
--    window's ScreenGui, so it dies with it and needs no teardown of its own
--    beyond its input connections.
--  * Rows are POOLED and repainted in place. The registry notifies on every
--    press, so a Hold key down/up must not churn instances.
--  * One accent element per row (the live dot). An active row lifts to `card`
--    instead of tinting accent, so a screen full of active binds still reads as
--    a list rather than a wall of green.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Fade = require(script.Parent.Parent.util.Fade)
local Icons = require(script.Parent.Parent.Icons)
local Bind = require(script.Parent.Parent.util.Bind)
local Collapse = require(script.Parent.Parent.util.Collapse)
local Log = require(script.Parent.Parent.util.Log)

local WIDTH = 248
local HEADER_H = 30
local ROW_H = 22
local PAD_X = 12
local NAME_X = 26
local KEY_W = 110 -- right column: "RShift · always" in 11px mono, with room to spare
local MARGIN = 8  -- keep-on-screen inset

-- One pooled bind row: dot (live marker) · name · "KEY · mode".
type Row = { frame: Frame, dot: Frame, name: TextLabel, key: TextLabel }

return function(ctx: any, parent: Instance, opts: any): any
	opts = opts or {}
	local colors = Theme.Colors
	Log.field("Hud", "Title", opts.Title, "string")
	Log.field("Hud", "X", opts.X, "number")
	Log.field("Hud", "Y", opts.Y, "number")
	Log.field("Hud", "MaxRows", opts.MaxRows, "number")
	Log.field("Hud", "Visible", opts.Visible, "boolean")
	Log.field("Hud", "Collapsed", opts.Collapsed, "boolean")
	Log.field("Hud", "Stats", opts.Stats, "boolean")
	Log.field("Hud", "Fps", opts.Fps, "boolean")
	Log.field("Hud", "Ping", opts.Ping, "boolean")

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

	-- ── panel ────────────────────────────────────────────────────────────────
	-- A miniature of the window: chrome header over a bg body, one border, same
	-- radius. It reads as part of the same UI without being a second window.
	local panel = Create("Frame", {
		Name = "Hud",
		Position = UDim2.fromOffset(tonumber(opts.X) or 16, tonumber(opts.Y) or 140),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.bg,
		ClipsDescendants = true,
		Visible = false, -- revealed below, so the fade snapshots a finished panel
		ZIndex = 10,
		Parent = parent,
	}, {
		Create.corner(10),
		Create.stroke(colors.border),
		Create.listLayout(),
		Create("UIScale", {}),
	})
	local panelScale = panel:FindFirstChildOfClass("UIScale") :: UIScale
	local fade = Fade.new(panel)

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
		Create("Frame", {
			Name = "SquareFill",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 10),
			BackgroundColor3 = colors.chrome,
			BorderSizePixel = 0,
		}),
		Create("Frame", {
			Name = "Border",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = colors.border_soft,
			BorderSizePixel = 0,
		}),
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

	local statsRow = Create("Frame", {
		Name = "Stats",
		Visible = false,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = body,
	}, {
		Create.padding(0, PAD_X),
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 14),
		}),
	})
	local statsBorder = Create("Frame", {
		Name = "StatsBorder",
		Visible = false,
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = colors.border_soft,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Parent = body,
	})

	local list = Create("Frame", {
		Name = "Binds",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
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

	-- ── stat pills ───────────────────────────────────────────────────────────
	-- `key` is the trailing unit label AND the identity, so SetStat("FPS", …)
	-- updates the same pill every tick and a caller's SetStat("Coins", "1.2k")
	-- just appends another one.
	local statLabels: { [string]: TextLabel } = {}
	local statOrder = 0
	local function syncStatsRow()
		local any = next(statLabels) ~= nil
		statsRow.Visible = showStats and any
		statsBorder.Visible = statsRow.Visible
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
				Parent = statsRow,
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

	local function paintRow(row: Row, entry: any)
		local active = entry:GetState() == true
		local keyName = Bind.name(entry:GetKey())
		if keyName == "None" then
			keyName = "—" -- unbound: the row still says what the feature is
		end
		row.name.Text = entry:GetLabel() or "Bind"
		row.name.TextColor3 = active and colors.text or colors.text_muted
		row.key.Text = ('%s<font color="#%s"> · %s</font>')
			:format(keyName, colors.text_dim:ToHex(), entry:GetMode():lower())
		row.key.TextColor3 = active and colors.text or colors.text_dim
		row.dot.BackgroundColor3 = active and ctx.Accent or colors.border
		row.frame.BackgroundTransparency = active and 0 or 1
		row.frame.Visible = true
	end

	local function refresh()
		if destroyed then
			return
		end
		local listed = {}
		for _, entry in binds:List() do
			if entry:IsListed() then
				table.insert(listed, entry)
			end
		end
		-- Under the cap, rows stay in registration order so nothing jumps around
		-- while you read it. Over the cap, what's LIVE has to be the part you can
		-- see, so active binds float to the top (relative order preserved).
		if #listed > maxRows then
			local active, idle = {}, {}
			for _, entry in listed do
				table.insert(entry:GetState() and active or idle, entry)
			end
			listed = active
			for _, entry in idle do
				table.insert(listed, entry)
			end
		end

		local shown = math.min(#listed, maxRows)
		for i = 1, shown do
			local row = rows[i]
			if not row then
				row = newRow(i)
				rows[i] = row
			end
			paintRow(row, listed[i])
		end
		for i = shown + 1, #rows do
			rows[i].frame.Visible = false
		end
		empty.Visible = shown == 0
		local rest = #listed - shown
		more.Visible = rest > 0
		more.Text = ("+%d more"):format(rest)
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
		local size = panel.AbsoluteSize
		if vp and vp.X > 0 and size.X > 0 then
			p = Vector2.new(
				math.clamp(p.X, MARGIN, math.max(MARGIN, vp.X - size.X - MARGIN)),
				math.clamp(p.Y, MARGIN, math.max(MARGIN, vp.Y - size.Y - MARGIN))
			)
		end
		pos = Vector2.new(math.round(p.X), math.round(p.Y))
		panel.Position = UDim2.fromOffset(pos.X, pos.Y)
	end
	place(pos)
	-- A viewport (or a collapse) that shrinks under the panel would otherwise
	-- leave it hanging off an edge with nothing to grab.
	table.insert(connections, (parent :: any):GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		place(pos)
	end))
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		place(pos)
	end)

	-- The whole panel is the drag handle (its rows are plain labels, so input
	-- reaches the panel through them) — only the caret button is a click target.
	local dragging = false
	local dragStart = Vector2.zero
	local dragOrigin = pos
	local dragMoved = false
	panel.InputBegan:Connect(function(input)
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
			dragging = false
			-- Clear the drag flag here rather than only in the caret's handler. The
			-- caret is a TextButton and sinks input, so a click on it never reaches
			-- panel.InputBegan to reset the flag — after any drag of the panel, the
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
	-- anyway. Skipped entirely while the panel is hidden or collapsed.
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
			if not visible or collapsed then
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
	local handle: any = {}
	handle.Frame = panel
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
		visible = value
		if value then
			panel.Visible = true
			-- Repaint once the fade lands: rows that changed state while the panel
			-- was hidden were driven by the fade's snapshot, not by their own paint,
			-- so their fill is stale until the snapshot is released at alpha 0.
			if animate == false then
				fade:Set(0)
				panelScale.Scale = 1
				refresh()
			else
				fade:Set(1)
				panelScale.Scale = 0.94
				Tween.play(panelScale, Tween.Pop, { Scale = 1 })
				fade:To(Tween.Normal, 0, refresh)
			end
			place(pos)
		elseif animate == false then
			panel.Visible = false
		else
			Tween.play(panelScale, Tween.MenuOut, { Scale = 0.94 })
			fade:To(Tween.MenuOut, 1, function()
				if not visible then
					panel.Visible = false
				end
			end)
		end
		if handle.OnVisible then
			handle.OnVisible(visible)
		end
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
		-- `animate = false` (a config load) has to snap the caret too, or the panel
		-- restores collapsed while its arrow spins into place a beat later.
		if animate == false then
			caret.Rotation = collapsed and 180 or 0
		else
			Tween.play(caret, Tween.Spin, { Rotation = collapsed and 180 or 0 })
		end
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
		panel:Destroy()
	end

	-- The caret is inside the drag surface, so a drag that happens to start on it
	-- must not also collapse the panel when the button comes back up.
	caretBtn.Activated:Connect(function()
		if dragMoved then
			dragMoved = false
			return
		end
		handle:SetCollapsed(not collapsed)
	end)

	refresh()
	if collapsed then
		caret.Rotation = 180
	end
	-- Reveal on a deferred pass: the fade has to snapshot a finished panel, and
	-- the caller's controls (and therefore its binds) are usually still being
	-- built at this point.
	-- `not panel.Visible` so a caller that already showed it on this frame
	-- (Window:SetHudVisible, which builds and shows in one go) doesn't get the
	-- entrance played twice.
	if visible then
		task.defer(function()
			if not destroyed and visible and not panel.Visible then
				handle:SetVisible(true)
			end
		end)
	end

	return handle
end
