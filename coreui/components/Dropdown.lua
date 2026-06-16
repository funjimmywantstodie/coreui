--!strict
-- components/Dropdown.lua — single + multi select.
-- Box is a TextButton; the menu lives in the window overlay (high ZIndex) so it
-- escapes the scrolling content's clip. Single sets + closes; multi toggles a
-- check per option and stays open. Outside click closes (Context popover).

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

local function build(ctx: any, opts: any, multi: boolean)
	local colors = Theme.Colors
	local options = opts.Options or {}
	local placeholder = opts.Placeholder or "None"
	local stack = opts.Stack == true

	local single: string? = opts.Default
	local selected: { [string]: boolean } = {}
	if multi and type(opts.Default) == "table" then
		for _, v in opts.Default do
			selected[v] = true
		end
	end

	local f = Field.new(ctx, opts, stack)

	-- box ────────────────────────────────────────────────────────────────────
	local box = Create("TextButton", {
		Name = "Dropdown",
		AutoButtonColor = false,
		Text = "",
		Size = stack and UDim2.new(1, 0, 0, 32) or UDim2.fromOffset(opts.Width or 130, 32),
		BackgroundColor3 = colors.control,
		LayoutOrder = 2,
		Parent = stack and f.field or f.row,
	}, {
		Create.corner(Theme.Metrics.controlRadius),
		Create.stroke(colors.border),
		Create.padding(0, 8, 0, 12),
		-- No UIListLayout: a layout-managed child won't render its Rotation, so
		-- the caret is positioned manually to keep it free to spin.
	})
	local boxStroke = box:FindFirstChildOfClass("UIStroke") :: UIStroke

	local valLabel = Create("TextLabel", {
		Name = "Value",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 1, 0), -- fills, leaving 10px gap + 14px chevron
		AutomaticSize = Enum.AutomaticSize.None,
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
		Name = "DropdownMenu",
		Visible = false,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(150, 0),
		BackgroundColor3 = colors.pop,
		ClipsDescendants = true,
	}, {
		Create.corner(8),
		Create.stroke(colors.border),
		Create.padding(5),
		Create.listLayout({ Padding = UDim.new(0, 2) }),
		Create("UISizeConstraint", { MaxSize = Vector2.new(math.huge, 210) }),
	})

	local function valueLabelText(): (string, boolean)
		if multi then
			local list = {}
			for _, opt in options do
				if selected[opt] then
					table.insert(list, opt)
				end
			end
			if #list == 0 then
				return placeholder, false
			end
			return table.concat(list, ", "), true
		else
			if single == nil then
				return placeholder, false
			end
			return single, true
		end
	end

	local function relabel()
		local text, hasVal = valueLabelText()
		valLabel.Text = text
		valLabel.TextColor3 = hasVal and colors.text or colors.text_muted
	end

	local function isSelected(opt: string): boolean
		if multi then
			return selected[opt] == true
		end
		return single == opt
	end

	local rebuild -- fwd
	local function fireMulti(): { string }
		local list = {}
		for _, opt in options do
			if selected[opt] then
				table.insert(list, opt)
			end
		end
		return list
	end

	rebuild = function()
		for _, child in menu:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		for i, opt in options do
			local sel = isSelected(opt)
			local optBtn = Create("TextButton", {
				Name = opt,
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
				Create.padding(7, 9),
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
				Parent = optBtn,
			})
			local tick = Icons.new("check", 14, ctx.Accent)
			tick.Visible = sel;
			(tick :: any).Parent = tickHolder

			Create("TextLabel", {
				Name = "Label",
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 0, 16),
				Text = opt,
				TextColor3 = sel and colors.text or colors.text_muted,
				TextSize = 13,
				FontFace = Theme.Font.Regular,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 2,
				Parent = optBtn,
			})

			optBtn.MouseEnter:Connect(function()
				Tween.play(optBtn, Tween.Fast, { BackgroundTransparency = 0 })
			end)
			optBtn.MouseLeave:Connect(function()
				Tween.play(optBtn, Tween.Fast, { BackgroundTransparency = 1 })
			end)
			optBtn.Activated:Connect(function()
				if multi then
					selected[opt] = not selected[opt] or nil
					relabel()
					rebuild()
					if opts.Callback then
						opts.Callback(fireMulti())
					end
				else
					single = opt
					relabel()
					ctx:ClosePopover()
					if opts.Callback then
						opts.Callback(single)
					end
				end
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
		menu.Size = UDim2.fromOffset(math.max(box.AbsoluteSize.X, 150), 0)
		setOpenVisual(true)
		ctx:OpenPopover(menu, box, function()
			setOpenVisual(false)
		end)
	end)
	hover(box, colors.control, colors.control_hi)

	ctx:RegisterAccent(function() end) -- ticks/box read ctx.Accent live on open
	relabel()

	local handle = {}
	function handle:Get(): any
		if multi then
			return fireMulti()
		end
		return single
	end
	function handle:Set(value: any)
		if multi then
			selected = {}
			if type(value) == "table" then
				for _, v in value do
					selected[v] = true
				end
			end
		else
			single = value
		end
		relabel()
		if opts.Callback then
			opts.Callback(multi and fireMulti() or single)
		end
	end

	return f.field, handle, true
end

return build
