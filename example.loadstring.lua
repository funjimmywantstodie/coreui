-- example.loadstring.lua — the Krypton demo, loaded over HTTP from the bundle.
-- Paste this whole thing into your executor. No instance tree / require needed:
-- loadstring runs the bundled source and returns the library table.

local URL = "https://raw.githubusercontent.com/funjimmywantstodie/coreui/refs/heads/main/coreui.bundle.lua"
local Krypton = loadstring(game:HttpGet(URL .. "?v=" .. tick()))()

local Window = Krypton:CreateWindow({
	Title        = "Krypton",
	Subtitle     = "script hub",
	Version      = "v1.0.0",
	ConfigFolder = "krypton",                -- where saved configs live on disk
	ToggleKey    = Enum.KeyCode.RightShift, -- show/hide the window
	-- ScreenGui is parented to LocalPlayer.PlayerGui
})

--------------------------------------------------------------------------------
-- TAB 1 · Home
--------------------------------------------------------------------------------
local Home = Window:CreateTab({ Name = "Home", Icon = "home" })

local Profile = Home:CreateGroup({ Title = "Profile", Column = 1 }) -- 1 = left
Profile:Player({
	Username    = "guest",
	DisplayName = "Guest",
	UserId      = 0,
	Badge       = "Free",
})
Profile:Paragraph({
	Title = "Welcome",
	Body  = "This is the player / info panel — username, display name and id. "
	     .. "Everything you see is a live component from the library.",
})

local Session = Home:CreateGroup({ Title = "Session", Column = 2 }) -- 2 = right
Session:Label({ Key = "Library",    Value = "Krypton" })
Session:Label({ Key = "Version",    Value = "1.0.0" })
Session:Label({ Key = "Components", Value = "15" })
Session:Label({ Key = "Status",     Value = "Connected" })
Session:Divider()
Session:Button({
	Label  = "Send Notification",
	Accent = true,
	Callback = function()
		Window:Notify({ Title = "Notification", Text = "A toast from Krypton." })
	end,
})

--------------------------------------------------------------------------------
-- TAB 2 · Components
--------------------------------------------------------------------------------
local Components = Window:CreateTab({ Name = "Components", Icon = "layers" })

-- left column ----------------------------------------------------------------
local Inputs = Components:CreateGroup({ Title = "Inputs", Column = 1 })
-- A `Flag` makes a control's value persist — captured by config save/load (see
-- the Settings tab) and restored on auto-load.
Inputs:Input({
	Name = "Username", Desc = "This is a textbox.", Placeholder = "Enter text...",
	Flag = "username",
	Callback = function(text) print("username:", text) end,
})
Inputs:Input({ Name = "Webhook URL", Placeholder = "https://...", Flag = "webhook" })
Inputs:Slider({
	Name = "Volume", Desc = "This is a slider — drag the handle.",
	Min = 0, Max = 100, Default = 50, Suffix = "%", Flag = "volume",
	Callback = function(v) print("volume:", v) end,
})
Inputs:Keybind({
	Name = "Toggle Menu", Desc = "This is a keybind — click, then press a key.",
	Default = Enum.KeyCode.RightShift, Flag = "menu_key",
	Callback = function(key) print("bound:", key) end,
})

local Selection = Components:CreateGroup({ Title = "Selection", Column = 1 })
Selection:Dropdown({
	Name = "Single Select", Desc = "This is a dropdown — pick one.", Stack = true,
	Options = { "Option A", "Option B", "Option C", "Option D" }, Placeholder = "Select...",
	Flag = "single_select",
	Callback = function(choice) print("picked:", choice) end,
})
Selection:MultiDropdown({
	Name = "Multi Select", Desc = "This is a multi-select — pick several.", Stack = true,
	Options = { "Fire", "Water", "Earth", "Air", "Light", "Dark" },
	Default = { "Fire", "Water" }, Flag = "multi_select",
	Callback = function(list) print("selected:", table.concat(list, ", ")) end,
})
Selection:Dropdown({ Name = "Quality", Options = { "Low", "Medium", "High", "Ultra" }, Default = "High", Width = 120 })
Selection:PlayerSelect({
	Name = "Target Player", Desc = "This is a player select — pick one from everyone online, with avatar.",
	Stack = true, Flag = "target_player",
	Callback = function(p) print("target:", p and p.Name or "none") end,
})
Selection:PlayerMultiSelect({
	Name = "Squad", Desc = "This is a multi player select — pick several players.",
	Stack = true, Flag = "squad",
	Callback = function(list)
		local names = {}
		for _, p in list do table.insert(names, p.Name) end
		print("squad:", table.concat(names, ", "))
	end,
})

-- A Code field: a multi-line monospace editor for pasting raw config that won't
-- fit a structured control (Lua tables, JSON, scripts). `Parse` validates it on
-- blur — a parse error paints the box red and prints the message beneath it.
-- `:GetValue()` returns the last parsed result; the raw text is Flag-saved.
local RawConfig = Components:CreateGroup({ Title = "Raw Config", Column = 1 })
local cfg = RawConfig:Code({
	Name = "Action Sequence", Desc = "Paste a Lua config table — validated on blur.",
	LineNumbers = true, Height = 180, Flag = "raw_config",
	Default = "return {\n  { type = \"place\",   id = \"pyro1\", cost = 1350 },\n  { type = \"upgrade\", id = \"pyro1\", tier = 1, cost = 487 },\n}",
	Parse = function(text)
		local fn = loadstring(text)        -- compile…
		if not fn then error("syntax error") end
		return fn()                        -- …and run; must return a table
	end,
	OnParse = function(ok, value, err)
		if ok then
			print("config ok:", #value, "actions")
		else
			print("config error:", err)
		end
	end,
})
RawConfig:Button({
	Label = "Run Config", Accent = true,
	Callback = function()
		local data = cfg:GetValue()
		Window:Notify({
			Title = "Config",
			Text = (type(data) == "table") and ("Parsed " .. #data .. " actions.") or "Fix the errors first.",
		})
	end,
})

-- right column ---------------------------------------------------------------
local Controls = Components:CreateGroup({ Title = "Controls", Column = 2 })
Controls:Toggle({
	Name = "Enable Feature", Desc = "This is a toggle switch.", Default = true,
	Flag = "enable_feature",
	Callback = function(on) print("feature:", on) end,
})
Controls:Toggle({ Name = "Auto Mode", Default = false, Flag = "auto_mode" })
Controls:Button({
	Name = "Primary Button", Desc = "This is an accent button.",
	Label = "Confirm", Accent = true,
	Callback = function() Window:Notify({ Title = "Button", Text = "Primary button clicked." }) end,
})
Controls:ButtonRow({
	{ Label = "Save", Callback = function() print("save") end },
	{ Label = "Load", Callback = function() print("load") end },
})

-- Images. `Image` accepts a bare decal id, an "rbxassetid://…" string, an https
-- url (downloaded + cached on first use), or a file the executor wrote to disk —
-- Krypton.Asset.resolve normalizes all of them, so you can paste whichever form
-- you have. Same for Player.Avatar and a MediaPlayer track's Cover.
local Media = Components:CreateGroup({ Title = "Media", Column = 2 })
local banner = Media:Image({
	Name    = "Logo",
	Desc    = "A 512×512 mark, rounded off by the frame.",
	Image   = 91296376944710, -- bare id — no rbxassetid:// prefix needed
	Height  = 150,
	Fit     = "contain",
	Caption = "Image = <decal id> | \"rbxassetid://…\" | \"https://…\" | \"folder/art.png\"",
})
Media:Button({
	Label = "Swap Image",
	Callback = function()
		-- :Set takes the same source types; a headshot is a handy live example.
		local me = game:GetService("Players").LocalPlayer
		banner:Set(Krypton.Asset.headshot(me and me.UserId or 1, 352))
	end,
})

local Appearance = Components:CreateGroup({ Title = "Appearance", Column = 2 })
Appearance:Colorpicker({
	Name = "Accent", Desc = "This is a color picker — it re-themes the UI.",
	Default = Color3.fromHex("00c46a"),
	Callback = function(c) Window:SetAccent(c) end, -- live re-theme
})
Appearance:Colorpicker({ Name = "Highlight", Default = Color3.fromHex("1fe087") })
Appearance:Divider()
Appearance:Paragraph({ Title = "Paragraph", Body = "Title plus body text for notes and instructions." })

-- Images: `Image` takes a bare decal id, an rbxassetid string, an https url, or
-- a local file the executor wrote — see the Media group on the Components tab.

-- NOTE: `Group:MediaPlayer{...}` is still part of the library (see
-- coreui/components/MediaPlayer.lua and the CLAUDE.md section on it) — it's just
-- left out of this demo for now so the tour stays focused on the core controls.

--------------------------------------------------------------------------------
-- TAB 3 · Settings (built in — accent, toggle key, config save/load)
-- Create it LAST so its auto-load pass sees every flagged control above.
--------------------------------------------------------------------------------
Window:CreateSettingsTab()

print("[Krypton] demo built — Home / Components / Settings tabs ready")
