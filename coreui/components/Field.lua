--!strict
-- components/Field.lua — the row scaffold every control sits on.
--
-- Layout mirrors `.coreui-field` from the CSS: 10px vertical padding, a flex
-- row with a name/description block on the left and the control on the right.
-- "Stacked" fields (slider, input, full-width dropdown/button) drop the control
-- to its own full-width line below the row.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)

local Field = {}

export type Field = {
	field: Frame, -- the whole field (parent for stacked controls)
	row: Frame,   -- the name | control row (parent for inline controls)
	main: Frame?, -- the name/description block, if a Name was given
}

function Field.new(ctx: any, opts: { Name: string?, Desc: string? }, stack: boolean?): Field
	local colors = Theme.Colors

	local field = Create("Frame", {
		Name = "Field",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Create.padding(10, 2),
		Create.listLayout({ Padding = UDim.new(0, 9) }),
	})

	local ROW_GAP = 14
	local row = Create("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = field,
	}, {
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, ROW_GAP),
		}),
	})

	local main: Frame? = nil
	if opts.Name then
		local block = Create("Frame", {
			Name = "Main",
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = row,
		}, {
			Create.listLayout({ Padding = UDim.new(0, 3) }),
		})

		Create("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = opts.Name,
			TextColor3 = colors.text,
			TextSize = 13,
			FontFace = Theme.Font.Regular,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			LayoutOrder = 1,
			Parent = block,
		})

		if opts.Desc then
			Create("TextLabel", {
				Name = "Desc",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = opts.Desc,
				TextColor3 = colors.text_muted,
				TextSize = 12,
				FontFace = Theme.Font.Regular,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true,
				LineHeight = 1.1,
				LayoutOrder = 2,
				Parent = block,
			})
		end
		main = block

		-- No flexbox: the label block consumes the row's leftover width so the
		-- control (added by the caller into `row`) lands flush right. Width is
		-- the row minus every sibling's measured width and the gap to each.
		local function syncMain()
			local used, others = 0, 0
			for _, child in row:GetChildren() do
				if child:IsA("GuiObject") and child ~= block then
					used += child.AbsoluteSize.X
					others += 1
				end
			end
			local avail = row.AbsoluteSize.X - used - others * ROW_GAP
			block.Size = UDim2.new(0, math.max(0, avail), 0, 0)
		end
		row:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncMain)
		row.ChildAdded:Connect(function(child)
			if child:IsA("GuiObject") then
				child:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncMain)
			end
			task.defer(syncMain)
		end)
		task.defer(syncMain)
	end

	return { field = field, row = row, main = main }
end

return Field
