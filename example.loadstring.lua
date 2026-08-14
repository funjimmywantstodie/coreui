-- example.loadstring.lua — the Uranium demo, loaded over HTTP from the bundle.
-- Paste this whole thing into your executor. No instance tree / require needed:
-- loadstring runs the bundled source and returns the library table.

local URL = "https://raw.githubusercontent.com/funjimmywantstodie/coreui/refs/heads/main/coreui.bundle.lua"
local Uranium = loadstring(game:HttpGet(URL .. "?v=" .. tick()))()

local Window = Uranium:CreateWindow({
	Title        = "Uranium",
	Subtitle     = "script hub",
	Version      = "v1.0.0",
	ConfigFolder = "uranium",                -- where saved configs live on disk
	ToggleKey    = Enum.KeyCode.RightShift, -- show/hide the window
	-- Boot animation — `Splash = true` for the defaults, or a table to tune it.
	-- Duration is the whole thing (1–8s); the bar fills for whatever is left
	-- after the intro, and Steps captions it as it goes.
	Splash       = {
		Duration = 2.2,
		Steps    = { "initializing", "loading components", "ready" },
	},
	-- Floating bind HUD — `Hud = true` for the defaults, or a table to place it.
	-- It lists every named bind with its mode, lights the ones that are live right
	-- now, and reads out FPS / ping. Drag it anywhere, click the caret to collapse
	-- it to a title bar. It stays up while the window is minimized (that's the
	-- point), the Settings tab has a switch for it, and a saved config remembers
	-- where you left it.
	Hud          = { X = 16, Y = 120 },
	-- ScreenGui is parented to LocalPlayer.PlayerGui
})

--------------------------------------------------------------------------------
-- TAB 1 · Home
--
-- The sidebar is icon-only, so `Name`/`Desc`/`Badge` are what the hover flyout
-- shows — that's the tab's label. Everything else about a tab is optional and
-- listed under "Tab" in DOCS.md: Pin, Color, Style, Dot, Rail, Separator.
--------------------------------------------------------------------------------
local Home = Window:CreateTab({
	Name = "Home",
	Icon = "home",
	Desc = "Profile and session info.",
})

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
Session:Label({ Key = "Library",    Value = "Uranium" })
Session:Label({ Key = "Version",    Value = "1.0.0" })
Session:Label({ Key = "Components", Value = "15" })
Session:Label({ Key = "Status",     Value = "Connected" })
Session:Divider()
Session:Button({
	Label  = "Send Notification",
	Accent = true,
	Callback = function()
		Window:Notify({ Title = "Notification", Text = "A toast from Uranium." })
	end,
})

-- Three bound features, one per mode — this is what the HUD is for. Each shows up
-- in it as soon as it's built (the toggle's own `Name` is the label), and lights
-- while it's live, so you can read the state of the menu with the menu closed.
local Bound = Home:CreateGroup({ Title = "Bound Features", Column = 2 })
Bound:Toggle({
	Name = "Auto Parry", Desc = "Toggle — the key flips it.",
	Keybind = Enum.KeyCode.F, KeybindMode = "Toggle",
	Flag = "autoparry", KeybindFlag = "autoparry_key",
	Callback = function(on) print("autoparry:", on) end,
})
Bound:Toggle({
	Name = "Aim Assist", Desc = "Hold — on only while the key is down.",
	Keybind = Enum.KeyCode.E, KeybindMode = "Hold",
	Flag = "aim_assist", KeybindFlag = "aim_assist_key",
	Callback = function(on) print("aim:", on) end,
})
Bound:Toggle({
	Name = "ESP", Desc = "Always — pinned on, the key does nothing.",
	Keybind = Enum.KeyCode.X, KeybindMode = "Always",
	Flag = "esp", KeybindFlag = "esp_key",
	Callback = function(on) print("esp:", on) end,
})

-- The HUD's readout row is extensible: SetStat(label, value) adds or updates a
-- pill next to FPS / MS, SetStat(label, nil) drops it again. GetHud() returns nil
-- once the window is unloaded, which is what ends this loop.
task.spawn(function()
	while Window:GetHud() do
		Window:GetHud():SetStat("PLRS", #game:GetService("Players"):GetPlayers())
		task.wait(5)
	end
end)

--------------------------------------------------------------------------------
-- TAB 2 · Components
--------------------------------------------------------------------------------
local Components = Window:CreateTab({
	Name = "Components",
	Icon = "layers",
	Desc = "Every control in the library.",
})

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
-- A plain keybind is a key PICKER: no Mode, so nothing is bound and the callback
-- just tells you which key was chosen.
Inputs:Keybind({
	Name = "Toggle Menu", Desc = "This is a keybind — click, then press a key.",
	Default = Enum.KeyCode.RightShift, Flag = "menu_key",
	Callback = function(key) print("bound:", key) end,
})
-- Give it a `Mode` and it becomes a live bind: the key drives a value and the
-- callback fires on every activation. The chip grows a second half you click to
-- cycle the mode; right/middle click on the key half binds MB2 / MB3.
--   "Toggle" press flips it · "Hold" on only while held · "Press" one-shot
--   command · "Always" pinned on · "None" the picker above.
Inputs:Keybind({
	Name = "Sprint", Desc = "Hold to sprint — click the chip's mode half for Toggle / Hold / Always.",
	Default = Enum.KeyCode.LeftShift, Mode = "Hold", Flag = "sprint_key",
	Callback = function(active, info) print("sprint:", active, info.KeyName, info.Mode) end,
	OnChanged = function(key, mode) print("re-bound to", key, "as", mode) end,
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
-- Any toggle can carry its own key — `Keybind` binds it, `KeybindMode` says what
-- the key does. `KeybindFlag` persists the key + mode alongside the value, so a
-- saved config restores "hold B" as well as "on".
-- Flags are one global namespace: this can't be `walkspeed`, because the Movement
-- tab's WalkSpeed slider already owns that one and the second registration would
-- quietly take over the slot (only the last one saves or loads).
Controls:Toggle({
	Name = "Walkspeed", Desc = "Bound to B — click the chip's mode half for Toggle / Hold / Always.",
	Keybind = Enum.KeyCode.B, KeybindMode = "Hold",
	Flag = "walkspeed_boost", KeybindFlag = "walkspeed_boost_key",
	Callback = function(on)
		local char = game:GetService("Players").LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = on and 50 or 16 end
	end,
})
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
-- url (downloaded + cached on first use), a file the executor wrote to disk, or
-- an ARRAY of those as a fallback chain. Same for Player.Avatar and a
-- MediaPlayer track's Cover.
--
-- Prefer a URL first, id second: the URL is cached to disk and loaded via
-- getcustomasset, so it dodges Roblox moderation / Asset Privacy / decal-id
-- issues entirely, and the id covers executors with no file access. The Uranium
-- mark isn't uploaded as an asset yet, so this chain is URL-only for now.
-- `Uranium.Asset.url("name.png")` resolves a filename against the public
-- asset repo, so shipping new art is just committing the file.
local Media = Components:CreateGroup({ Title = "Media", Column = 2 })
local banner = Media:Image({
	Name    = "Logo",
	Desc    = "A 512×512 mark, rounded off by the frame.",
	Image   = { Uranium.Asset.url("uranium-orbitals-512-square.png") },
	Height  = 150,
	Fit     = "contain",
	Caption = "Image = <id> | \"https://…\" | \"folder/art.png\" | { chain, of, these }",
})
Media:Button({
	Label = "Swap Image",
	Callback = function()
		-- :Set takes the same source types; a headshot is a handy live example.
		local me = game:GetService("Players").LocalPlayer
		banner:Set(Uranium.Asset.headshot(me and me.UserId or 1, 352))
	end,
})

local Appearance = Components:CreateGroup({ Title = "Appearance", Column = 2 })
Appearance:Colorpicker({
	Name = "Accent", Desc = "This is a color picker — it re-themes the UI.",
	Default = Color3.fromHex("7be04a"),
	Callback = function(c) Window:SetAccent(c) end, -- live re-theme
})
Appearance:Colorpicker({ Name = "Highlight", Default = Color3.fromHex("96ec69") })
Appearance:Divider()
Appearance:Paragraph({ Title = "Paragraph", Body = "Title plus body text for notes and instructions." })

-- Images: `Image` takes a bare decal id, an rbxassetid string, an https url, or
-- a local file the executor wrote — see the Media group on the Components tab.

-- NOTE: `Group:MediaPlayer{...}` is still part of the library (see
-- coreui/components/MediaPlayer.lua and the CLAUDE.md section on it) — it's just
-- left out of this demo for now so the tour stays focused on the core controls.

--------------------------------------------------------------------------------
-- TAB 3 + 4 · two CLASSES of tab, told apart at a glance
--
-- This is what the tab options are for. A script hub usually has two kinds of
-- tab and the sidebar gives you no way to tell them apart: mods that work in any
-- game, and mods that only mean something in the game you happen to be in. So:
--
--   * they get their own `Color` (blue = universal, amber = this game only),
--     which paints the active tile, the rail, the dot and the flyout badge;
--   * a `Dot` marks them even when they're not selected — no hover needed;
--   * `Separator` cuts the rail above them, so they read as their own cluster;
--   * `Badge`/`Desc` spell it out in the flyout;
--   * the game tab is `Style = "solid"` — a filled tile, the loudest of the
--     three active styles, because it's the one tab that isn't always there.
--------------------------------------------------------------------------------
local Universal = Window:CreateTab({
	Name      = "Player Mods",
	Icon      = "person",
	Desc      = "Universal — works in any game.",
	Badge     = "Global",
	Color     = Color3.fromHex("4AA8E0"),
	Dot       = true,
	Separator = true, -- start a new cluster in the rail
})
local Movement = Universal:CreateGroup({ Title = "Movement", Column = 1 })
Movement:Slider({ Name = "WalkSpeed", Min = 16, Max = 200, Default = 16, Flag = "walkspeed" })
Movement:Slider({ Name = "JumpPower", Min = 50, Max = 300, Default = 50, Flag = "jumppower" })
Movement:Toggle({
	Name = "Infinite Jump", Desc = "Bound to J — click the chip's mode half for the mode.",
	Keybind = Enum.KeyCode.J, KeybindMode = "Toggle", Flag = "infjump",
})
local Safety = Universal:CreateGroup({ Title = "Safety", Column = 2 })
Safety:Toggle({ Name = "No Fall Damage", Flag = "nofall" })
Safety:Toggle({ Name = "Anti AFK", Default = true, Flag = "antiafk" })

-- The game tab, hidden until we know the game is supported. `Visible = false` at
-- build time takes the same path as tab:SetVisible(false) later, so nothing
-- selects a tab that isn't in the sidebar.
local ThisGame = Window:CreateTab({
	Name    = "This Game",
	Icon    = "bug",
	Desc    = "Only for the place you're in.",
	Badge   = "Game",
	Color   = Color3.fromHex("FFC53D"),
	Style   = "solid",
	Visible = false,
	Callback = function(tab)
		-- Fires every time the tab is opened — the hook for re-scanning whatever
		-- the game side of a hub needs to find fresh.
		print("[demo] game tab opened:", tab:GetColor())
	end,
})
local Detected = ThisGame:CreateGroup({ Title = "Detected", Column = 1 })
Detected:Label({ Key = "PlaceId", Value = tostring(game.PlaceId) })
Detected:Paragraph({
	Title = "Supported",
	Body  = "A real hub swaps this tab's name, icon and contents per game, then "
	     .. "shows it with tab:SetVisible(true). Everything here is settable at "
	     .. "runtime: SetName / SetIcon / SetColor / SetStyle / SetDot / SetPin.",
})
-- Pretend we just recognized the game.
ThisGame:SetName("Metro Destruction Wars")
ThisGame:SetVisible(true)

--------------------------------------------------------------------------------
-- TAB 5 · Settings (built in — accent, toggle key, config save/load)
-- Create it LAST so its auto-load pass sees every flagged control above.
--
-- Pinned to the BOTTOM of the rail: it isn't a feature tab, and the bottom
-- cluster is where a chrome tab belongs. CreateSettingsTab forwards every
-- CreateTab option, so it takes Pin / Color / Style / Dot like any other tab.
--------------------------------------------------------------------------------
Window:CreateSettingsTab({
	Pin  = "bottom",
	Desc = "Accent, keybind, configs.",
})

-- A keybind with no control attached, for logic the menu doesn't expose. Same
-- modes, same router (so it pauses while a keybind chip is capturing a key).
-- Returns the binding: :SetKey / :SetMode / :GetState / :Destroy.
Window:Bind(Enum.KeyCode.F, function()
	Window:Notify({ Title = "Bind", Text = "F pressed." })
end, "Press")

print("[Uranium] demo built — Home / Components / Player / This Game / Settings tabs ready")
