--!strict
-- components/Input.lua — full-width 36px TextBox, accent stroke on focus.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Field = require(script.Parent.Field)

return function(ctx: any, opts: any)
	local colors = Theme.Colors
	local f = Field.new(ctx, opts, true)

	local box = Create("TextBox", {
		Name = "Input",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = colors.control,
		Text = opts.Default or "",
		PlaceholderText = opts.Placeholder or "",
		PlaceholderColor3 = colors.text_dim,
		TextColor3 = colors.text,
		TextSize = 13,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		LayoutOrder = 2,
		Parent = f.field,
	}, {
		Create.corner(Theme.Metrics.controlRadius),
		Create.stroke(colors.border),
		Create.padding(0, 12),
	})
	local stroke = box:FindFirstChildOfClass("UIStroke") :: UIStroke

	box.Focused:Connect(function()
		Tween.play(stroke, Tween.Fast, { Color = ctx.Accent })
	end)
	box.FocusLost:Connect(function(enterPressed)
		Tween.play(stroke, Tween.Fast, { Color = colors.border })
		if enterPressed and opts.OnEnter then
			opts.OnEnter(box.Text)
		end
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if opts.Callback then
			opts.Callback(box.Text)
		end
	end)

	local handle = {}
	function handle:Get(): string
		return box.Text
	end
	function handle:Set(value: string)
		box.Text = value
	end

	return f.field, handle, true
end
