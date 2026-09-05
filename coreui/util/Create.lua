--!strict
-- util/Create.lua — tiny instance factory + common UI helpers.
--
--   Create("Frame", { Size = ..., Parent = ... }, { childA, childB })
--
-- `Parent` is always applied LAST, so children exist before the instance enters
-- the tree. Everything else is assigned in whatever order the table iterates —
-- which is a hash order, i.e. arbitrary and not the source order, whatever the
-- literal looks like. (This used to be documented as "props are assigned in
-- order", which is not true and is exactly the sort of thing someone eventually
-- writes an order-dependent pair against.) Nothing in the library depends on
-- one property landing before another; if you ever need that, set it explicitly
-- after the call rather than relying on the literal's layout.
--
-- Helper constructors (corner, stroke, padding, listLayout) cover the
-- boilerplate instances used everywhere.

-- util/Tween.lua only requires util/Services.lua, so there's no cycle back here.
local Tween = require(script.Parent.Tween)

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

-- The hover pair: tween `prop` to `over` on MouseEnter, back to `base` on
-- MouseLeave, at Tween.Fast.
--
--   Create.hover(button, "BackgroundColor3", colors.control, colors.control_hi)
--
-- This was the same six lines at eight call sites — and at two of them
-- (components/Dropdown.lua, components/PlayerSelect.lua) it was already the same
-- private `hover` helper, copied verbatim into both files. It isn't a deep
-- abstraction; it's the shape a hover has in this library, written once so a new
-- control doesn't re-derive it and so `Tween.Fast` stays the single answer to
-- "how fast is a hover" rather than whatever got pasted alongside it.
--
-- Returns the instance (so it can be chained) and `set(base, over)`, which
-- re-points both ends AND repaints immediately if the pointer is currently
-- inside. That second part is what an accent-coloured control needs:
-- `Window:SetAccent` can move the colour out from under a button the cursor is
-- already sitting on, and every call site that handled this before had to track
-- its own `hovering` boolean to do it.
--
-- Deliberately not for every MouseEnter in the library — a hover that runs a
-- state machine (components/BindChip.lua), tints an icon (components/Hud.lua) or
-- animates a different instance than the one under the pointer
-- (components/Colorpicker.lua) is a different shape and stays hand-written.
function Create.hover<T>(inst: GuiObject, prop: string, base: T, over: T): (GuiObject, (T, T) -> ())
	local restingValue, hoverValue = base, over
	local inside = false
	inst.MouseEnter:Connect(function()
		inside = true
		Tween.play(inst, Tween.Fast, { [prop] = hoverValue })
	end)
	inst.MouseLeave:Connect(function()
		inside = false
		Tween.play(inst, Tween.Fast, { [prop] = restingValue })
	end)
	return inst, function(newBase: T, newOver: T)
		restingValue, hoverValue = newBase, newOver;
		-- Snapped, not tweened: this is a re-theme landing, not an interaction.
		-- (The `;` above is load-bearing — without it Lua reads the `(` as a call
		-- on the previous line's last value.)
		(inst :: any)[prop] = inside and hoverValue or restingValue
	end
end

-- The edge half of a control's hover: a UIStroke's Color tweened `base` → `over`
-- while the pointer is on `inst`, at Tween.Fast like `Create.hover`. Same shape,
-- same `set(base, over)` return, split out because a stroke isn't a GuiObject
-- and has no MouseEnter of its own — it has to borrow the control's.
--
-- Every control resting inside a card draws its edge in `border_soft` and firms
-- it to `border` on hover (see the note on the two line weights in Theme.lua), so
-- this is called next to `Create.hover` on the fill at each of those sites.
function Create.edge(inst: GuiObject, stroke: UIStroke, base: Color3, over: Color3): ((Color3, Color3) -> ())
	local restingValue, hoverValue = base, over
	local inside = false
	inst.MouseEnter:Connect(function()
		inside = true
		Tween.play(stroke, Tween.Fast, { Color = hoverValue })
	end)
	inst.MouseLeave:Connect(function()
		inside = false
		Tween.play(stroke, Tween.Fast, { Color = restingValue })
	end)
	return function(newBase: Color3, newOver: Color3)
		restingValue, hoverValue = newBase, newOver
		stroke.Color = inside and hoverValue or restingValue
	end
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
