--!strict
-- components/Keybind.lua — click to listen, capture the next key pressed;
-- right-click to cycle the mode.
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

	local f = Field.new(ctx, opts)
	local mode = Bind.mode(opts.Mode, where, "None")
	local picker = mode == "None"

	local chip, handle = BindChip(ctx, {
		Key = opts.Default,
		Mode = mode,
		Modes = opts.Modes,
		Default = opts.DefaultState,
		Where = where,
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
