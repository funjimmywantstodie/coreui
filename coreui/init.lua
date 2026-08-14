--!strict
-- Uranium — a reusable dark-theme Roblox UI component library.
--
--   local Uranium = require(path.to.Uranium)
--   local Window  = Uranium:CreateWindow({ Title = "Uranium", Subtitle = "hub", Version = "v1" })
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

local Uranium = {}

-- Image plumbing, exposed so callers can resolve their own art (ids, https urls,
-- local files) the same way the components do — see util/Asset.lua.
Uranium.Asset = Asset
Uranium.Theme = Theme

-- Point the asset helper at the public art repo, so `Asset.url("x.png")`
-- resolves a bare filename against it. Set here (not in Asset.lua) to keep the
-- brand URL in one place — Theme.Brand.
Asset.Base = Theme.Brand.assets

function Uranium:CreateWindow(options: any?)
	-- A very common miscall is `Uranium.CreateWindow(...)` (dot, not colon) — then
	-- `options` is the table but `self` swallowed nothing, or the caller passes a
	-- bare string title. Catch a non-table here so the failure names the fix
	-- instead of surfacing as a nil-index inside Window.
	if options ~= nil and type(options) ~= "table" then
		Log.fail("CreateWindow", ("options must be a table like { Title = ... }, got %s"
			.. " (did you use Uranium.CreateWindow(...) instead of Uranium:CreateWindow(...)?)")
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
--   if Uranium:IsLoaded() then ... end          -- or getgenv()._URANIUM_LOADED
--   Uranium:Unload()                            -- tear down the live window
Uranium.Singleton = Singleton

function Uranium:IsLoaded(): boolean
	return Singleton.get() ~= nil
end

-- Returns true if a window was actually torn down.
function Uranium:Unload(): boolean
	return Singleton.unloadExisting(Theme.Brand.name)
end

return Uranium
