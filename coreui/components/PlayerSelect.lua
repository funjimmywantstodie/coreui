--!strict
-- components/PlayerSelect.lua — single + multi player picker.
-- Same box/popover shell as Dropdown, but the menu lists Players:GetPlayers()
-- live (refetched on every open, and kept in sync while open) with a headshot
-- thumbnail, display name and @username per row. Selection is tracked by UserId
-- so it round-trips through config Flags; :Get() always resolves live against the
-- current player list, so a player who leaves quietly drops out instead of
-- leaving a stale handle.
--
-- The menu SCROLLS: a full server is 30+ players, so the row list lives in a
-- ScrollingFrame capped at MENU_MAX_H. (It used to be a plain auto-sized frame
-- under a UISizeConstraint, which clipped everyone past the sixth player with no
-- way to reach them.)

local Players = game:GetService("Players")

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)
local Field = require(script.Parent.Field)

local MENU_MAX_H = 264 -- popover height cap; rows scroll past it
local MENU_MIN_W = 230
local ROW_H = 40
local TICK_W, AVATAR_W, GAP = 15, 28, 9

-- Headshot URLs are a network round-trip and never change within a session, so
-- they're cached process-wide and in-flight requests are shared. Re-opening the
-- menu (or toggling a row in a multi-select) then reuses the resolved image
-- instead of re-fetching every avatar, which is what made them flicker.
local thumbCache: { [number]: string } = {}
local thumbWaiters: { [number]: { (string) -> () } } = {}

local function requestThumb(userId: number, apply: (string) -> ())
	local cached = thumbCache[userId]
	if cached then
		apply(cached)
		return
	end
	local waiting = thumbWaiters[userId]
	if waiting then
		table.insert(waiting, apply)
		return
	end
	thumbWaiters[userId] = { apply }
	task.spawn(function()
		local ok, content = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size48x48
		)
		local list = thumbWaiters[userId]
		thumbWaiters[userId] = nil
		if not ok or type(content) ~= "string" or content == "" then
			return
		end
		thumbCache[userId] = content
		for _, fn in list or {} do
			pcall(fn, content)
		end
	end)
end

local function hover(button: GuiButton, base: Color3, over: Color3)
	button.MouseEnter:Connect(function()
		Tween.play(button, Tween.Fast, { BackgroundColor3 = over })
	end)
	button.MouseLeave:Connect(function()
		Tween.play(button, Tween.Fast, { BackgroundColor3 = base })
	end)
end

local function displayName(p: Player): string
	if p.DisplayName ~= "" and p.DisplayName ~= p.Name then
		return p.DisplayName
	end
	return p.Name
end

local function toId(v: any): number?
	if typeof(v) == "Instance" and v:IsA("Player") then
		return v.UserId
	elseif type(v) == "number" then
		return v
	end
	return nil
end

local function build(ctx: any, opts: any, multi: boolean)
	local colors = Theme.Colors
	local placeholder = opts.Placeholder or (multi and "Select players..." or "Select a player...")
	local stack = opts.Stack == true

	local singleId: number? = toId(opts.Default)
	local selected: { [number]: boolean } = {}
	if multi and type(opts.Default) == "table" then
		for _, v in opts.Default do
			local id = toId(v)
			if id then
				selected[id] = true
			end
		end
	end

	local f = Field.new(ctx, opts, stack)

	-- box ────────────────────────────────────────────────────────────────────
	local box = Create("TextButton", {
		Name = "PlayerSelect",
		AutoButtonColor = false,
		Text = "",
		Size = stack and UDim2.new(1, 0, 0, 32) or UDim2.fromOffset(opts.Width or 160, 32),
		BackgroundColor3 = colors.control,
		LayoutOrder = 2,
		Parent = stack and f.field or f.row,
	}, {
		Create.corner(Theme.Metrics.controlRadius),
		Create.stroke(colors.border),
		Create.padding(0, 8, 0, 12),
	})
	local boxStroke = box:FindFirstChildOfClass("UIStroke") :: UIStroke

	local valLabel = Create("TextLabel", {
		Name = "Value",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 1, 0),
		Text = placeholder,
		TextColor3 = colors.text_muted,
		TextSize = 13,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = box,
	})

	local chevron = Icons.new("caret", 14, colors.text_dim)
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, 0, 0.5, 0);
	(chevron :: any).Parent = box

	-- menu ─────────────────────────────────────────────────────────────────── (parented to overlay on open)
	-- The menu auto-sizes to the scroller, whose height is fitted to the row list
	-- up to MENU_MAX_H (see fitMenu) — past that the content overflows and the
	-- list scrolls instead of being silently cut off. A Frame, not a CanvasGroup:
	-- a group buffer would blur every name in the list (see util/Fade.lua).
	local menu = Create("Frame", {
		Name = "PlayerMenu",
		Visible = false,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(MENU_MIN_W, 0),
		BackgroundColor3 = colors.pop,
		ClipsDescendants = true,
	}, {
		Create.corner(8),
		Create.stroke(colors.border),
		Create.padding(5),
	})

	local scroller = Create("ScrollingFrame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = colors.text_dim,
		ScrollBarImageTransparency = 0.35,
		Parent = menu,
	}, {
		Create.listLayout({ Padding = UDim.new(0, 2) }),
	})

	-- The viewport is driven off the layout's measured content height rather than
	-- AutomaticSize, so the menu is exactly as tall as its rows up to MENU_MAX_H
	-- and scrolls beyond it. (The canvas keeps auto-sizing, which is what gives
	-- the overflow something to scroll through.)
	local rowLayout = scroller:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	local function fitMenu()
		scroller.Size = UDim2.new(1, 0, 0, math.min(MENU_MAX_H, rowLayout.AbsoluteContentSize.Y))
	end
	rowLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitMenu)

	local function selectedPlayers(): { Player }
		local list = {}
		for _, p in Players:GetPlayers() do
			if selected[p.UserId] then
				table.insert(list, p)
			end
		end
		return list
	end

	local function valueLabelText(): (string, boolean)
		if multi then
			local names = {}
			for _, p in selectedPlayers() do
				table.insert(names, displayName(p))
			end
			if #names == 0 then
				return placeholder, false
			end
			return table.concat(names, ", "), true
		else
			local p = singleId and Players:GetPlayerByUserId(singleId)
			if not p then
				return placeholder, false
			end
			return displayName(p), true
		end
	end

	local function relabel()
		local text, hasVal = valueLabelText()
		valLabel.Text = text
		valLabel.TextColor3 = hasVal and colors.text or colors.text_muted
	end

	local function fireCallback()
		if not opts.Callback then
			return
		end
		if multi then
			task.spawn(opts.Callback, selectedPlayers())
		else
			task.spawn(opts.Callback, singleId and Players:GetPlayerByUserId(singleId) or nil)
		end
	end

	local function isSelected(userId: number): boolean
		if multi then
			return selected[userId] == true
		end
		return singleId == userId
	end

	-- Live row handles, keyed by UserId, so picking (or an external :Set) repaints
	-- the affected rows in place instead of tearing the whole menu down — a
	-- rebuild would drop every hover state and restart the open animation.
	type Row = { tick: GuiObject, name: TextLabel }
	local rows: { [number]: Row } = {}

	local function paintRow(userId: number)
		local row = rows[userId]
		if not row then
			return
		end
		local sel = isSelected(userId)
		row.tick.Visible = sel
		row.name.TextColor3 = sel and colors.text or colors.text_muted
	end

	local function repaintAll()
		for userId in rows do
			paintRow(userId)
		end
	end

	local function pick(p: Player)
		if multi then
			local was = selected[p.UserId] == true
			selected[p.UserId] = (not was) or nil
			paintRow(p.UserId)
			relabel()
		else
			local previous = singleId
			singleId = p.UserId
			if previous then
				paintRow(previous)
			end
			paintRow(p.UserId)
			relabel()
			ctx:ClosePopover()
		end
		fireCallback()
	end

	local function rebuild()
		table.clear(rows)
		for _, child in scroller:GetChildren() do
			if child:IsA("GuiButton") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end

		local players = Players:GetPlayers()
		table.sort(players, function(a, b)
			return displayName(a):lower() < displayName(b):lower()
		end)

		if #players == 0 then
			Create("TextLabel", {
				Name = "Empty",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 28),
				Text = "No players online",
				TextColor3 = colors.text_muted,
				TextSize = 13,
				FontFace = Theme.Font.Regular,
				Parent = scroller,
			})
			return
		end

		for i, p in players do
			local userId = p.UserId

			local row = Create("TextButton", {
				Name = tostring(userId),
				AutoButtonColor = false,
				Text = "",
				BackgroundColor3 = colors.control_hi,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -4, 0, ROW_H), -- -4 keeps rows clear of the scrollbar
				LayoutOrder = i,
				ClipsDescendants = true,
				Parent = scroller,
			}, {
				Create.corner(6),
				Create.padding(0, 8),
				Create.listLayout({
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, GAP),
				}),
			})

			local tickHolder = Create("Frame", {
				Name = "Tick",
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(TICK_W, TICK_W),
				LayoutOrder = 1,
				Parent = row,
			})
			local tick = Icons.new("check", 14, ctx.Accent)
			tick.Visible = false;
			(tick :: any).Parent = tickHolder

			-- avatar: accent-tinted placeholder with a generic icon, swapped for the
			-- real headshot once the (cached) thumbnail lookup resolves — the fetch
			-- runs off-thread so opening the menu never blocks on the network.
			local avatar = Create("Frame", {
				Name = "Avatar",
				Size = UDim2.fromOffset(AVATAR_W, AVATAR_W),
				BackgroundColor3 = ctx.AccentSoft,
				ClipsDescendants = true,
				LayoutOrder = 2,
				Parent = row,
			}, {
				Create.corner(8),
			})
			local avatarIcon = Icons.new("avatar", 16, ctx.Accent)
			avatarIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			avatarIcon.Position = UDim2.fromScale(0.5, 0.5);
			(avatarIcon :: any).Parent = avatar

			requestThumb(userId, function(image)
				if not avatar.Parent then
					return
				end
				avatarIcon.Visible = false
				local existing = avatar:FindFirstChild("Image")
				if existing and existing:IsA("ImageLabel") then
					existing.Image = image
					return
				end
				Create("ImageLabel", {
					Name = "Image",
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Image = image,
					Parent = avatar,
				})
			end)

			-- Names take the row's leftover width (offset-sized, truncated) so a long
			-- display name can't push the @username past the menu edge.
			local names = Create("Frame", {
				Name = "Names",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -(TICK_W + AVATAR_W + GAP * 2), 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 3,
				Parent = row,
			}, {
				Create.listLayout({ Padding = UDim.new(0, 1) }),
			})

			local nameLabel = Create("TextLabel", {
				Name = "Display",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 15),
				Text = displayName(p),
				TextColor3 = colors.text_muted,
				TextSize = 13,
				FontFace = Theme.Font.Regular,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 1,
				Parent = names,
			})
			Create("TextLabel", {
				Name = "Username",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 13),
				Text = "@" .. p.Name,
				TextColor3 = colors.text_dim,
				TextSize = 11,
				FontFace = Theme.Font.Regular,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 2,
				Parent = names,
			})

			rows[userId] = { tick = tick, name = nameLabel }
			paintRow(userId)

			row.MouseEnter:Connect(function()
				Tween.play(row, Tween.Fast, { BackgroundTransparency = 0 })
			end)
			row.MouseLeave:Connect(function()
				Tween.play(row, Tween.Fast, { BackgroundTransparency = 1 })
			end)
			row.Activated:Connect(function()
				pick(p)
			end)
		end
	end

	local function setOpenVisual(open: boolean)
		Tween.play(boxStroke, Tween.Fast, { Color = open and ctx.Accent or colors.border })
		Tween.play(chevron, Tween.Spin, { Rotation = open and 180 or 0 })
	end

	-- Roster changes while the menu is open rebuild it, so someone joining or
	-- leaving mid-pick doesn't leave a row pointing at a player who's gone.
	local liveConns: { RBXScriptConnection } = {}
	local function stopWatching()
		for _, conn in liveConns do
			conn:Disconnect()
		end
		table.clear(liveConns)
	end

	box.Activated:Connect(function()
		if ctx:IsOpen(menu) then
			ctx:ClosePopover()
			return
		end
		rebuild()
		fitMenu()
		scroller.CanvasPosition = Vector2.new(0, 0)
		menu.Size = UDim2.fromOffset(math.max(box.AbsoluteSize.X, MENU_MIN_W), 0)
		setOpenVisual(true)
		table.insert(liveConns, Players.PlayerAdded:Connect(rebuild))
		table.insert(liveConns, Players.PlayerRemoving:Connect(function()
			-- PlayerRemoving fires before the player leaves GetPlayers(), so rebuild
			-- on the next step to get the post-departure roster.
			task.defer(function()
				if ctx:IsOpen(menu) then
					rebuild()
				end
			end)
		end))
		ctx:OpenPopover(menu, box, function()
			stopWatching()
			setOpenVisual(false)
		end)
	end)
	hover(box, colors.control, colors.control_hi)

	-- The box label resolves UserIds to live players, so it has to be redrawn when
	-- someone selected leaves (or rejoins) — otherwise it keeps naming a player
	-- who isn't in the server any more. Self-disconnects once the control is gone,
	-- since these signals outlive the ScreenGui.
	do
		local rosterConns: { RBXScriptConnection } = {}
		local function onRoster(p: Player)
			if not box:IsDescendantOf(game) then
				for _, conn in rosterConns do
					conn:Disconnect()
				end
				table.clear(rosterConns)
				return
			end
			if isSelected(p.UserId) then
				task.defer(relabel)
			end
		end
		table.insert(rosterConns, Players.PlayerRemoving:Connect(onRoster))
		table.insert(rosterConns, Players.PlayerAdded:Connect(onRoster))
	end

	relabel()

	local handle = {}
	function handle:Get(): any
		if multi then
			return selectedPlayers()
		end
		return singleId and Players:GetPlayerByUserId(singleId) or nil
	end
	function handle:Set(value: any)
		if multi then
			table.clear(selected)
			if type(value) == "table" then
				for _, v in value do
					local id = toId(v)
					if id then
						selected[id] = true
					end
				end
			end
		else
			singleId = toId(value)
		end
		relabel()
		repaintAll()
		fireCallback()
	end

	return f.field, handle, true
end

return build
