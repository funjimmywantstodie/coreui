--!strict
-- util/Log.lua — one place every Krypton diagnostic flows through, so the format
-- stays uniform and the library explains a mistake instead of throwing a bare
-- "attempt to index nil value" three frames deep in a bundled chunk.
--
-- Policy:
--   * fail  — the call genuinely can't proceed (wrong TYPE for a required arg).
--             Raised with level 0 so the executor console shows our clean
--             "[Krypton] Slider "Speed": ..." text, not a bundle file:line prefix.
--   * warn  — a recoverable mistake (bad enum value, out-of-range index, a
--             missing option we can default). We say what happened + what we did
--             and keep building, so one typo never blanks the whole menu.
--
-- `where` is a short human label for the call site, e.g. `Log.where("Slider",
-- opts.Name)` → `Slider "Speed"`. Keep messages actionable: name the field, the
-- value we got, and the fix.

local PREFIX = "[Krypton]"

local Log = {}

-- Build a "Control \"Name\"" label for messages. Falls back to just the control
-- name when the field is anonymous.
function Log.where(control: string, name: any?): string
	if type(name) == "string" and name ~= "" then
		return ('%s "%s"'):format(control, name)
	end
	return control
end

-- Hard stop. Never returns.
function Log.fail(where: string, msg: string): never
	return error(("%s %s: %s"):format(PREFIX, where, msg), 0)
end

-- Soft warning — lands in the executor console (warn channel), build continues.
function Log.warn(where: string, msg: string)
	warn(("%s %s: %s"):format(PREFIX, where, msg))
end

-- fail(where, msg) unless `cond` is truthy. Returns cond so it can be inlined.
function Log.assert(cond: any, where: string, msg: string): any
	if not cond then
		Log.fail(where, msg)
	end
	return cond
end

-- Type guard for a single option field. `accepts` is one type name or a list of
-- them (as returned by `typeof`, so "table"/"number"/"function"/"Color3"/
-- "EnumItem"/…). `nil`/absent always passes — callers validate required-ness
-- separately. Fails with a message naming the field, the accepted type(s), and
-- what we actually got.
function Log.field(where: string, field: string, value: any, accepts: string | { string })
	if value == nil then
		return value
	end
	local got = typeof(value)
	local list = type(accepts) == "table" and accepts or { accepts :: string }
	for _, want in list do
		if got == want then
			return value
		end
	end
	Log.fail(where, ("%s must be a %s, got %s"):format(field, table.concat(list, " or "), got))
	return value
end

return Log
