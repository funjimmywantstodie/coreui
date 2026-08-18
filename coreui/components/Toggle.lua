--!strict
-- components/Toggle.lua — 42×23 pill, 17px knob, +19px travel.
--
-- Every toggle carries a keybind chip in the same row, so "hold B for
-- walkspeed" is one option on the control rather than a second control wired up
-- by hand. The chip owns a binding in util/Bind.lua; the toggle's value stays
-- the single source of truth, which is why Toggle mode asks for it via
-- `GetState` instead of tracking its own.
--
-- The chip is built even when the call site says nothing about keys — empty,
-- in Toggle mode — because "is this bindable?" isn't a decision the menu author
-- should have to make on the user's behalf. It used to be opt-in, which meant
-- hubs hardcoded a default key just to get the chip on screen, and every one of
-- those landed in the bind HUD as a bind nobody asked for. An unbound chip on an
-- *off* toggle costs the HUD nothing (util/Bind.lua's `IsListed` keeps idle
-- keyless binds out; switching the toggle on lists it, keyed or not, because the
-- HUD's job is to say what's running), so the default is free.
-- `Keybind` / `KeybindMode` / `KeybindModes` still
-- preset it exactly as before; `Keybind = false` opts one control out, and
-- `CreateWindow{ Keybinds = false }` opts the whole window out.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Log = require(script.Parent.Parent.util.Log)
local Field = require(script.Parent.Field)
local BindChip = require(script.Parent.BindChip)

local OFF_POS = UDim2.fromOffset(3, 3)
local ON_POS = UDim2.fromOffset(22, 3) -- 3 + 19px travel

-- The options this control adds on top of the ones every control takes
-- (`Name`/`Desc`/`Default`/`Callback`/`Flag`, checked by components/Controls.lua).
local SCHEMA: Log.Schema = {
	-- `false` is the opt-out ("this toggle isn't bindable"), so it's a legal value
	-- here alongside a key.
	{ "Keybind", { "EnumItem", "boolean" } },
	{ "KeybindMode", "string" },
	{ "KeybindModes", "table" },
	{ "KeybindFlag", "string" },
	{ "Hud", "boolean" },
	{ "Parent", { "string", "table" } },
}

return function(ctx: any, opts: any)
	opts = opts or {}
	local colors = Theme.Colors
	local where = Log.where("Toggle", opts.Name)
	Log.check(where, opts, SCHEMA)

	local f = Field.new(ctx, opts)
	local state = opts.Default == true

	local track = Create("TextButton", {
		Name = "Toggle",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(42, 23),
		BackgroundColor3 = colors.toggle_off,
		LayoutOrder = 3,
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

	local bind: any = nil

	local handle = {}
	function handle:Get(): boolean
		return state
	end
	function handle:Set(value: boolean)
		state = value == true
		paint(true)
		-- Keep the chip's idea of the value in step (so a Hold chip un-lights, and
		-- a Toggle press after a manual click flips the right way) without letting
		-- it re-enter the callback.
		if bind then
			bind:SetState(state)
		end
		if opts.Callback then
			task.spawn(opts.Callback, state)
		end
	end

	-- Tagged so a host watching Context:OnFlagChanged can tell a switch the user
	-- flipped from one a script set. The tag is dynamically scoped and task.spawn
	-- resumes immediately, so it still covers the callback :Set fires.
	track.Activated:Connect(function()
		ctx:User(function()
			handle:Set(not state)
		end)
	end)

	-- ── keybind ──────────────────────────────────────────────────────────────
	-- On unless someone said otherwise. A keybind option on the control is that
	-- someone either way: `Keybind = false` opts this one out, and any explicit
	-- key / mode / mode-list turns it back on over a window-wide
	-- `CreateWindow{ Keybinds = false }`.
	local bindable
	if opts.Keybind == false then
		bindable = false
	elseif opts.Keybind ~= nil or opts.KeybindMode ~= nil or opts.KeybindModes ~= nil then
		bindable = true
	else
		bindable = ctx.Keybinds ~= false
	end

	if bindable then
		-- Resolved before the chip is built so the chip's OnChanged can name it —
		-- re-keying or mode-cycling the chip is a change to this flag, and it's the
		-- only one whose value never passes through a control callback (the chip
		-- isn't mounted through components/Controls.lua, the toggle is).
		local keyFlag = opts.KeybindFlag
		if keyFlag == nil and type(opts.Flag) == "string" and opts.Flag ~= "" then
			keyFlag = opts.Flag .. "_key"
		end

		local chip, chipHandle = BindChip(ctx, {
			-- `true` (force the chip on) isn't a key — only a real one presets it.
			Key = typeof(opts.Keybind) == "EnumItem" and opts.Keybind or nil,
			Mode = opts.KeybindMode or "Toggle",
			Modes = opts.KeybindModes,
			Default = state,
			Compact = true,
			LayoutOrder = 2,
			Where = where,
			-- The toggle's own label is what the bind HUD lists it under, so
			-- "hold B for aim" appears there without a second declaration.
			Label = opts.Name,
			-- ...and its Flag is what a sub-option points `Parent` at. Either name
			-- resolves (util/Bind.lua `Binding:_named`), so a section of sub-toggles
			-- can say `Parent = "aimbot"` or `Parent = "Aimbot"`.
			Id = opts.Flag,
			-- Declaring this toggle a sub-option of another feature keeps it out of
			-- the bind HUD when it's merely switched on — its parent's row speaks for
			-- it. A key of its own still lists it.
			Parent = opts.Parent,
			Hud = opts.Hud,
			GetState = function()
				return state
			end,
			OnActivate = function(active)
				handle:Set(active)
			end,
			OnChanged = function()
				if keyFlag then
					ctx:NotifyFlag(keyFlag)
				end
			end,
		})
		chip.Parent = f.row
		bind = chipHandle
		handle.Bind = chipHandle
		-- The key + mode persist separately from the toggle's own value, so a saved
		-- config restores "hold B" as well as "on". A chip whose key doesn't
		-- survive a config load is worse than no chip, and nothing now asks the
		-- call site for one — so with no `KeybindFlag` given, derive it from the
		-- toggle's own `Flag` (resolved above). `<flag>_key` is the convention
		-- consumers were already spelling out by hand, so a derived name matches
		-- what's in the configs they've already saved. An explicit `KeybindFlag`
		-- still wins.
		if keyFlag then
			ctx:RegisterFlag(keyFlag, chipHandle, "bind")
		end
	end

	ctx:RegisterAccent(function()
		paint(false)
	end)

	-- Opt-in build-time fire: `Default` on its own never runs `Callback`
	-- (see COMMON_SCHEMA in components/Controls.lua for why it stays opt-in).
	if opts.FireDefault == true and opts.Callback then
		task.spawn(opts.Callback, state)
	end

	return f.field, handle, true
end
