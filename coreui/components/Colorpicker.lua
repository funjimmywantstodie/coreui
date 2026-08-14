--!strict
-- components/Colorpicker.lua — swatch button + preset grid popover with hex.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Log = require(script.Parent.Parent.util.Log)
local Field = require(script.Parent.Field)

-- Uranium accent ramp first, then the useful off-palette signals.
local DEFAULT_PRESETS = {
	"7be04a", "96ec69", "4e9b2b", "2dd4bf", "ffc53d", "ff6b6b",
	"3b82f6", "8b5cf6", "ec4899", "e9f2e5", "98a394", "171d15",
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
	local where = Log.where("Colorpicker", opts.Name)
	Log.field(where, "Default", opts.Default, "Color3")
	Log.field(where, "Presets", opts.Presets, "table")
	local f = Field.new(ctx, opts)
	-- ctx.Accent, not the static theme accent: a window built with a custom accent
	-- would otherwise hand an un-defaulted picker theme green as its swatch and as
	-- its :Get()/flag value.
	local value: Color3 = opts.Default or ctx.Accent

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

	-- Frame, not CanvasGroup — the hex readout inside it would come out blurry
	-- (see util/Fade.lua); Context:OpenPopover fades it in without a buffer.
	local menu = Create("Frame", {
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
		-- Presets are caller-supplied, and Color3.fromHex throws on anything it
		-- can't parse — so one typo in a menu's palette used to kill the whole
		-- window build with a raw engine error rather than the offending swatch.
		local okHex, preset = pcall(Color3.fromHex, hex)
		if not okHex then
			Log.warn(where, ('Preset #%d ("%s") isn\'t a hex colour — skipped.')
				:format(i, tostring(hex)))
			continue
		end
		local chip = Create("TextButton", {
			Name = "Chip" .. i,
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = preset,
			LayoutOrder = i,
			Parent = grid,
		}, {
			Create.corner(6),
			Create("UIStroke", { Color = colors.text, Transparency = 0.9 }),
			Create("UIScale", {}),
		})
		local chipScale = chip:FindFirstChildOfClass("UIScale") :: UIScale
		chip.MouseEnter:Connect(function()
			Tween.play(chipScale, Tween.Spring, { Scale = 1.18 })
		end)
		chip.MouseLeave:Connect(function()
			Tween.play(chipScale, Tween.Fast, { Scale = 1 })
		end)
		-- User-driven, so it's tagged for Context:OnFlagChanged — `handle:Set` and a
		-- config load reach `apply` too, and keep whatever tag they came in under.
		chip.Activated:Connect(function()
			ctx:User(apply, chip.BackgroundColor3)
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
