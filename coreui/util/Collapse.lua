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
	local watcher: RBXScriptConnection? = nil
	-- Bumped by every `set`, so a tween/watcher left over from the previous state
	-- can't finalise on top of the current one.
	local generation = 0

	local function stop()
		generation += 1
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end
		if watcher then
			watcher:Disconnect()
			watcher = nil
		end
	end

	-- Expanding measures a target the content can't honestly report yet: while
	-- collapsed the holder is 0px and clipping, so the subtree isn't rendered and
	-- anything sized from a render pass (wrapped text, auto-sized rows still
	-- settling) measures short or not at all. Tweening to that snapshot and then
	-- handing height back to AutomaticSize made the panel slide part of the way
	-- and snap the remainder in. So the expand watches the content and re-aims
	-- while it's in flight: a re-aim starts from the height the holder is at right
	-- now, so the motion stays continuous and simply carries on to the real one.
	local function expand()
		local gen = generation
		local target = -1

		local function slideTo(height: number)
			if activeTween then
				activeTween:Cancel()
			end
			local t = Tween.play(holder, Tween.Slide, { Size = UDim2.new(1, 0, 0, height) })
			activeTween = t
			t.Completed:Once(function(state)
				if gen ~= generation or state ~= Enum.PlaybackState.Completed then
					return
				end
				-- Landed on the content's own height: hand tracking back so later
				-- content changes keep growing the holder.
				if watcher then
					watcher:Disconnect()
					watcher = nil
				end
				activeTween = nil
				holder.AutomaticSize = Enum.AutomaticSize.Y
			end)
		end

		watcher = content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if gen ~= generation then
				return
			end
			local height = content.AbsoluteSize.Y
			-- Sub-pixel churn isn't worth restarting the tween over.
			if math.abs(height - target) < 0.5 then
				return
			end
			target = height
			slideTo(height)
		end)

		target = content.AbsoluteSize.Y
		if target > 0 then
			slideTo(target)
		end
		-- target == 0 means the content has never been laid out (a group built
		-- collapsed and opened before its first render). Nothing to slide to yet —
		-- the watcher above starts the slide the frame it measures.
	end

	local function set(value: boolean, animate: boolean?)
		if value == collapsed then
			return
		end
		collapsed = value
		stop()

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
			expand()
		end
	end

	return holder, set
end

return Collapse
