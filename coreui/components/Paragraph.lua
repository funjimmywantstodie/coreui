--!strict
-- components/Paragraph.lua — optional title + body copy.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)

return function(ctx: any, opts: any)
	local colors = Theme.Colors

	local p = Create("Frame", {
		Name = "Paragraph",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Create.padding(11, 2),
		Create.listLayout({ Padding = UDim.new(0, 5) }),
	})

	if opts.Title then
		Create("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = opts.Title,
			TextColor3 = colors.text,
			TextSize = 13,
			FontFace = Theme.Font.Medium,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			LayoutOrder = 1,
			Parent = p,
		})
	end

	Create("TextLabel", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = opts.Body or "",
		TextColor3 = colors.text_muted,
		TextSize = 12,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		LineHeight = 1.3,
		LayoutOrder = 2,
		Parent = p,
	})

	return p, {}, true
end
