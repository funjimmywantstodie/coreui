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

print("[coreui] build: chevron-spin-1 loaded") -- build marker; remove once verified

local coreui = {}

function coreui:CreateWindow(options: any?)
	return Window(options)
end

return coreui
