--!strict
-- components/Slider.lua — 6px pill track, accent fill, 15px white knob.
-- Live drag via UserInputService (no tween), clamped + stepped.

local Services = require(script.Parent.Parent.util.Services)

local UserInputService = Services.UserInputService

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Log = require(script.Parent.Parent.util.Log)
local Field = require(script.Parent.Field)

local function clamp(v: number, a: number, b: number): number
	return math.max(a, math.min(b, v))
end

local function format(v: number, suffix: string): string
	return ("%g"):format(v) .. suffix
end

local SCHEMA: Log.Schema = {
	{ "Min", "number" },
	{ "Max", "number" },
	{ "Step", "number" },
}

return function(ctx: any, opts: any)
	local colors = Theme.Colors
	local where = Log.where("Slider", opts.Name)
	Log.check(where, opts, SCHEMA)

	local min = opts.Min or 0
	local max = opts.Max or 100
	-- An inverted or collapsed range makes every position map to the same value
	-- (render()/snap() guard the maths, but the control would be dead). Warn and
	-- fall back to a sane [min, min+1] so it's at least usable.
	if min >= max then
		Log.warn(where, ("Min (%s) must be less than Max (%s) — using [%s, %s]."):format(
			("%g"):format(min), ("%g"):format(max), ("%g"):format(min), ("%g"):format(min + 1)))
		max = min + 1
	end
	local step = opts.Step or 1
	if step < 0 then
		Log.warn(where, ("Step (%s) can't be negative — using 1."):format(("%g"):format(step)))
		step = 1
	end
	local suffix = opts.Suffix or ""

	local function snap(v: number): number
		-- guard a zero step so a bad config can't divide-by-zero. (Explicit if,
		-- not `and/or` — the snapped value can legitimately be 0, which the idiom
		-- would mistake for false and fall through to v.)
		-- Steps are counted from min, not from zero: quantizing in absolute value
		-- space means a range like Min=1, Max=10, Step=2 lands on 2/4/6/8/10 and
		-- can never produce 1, so the slider couldn't report its own minimum.
		if step > 0 then
			return min + math.round((v - min) / step) * step
		end
		return v
	end

	-- The default is snapped as well as clamped, or the control opens showing a
	-- value it can't otherwise produce (and hands that value to :Get()/the config
	-- snapshot) until the first drag quietly moves it onto the grid.
	local value = clamp(snap(opts.Default or min), min, max)

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

	-- The grab area is 18px tall and transparent; the visible 6px rail is centered
	-- inside it. A 6px-tall button is a genuinely hard target to hit with a mouse
	-- (and near-impossible on touch), which is what made the slider feel broken.
	local track = Create("TextButton", {
		Name = "Slider",
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 2,
		Parent = f.field,
	})

	local rail = Create("Frame", {
		Name = "Rail",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = colors.toggle_off,
		Parent = track,
	}, {
		Create.corner(999),
	})

	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = ctx.Accent,
		Parent = rail,
	}, {
		Create.corner(999),
	})

	local knob = Create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(15, 15),
		-- Text (not knockout): at value 0 the knob sits off the accent fill, on
		-- the bare rail, where a knockout-dark knob would disappear.
		BackgroundColor3 = colors.text,
		ZIndex = 2,
		Parent = rail,
	}, {
		Create.corner(999),
		Create("UIScale", {}),
	})
	local knobScale = knob:FindFirstChildOfClass("UIScale") :: UIScale

	-- The value, over the knob, while a FINGER drags it: the thumb covers the
	-- knob and the value box is a row away. A sibling of the knob on the rail
	-- rather than a child of it, so the knob's grab-scale doesn't blow it up too.
	local bubble = Create("TextLabel", {
		Name = "Bubble",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0, 0, 0, -12),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		BackgroundColor3 = colors.pop,
		Text = "",
		TextColor3 = colors.text,
		TextSize = 13,
		FontFace = Theme.Font.Medium,
		ZIndex = 3,
		Parent = rail,
	}, {
		Create.corner(6),
		Create.stroke(colors.border),
		Create.padding(0, 9),
	})

	-- Thumb-sized grab area on a phone; the desktop's 18px stays.
	local function fitTouch()
		track.Size = UDim2.new(1, 0, 0, ctx:IsTouch() and 32 or 18)
	end
	fitTouch()
	local unsubscribeTouch = ctx:OnTouch(fitTouch)

	local function render()
		-- guard min==max (degenerate range) so the ratio never produces NaN
		local span = max - min
		local pct = span ~= 0 and (value - min) / span or 0
		fill.Size = UDim2.fromScale(pct, 1)
		knob.Position = UDim2.fromScale(pct, 0.5)
		local text = format(value, suffix)
		valBox.Text = text
		bubble.Text = text
		bubble.Position = UDim2.new(pct, 0, 0, -12)
	end

	-- Drag is the only caller, so the whole body is user-driven — tagged for
	-- Context:OnFlagChanged, which is how a host tells a slider someone dragged
	-- from one a script moved.
	local function setFromX(x: number)
		local span = rail.AbsoluteSize.X
		local pct = span > 0 and clamp((x - rail.AbsolutePosition.X) / span, 0, 1) or 0
		local target = clamp(snap(min + pct * (max - min)), min, max)
		-- The mouse moves ~60 times a second and the value is quantized to `step`,
		-- so most of those frames land on the value we're already at. Firing anyway
		-- meant dragging a plain 0–100 slider one notch handed the consumer's
		-- callback a few dozen identical values — and the consumer is game code
		-- doing real work per call (a tween, a remote, a property write on every
		-- part it manages). Nothing downstream can tell those apart from a genuine
		-- change, so the filter belongs here.
		if target == value then
			return
		end
		value = target
		render()
		if opts.Callback then
			ctx:User(task.spawn, opts.Callback, value)
		end
	end

	-- The move/release listeners are global (UserInputService), so they're only
	-- connected for the duration of a drag and torn down on release. That avoids
	-- N idle sliders each leaking a permanent listener that fires on every mouse
	-- move and survives Window:Destroy.
	local dragConns: { RBXScriptConnection } = {}
	-- Whether this drag holds the page still (Context:LockScroll). Only a touch
	-- drag does: a mouse drag can't scroll the content, and the lock is counted,
	-- so the release has to match the grab exactly.
	local scrollLocked = false
	local function endDrag()
		for _, c in dragConns do
			c:Disconnect()
		end
		table.clear(dragConns)
		bubble.Visible = false
		if scrollLocked then
			scrollLocked = false
			ctx:LockScroll(false)
		end
		Tween.play(knobScale, Tween.Spring, { Scale = 1 }) -- settle back on release
	end
	-- The move/release pair lives on UserInputService, which outlives the tree the
	-- slider is in: unloading the window (or a config swapping a tab out) mid-drag
	-- left them connected forever, running setFromX against a destroyed rail on
	-- every mouse move for the rest of the session. Releasing the button is the
	-- normal exit; this is the one that can't be relied on to happen.
	track.Destroying:Connect(function()
		endDrag()
		unsubscribeTouch()
	end)
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			if #dragConns > 0 then
				return
			end
			if input.UserInputType == Enum.UserInputType.Touch then
				-- A horizontal drag on the slider must not scroll the page: the
				-- content frame scrolls on the vertical drift of a thumb, so it's held
				-- for the gesture. And the finger covers the value, so it goes up top.
				scrollLocked = true
				ctx:LockScroll(true)
				bubble.Visible = true
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
			task.spawn(opts.Callback, value)
		end
	end

	-- Opt-in build-time fire: `Default` on its own never runs `Callback`
	-- (see COMMON_SCHEMA in components/Controls.lua for why it stays opt-in).
	if opts.FireDefault == true and opts.Callback then
		task.spawn(opts.Callback, value)
	end

	return f.field, handle, true
end
