--!strict
-- Krypton — a reusable dark-theme Roblox UI component library.
--
--   local Krypton = require(path.to.krypton)
--   local Window  = Krypton:CreateWindow({ Title = "Krypton", Subtitle = "hub", Version = "v1" })
--   local Tab     = Window:CreateTab({ Name = "Home", Icon = "home" })
--   local Group   = Tab:CreateGroup({ Title = "Profile", Column = 1 })
--   Group:Toggle({ Name = "Enable", Default = true, Callback = function(on) end })
--
-- See the component modules under components/ for each control's options.

local Window = require(script.components.Window)
local Theme = require(script.Theme)
local Asset = require(script.util.Asset)
local Log = require(script.util.Log)
local Singleton = require(script.util.Singleton)

local Krypton = {}

-- Image plumbing, exposed so callers can resolve their own art (ids, https urls,
-- local files) the same way the components do — see util/Asset.lua.
Krypton.Asset = Asset
Krypton.Theme = Theme

function Krypton:CreateWindow(options: any?)
	-- A very common miscall is `Krypton.CreateWindow(...)` (dot, not colon) — then
	-- `options` is the table but `self` swallowed nothing, or the caller passes a
	-- bare string title. Catch a non-table here so the failure names the fix
	-- instead of surfacing as a nil-index inside Window.
	if options ~= nil and type(options) ~= "table" then
		Log.fail("CreateWindow", ("options must be a table like { Title = ... }, got %s"
			.. " (did you use Krypton.CreateWindow(...) instead of Krypton:CreateWindow(...)?)")
			:format(typeof(options)))
	end
	return Window(options)
end

-- ── single instance ─────────────────────────────────────────────────────────
-- CreateWindow already unloads whatever a previous run of the loadstring left
-- on screen (util/Singleton.lua), so re-running the loader refreshes the UI
-- instead of stacking a second copy. These expose the same slot to loaders that
-- want to check or clear it themselves:
--
--   if Krypton:IsLoaded() then ... end          -- or getgenv()._KRYPTON_LOADED
--   Krypton:Unload()                            -- tear down the live window
Krypton.Singleton = Singleton

function Krypton:IsLoaded(): boolean
	return Singleton.get() ~= nil
end

-- Returns true if a window was actually torn down.
function Krypton:Unload(): boolean
	return Singleton.unloadExisting(Theme.Brand.name)
end

return Krypton
