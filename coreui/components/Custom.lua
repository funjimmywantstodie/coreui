--!strict
-- components/Custom.lua — escape hatch for parenting arbitrary Instances into
-- a Group/Section, for tools shaped nothing like the built-in controls (data
-- grids, custom previews, bespoke widgets).
--
-- `frame` is already (1,0)-wide + AutomaticSize.Y, matching the height-
-- reporting contract every control relies on (see CLAUDE.md "Adding a new
-- control") — nest your own content into it directly. If you need a fixed-
-- height scrollable viewport instead of unbounded growth, wrap a fixed-size
-- ScrollingFrame inside `frame`, the same way components/Code.lua does.

local Create = require(script.Parent.Parent.util.Create)

return function(ctx: any, builder: ((any, Frame) -> ())?): (Frame, {}, boolean)
	local frame = Create("Frame", {
		Name = "Custom",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}) :: Frame

	if builder then
		builder(ctx, frame)
	end

	return frame, {}, false
end
