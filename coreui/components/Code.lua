--!strict
-- components/Code.lua — multi-line monospace editor for pasting / editing raw
-- config blobs (Lua tables, JSON, scripts) that don't fit a structured control.
--
-- Stacked field: label/desc on top, a fixed-height scrolling TextBox below.
-- Wraps by default (clean for prose-ish config). `LineNumbers = true` adds a
-- left gutter — that mode disables wrap so each logical line is exactly one row
-- (so the numbers stay aligned) and scrolls horizontally instead.
--
-- An optional `Parse` fn turns the editor into a validated input: it runs on
-- blur inside a pcall; success caches the parsed value (read via :GetValue()),
-- failure paints the stroke red and prints the error on a line beneath the box.
--
-- Flag-captured as a plain string (the raw text), so it saves / loads through
-- the config system exactly like :Input.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Field = require(script.Parent.Field)

local GUTTER_W = 30

return function(ctx: any, opts: any)
	local colors = Theme.Colors
	local f = Field.new(ctx, opts, true)

	local numbered = opts.LineNumbers == true
	local wrap = not numbered
	local height = opts.Height or 168

	local scroller = Create("ScrollingFrame", {
		Name = "Editor",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = colors.control,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.XY,
		ScrollingDirection = wrap and Enum.ScrollingDirection.Y or Enum.ScrollingDirection.XY,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = colors.text_dim,
		ScrollBarImageTransparency = 0.35,
		LayoutOrder = 2,
		Parent = f.field,
	}, {
		Create.corner(Theme.Metrics.controlRadius),
		Create.stroke(colors.border),
		Create.padding(9, 11),
	})
	local stroke = scroller:FindFirstChildOfClass("UIStroke") :: UIStroke

	local gutter: TextLabel? = nil
	if numbered then
		gutter = Create("TextLabel", {
			Name = "Gutter",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(GUTTER_W, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = "1",
			TextColor3 = colors.text_dim,
			TextSize = 13,
			FontFace = Theme.Font.Mono,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = scroller,
		}, { Create.padding(0, 8, 0, 0) })
	end

	local boxX = numbered and GUTTER_W or 0
	local box = Create("TextBox", {
		Name = "Box",
		Position = UDim2.fromOffset(boxX, 0),
		Size = wrap and UDim2.new(1, -boxX, 0, 0) or UDim2.fromOffset(0, 0),
		AutomaticSize = wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Text = opts.Default or "",
		PlaceholderText = opts.Placeholder or "",
		PlaceholderColor3 = colors.text_dim,
		TextColor3 = colors.text,
		TextSize = 13,
		FontFace = Theme.Font.Mono,
		MultiLine = true,
		ClearTextOnFocus = false,
		TextWrapped = wrap,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = scroller,
	})

	-- Error line beneath the editor — hidden while the text parses (or no parser).
	local status = Create("TextLabel", {
		Name = "Status",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = colors.danger,
		TextSize = 12,
		FontFace = Theme.Font.Mono,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Visible = false,
		LayoutOrder = 3,
		Parent = f.field,
	})

	local lastValue: any = nil
	local valid = true

	local function syncGutter()
		if not gutter then
			return
		end
		local n = 1
		for _ in string.gmatch(box.Text, "\n") do
			n += 1
		end
		local lines = table.create(n)
		for i = 1, n do
			lines[i] = tostring(i)
		end
		gutter.Text = table.concat(lines, "\n")
	end

	-- Run the consumer parser; cache value on success, surface the error on fail.
	-- No parser → always "valid", value stays nil (Get() still yields raw text).
	local function validate(focused: boolean?)
		if not opts.Parse then
			return
		end
		local ok, res = pcall(opts.Parse, box.Text)
		valid = ok and res ~= nil
		lastValue = valid and res or nil

		if valid then
			status.Visible = false
			if not focused then
				Tween.play(stroke, Tween.Fast, { Color = colors.border })
			end
		else
			status.Text = ok and "Parse returned nil" or tostring(res)
			status.Visible = true
			Tween.play(stroke, Tween.Fast, { Color = colors.danger })
		end
		if opts.OnParse then
			opts.OnParse(valid, lastValue, (not valid) and status.Text or nil)
		end
	end

	box.Focused:Connect(function()
		Tween.play(stroke, Tween.Fast, { Color = ctx.Accent })
	end)
	box.FocusLost:Connect(function()
		validate(false)
		if valid then
			Tween.play(stroke, Tween.Fast, { Color = colors.border })
		end
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		syncGutter()
		if opts.Callback then
			task.spawn(opts.Callback, box.Text)
		end
	end)

	syncGutter()
	task.defer(function()
		validate(false)
	end)

	local handle = {}
	function handle:Get(): string
		return box.Text
	end
	function handle:Set(value: any)
		box.Text = tostring(value)
		syncGutter()
		validate(false)
	end
	-- The parsed value from the last successful Parse (nil if invalid / no parser).
	function handle:GetValue(): any
		return lastValue
	end
	-- Force a re-parse now; returns ok, value|errString.
	function handle:Validate(): (boolean, any)
		validate(false)
		-- Explicit branch, not `valid and lastValue or status.Text`: with no Parse
		-- (or a parser whose value is falsy) lastValue is nil and the idiom falls
		-- through to the status label, reporting the empty string as an error
		-- message on a control that is perfectly valid.
		if valid then
			return true, lastValue
		end
		return false, status.Text
	end

	return f.field, handle, true
end
