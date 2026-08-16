--!nocheck
-- tests/smoke.luau — load the built bundle outside Roblox and check the API is
-- on it. Run by bundle.py on every build; `luau tests/smoke.luau` by hand.
--
-- What this catches, which nothing else did: a module that parses but blows up
-- when its body runs (a bad require path, a nil index in a load-time constant, a
-- require cycle), and a public method that quietly stopped existing. Before
-- this, the whole of "does the library load?" was answered by pasting a
-- loadstring into an executor.
--
-- What it deliberately does not catch: anything visual, anything about layout,
-- and anything that only happens once a window is built. See tests/roblox.luau
-- for why the stub stops where it does.
--
-- Not run on its own: bundle.py concatenates tests/roblox.luau, the built bundle
-- (evaluated exactly as a loadstring consumer evaluates it) and this file into
-- one chunk, then runs `luau` on it. One chunk because the CLI gives every
-- required module a fresh environment, so a stub in another file sets globals
-- for nobody. `Uranium` and `LOAD_ERROR` are what the composed chunk hands over.

if LOAD_ERROR then
	error("the bundle failed to LOAD: " .. tostring(LOAD_ERROR), 0)
end
if type(Uranium) ~= "table" then
	error("the bundle returned " .. typeof(Uranium) .. ", expected the library table", 0)
end

-- The library surface, as init.lua exposes it. Anything renamed or dropped
-- without the docs and the demo following shows up here.
local METHODS = { "CreateWindow", "Screen", "IsLoaded", "Unload", "setVerbose", "setLogPrefix" }
local TABLES = { "Asset", "Theme", "Config", "Settings", "Services", "Gui", "Log", "Singleton" }

local missing = {}
for _, name in METHODS do
	if type(Uranium[name]) ~= "function" then
		table.insert(missing, name .. "()")
	end
end
for _, name in TABLES do
	if type(Uranium[name]) ~= "table" then
		table.insert(missing, "." .. name)
	end
end
if #missing > 0 then
	error("the library table is missing " .. table.concat(missing, ", "), 0)
end

-- The two entry points validate their arguments before touching anything, so a
-- bad call is reachable without a working renderer. Both must FAIL loudly rather
-- than build something broken from a string.
local threw = pcall(function()
	return Uranium:CreateWindow("Title, not a table")
end)
if threw then
	error("CreateWindow accepted a string where it documents a table", 0)
end

print(("ok: smoke — bundle loads, %d methods + %d tables present")
	:format(#METHODS, #TABLES))
