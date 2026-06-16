--!strict
-- util/Create.lua — tiny instance factory + common UI helpers.
--
--   Create("Frame", { Size = ..., Parent = ... }, { childA, childB })
--
-- Props are assigned in order; `Parent` is always applied last so children
-- exist before the instance enters the tree. Helper constructors (corner,
-- stroke, padding, listLayout) cover the boilerplate instances used everywhere.

local Create = setmetatable({}, {
	__call = function(_, className: string, props: { [string]: any }?, children: { Instance }?): any
		local inst = Instance.new(className)
		local parent
		if props then
			for key, value in props do
				if key == "Parent" then
					parent = value
				else
					(inst :: any)[key] = value
				end
			end
		end
		if children then
			for _, child in children do
				child.Parent = inst
			end
		end
		inst.Parent = parent
		return inst
	end,
})

function Create.corner(radius: number): UICorner
	return Create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function Create.stroke(color: Color3, thickness: number?): UIStroke
	return Create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		-- Round joins trace the UICorner arc smoothly instead of cutting it with
		-- mitred corners, which is what made bordered cards/controls look jagged.
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

function Create.padding(top: number, right: number?, bottom: number?, left: number?): UIPadding
	right = right or top
	bottom = bottom or top
	left = left or right
	return Create("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom),
		PaddingLeft = UDim.new(0, left),
	})
end

function Create.listLayout(props: { [string]: any }?): UIListLayout
	local layout = Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Vertical,
	})
	if props then
		for key, value in props do
			(layout :: any)[key] = value
		end
	end
	return layout
end

return Create
