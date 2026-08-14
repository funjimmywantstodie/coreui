--!strict
-- components/BindChip.lua — the little mono key chip, shared by the Keybind
-- control and by any control that takes a `Keybind` option (Toggle today).
--
-- Click it to rebind (Escape cancels, Backspace/Delete clears, a click anywhere
-- else abandons); right-click to cycle the mode. It owns the actual binding in
-- util/Bind.lua, so the routing, the mode machine and the input gating all live
-- in one place and this file is only paint + capture.
--
-- The mode suffix is drawn only when the mode isn't the implied "Toggle", so a
-- plain bind reads as just "B" and a hold bind reads "B · hold".

local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Bind = require(script.Parent.Parent.util.Bind)

-- Modes with nothing useful to cycle to (a pure picker, a one-shot command)
-- keep their chip inert on right-click.
local function cycleList(mode: string, modes: { string }?): { string }
	if mode == "None" then
		return { "None" }
	end
	local list = modes or Bind.DefaultModes
	for _, m in list do
		if m == mode then
			return list
		end
	end
	-- The starting mode isn't in the cycle list (e.g. Mode = "Press" with the
	-- default list) — keep it reachable by putting it first.
	local merged = { mode }
	for _, m in list do
		table.insert(merged, m)
	end
	return merged
end

return function(ctx: any, opts: any): (TextButton, any)
	local colors = Theme.Colors
	local compact = opts.Compact == true
	local where = opts.Where or "Keybind"

	local mode = Bind.mode(opts.Mode, where, "Toggle")
	local modes = cycleList(mode, opts.Modes)
	local listening = false

	local height = compact and 24 or 32
	local minWidth = compact and 46 or 70

	local button = Create("TextButton", {
		Name = "Keybind",
		AutoButtonColor = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(minWidth, height),
		BackgroundColor3 = colors.control,
		RichText = true,
		Text = "",
		TextColor3 = colors.text,
		TextSize = compact and 11 or 12,
		FontFace = Theme.Font.Mono,
		LayoutOrder = opts.LayoutOrder or 2,
	}, {
		Create.corner(Theme.Metrics.controlRadius),
		Create.stroke(colors.border),
		Create.padding(0, compact and 9 or 14),
		Create("UISizeConstraint", { MinSize = Vector2.new(minWidth, height) }),
	})
	local stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke

	local binding = Bind.get(ctx):Register({
		Key = opts.Key,
		Mode = mode,
		Modes = modes,
		Default = opts.Default,
		Where = where,
		GetState = opts.GetState,
		Callback = opts.OnActivate,
		OnChanged = opts.OnChanged,
	})

	-- ── paint ────────────────────────────────────────────────────────────────
	local function paint()
		if listening then
			button.Text = "..."
			button.TextColor3 = ctx.Accent
			stroke.Color = ctx.Accent
			return
		end
		local label = Bind.name(binding:GetKey())
		local m = binding:GetMode()
		if m ~= "Toggle" and m ~= "None" then
			label ..= ('<font color="#%s"> · %s</font>'):format(colors.text_dim:ToHex(), m:lower())
		end
		button.Text = label
		-- An active bind (held, or toggled on) lights up, so a Hold key reads as
		-- live while it's down without anything else on the row moving.
		local active = binding:GetState()
		button.TextColor3 = active and ctx.Accent or colors.text
		stroke.Color = active and ctx.Accent or colors.border
	end

	binding.onState = function()
		paint()
	end
	ctx:RegisterAccent(function()
		paint()
	end)

	button.MouseEnter:Connect(function()
		if not listening then
			button.BackgroundColor3 = colors.control_hi
		end
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = colors.control
	end)

	-- ── rebind ───────────────────────────────────────────────────────────────
	button.Activated:Connect(function()
		if listening then
			return
		end
		listening = true
		-- Claim key capture so the window's toggle-key listener (and every other
		-- binding) ignores input until the bind completes — otherwise binding e.g.
		-- RightShift also hid the window on that same keystroke.
		ctx:BeginCapture()
		paint()

		local conn: RBXScriptConnection
		conn = UserInputService.InputBegan:Connect(function(input)
			local fromKey = input.UserInputType == Enum.UserInputType.Keyboard
			-- A click anywhere else abandons the bind. Without this the chip sat in
			-- "..." forever holding key capture, which silently killed the window's
			-- toggle key until some key was eventually pressed.
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
					-- leave the bind untouched
				elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
					binding:SetKey(Enum.KeyCode.Unknown)
				else
					binding:SetKey(input.KeyCode)
				end
			end
			paint()
		end)
	end)

	-- ── mode cycle ───────────────────────────────────────────────────────────
	button.MouseButton2Click:Connect(function()
		if listening or #modes < 2 then
			return
		end
		local current = binding:GetMode()
		local index = 1
		for i, m in modes do
			if m == current then
				index = i
				break
			end
		end
		binding:SetMode(modes[(index % #modes) + 1])
		paint()
	end)

	-- ── handle ───────────────────────────────────────────────────────────────
	local handle = {}
	handle.Binding = binding

	function handle:Get(): any
		return binding:GetKey()
	end
	function handle:Set(key: any)
		binding:SetKey(key)
		paint()
	end
	function handle:GetMode(): string
		return binding:GetMode()
	end
	function handle:SetMode(m: string)
		binding:SetMode(m)
		paint()
	end
	function handle:GetState(): boolean
		return binding:GetState()
	end
	-- `fire` = also run the activation callback (default: just sync + repaint).
	function handle:SetState(active: boolean, fire: boolean?)
		binding:SetState(active, fire)
		paint()
	end
	function handle:SetEnabled(enabled: boolean)
		binding:SetEnabled(enabled)
	end
	-- Config save/load: a bind is a key AND a mode, so it persists as both rather
	-- than through the plain :Get()/:Set() pair (util/Context.lua `bind` codec).
	function handle:GetFlag(): any
		return { Key = binding:GetKey(), Mode = binding:GetMode() }
	end
	function handle:SetFlag(value: any)
		if typeof(value) == "EnumItem" then
			binding:SetKey(value)
		elseif type(value) == "table" then
			if value.Key ~= nil then
				binding:SetKey(value.Key)
			end
			if value.Mode ~= nil then
				binding:SetMode(value.Mode)
			end
		end
		paint()
	end
	function handle:Destroy()
		binding:Destroy()
	end

	paint()
	return button, handle
end
