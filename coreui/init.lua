--!strict
-- coreui — a reusable dark-theme Roblox UI component library.
--
--   local coreui = require(path.to.coreui)
--   local Window = coreui:CreateWindow({ Title = "coreui", Subtitle = "kit", Version = "v1" })
--   local Tab    = Window:CreateTab({ Name = "Home", Icon = "home" })
--   local Group  = Tab:CreateGroup({ Title = "Profile", Column = 1 })
--   Group:Toggle({ Name = "Enable", Default = true, Callback = function(on) end })
--
-- See the component modules under components/ for each control's options.

local Window = require(script.components.Window)
local Log = require(script.util.Log)

local coreui = {}

function coreui:CreateWindow(options: any?)
	-- A very common miscall is `coreui.CreateWindow(...)` (dot, not colon) — then
	-- `options` is the table but `self` swallowed nothing, or the caller passes a
	-- bare string title. Catch a non-table here so the failure names the fix
	-- instead of surfacing as a nil-index inside Window.
	if options ~= nil and type(options) ~= "table" then
		Log.fail("CreateWindow", ("options must be a table like { Title = ... }, got %s"
			.. " (did you use coreui.CreateWindow(...) instead of coreui:CreateWindow(...)?)")
			:format(typeof(options)))
	end
	return Window(options)
end

return coreui
