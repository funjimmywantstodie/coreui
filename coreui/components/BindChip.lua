--!strict
-- components/BindChip.lua — the little mono key chip, shared by the Keybind
-- control and by any control that takes a `Keybind` option (Toggle today).
--
-- The chip is TWO click targets in one pill:
--
--     ┌──────┬──────┐
--     │ MB2  │ hold │
--     └──────┴──────┘
--        ^       ^
--        |       └─ mode segment — click cycles Toggle → Hold → Always. Only
--        |          drawn when there's more than one mode to pick, so a pure
--        |          key picker still reads as a single plain chip.
--        └─ key segment — click to arm, then press the key to bind.
--
-- Mode cycling used to live on *right-clicking the chip*, which was both
-- invisible (nothing on screen said so) and a trap: right-click is the mouse
-- button people most want to bind, and pressing it just flipped the mode
-- instead. So the two jobs are now split by position rather than by button:
-- every click on the key half is about the key, and the mode has a label you
-- can see and press.
--
-- That frees the mouse buttons for binding. While armed, a right/middle click
-- **on the chip** binds MB2/MB3; a click anywhere **else** abandons the bind,
-- which is the same escape hatch as before. Left click is deliberately not
-- bindable from the UI — it's how you operate the menu (and the chip) — but
-- `handle:Set(Enum.UserInputType.MouseButton1)` still works for a caller that
-- really wants it.

local Services = require(script.Parent.Parent.util.Services)

local UserInputService = Services.UserInputService

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Bind = require(script.Parent.Parent.util.Bind)

-- Mouse buttons the click-to-bind UI will capture. MB1 is left out on purpose
-- (see the header) — it stays the "operate the UI" button.
local BINDABLE_MOUSE: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
}

-- Modes with nothing useful to cycle to (a pure picker, a one-shot command)
-- keep their chip single-segment.
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

return function(ctx: any, opts: any): (Frame, any)
	local colors = Theme.Colors
	local compact = opts.Compact == true
	local where = opts.Where or "Keybind"

	local mode = Bind.mode(opts.Mode, where, "Toggle")
	local modes = cycleList(mode, opts.Modes)
	local switchable = #modes > 1
	local listening = false

	local height = compact and 24 or 32
	local padX = compact and 9 or 13
	local textSize = compact and 11 or 12
	-- The key half keeps the old minimum so a chip doesn't jump around as the
	-- bound key changes; the mode half sizes to its word.
	local keyMin = compact and 46 or 70

	local chip = Create("Frame", {
		Name = "BindChip",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, height),
		BackgroundColor3 = colors.control,
		LayoutOrder = opts.LayoutOrder or 2,
	}, {
		Create.corner(Theme.Metrics.controlRadius),
		Create.stroke(colors.border),
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
	local stroke = chip:FindFirstChildOfClass("UIStroke") :: UIStroke

	-- Hover is tracked per segment: the segments tile the whole chip, so "the
	-- pointer is over one of them" is also "the pointer is over the chip", which
	-- is what decides whether a click while armed binds or abandons. (The parent
	-- Frame's own MouseEnter/Leave can't be used — a child button takes the
	-- mouse target away from it.)
	local hovered: { [Instance]: boolean } = {}

	local keyBtn: TextButton
	local modeBtn: TextButton? = nil
	local paint: () -> ()

	local function segment(name: string, order: number, minWidth: number): TextButton
		local btn = Create("TextButton", {
			Name = name,
			AutoButtonColor = false,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, height),
			BackgroundTransparency = 1,
			Text = "",
			TextColor3 = colors.text,
			TextSize = textSize,
			FontFace = Theme.Font.Mono,
			LayoutOrder = order,
			Parent = chip,
		}, {
			Create.padding(0, padX),
			Create("UISizeConstraint", { MinSize = Vector2.new(minWidth, height) }),
		})
		btn.MouseEnter:Connect(function()
			hovered[btn] = true
			paint()
		end)
		btn.MouseLeave:Connect(function()
			hovered[btn] = false
			paint()
		end)
		return btn
	end

	keyBtn = segment("Key", 1, keyMin)

	if switchable then
		modeBtn = segment("Mode", 2, compact and 34 or 44)
		-- Hairline between the halves, pulled back out of the mode segment's left
		-- padding so it lands on the actual boundary. A Frame doesn't sink input,
		-- so it can't punch a dead spot in either segment's hover.
		Create("Frame", {
			Name = "Divider",
			BackgroundColor3 = colors.border,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(-padX, 0),
			Size = UDim2.new(0, 1, 1, 0),
			Parent = modeBtn,
		})
	end

	local function overChip(): boolean
		return hovered[keyBtn] == true or (modeBtn ~= nil and hovered[modeBtn] == true)
	end

	local binding = Bind.get(ctx):Register({
		Key = opts.Key,
		Mode = mode,
		Modes = modes,
		Default = opts.Default,
		Where = where,
		-- What the bind HUD calls this bind (components/Hud.lua). The consumers
		-- pass their control's own `Name`, so nothing is declared twice.
		Label = opts.Label,
		-- ...and their own `Flag` as the id other controls point `Parent` at, for
		-- the same reason: the name a sub-option refers to its feature by is one
		-- the call site already wrote down.
		Id = opts.Id,
		Parent = opts.Parent,
		Hud = opts.Hud,
		GetState = opts.GetState,
		Callback = opts.OnActivate,
		OnChanged = opts.OnChanged,
	})

	-- ── paint ────────────────────────────────────────────────────────────────
	function paint()
		local over = overChip()
		-- The whole pill lifts on hover (it's one control), and the half under the
		-- pointer brightens its label — that's what tells you the two halves do
		-- different things before you click either of them.
		chip.BackgroundColor3 = over and colors.control_hi or colors.control

		if listening then
			keyBtn.Text = "..."
			keyBtn.TextColor3 = ctx.Accent
			stroke.Color = ctx.Accent
		else
			keyBtn.Text = Bind.name(binding:GetKey())
			-- An active bind (held, or toggled on) lights up, so a Hold key reads as
			-- live while it's down without anything else on the row moving.
			local active = binding:GetState()
			keyBtn.TextColor3 = active and ctx.Accent or colors.text
			stroke.Color = active and ctx.Accent or colors.border
		end

		if modeBtn then
			modeBtn.Text = binding:GetMode():lower()
			-- Muted, not dim: the mode half is the only thing on screen advertising
			-- that the mode is switchable at all, so it has to be readable at rest.
			modeBtn.TextColor3 = (hovered[modeBtn] and not listening) and colors.text or colors.text_muted
		end
	end

	binding.onState = function()
		paint()
	end
	-- Kept so handle:Destroy can drop it. Unlike most controls a chip really can
	-- outlive nothing — `Keybind`/`Toggle` handles expose :Destroy — and the
	-- registry has no idea the instances are gone, so a dropped chip's closure
	-- would keep painting a destroyed pill on every SetAccent for the life of the
	-- window (see the note on Context:RegisterAccent).
	local unsubscribeAccent = ctx:RegisterAccent(function()
		paint()
	end)

	-- ── rebind ───────────────────────────────────────────────────────────────
	-- The arming listener lives on UserInputService, so it outlives the chip's
	-- instances: a window torn down while a chip sat armed (a loader re-run,
	-- Uranium:Unload from a script) left it connected against a dead tree, holding
	-- the capture claim with nothing left that could release it. Kept at chip scope
	-- so `Destroying` and handle:Destroy can both cancel it.
	local armConn: RBXScriptConnection? = nil
	local function disarm(repaint: boolean?)
		if armConn then
			armConn:Disconnect()
			armConn = nil
		end
		if not listening then
			return
		end
		listening = false
		ctx:EndCapture()
		if repaint then
			paint()
		end
	end
	chip.Destroying:Connect(function()
		disarm(false)
		-- Also the path a chip taken down by an ancestor goes out on (a tab or
		-- group rebuilt under it), where handle:Destroy is never called.
		-- Unsubscribing twice is a no-op.
		unsubscribeAccent()
	end)

	keyBtn.Activated:Connect(function()
		if listening then
			return -- already armed; a left click on the chip is a no-op, not a bind
		end
		listening = true
		-- Claim key capture so the window's toggle-key listener (and every other
		-- binding) ignores input until the bind completes — otherwise binding e.g.
		-- RightShift also hid the window on that same keystroke.
		ctx:BeginCapture()
		paint()

		local function finish()
			disarm(true)
		end

		-- Every rebind below is tagged as user-driven, so a host watching flag
		-- changes (Context:OnFlagChanged) sees a chip the user re-keyed as
		-- exactly that, and not as the config load or the `:Set` that takes the
		-- same path through `binding:SetKey`.
		armConn = UserInputService.InputBegan:Connect(function(input)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.Keyboard then
				finish()
				-- Escape cancels (keep the current bind); Backspace/Delete clears it.
				if input.KeyCode == Enum.KeyCode.Escape then
					-- leave the bind untouched
				elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
					ctx:User(function()
						binding:SetKey(Enum.KeyCode.Unknown)
					end)
				else
					ctx:User(function()
						binding:SetKey(input.KeyCode)
					end)
				end
				paint()
				return
			end

			local isMouse = kind == Enum.UserInputType.MouseButton1
				or kind == Enum.UserInputType.MouseButton2
				or kind == Enum.UserInputType.MouseButton3
			if not isMouse and kind ~= Enum.UserInputType.Touch then
				return
			end

			if overChip() then
				-- A click on the chip is aimed AT the chip: bind the mouse button if
				-- it's one we capture, and otherwise (left click, touch) just stay
				-- armed rather than eating the click as a cancel.
				if BINDABLE_MOUSE[kind] then
					finish()
					ctx:User(function()
						binding:SetKey(kind)
					end)
					paint()
				end
				return
			end
			-- A click anywhere else abandons the bind. Without this the chip sat in
			-- "..." forever holding key capture, which silently killed the window's
			-- toggle key until some key was eventually pressed.
			finish()
		end)
	end)

	-- ── mode cycle ───────────────────────────────────────────────────────────
	-- Left click only, and only on the mode half. Nothing about the mode is
	-- reachable from a mouse button any more, which is what lets the key half
	-- claim right/middle click for binding.
	if modeBtn then
		modeBtn.Activated:Connect(function()
			if listening then
				return
			end
			local current = binding:GetMode()
			-- 0 = the current mode isn't in the cycle list at all (a config restored
			-- a mode this chip doesn't offer), which cycles to modes[1] rather than
			-- silently skipping it.
			local index = 0
			for i, m in modes do
				if m == current then
					index = i
					break
				end
			end
			ctx:User(function()
				binding:SetMode(modes[(index % #modes) + 1])
			end)
			paint()
		end)
	end

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
	-- The `info` an activation callback is handed (`{ Key, Mode, KeyName }`), so a
	-- caller firing one itself — components/Keybind.lua's `FireDefault` — passes
	-- the same table util/Bind.lua would, rather than rebuilding the shape and
	-- drifting from it.
	function handle:GetInfo(): any
		return binding:_info()
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
			-- Both halves land silently and ONE notification covers the record. Left
			-- to themselves, SetKey reports the pre-load mode and SetMode reports
			-- again — and SetMode no-ops (so reports nothing) when the saved mode
			-- already matches, which is the common case. The Settings tab's picker
			-- runs window:SetToggleKey off this callback, so it has to fire exactly
			-- once either way.
			local changed = false
			if value.Key ~= nil then
				binding:SetKey(value.Key, true)
				changed = true
			end
			if value.Mode ~= nil then
				binding:SetMode(value.Mode, true)
				changed = true
			end
			if changed and binding.onChanged then
				binding.onChanged(binding:GetKey(), binding:GetMode())
			end
		end
		paint()
	end
	function handle:Destroy()
		disarm(false)
		unsubscribeAccent()
		binding:Destroy()
	end

	paint()
	return chip, handle
end
