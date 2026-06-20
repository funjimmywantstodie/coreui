--!strict
-- components/Colorpicker.lua — swatch button + preset grid popover with hex.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Field = require(script.Parent.Field)

local DEFAULT_PRESETS = {
	"f2680c", "ff5757", "ffb020", "34c759", "2dd4bf", "3b82f6",
	"8b5cf6", "ec4899", "ededf0", "8c8c94", "3a3a3e", "161618",
}

local function toHex(color: Color3): string
	return ("#%02X%02X%02X"):format(
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

return function(ctx: any, opts: any)
	local colors = Theme.Colors
	local f = Field.new(ctx, opts)
	local value: Color3 = opts.Default or Color3.fromHex("f2680c")

	local swatch = Create("TextButton", {
		Name = "Colorpicker",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = value,
		LayoutOrder = 2,
		Parent = f.row,
	}, {
		Create.corner(8),
		Create.stroke(colors.border),
	})

	local menu = Create("CanvasGroup", {
		Name = "ColorMenu",
		Visible = false,
		Size = UDim2.fromOffset(168, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.pop,
	}, {
		Create.corner(10),
		Create.stroke(colors.border),
		Create.padding(10),
		Create.listLayout({ Padding = UDim.new(0, 9) }),
	})

	local grid = Create("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = menu,
	}, {
		Create("UIGridLayout", {
			CellSize = UDim2.fromOffset(19, 19),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local hexLabel = Create("TextLabel", {
		Name = "Hex",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 14),
		Text = toHex(value),
		TextColor3 = colors.text_muted,
		TextSize = 12,
		FontFace = Theme.Font.Mono,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
		Parent = menu,
	})

	local function apply(color: Color3)
		value = color
		Tween.play(swatch, Tween.Normal, { BackgroundColor3 = color })
		hexLabel.Text = toHex(color)
		if opts.Callback then
			task.spawn(opts.Callback, color)
		end
	end

	for i, hex in (opts.Presets or DEFAULT_PRESETS) do
		local chip = Create("TextButton", {
			Name = "Chip" .. i,
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = Color3.fromHex(hex),
			LayoutOrder = i,
			Parent = grid,
		}, {
			Create.corner(6),
			Create("UIStroke", { Color = colors.white, Transparency = 0.9 }),
			Create("UIScale", {}),
		})
		local chipScale = chip:FindFirstChildOfClass("UIScale") :: UIScale
		chip.MouseEnter:Connect(function()
			Tween.play(chipScale, Tween.Spring, { Scale = 1.18 })
		end)
		chip.MouseLeave:Connect(function()
			Tween.play(chipScale, Tween.Fast, { Scale = 1 })
		end)
		chip.Activated:Connect(function()
			apply(chip.BackgroundColor3)
			ctx:ClosePopover()
		end)
	end

	swatch.Activated:Connect(function()
		if ctx:IsOpen(menu) then
			ctx:ClosePopover()
		else
			ctx:OpenPopover(menu, swatch)
		end
	end)

	local handle = {}
	function handle:Get(): Color3
		return value
	end
	function handle:Set(color: Color3)
		apply(color)
	end

	return f.field, handle, true
end
