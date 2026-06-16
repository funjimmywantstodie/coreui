--!strict
-- components/Label.lua — key / value row; handle :Set(v) updates the value.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)

return function(ctx: any, opts: any)
	local colors = Theme.Colors

	local row = Create("Frame", {
		Name = "Label",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Create.padding(9, 2),
	})

	Create("TextLabel", {
		Name = "Key",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Position = UDim2.fromScale(0, 0),
		Text = opts.Key or "",
		TextColor3 = colors.text_muted,
		TextSize = 13,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local valueLabel = Create("TextLabel", {
		Name = "Value",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Text = opts.Value or "",
		TextColor3 = colors.text,
		TextSize = 13,
		FontFace = Theme.Font.Medium,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local handle = {}
	function handle:Set(value: string)
		valueLabel.Text = value
	end

	return row, handle, true
end
