--!strict
-- components/Slider.lua — 6px pill track, accent fill, 15px white knob.
-- Live drag via UserInputService (no tween), clamped + stepped.

local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Field = require(script.Parent.Field)

local function clamp(v: number, a: number, b: number): number
	return math.max(a, math.min(b, v))
end

local function format(v: number, suffix: string): string
	return ("%g"):format(v) .. suffix
end

return function(ctx: any, opts: any)
	local colors = Theme.Colors
	local min = opts.Min or 0
	local max = opts.Max or 100
	local step = opts.Step or 1
	local suffix = opts.Suffix or ""
	local value = clamp(opts.Default or min, min, max)

	local f = Field.new(ctx, opts, true)

	local valBox = Create("TextLabel", {
		Name = "Value",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(38, 22),
		BackgroundColor3 = colors.control,
		Text = format(value, suffix),
		TextColor3 = colors.text_muted,
		TextSize = 12,
		FontFace = Theme.Font.Medium,
		LayoutOrder = 2,
		Parent = f.row,
	}, {
		Create.corner(6),
		Create.stroke(colors.border),
		Create.padding(2, 9),
		Create("UISizeConstraint", { MinSize = Vector2.new(38, 22) }),
	})

	local track = Create("TextButton", {
		Name = "Slider",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = colors.toggle_off,
		LayoutOrder = 2,
		Parent = f.field,
	}, {
		Create.corner(999),
	})

	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = ctx.Accent,
		Parent = track,
	}, {
		Create.corner(999),
	})

	local knob = Create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(15, 15),
		BackgroundColor3 = colors.white,
		ZIndex = 2,
		Parent = track,
	}, {
		Create.corner(999),
		Create("UIScale", {}),
	})
	local knobScale = knob:FindFirstChildOfClass("UIScale") :: UIScale

	local function render()
		local pct = (value - min) / (max - min)
		fill.Size = UDim2.fromScale(pct, 1)
		knob.Position = UDim2.fromScale(pct, 0.5)
		valBox.Text = format(value, suffix)
	end

	local function setFromX(x: number)
		local pct = clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local raw = min + pct * (max - min)
		value = clamp(math.round(raw / step) * step, min, max)
		render()
		if opts.Callback then
			opts.Callback(value)
		end
	end

	local dragging = false
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			Tween.play(knobScale, Tween.Spring, { Scale = 1.3 }) -- grow while grabbed
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			if dragging then
				Tween.play(knobScale, Tween.Spring, { Scale = 1 }) -- settle back on release
			end
			dragging = false
		end
	end)

	ctx:RegisterAccent(function(accent)
		fill.BackgroundColor3 = accent
	end)
	render()

	local handle = {}
	function handle:Get(): number
		return value
	end
	function handle:Set(v: number)
		value = clamp(v, min, max)
		render()
		if opts.Callback then
			opts.Callback(value)
		end
	end

	return f.field, handle, true
end
