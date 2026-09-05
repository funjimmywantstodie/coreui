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

	local keyLabel = Create("TextLabel", {
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

	-- The value WRAPS in whatever the key leaves it, right-aligned. It used to
	-- auto-size on X too, anchored to the right edge — so a long value (a feature
	-- list, a path) grew leftward straight through the key and out of the card,
	-- with nothing clipping it. Width is set by hand from the key's measured
	-- width, like components/Field.lua's `syncMain`, because two auto-sized
	-- labels in one row have no way to negotiate it.
	local GAP = 12
	local valueLabel = Create("TextLabel", {
		Name = "Value",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(1, 0, 0, 0),
		Text = opts.Value or "",
		TextColor3 = colors.text,
		TextSize = 13,
		FontFace = Theme.Font.Medium,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Parent = row,
	})
	local function fitValue()
		local keyW = keyLabel.AbsoluteSize.X
		valueLabel.Size = UDim2.new(1, -(keyW > 0 and keyW + GAP or 0), 0, 0)
	end
	keyLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitValue)
	fitValue()

	local handle = {}
	function handle:Set(value: string)
		valueLabel.Text = value
	end

	return row, handle, true
end
