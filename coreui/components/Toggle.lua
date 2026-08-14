--!strict
-- components/Toggle.lua — 42×23 pill, 17px knob, +19px travel.
--
-- Optionally carries a keybind chip in the same row (`Keybind` /
-- `KeybindMode`), so "hold B for walkspeed" is one option on the control rather
-- than a second control wired up by hand. The chip owns a binding in
-- util/Bind.lua; the toggle's value stays the single source of truth, which is
-- why Toggle mode asks for it via `GetState` instead of tracking its own.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Log = require(script.Parent.Parent.util.Log)
local Field = require(script.Parent.Field)
local BindChip = require(script.Parent.BindChip)

local OFF_POS = UDim2.fromOffset(3, 3)
local ON_POS = UDim2.fromOffset(22, 3) -- 3 + 19px travel

return function(ctx: any, opts: any)
	opts = opts or {}
	local colors = Theme.Colors
	local where = Log.where("Toggle", opts.Name)
	Log.field(where, "Keybind", opts.Keybind, "EnumItem")
	Log.field(where, "KeybindMode", opts.KeybindMode, "string")
	Log.field(where, "KeybindModes", opts.KeybindModes, "table")
	Log.field(where, "KeybindFlag", opts.KeybindFlag, "string")

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

	track.Activated:Connect(function()
		handle:Set(not state)
	end)

	-- ── optional keybind ─────────────────────────────────────────────────────
	if opts.Keybind ~= nil or opts.KeybindMode ~= nil then
		local chip, chipHandle = BindChip(ctx, {
			Key = opts.Keybind,
			Mode = opts.KeybindMode or "Toggle",
			Modes = opts.KeybindModes,
			Default = state,
			Compact = true,
			LayoutOrder = 2,
			Where = where,
			GetState = function()
				return state
			end,
			OnActivate = function(active)
				handle:Set(active)
			end,
		})
		chip.Parent = f.row
		bind = chipHandle
		handle.Bind = chipHandle
		-- The key + mode persist separately from the toggle's own value, so a saved
		-- config restores "hold B" as well as "on".
		if opts.KeybindFlag then
			ctx:RegisterFlag(opts.KeybindFlag, chipHandle, "bind")
		end
	end

	ctx:RegisterAccent(function()
		paint(false)
	end)

	return f.field, handle, true
end
