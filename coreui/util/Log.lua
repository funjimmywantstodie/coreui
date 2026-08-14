--!strict
-- util/Log.lua — one place every Uranium diagnostic flows through, so the format
-- stays uniform and the library explains a mistake instead of throwing a bare
-- "attempt to index nil value" three frames deep in a bundled chunk.
--
-- Policy:
--   * fail  — the call genuinely can't proceed (wrong TYPE for a required arg).
--             Raised with level 0 so the executor console shows our clean
--             "[Uranium] Slider "Speed": ..." text, not a bundle file:line prefix.
--   * warn  — a recoverable mistake (bad enum value, out-of-range index, a
--             missing option we can default). We say what happened + what we did
--             and keep building, so one typo never blanks the whole menu.
--
--   * info  — chatty progress/diagnostic output ("loaded", "SaveConfig -> ok",
--             the detected file-API capabilities). **Silent by default.** A game
--             scraping LogService reads everything the client prints, and six
--             branded lines on a normal load is a free fingerprint. Turn it on
--             with `CreateWindow{ Verbose = true }`, `Uranium.setVerbose(true)`,
--             or — for the lines that fire before any of that runs, at require
--             time — `getgenv().URANIUM_VERBOSE = true` before the loadstring.
--
-- `where` is a short human label for the call site, e.g. `Log.where("Slider",
-- opts.Name)` → `Slider "Speed"`. Keep messages actionable: name the field, the
-- value we got, and the fix.

local Log = {}

-- Every line the library prints is stamped with this, and it's writable from one
-- place so a host can rename it (or empty it) without patching call sites.
Log.Prefix = "[Uranium]"

-- Chatty output gate. warn/fail ignore it — a real failure that prints nothing
-- is worse than a fingerprint.
Log.Verbose = false

-- Build stamp, injected by bundle.py into the bundled build (nil in the plain
-- ModuleScript tree). Logged by Window under Verbose instead of unconditionally
-- at the top of the chunk.
Log.Build = nil :: string?

-- Pre-set opt-in, read once at require time: the banner and the config
-- capability line happen before CreateWindow can be reached.
do
	local on = false
	pcall(function()
		local env: any = if type(getgenv) == "function" then getgenv() else _G
		if type(env) == "table" and env.URANIUM_VERBOSE == true then
			on = true
		end
	end)
	Log.Verbose = on
end

function Log.setPrefix(prefix: string)
	if type(prefix) == "string" then
		Log.Prefix = prefix
	end
end

function Log.setVerbose(on: boolean?)
	Log.Verbose = on == true
end

-- Chatty line — dropped entirely unless Verbose.
function Log.info(msg: string)
	if not Log.Verbose then
		return
	end
	print(("%s %s"):format(Log.Prefix, msg))
end

-- Same, formatted. The format runs only when we're actually going to print.
function Log.infof(fmt: string, ...: any)
	if not Log.Verbose then
		return
	end
	print(("%s %s"):format(Log.Prefix, fmt:format(...)))
end

-- The build stamp, at most once per load. Two callers race for it: the bundled
-- chunk (which can only honour the pre-set env global) and CreateWindow (which
-- knows about `Verbose = true`, but runs later). Whichever gets there with
-- Verbose on prints; the other is a no-op. A run with output off never marks it,
-- so a second window built after `setVerbose(true)` still stamps.
local bannered = false

function Log.banner()
	if bannered or not Log.Verbose then
		return
	end
	bannered = true
	print(("%s build %s loaded"):format(Log.Prefix, Log.Build or "dev (module tree)"))
end

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
	return error(("%s %s: %s"):format(Log.Prefix, where, msg), 0)
end

-- Soft warning — lands in the executor console (warn channel), build continues.
function Log.warn(where: string, msg: string)
	warn(("%s %s: %s"):format(Log.Prefix, where, msg))
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
