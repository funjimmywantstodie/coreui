--!strict
-- util/Collapse.lua — animate a frame collapsing/expanding by height.
--
-- Wraps an AutomaticSize.Y `content` frame in a ClipsDescendants holder whose
-- height is what actually animates. While open the holder tracks the content via
-- AutomaticSize.Y (so dynamically-added controls still grow it); during the
-- collapse/expand it switches to a manual offset height that we tween to/from 0.
-- The content keeps its natural size the whole time (clipping only hides it), so
-- the target height can be read straight off it even while collapsed.

local Tween = require(script.Parent.Tween)
local Create = require(script.Parent.Create)

local Collapse = {}

-- `content` must be (1, 0) wide with AutomaticSize.Y. Returns the holder to drop
-- into the surrounding layout, plus `set(collapsed, animate)`.
function Collapse.wrap(content: GuiObject, startCollapsed: boolean): (Frame, (boolean, boolean?) -> ())
	local holder = Create("Frame", {
		Name = "Collapse",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		ClipsDescendants = true,
		AutomaticSize = startCollapsed and Enum.AutomaticSize.None or Enum.AutomaticSize.Y,
	})
	content.Parent = holder

	local collapsed = startCollapsed
	local activeTween: Tween? = nil

	local function set(value: boolean, animate: boolean?)
		if value == collapsed then
			return
		end
		collapsed = value
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end

		if not animate then
			holder.AutomaticSize = value and Enum.AutomaticSize.None or Enum.AutomaticSize.Y
			holder.Size = UDim2.new(1, 0, 0, value and 0 or content.AbsoluteSize.Y)
			return
		end

		-- Hand height control to a manual offset for the duration of the tween.
		holder.AutomaticSize = Enum.AutomaticSize.None
		if value then
			-- collapse: freeze at the current rendered height, slide to 0
			holder.Size = UDim2.new(1, 0, 0, holder.AbsoluteSize.Y)
			activeTween = Tween.play(holder, Tween.Slide, { Size = UDim2.new(1, 0, 0, 0) })
		else
			-- expand: slide up to the content's natural height, then hand back to
			-- AutomaticSize so later content changes keep tracking
			local target = content.AbsoluteSize.Y
			local t = Tween.play(holder, Tween.Slide, { Size = UDim2.new(1, 0, 0, target) })
			activeTween = t
			t.Completed:Once(function(state)
				if state == Enum.PlaybackState.Completed and not collapsed then
					holder.AutomaticSize = Enum.AutomaticSize.Y
				end
			end)
		end
	end

	return holder, set
end

return Collapse
