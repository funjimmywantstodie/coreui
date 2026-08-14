--!strict
-- util/Services.lua — the single place the library touches `game:GetService`.
--
-- Two reasons this exists, and only one of them is tidiness:
--
--  1. **cloneref.** Executors expose `cloneref(service)`, which hands back a
--     reference that is NOT the one the place gets from its own
--     `game:GetService("UserInputService")`. A game that hooks a service's
--     methods, or compares identities (`svc == game:GetService(...)`), sees the
--     library's calls as coming from somewhere else entirely. Fifteen scattered
--     `game:GetService` calls can't be wrapped after the fact; one funnel can.
--  2. **The host's own cache.** A hub that already built its cloned services
--     passes the table in as the chunk vararg (`loadstring(src)(Services)`), and
--     the library adopts it instead of making a second set of clones — so the
--     hub and the UI hold the *same* references. The library must still work
--     standalone, so a missing/!table vararg falls through to building its own.
--
-- Access is lazy and memoized: `Services.UserInputService` resolves on first
-- touch, `rawset`s itself, and every later read is a plain table index.
--
-- In the bundled build, bundle.py wraps each module as `function(...)` and
-- threads the chunk's varargs through `__require`, so `...` here is whatever the
-- loader passed. In the plain ModuleScript tree `...` is simply empty, and the
-- fallback branch runs.

local passed: any = ...

local Services: any = if type(passed) == "table" then passed else nil

if Services == nil then
	Services = setmetatable({}, {
		__index = function(self: any, name: string): any
			local ok, svc = pcall(function()
				local s = game:GetService(name :: any)
				-- Feature-detected exactly like the file globals in util/Config.lua:
				-- absent in Studio and on some executors, and never required.
				return (type(cloneref) == "function") and cloneref(s) or s
			end)
			if not ok then
				error("Invalid Service: " .. tostring(name), 2)
			end
			rawset(self, name, svc)
			return svc
		end,
	})
end

return Services
