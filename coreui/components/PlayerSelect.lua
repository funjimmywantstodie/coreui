--!strict
-- components/PlayerSelect.lua — single + multi player picker.
-- Same box/popover shell as Dropdown, but the menu lists Players:GetPlayers()
-- live (refetched on every open) with a headshot thumbnail, display name and
-- @username per row. Selection is tracked by UserId so it round-trips through
-- config Flags; :Get() always resolves live against the current player list,
-- so a player who leaves quietly drops out instead of leaving a stale handle.

local Players = game:GetService("Players")

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)
local Field = require(script.Parent.Field)

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
	local menu = Create("CanvasGroup", {
		Name = "PlayerMenu",
		Visible = false,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(230, 0),
		BackgroundColor3 = colors.pop,
		ClipsDescendants = true,
	}, {
		Create.corner(8),
		Create.stroke(colors.border),
		Create.padding(5),
		Create.listLayout({ Padding = UDim.new(0, 2) }),
		Create("UISizeConstraint", { MaxSize = Vector2.new(math.huge, 260) }),
	})

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

	local rebuild -- fwd
	local function pick(p: Player)
		if multi then
			selected[p.UserId] = not selected[p.UserId] or nil
			relabel()
			rebuild()
		else
			singleId = p.UserId
			relabel()
			ctx:ClosePopover()
		end
		fireCallback()
	end

	rebuild = function()
		for _, child in menu:GetChildren() do
			if child:IsA("GuiButton") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end

		local players = Players:GetPlayers()
		if #players == 0 then
			Create("TextLabel", {
				Name = "Empty",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 28),
				Text = "No players online",
				TextColor3 = colors.text_muted,
				TextSize = 13,
				FontFace = Theme.Font.Regular,
				Parent = menu,
			})
			return
		end

		for i, p in players do
			local sel = multi and selected[p.UserId] == true or (not multi and singleId == p.UserId)

			local row = Create("TextButton", {
				Name = p.Name,
				AutoButtonColor = false,
				Text = "",
				BackgroundColor3 = colors.control_hi,
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 0),
				LayoutOrder = i,
				Parent = menu,
			}, {
				Create.corner(6),
				Create.padding(6, 8),
				Create.listLayout({
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 9),
				}),
			})

			local tickHolder = Create("Frame", {
				Name = "Tick",
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(15, 15),
				LayoutOrder = 1,
				Parent = row,
			})
			local tick = Icons.new("check", 14, ctx.Accent)
			tick.Visible = sel;
			(tick :: any).Parent = tickHolder

			-- avatar: accent-tinted placeholder with a generic icon, swapped for the
			-- real headshot once GetUserThumbnailAsync resolves (it's a network call,
			-- so it runs off-thread and never blocks the menu from opening).
			local avatar = Create("Frame", {
				Name = "Avatar",
				Size = UDim2.fromOffset(28, 28),
				BackgroundColor3 = ctx.Accent,
				ClipsDescendants = true,
				LayoutOrder = 2,
				Parent = row,
			}, {
				Create.corner(8),
			})
			local avatarIcon = Icons.new("avatar", 16, colors.white)
			avatarIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			avatarIcon.Position = UDim2.fromScale(0.5, 0.5);
			(avatarIcon :: any).Parent = avatar

			task.spawn(function()
				local ok, content = pcall(
					Players.GetUserThumbnailAsync,
					Players,
					p.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size48x48
				)
				if ok and avatar.Parent then
					avatarIcon.Visible = false
					Create("ImageLabel", {
						Name = "Image",
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						Image = content,
						Parent = avatar,
					})
				end
			end)

			local names = Create("Frame", {
				Name = "Names",
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.XY,
				Size = UDim2.new(0, 0, 0, 0),
				LayoutOrder = 3,
				Parent = row,
			}, {
				Create.listLayout({ Padding = UDim.new(0, 1) }),
			})

			Create("TextLabel", {
				Name = "Display",
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.XY,
				Text = displayName(p),
				TextColor3 = sel and colors.text or colors.text_muted,
				TextSize = 13,
				FontFace = Theme.Font.Regular,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 1,
				Parent = names,
			})
			Create("TextLabel", {
				Name = "Username",
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.XY,
				Text = "@" .. p.Name,
				TextColor3 = colors.text_dim,
				TextSize = 11,
				FontFace = Theme.Font.Regular,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 2,
				Parent = names,
			})

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

	box.Activated:Connect(function()
		if ctx:IsOpen(menu) then
			ctx:ClosePopover()
			return
		end
		rebuild()
		menu.Size = UDim2.fromOffset(math.max(box.AbsoluteSize.X, 230), 0)
		setOpenVisual(true)
		ctx:OpenPopover(menu, box, function()
			setOpenVisual(false)
		end)
	end)
	hover(box, colors.control, colors.control_hi)

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
			selected = {}
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
		if ctx:IsOpen(menu) then
			rebuild()
		end
		fireCallback()
	end

	return f.field, handle, true
end

return build
