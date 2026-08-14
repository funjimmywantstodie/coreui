--!strict
-- components/Keybind.lua — click the key half of the chip to listen, then press
-- the key (or right/middle click the chip for MB2/MB3); the chip's mode half
-- cycles Toggle/Hold/Always when there's more than one mode to pick.
--
-- The chip, the routing and the mode machine live in components/BindChip.lua +
-- util/Bind.lua; this file is the field row around them and the callback
-- contract:
--
--   Mode = "None" (the default)  — a pure key PICKER. Nothing is bound; the
--       control just holds a key and `Callback(key)` fires whenever it changes.
--       This is the original Keybind behaviour, kept so existing menus (and the
--       Settings tab's Toggle-UI bind) don't change under them.
--   Mode = "Toggle" / "Hold" / "Press" / "Always" — an ACTIVATION bind. The key
--       drives a value and `Callback(active, info)` fires on every activation,
--       with `info = { Key, Mode, KeyName }`.
--
-- `OnChanged(key, mode)` fires when the bind itself is re-keyed or its mode is
-- cycled, in every mode.

local Log = require(script.Parent.Parent.util.Log)
local Bind = require(script.Parent.Parent.util.Bind)
local Field = require(script.Parent.Field)
local BindChip = require(script.Parent.BindChip)

return function(ctx: any, opts: any)
	opts = opts or {}
	local where = Log.where("Keybind", opts.Name)
	Log.field(where, "Default", opts.Default, "EnumItem")
	Log.field(where, "Mode", opts.Mode, "string")
	Log.field(where, "Modes", opts.Modes, "table")
	Log.field(where, "OnChanged", opts.OnChanged, "function")
	Log.field(where, "Hud", opts.Hud, "boolean")

	local f = Field.new(ctx, opts)
	local mode = Bind.mode(opts.Mode, where, "None")
	local picker = mode == "None"

	local chip, handle = BindChip(ctx, {
		Key = opts.Default,
		Mode = mode,
		Modes = opts.Modes,
		Default = opts.DefaultState,
		Where = where,
		-- The field's own label is what the bind HUD lists it under. A picker
		-- (Mode = "None") never activates, so it stays out of the HUD regardless.
		Label = opts.Name,
		Hud = opts.Hud,
		-- Picker mode has no activation, so `Callback` keeps its original
		-- "the key changed" meaning there and only there.
		OnActivate = not picker and opts.Callback or nil,
		OnChanged = function(key, m)
			if picker and opts.Callback then
				task.spawn(opts.Callback, key)
			end
			if opts.OnChanged then
				task.spawn(opts.OnChanged, key, m)
			end
		end,
	})
	chip.Parent = f.row

	return f.field, handle, true
end
