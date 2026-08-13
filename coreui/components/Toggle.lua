--!strict
-- components/Toggle.lua — 42×23 pill, 17px knob, +19px travel.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Field = require(script.Parent.Field)

local OFF_POS = UDim2.fromOffset(3, 3)
local ON_POS = UDim2.fromOffset(22, 3) -- 3 + 19px travel

return function(ctx: any, opts: any)
	local colors = Theme.Colors
	local f = Field.new(ctx, opts)
	local state = opts.Default == true

	local track = Create("TextButton", {
		Name = "Toggle",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(42, 23),
		BackgroundColor3 = colors.toggle_off,
		LayoutOrder = 2,
		Parent = f.row,
	}, {
		Create.corner(999),
	})

	local knob = Create("Frame", {
		Name = "Knob",
		Size = UDim2.fromOffset(17, 17),
		Position = OFF_POS,
		BackgroundColor3 = colors.knob,
		Parent = track,
	}, {
		Create.corner(999),
	})

	local function paint(animate: boolean)
		local trackColor = state and ctx.Accent or colors.toggle_off
		-- on = knockout knob on the accent track, off = text-faint knob on surface
		local knobColor = state and colors.knockout or colors.knob
		local pos = state and ON_POS or OFF_POS
		if animate then
			Tween.play(track, Tween.Normal, { BackgroundColor3 = trackColor })
			Tween.play(knob, Tween.Normal, { BackgroundColor3 = knobColor })
			Tween.play(knob, Tween.Spring, { Position = pos }) -- slight overshoot on the slide
		else
			track.BackgroundColor3 = trackColor
			knob.BackgroundColor3 = knobColor
			knob.Position = pos
		end
	end

	local handle = {}
	function handle:Get(): boolean
		return state
	end
	function handle:Set(value: boolean)
		state = value == true
		paint(true)
		if opts.Callback then
			task.spawn(opts.Callback, state)
		end
	end

	track.Activated:Connect(function()
		handle:Set(not state)
	end)

	ctx:RegisterAccent(function()
		paint(false)
	end)

	return f.field, handle, true
end
