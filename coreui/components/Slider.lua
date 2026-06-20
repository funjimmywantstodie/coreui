--!strict
-- components/Slider.lua — 6px pill track, accent fill, 15px white knob.
-- Live drag via UserInputService (no tween), clamped + stepped.

local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Field = require(script.Parent.Field)

local function clamp(v: number, a: number, b: number): number
	return math.max(a, math.min(b, v))
end

local function format(v: number, suffix: string): string
	return ("%g"):format(v) .. suffix
end

return function(ctx: any, opts: any)
	local colors = Theme.Colors
	local min = opts.Min or 0
	local max = opts.Max or 100
	local step = opts.Step or 1
	local suffix = opts.Suffix or ""
	local value = clamp(opts.Default or min, min, max)

	local f = Field.new(ctx, opts, true)

	local valBox = Create("TextLabel", {
		Name = "Value",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(38, 22),
		BackgroundColor3 = colors.control,
		Text = format(value, suffix),
		TextColor3 = colors.text_muted,
		TextSize = 12,
		FontFace = Theme.Font.Medium,
		LayoutOrder = 2,
		Parent = f.row,
	}, {
		Create.corner(6),
		Create.stroke(colors.border),
		Create.padding(2, 9),
		Create("UISizeConstraint", { MinSize = Vector2.new(38, 22) }),
	})

	local track = Create("TextButton", {
		Name = "Slider",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = colors.toggle_off,
		LayoutOrder = 2,
		Parent = f.field,
	}, {
		Create.corner(999),
	})

	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = ctx.Accent,
		Parent = track,
	}, {
		Create.corner(999),
	})

	local knob = Create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(15, 15),
		BackgroundColor3 = colors.white,
		ZIndex = 2,
		Parent = track,
	}, {
		Create.corner(999),
		Create("UIScale", {}),
	})
	local knobScale = knob:FindFirstChildOfClass("UIScale") :: UIScale

	local function snap(v: number): number
		-- guard a zero step so a bad config can't divide-by-zero. (Explicit if,
		-- not `and/or` — the snapped value can legitimately be 0, which the idiom
		-- would mistake for false and fall through to v.)
		if step > 0 then
			return math.round(v / step) * step
		end
		return v
	end

	local function render()
		-- guard min==max (degenerate range) so the ratio never produces NaN
		local span = max - min
		local pct = span ~= 0 and (value - min) / span or 0
		fill.Size = UDim2.fromScale(pct, 1)
		knob.Position = UDim2.fromScale(pct, 0.5)
		valBox.Text = format(value, suffix)
	end

	local function setFromX(x: number)
		local span = track.AbsoluteSize.X
		local pct = span > 0 and clamp((x - track.AbsolutePosition.X) / span, 0, 1) or 0
		value = clamp(snap(min + pct * (max - min)), min, max)
		render()
		if opts.Callback then
			opts.Callback(value)
		end
	end

	-- The move/release listeners are global (UserInputService), so they're only
	-- connected for the duration of a drag and torn down on release. That avoids
	-- N idle sliders each leaking a permanent listener that fires on every mouse
	-- move and survives Window:Destroy.
	local dragConns: { RBXScriptConnection } = {}
	local function endDrag()
		for _, c in dragConns do
			c:Disconnect()
		end
		table.clear(dragConns)
		Tween.play(knobScale, Tween.Spring, { Scale = 1 }) -- settle back on release
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			if #dragConns > 0 then
				return
			end
			Tween.play(knobScale, Tween.Spring, { Scale = 1.3 }) -- grow while grabbed
			setFromX(input.Position.X)
			table.insert(dragConns, UserInputService.InputChanged:Connect(function(move)
				if move.UserInputType == Enum.UserInputType.MouseMovement
					or move.UserInputType == Enum.UserInputType.Touch then
					setFromX(move.Position.X)
				end
			end))
			table.insert(dragConns, UserInputService.InputEnded:Connect(function(up)
				if up.UserInputType == Enum.UserInputType.MouseButton1
					or up.UserInputType == Enum.UserInputType.Touch then
					endDrag()
				end
			end))
		end
	end)

	ctx:RegisterAccent(function(accent)
		fill.BackgroundColor3 = accent
	end)
	render()

	local handle = {}
	function handle:Get(): number
		return value
	end
	function handle:Set(v: number)
		value = clamp(snap(v), min, max)
		render()
		if opts.Callback then
			opts.Callback(value)
		end
	end

	return f.field, handle, true
end
