--!strict
-- components/List.lua — bullet list. Items: { Name?, Value?, Text?, Dim? }.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)

return function(ctx: any, items: { any })
	local colors = Theme.Colors

	local list = Create("Frame", {
		Name = "List",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Create.padding(6, 2),
		Create.listLayout({ Padding = UDim.new(0, 2) }),
	})

	for i, item in items or {} do
		local dim = item.Dim == true
		local dotColor = dim and colors.text_dim or colors.text_muted

		local li = Create("Frame", {
			Name = "Item",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = i,
			Parent = list,
		}, {
			Create.listLayout({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				Padding = UDim.new(0, 9),
			}),
		})

		Create("Frame", {
			Name = "Dot",
			BackgroundColor3 = dotColor,
			Size = UDim2.fromOffset(4, 4),
			Position = UDim2.fromOffset(3, 6),
			LayoutOrder = 1,
			Parent = li,
		}, { Create.corner(999) })

		local text: string
		if item.Name then
			text = item.Name .. ":  " .. (item.Value or "")
		else
			text = item.Text or ""
		end

		Create("TextLabel", {
			Name = "Text",
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -13, 0, 0),
			Text = text,
			TextColor3 = dim and colors.text_dim or colors.text_muted,
			TextSize = 13,
			FontFace = Theme.Font.Regular,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			LayoutOrder = 2,
			Parent = li,
		})
	end

	return list, {}, false
end
