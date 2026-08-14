--!strict
-- components/Dropdown.lua — single + multi select.
-- Box is a TextButton; the menu lives in the window overlay (high ZIndex) so it
-- escapes the scrolling content's clip. Single sets + closes; multi toggles a
-- check per option and stays open. Outside click closes (Context popover).

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)
local Log = require(script.Parent.Parent.util.Log)
local Field = require(script.Parent.Field)

local MENU_MAX_H = 232 -- popover height cap; options scroll past it
local MENU_MIN_W = 150

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
	local where = Log.where(multi and "MultiDropdown" or "Dropdown", opts.Name)
	if opts.Options ~= nil and type(opts.Options) ~= "table" then
		Log.fail(where, ("Options must be an array of strings, got %s"):format(typeof(opts.Options)))
	end
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
	-- The option list lives in a ScrollingFrame capped at MENU_MAX_H: it used to be
	-- a plain auto-sized frame under a UISizeConstraint, which silently clipped
	-- every option past the sixth with no way to reach them.
	-- A Frame, not a CanvasGroup: a CanvasGroup would rasterize every option
	-- label into a buffer and blur it. Context:OpenPopover fades it in with
	-- util/Fade.lua instead, and ClipsDescendants does the clipping the group's
	-- canvas used to do for free.
	local menu = Create("Frame", {
		Name = "DropdownMenu",
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
		Name = "Options",
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
	-- AutomaticSize, so the menu is exactly as tall as its options up to
	-- MENU_MAX_H and scrolls beyond it. (The canvas keeps auto-sizing, which is
	-- what gives the overflow something to scroll through.)
	local optionLayout = scroller:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	local function fitMenu()
		scroller.Size = UDim2.new(1, 0, 0, math.min(MENU_MAX_H, optionLayout.AbsoluteContentSize.Y))
	end
	optionLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitMenu)

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

	local function fireMulti(): { string }
		local list = {}
		for _, opt in options do
			if selected[opt] then
				table.insert(list, opt)
			end
		end
		return list
	end

	-- Live row handles so toggling a multi-select option repaints just that row.
	-- Rebuilding the whole menu on every click dropped hover states and re-ran the
	-- open animation mid-interaction.
	type Row = { tick: GuiObject, label: TextLabel }
	local rows: { [string]: Row } = {}

	local function paintRow(opt: string)
		local row = rows[opt]
		if not row then
			return
		end
		local sel = isSelected(opt)
		row.tick.Visible = sel
		row.label.TextColor3 = sel and colors.text or colors.text_muted
	end

	local function rebuild()
		table.clear(rows)
		for _, child in scroller:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		for i, opt in options do
			local optBtn = Create("TextButton", {
				Name = opt,
				AutoButtonColor = false,
				Text = "",
				BackgroundColor3 = colors.control_hi,
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, -4, 0, 0), -- -4 keeps rows clear of the scrollbar
				LayoutOrder = i,
				Parent = scroller,
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
			tick.Visible = false;
			(tick :: any).Parent = tickHolder

			-- Offset-sized + truncated: an option longer than the menu used to grow
			-- past its edge and get clipped by the menu instead of eliding.
			local label = Create("TextLabel", {
				Name = "Label",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -24, 0, 16),
				Text = opt,
				TextColor3 = colors.text_muted,
				TextSize = 13,
				FontFace = Theme.Font.Regular,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 2,
				Parent = optBtn,
			})

			rows[opt] = { tick = tick, label = label }
			paintRow(opt)

			optBtn.MouseEnter:Connect(function()
				Tween.play(optBtn, Tween.Fast, { BackgroundTransparency = 0 })
			end)
			optBtn.MouseLeave:Connect(function()
				Tween.play(optBtn, Tween.Fast, { BackgroundTransparency = 1 })
			end)
			optBtn.Activated:Connect(function()
				if multi then
					selected[opt] = not selected[opt] or nil
					paintRow(opt)
					relabel()
					if opts.Callback then
						task.spawn(opts.Callback, fireMulti())
					end
				else
					local previous = single
					single = opt
					if previous then
						paintRow(previous)
					end
					paintRow(opt)
					relabel()
					ctx:ClosePopover()
					if opts.Callback then
						task.spawn(opts.Callback, single)
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
		fitMenu()
		scroller.CanvasPosition = Vector2.new(0, 0)
		menu.Size = UDim2.fromOffset(math.max(box.AbsoluteSize.X, MENU_MIN_W), 0)
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
		for opt in rows do
			paintRow(opt)
		end
		if opts.Callback then
			task.spawn(opts.Callback, multi and fireMulti() or single)
		end
	end
	-- Replace the option list at runtime (e.g. a refreshed saved-config list).
	-- Drops any selection that's no longer present so the label stays honest.
	function handle:SetOptions(list: { string })
		options = list or {}
		local function present(v: string): boolean
			for _, o in options do
				if o == v then
					return true
				end
			end
			return false
		end
		if multi then
			for key in selected do
				if not present(key) then
					selected[key] = nil
				end
			end
		elseif single ~= nil and not present(single) then
			single = nil
		end
		relabel()
		if ctx:IsOpen(menu) then
			rebuild()
		end
	end

	return f.field, handle, true
end

return build
