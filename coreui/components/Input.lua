--!strict
-- components/Input.lua — full-width 36px TextBox, accent stroke on focus.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Field = require(script.Parent.Field)

-- Live character filters keyed by opts.Type. Each takes the raw box text and
-- returns it with disallowed characters stripped; the number kinds also collapse
-- to a single leading '-' and a single '.' so the result is always parseable.
local function sanitizer(kind: string?): (((string) -> string)?)
	if kind == "number" then
		return function(s)
			local neg = s:sub(1, 1) == "-"
			s = s:gsub("[^%d%.]", "")
			local dot = s:find("%.")
			if dot then
				s = s:sub(1, dot) .. (s:sub(dot + 1):gsub("%.", ""))
			end
			return neg and ("-" .. s) or s
		end
	elseif kind == "integer" then
		return function(s)
			local neg = s:sub(1, 1) == "-"
			s = (s:gsub("[^%d]", ""))
			return neg and ("-" .. s) or s
		end
	elseif kind == "alpha" then
		return function(s)
			return (s:gsub("[^%a]", ""))
		end
	elseif kind == "alphanumeric" then
		return function(s)
			return (s:gsub("[^%w]", ""))
		end
	end
	return nil
end

return function(ctx: any, opts: any)
	local colors = Theme.Colors
	local f = Field.new(ctx, opts, true)
	-- opts.Filter (function) wins; otherwise opts.Type selects a preset filter.
	local clean = opts.Filter or sanitizer(opts.Type)

	local box = Create("TextBox", {
		Name = "Input",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = colors.control,
		Text = opts.Default or "",
		PlaceholderText = opts.Placeholder or "",
		PlaceholderColor3 = colors.text_dim,
		TextColor3 = colors.text,
		TextSize = 13,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		LayoutOrder = 2,
		Parent = f.field,
	}, {
		Create.corner(Theme.Metrics.controlRadius),
		Create.stroke(colors.border),
		Create.padding(0, 12),
	})
	local stroke = box:FindFirstChildOfClass("UIStroke") :: UIStroke

	box.Focused:Connect(function()
		Tween.play(stroke, Tween.Fast, { Color = ctx.Accent })
	end)
	box.FocusLost:Connect(function(enterPressed)
		Tween.play(stroke, Tween.Fast, { Color = colors.border })
		if enterPressed and opts.OnEnter then
			opts.OnEnter(box.Text)
		end
	end)
	local guard = false
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if guard then
			return
		end
		if clean then
			local filtered = clean(box.Text)
			if filtered ~= box.Text then
				-- Rewriting Text re-fires this signal synchronously; guard skips
				-- that pass so the callback below runs once with the clean value.
				guard = true
				box.Text = filtered
				guard = false
			end
		end
		if opts.Callback then
			-- The guard above means this signal only reaches here when the user typed
			-- (handle:Set writes under it and fires the callback itself), so it's an
			-- honest "user" for Context:OnFlagChanged.
			ctx:User(task.spawn, opts.Callback, box.Text)
		end
	end)

	local handle = {}
	function handle:Get(): string
		return box.Text
	end
	function handle:Set(value: any)
		-- Filter here and write under the same guard the live filter uses, then
		-- fire by hand: leaving the callback to the Text signal means setting the
		-- value the box already holds fires nothing, so a LoadConfig that restores
		-- an Input to its current text never re-applies it downstream. The guard
		-- is what keeps a genuine change from firing twice.
		--
		-- Coerced first: `TextBox.Text` refuses anything but a string, so a caller
		-- handing a number (which is what `Input{ Type = "number" }` invites — the
		-- control's whole job is numeric text) errored inside the engine instead of
		-- setting the field. The filters below assume a string too.
		local text = value == nil and "" or tostring(value)
		guard = true
		box.Text = clean and clean(text) or text
		guard = false
		if opts.Callback then
			task.spawn(opts.Callback, box.Text)
		end
	end

	return f.field, handle, true
end
