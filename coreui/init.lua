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
local Config = require(script.util.Config)
local Log = require(script.util.Log)
local Settings = require(script.components.Settings)
local Singleton = require(script.util.Singleton)
local Services = require(script.util.Services)
local Gui = require(script.util.Gui)
local Screen = require(script.components.Screen)

local Uranium = {}

-- Image plumbing, exposed so callers can resolve their own art (ids, https urls,
-- local files) the same way the components do — see util/Asset.lua.
Uranium.Asset = Asset
Uranium.Theme = Theme

-- The executor filesystem layer (util/Config.lua) — feature-detected
-- (`Config.supported`), fully pcall-guarded, and now reachable, because a host
-- that scopes or shares configs otherwise ends up rewriting all of it (globals
-- resolution, isfile/readfile guards, list-by-extension) to do anything the
-- window's own methods don't cover.
--
--   Uranium.Config.sanitize(name) == name   -- will this name round-trip?
--   Uranium.Config.list(folder)             -- another folder's configs
--   Uranium.Config.info(folder, name)       -- its metadata, without applying it
--   Uranium.Config.MetaKey                  -- the reserved key that metadata lives under
Uranium.Config = Config

-- The built-in settings panel, as three composable group builders
-- (`InterfaceGroup` / `ConfigGroup` / `DangerGroup`). `Window:CreateSettingsTab`
-- is these three on a tab of their own; a host that wants its own layout — or
-- only the Interface half next to its own config UI — builds from here instead:
--
--   local tab = Window:CreateTab({ Name = "Settings", Icon = "gear" })
--   Uranium.Settings.InterfaceGroup(Window, tab)
--   myOwnConfigGroup(tab)
Uranium.Settings = Settings

-- The service cache every module reads through (util/Services.lua) — cloned with
-- `cloneref` where the executor has it, so the library's references aren't the
-- ones the place gets from its own `game:GetService`. A host with its own cache
-- passes it as the chunk vararg (`loadstring(src)(Services)`) and the library
-- adopts it; this is the same table either way.
Uranium.Services = Services

-- Where the ScreenGui goes and what it's called (util/Gui.lua) — exposed so a
-- host can resolve the same container the library would (`Gui.mount`,
-- `Gui.roots`, `Gui.rname`) instead of reimplementing the gethui/CoreGui dance.
Uranium.Gui = Gui

-- Console output. Everything chatty is OFF by default — a game scraping
-- LogService reads every line the client prints, and a branded one is a free
-- fingerprint. Failures (`Log.warn` / `Log.fail`) still print.
--
--   Uranium.setVerbose(true)         -- or CreateWindow{ Verbose = true }
--   Uranium.setLogPrefix("[hub]")    -- one place; every line follows
--   getgenv().URANIUM_VERBOSE = true -- before the loadstring, for load-time lines
Uranium.Log = Log

function Uranium.setVerbose(on: boolean?)
	Log.setVerbose(on)
end

function Uranium.setLogPrefix(prefix: string)
	Log.setPrefix(prefix)
end

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

-- ── the status page ─────────────────────────────────────────────────────────
-- A full-screen page for the things a toast can't carry: the hub's own scripts
-- failing on the way up, or — before there is a hub at all — the delivery server
-- refusing the client. Those used to be a `warn()` behind whatever else was in
-- the executor console, i.e. invisible, i.e. "it doesn't work".
--
--   Uranium:Screen({
--       Title = "You've been banned",
--       Text  = "Reason: reselling builds.",
--       Code  = "BANNED",
--       Icon  = "ban",
--       Tone  = "error",           -- "error" | "warning" | "info"
--       Discord = "discord.gg/uranium",
--       Dismissable = false,
--   })
--
-- It needs no window and creates none — that's the main case. See DOCS.md and
-- components/Screen.lua; `ui/screen.lua` is the same page built with none of
-- the library behind it, for code that runs before this file is even fetched.
function Uranium:Screen(options: any?)
	-- Deliberately unguarded beyond this: the page's own options are all
	-- optional and coerced, but if building it genuinely fails, the caller's
	-- `pcall` around this call is what falls back to a console warning — and
	-- swallowing the error here would hand them a page that doesn't exist while
	-- reporting success.
	if options ~= nil and type(options) ~= "table" then
		Log.warn("Screen", ("options must be a table like { Title = ... }, got %s"
			.. " — showing the generic page."):format(typeof(options)))
		options = nil
	end
	-- `Uranium.Screen{...}` (dot, not colon) puts the options table in `self`.
	-- CreateWindow only has to warn about that; here it has to *recover*, because
	-- the generic "Something went wrong" page this would otherwise show is
	-- indistinguishable from the page the caller asked for and throws away the
	-- one thing they were trying to tell the user.
	if options == nil and type(self) == "table"
		and (self.Title ~= nil or self.Text ~= nil or self.Code ~= nil or self.Icon ~= nil) then
		options = self
	end
	return Screen(options)
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

-- "Is there a WINDOW?" — deliberately not "is any of our UI on screen". A status
-- page never claims the singleton slot, so a loader can put one up and still use
-- this to decide whether it needs to build its menu.
function Uranium:IsLoaded(): boolean
	return Singleton.get() ~= nil
end

-- Returns true if anything of ours was actually torn down. No name is passed:
-- current builds give the ScreenGui a random name and are found by attribute,
-- and the old brand names are swept from `Singleton.LegacyNames` anyway.
--
-- That attribute sweep is also what takes a live `Uranium:Screen` page down —
-- here and in `CreateWindow`, which runs the same sweep before it builds. It has
-- to: a ban page still sitting there after the user re-runs a fixed loadstring
-- is exactly the failure this is all supposed to prevent.
function Uranium:Unload(): boolean
	return Singleton.unloadExisting()
end

return Uranium
