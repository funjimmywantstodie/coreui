--!strict
-- components/Keybind.lua — click to listen, capture the next key pressed.

local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Field = require(script.Parent.Field)

return function(ctx: any, opts: any)
	local colors = Theme.Colors
	local f = Field.new(ctx, opts)
	local key: Enum.KeyCode = opts.Default or Enum.KeyCode.Unknown
	local listening = false

	local button = Create("TextButton", {
		Name = "Keybind",
		AutoButtonColor = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(70, 32),
		BackgroundColor3 = colors.control,
		Text = key ~= Enum.KeyCode.Unknown and key.Name or "None",
		TextColor3 = colors.text,
		TextSize = 12,
		FontFace = Theme.Font.Mono,
		LayoutOrder = 2,
		Parent = f.row,
	}, {
		Create.corner(Theme.Metrics.controlRadius),
		Create.stroke(colors.border),
		Create.padding(0, 14),
		Create("UISizeConstraint", { MinSize = Vector2.new(70, 32) }),
	})
	local stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke

	button.Activated:Connect(function()
		if listening then
			return
		end
		listening = true
		-- Claim key capture so the window's toggle-key listener ignores input until
		-- the bind completes — otherwise binding e.g. RightShift also hid the window.
		ctx:BeginCapture()
		button.Text = "..."
		button.TextColor3 = ctx.Accent
		stroke.Color = ctx.Accent

		local conn: RBXScriptConnection
		conn = UserInputService.InputBegan:Connect(function(input)
			local fromKey = input.UserInputType == Enum.UserInputType.Keyboard
			-- A click anywhere else abandons the bind. Without this the control sat
			-- in "..." forever holding key capture, which silently killed the
			-- window's toggle key until some key was eventually pressed.
			local fromClick = input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.MouseButton2
				or input.UserInputType == Enum.UserInputType.Touch
			if not fromKey and not fromClick then
				return
			end
			conn:Disconnect()
			listening = false
			ctx:EndCapture()
			if fromKey then
				-- Escape cancels (keep the current bind); Backspace/Delete clears it.
				if input.KeyCode == Enum.KeyCode.Escape then
					-- leave `key` untouched
				elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
					key = Enum.KeyCode.Unknown
				else
					key = input.KeyCode
				end
			end
			button.Text = key ~= Enum.KeyCode.Unknown and key.Name or "None"
			button.TextColor3 = colors.text
			stroke.Color = colors.border
			if fromKey and opts.Callback then
				task.spawn(opts.Callback, key)
			end
		end)
	end)

	local handle = {}
	function handle:Get(): Enum.KeyCode
		return key
	end
	function handle:Set(value: Enum.KeyCode)
		key = value
		button.Text = key ~= Enum.KeyCode.Unknown and key.Name or "None"
		-- A config load can land mid-listen; drop the "..." styling with it so the
		-- control doesn't stay stuck looking like it's still waiting for a key.
		button.TextColor3 = colors.text
		stroke.Color = colors.border
		if opts.Callback then
			task.spawn(opts.Callback, key)
		end
	end

	return f.field, handle, true
end
