--!strict
-- components/List.lua — bullet list. Items: { Name?, Value?, Text?, Dim? }.
--
-- `handle:Set(items)` replaces the rows. It repaints the ones already on screen
-- and only builds what the new list needs beyond them, rather than clearing the
-- frame and rebuilding it: the list is `AutomaticSize.Y` inside a card that is
-- also `AutomaticSize.Y`, so an empty frame — even for the one frame it takes to
-- refill — collapses the card and everything under it jumps. Rows past the end
-- are hidden rather than destroyed, and UIListLayout skips invisible children,
-- so a list that oscillates between five and six entries stops allocating after
-- the first six.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)

-- "Name:  Value" when there's a key, otherwise the free-text line.
local function itemText(item: any): string
	if item.Name then
		return item.Name .. ":  " .. (item.Value or "")
	end
	return item.Text or ""
end

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

	-- The pool, in layout order. Each entry is the row frame plus the two things
	-- a repaint touches, held directly so no repaint costs a FindFirstChild.
	local rows: { { frame: Frame, dot: Frame, label: TextLabel } } = {}

	local function newRow(index: number)
		local li = Create("Frame", {
			Name = "Item",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = index,
			Parent = list,
		}, {
			Create.listLayout({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				Padding = UDim.new(0, 9),
			}),
		})

		local dot = Create("Frame", {
			Name = "Dot",
			BackgroundColor3 = colors.text_muted,
			Size = UDim2.fromOffset(4, 4),
			Position = UDim2.fromOffset(3, 6),
			LayoutOrder = 1,
			Parent = li,
		}, { Create.corner(999) })

		local label = Create("TextLabel", {
			Name = "Text",
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -13, 0, 0),
			Text = "",
			TextColor3 = colors.text_muted,
			TextSize = 13,
			FontFace = Theme.Font.Regular,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			LayoutOrder = 2,
			Parent = li,
		})

		local row = { frame = li, dot = dot, label = label }
		rows[index] = row
		return row
	end

	local function render(source: { any }?)
		local data = source or {}
		for i, item in data do
			local row = rows[i] or newRow(i)
			local dim = item.Dim == true
			local color = dim and colors.text_dim or colors.text_muted
			row.dot.BackgroundColor3 = color
			row.label.TextColor3 = color
			row.label.Text = itemText(item)
			row.frame.Visible = true
		end
		for i = #data + 1, #rows do
			rows[i].frame.Visible = false
		end
	end

	render(items)

	local handle = {}
	-- Replace the rows. Same item shape as the constructor takes; `nil` or an
	-- empty array empties the list without destroying the control.
	function handle:Set(data: { any }?)
		render(data)
	end

	return list, handle, false
end
