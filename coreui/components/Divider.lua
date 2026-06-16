--!strict
-- components/Divider.lua — a hairline with 6px breathing room above/below.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)

return function(ctx: any, _opts: any)
	local holder = Create("Frame", {
		Name = "Divider",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 13),
	}, {
		Create("Frame", {
			Name = "Line",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Theme.Colors.border_soft,
			BorderSizePixel = 0,
		}),
	})
	-- The divider is itself the separating line → no managed bottom border.
	return holder, {}, false
end
