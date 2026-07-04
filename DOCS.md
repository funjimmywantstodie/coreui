# coreui — documentation

A dark-theme UI component library for Roblox, written in Luau. One window, a
sidebar of tabs, two-column cards, and a full set of controls (buttons, toggles,
sliders, dropdowns, inputs, keybinds, color pickers, …) with built-in theming
and config save/load.

This is the consumer-facing API reference. For the internal architecture and
build flow, see [CLAUDE.md](CLAUDE.md).

---

## Loading the library

### Via executor (loadstring over HTTP)

```lua
local URL = "https://raw.githubusercontent.com/funjimmywantstodie/coreui/refs/heads/main/coreui.bundle.lua"
local coreui = loadstring(game:HttpGet(URL))()
```

If you want to guard the network/load step, wrap it in `pcall` — but mind the
return order: **`pcall` returns `(ok, result)`, so the library is the *second*
value, not the first.** Getting this backwards is the most common load bug (you
end up with `coreui = true` and every `coreui:Method(...)` call throws "attempt
to index boolean"):

```lua
local ok, coreui = pcall(function()
    return loadstring(game:HttpGet(URL))()
end)
if not ok then
    warn("[coreui] failed to load:", coreui) -- on failure, `coreui` holds the error
    return
end
-- coreui is the library table here
```

> Tip: `raw.githubusercontent.com` CDN-caches each path for ~5 min and ignores
> `?` query busters on the *same* path. To always get a fresh build, load the
> **commit-pinned** URL (`…/<sha>/coreui.bundle.lua`) that `push.py` copies to
> your clipboard, not the `…/main/…` branch URL.

### As a ModuleScript (Studio / Rojo)

Drop the `coreui/` tree into your place and `require` its `init`:

```lua
local coreui = require(path.to.coreui)
```

The bundle prints `[coreui] build <timestamp> <sha>` on load so you can confirm
the build that's actually running.

---

## Quick start

```lua
local Window = coreui:CreateWindow({
    Title    = "coreui",
    Subtitle = "component kit",
    Version  = "v1.0.0",
})

local Tab   = Window:CreateTab({ Name = "Home", Icon = "home" })
local Group = Tab:CreateGroup({ Title = "Demo", Column = 1 })

Group:Toggle({
    Name = "Enable Feature", Default = true,
    Callback = function(on) print("feature:", on) end,
})
Group:Button({
    Label = "Click me", Accent = true,
    Callback = function() Window:Notify({ Title = "Hi", Text = "Button clicked." }) end,
})

Window:CreateSettingsTab() -- built-in settings panel; create it LAST
```

A complete, annotated example lives in
[example.loadstring.lua](example.loadstring.lua).

---

## Structure

```
Window                         coreui:CreateWindow{...}
├── Tab                        Window:CreateTab{...}
│   └── Group  (card)          Tab:CreateGroup{...}     -- left/right column
│       ├── Section            Group:Section{...}        -- nested, collapsible
│       └── controls           Group:Toggle{...}, :Slider{...}, …
└── Settings Tab               Window:CreateSettingsTab()
```

Controls are added to a **Group** (or a **Section** inside a group). A Group is a
titled card; Sections are indented, collapsible sub-blocks. Both expose the same
control methods.

---

## Window

```lua
local Window = coreui:CreateWindow({
    Title        = "coreui",                 -- titlebar title           (default "coreui")
    Subtitle     = "component kit",          -- status-bar left text     (default "")
    Version      = "v1.0.0",                 -- status-bar right text    (default "")
    ConfigFolder = "coreui",                 -- on-disk config folder    (default "coreui")
    ToggleKey    = Enum.KeyCode.RightShift,  -- show/hide key            (default RightShift)
    Accent       = Color3.fromHex("f2680c"), -- initial accent color     (default theme accent)
})
```

The window is draggable by its titlebar, has minimize / maximize / close
buttons and a search field in the titlebar (filters the active tab as you type).
It's parented to `LocalPlayer.PlayerGui` (or `CoreGui` in Studio).

### Window methods

| Method | Description |
| --- | --- |
| `Window:CreateTab(opts)` | Add a tab. Returns a **Tab**. See below. |
| `Window:CreateSettingsTab(opts?)` | Add the built-in settings panel. Call **last**. |
| `Window:Notify(opts)` | Show a toast notification (bottom-right). |
| `Window:Select(index)` | Switch to tab `index` (1-based). |
| `Window:SetAccent(color)` | Re-theme the whole UI to `color` (a `Color3`), live. |
| `Window:SetToggleKey(key)` | Re-bind the show/hide key (`Enum.KeyCode`). |
| `Window:SetNotificationsEnabled(bool)` | Enable/disable toasts globally. |
| `Window:SaveConfig(name)` → `bool` | Save all flagged values to `<name>.json`. |
| `Window:LoadConfig(name)` → `bool` | Load + apply a saved config. |
| `Window:DeleteConfig(name)` → `bool` | Delete a saved config. |
| `Window:ListConfigs()` → `{string}` | List saved config names. |
| `Window:Destroy()` | Fade out and fully unload (disconnects listeners). |

`Window.ConfigSupported` (`boolean`) tells you whether the executor exposes file
functions. In Studio / unsupported executors, config calls no-op safely.

### Notify

```lua
Window:Notify({
    Title    = "Saved",         -- optional
    Text     = "Config saved.",  -- body
    Type     = "success",        -- optional: "success" | "info" | "warning" | "error"
    Duration = 3.2,              -- seconds on screen (default 3.2)
})
```

`Type` picks a semantic style — a colored accent bar plus a matching icon
(success = green check, info = blue, warning = amber triangle, error = red).
It is case-insensitive and `"warn"` aliases `"warning"`. Omit `Type` (or pass
anything unrecognized) for the original accent-colored toast with no icon.

---

## Tab

```lua
local Tab = Window:CreateTab({
    Name = "Home",   -- sidebar label / tooltip (default "Tab")
    Icon = "home",   -- Lucide icon short-name  (default "gear")
})
```

| Method | Description |
| --- | --- |
| `Tab:CreateGroup(opts)` | Add a card. Returns a **Group** control surface. |

---

## Group

```lua
local Group = Tab:CreateGroup({
    Title     = "Profile",  -- card header                 (default "Group")
    Column    = 1,          -- 1 = left column, 2 = right  (default 1)
    Collapsed = false,      -- start collapsed             (default false)
})
```

The header is clickable — it collapses/expands the card. The returned object is a
**control surface**: call the control methods below on it. The same surface is
returned by `Group:Section{}`.

---

## Section (nested group)

```lua
local Sub = Group:Section({
    Title     = "Advanced",  -- section header   (default "Section")
    Collapsed = true,        -- start collapsed  (default false)
})
Sub:Toggle({ Name = "Verbose logging" })
```

Returns a nested control surface (indented, with a left rule and its own
collapse chevron). Add controls to it exactly like a Group.

---

## Controls

All controls below are methods on a **Group** or **Section** surface.

### Common conventions

- **`Name`** — the field label (left side). **`Desc`** — optional sub-text under it.
  Omitting `Name` on a Button makes it a bare full-width button.
- **`Callback`** — fired on every value change with the new value.
- **`Default`** — initial value.
- **`Flag = "id"`** — registers the control for config save/load. The value is
  captured on `SaveConfig` and restored on `LoadConfig` / auto-load. See
  [Config & flags](#config--flags). Only stateful controls support flags
  (Toggle, Slider, Dropdown, MultiDropdown, Input, Code, Keybind, Colorpicker).

Stateful controls return a **handle** with `:Get()` and `:Set(value)`. `:Set`
fires the callback.

---

### Toggle

```lua
local h = Group:Toggle({
    Name = "Enable Feature", Desc = "A toggle switch.",
    Default = true, Flag = "enable_feature",
    Callback = function(on) print(on) end,
})
h:Get()        -- → boolean
h:Set(false)
```

### Button / ButtonRow

```lua
-- titled button
Group:Button({
    Name = "Primary Button", Desc = "An accent button.",
    Label = "Confirm",   -- button text
    Accent = true,       -- accent-colored (default false)
    Callback = function() ... end,
})

-- bare full-width button (no Name)
Group:Button({ Label = "Run", Callback = function() ... end })

-- a row of evenly-split buttons
Group:ButtonRow({
    { Label = "Save", Callback = function() ... end },
    { Label = "Load", Accent = true, Callback = function() ... end },
})
```

Buttons are not flaggable (no persistent state).

### Slider

```lua
local h = Group:Slider({
    Name = "Volume", Desc = "Drag the handle.",
    Min = 0, Max = 100, Default = 50,
    Step = 1,            -- step increment (default 1)
    Suffix = "%",        -- shown after the value (default "")
    Flag = "volume",
    Callback = function(v) print(v) end,
})
h:Get()      -- → number
h:Set(75)
```

### Input

```lua
local h = Group:Input({
    Name = "Username", Desc = "A textbox.",
    Placeholder = "Enter text...",
    Default = "",
    Flag = "username",
    Callback = function(text) print(text) end,  -- fires on every keystroke
    OnEnter  = function(text) print("entered:", text) end, -- fires on Enter
})
h:Get()           -- → string
h:Set("hello")
```

### Code (multi-line editor)

A monospace, fixed-height scrolling editor for raw config that doesn't fit a
structured control — Lua tables, JSON, scripts. Built for the "paste a blob"
workflow: it stays clean instead of forcing you to build a bespoke grid per
schema.

```lua
local h = Group:Code({
    Name = "Action Sequence", Desc = "Paste a Lua config table.",
    Default     = "return {\n  { type = \"place\", id = \"pyro1\" },\n}",
    Placeholder = "return { ... }",
    LineNumbers = true,    -- left line-number gutter (default false)
    Height      = 180,     -- editor height in px      (default 168)
    Flag        = "raw_config",
    Callback = function(text) end,        -- fires on every keystroke (raw text)
    -- Optional validator. Runs on blur inside a pcall. Return the parsed value
    -- on success; `error(msg)` (or returning nil) marks it invalid — the stroke
    -- turns red and `msg` is printed on a line beneath the editor.
    Parse = function(text)
        local fn = loadstring(text)
        if not fn then error("syntax error") end
        return fn()                       -- must return a (non-nil) value
    end,
    OnParse = function(ok, value, err) end, -- after each validate
})
h:Get()        -- → string (the raw editor text)
h:Set("return { ... }")
h:GetValue()   -- → the last successfully parsed value (nil if invalid / no Parse)
h:Validate()   -- → ok, value | errString  (force a re-parse now)
```

**Wrapping vs. line numbers.** By default the text wraps and scrolls vertically.
`LineNumbers = true` disables wrap (so each logical line is exactly one gutter
number) and scrolls horizontally instead.

**Flag behaviour.** The *raw text* is what's saved/loaded (like `Input`) — the
parsed value is derived on demand via `:GetValue()`. So config save/load
round-trips whatever the user typed, valid or not.

### Keybind

```lua
local h = Group:Keybind({
    Name = "Toggle Menu", Desc = "Click, then press a key.",
    Default = Enum.KeyCode.RightShift,
    Flag = "menu_key",
    Callback = function(key) print(key) end,  -- key is an Enum.KeyCode
})
h:Get()                       -- → Enum.KeyCode
h:Set(Enum.KeyCode.F)
```

Click the chip, then press any key to bind it.

### Dropdown (single select)

```lua
local h = Group:Dropdown({
    Name = "Quality", Desc = "Pick one.",
    Options = { "Low", "Medium", "High", "Ultra" },
    Default = "High",
    Placeholder = "Select...",  -- shown when nothing is picked (default "None")
    Stack = true,               -- control drops to its own full-width line
    Width = 130,                -- inline width when not stacked (default 130)
    Flag = "quality",
    Callback = function(choice) print(choice) end,
})
h:Get()                        -- → string (or nil)
h:Set("Ultra")
h:SetOptions({ "A", "B" })     -- replace the option list at runtime
```

### MultiDropdown (multi select)

```lua
local h = Group:MultiDropdown({
    Name = "Elements", Stack = true,
    Options = { "Fire", "Water", "Earth", "Air" },
    Default = { "Fire", "Water" },   -- a table
    Flag = "elements",
    Callback = function(list) print(table.concat(list, ", ")) end,
})
h:Get()                          -- → { string }
h:Set({ "Earth" })
h:SetOptions({ ... })
```

The menu stays open while you toggle items; each selected option gets a check.

### Colorpicker

```lua
local h = Group:Colorpicker({
    Name = "Accent", Desc = "Re-themes the UI.",
    Default = Color3.fromHex("f2680c"),
    Presets = { "ff5757", "3b82f6", ... },  -- optional hex grid (12 defaults)
    Flag = "accent",
    Callback = function(c) Window:SetAccent(c) end,  -- live re-theme
})
h:Get()                         -- → Color3
h:Set(Color3.fromHex("3b82f6"))
```

Opens a preset swatch grid with the current hex shown.

---

## Display-only components

These have no persistent value (no `Flag`, no `:Get`/`:Set` except where noted).

### Label (key / value row)

```lua
local h = Group:Label({ Key = "Status", Value = "Connected" })
h:Set("Disconnected")   -- update the value at runtime
```

### Paragraph

```lua
Group:Paragraph({
    Title = "Welcome",   -- optional
    Body  = "Some explanatory copy that wraps across lines.",
})
```

### Divider

```lua
Group:Divider()   -- a hairline separator
```

### List (bullet list)

```lua
Group:List({
    { Name = "Version", Value = "1.0.0" },  -- "Name:  Value"
    { Text = "Plain bullet line" },          -- free text
    { Text = "Dimmed line", Dim = true },    -- muted color
})
```

### Player (profile panel)

```lua
Group:Player({
    Username    = "guest",
    DisplayName = "Guest",
    UserId      = 0,
    Badge       = "Free",            -- optional pill (uppercased)
    Avatar      = "rbxassetid://...", -- optional image; falls back to an icon
})
```

---

## Config & flags

Any stateful control built with `Flag = "id"` is tracked. The window can
snapshot every flag to JSON and restore it later.

```lua
Group:Toggle({ Name = "Auto", Default = false, Flag = "auto" })
Group:Slider({ Name = "Speed", Min = 0, Max = 10, Flag = "speed" })

Window:SaveConfig("loadout")   -- writes <ConfigFolder>/configs/loadout.json
Window:LoadConfig("loadout")   -- restores + fires callbacks
Window:ListConfigs()           -- { "loadout", ... }
Window:DeleteConfig("loadout")
```

- Values are serialized per type: `Color3` → hex, `Enum.KeyCode` → name.
- Configs live at `<ConfigFolder>/configs/<name>.json`;
  `<ConfigFolder>/autoload.txt` holds the auto-load pointer.
- Persistence requires executor file functions (`writefile`/`readfile`/…). When
  unavailable (Studio, locked-down executors) the calls no-op and
  `Window.ConfigSupported` is `false`.

### Built-in Settings tab

```lua
Window:CreateSettingsTab({
    Name = "Settings",  -- tab label (default "Settings")
    Icon = "gear",      -- tab icon  (default "gear")
})
```

A drop-in panel that wires up: accent color picker, the toggle-UI keybind, a
notifications switch, and config **save / load / delete / refresh** plus an
**Auto Load** toggle and an **Unload** button.

> **Call it last.** Its auto-load pass runs deferred and only sees flags that
> were registered *before* it. Create all your other tabs and controls first.

---

## Icons

`Icon` fields take a Lucide icon **short-name** (e.g. `"home"`, `"layers"`,
`"gear"`, `"search"`, `"user"`). Unknown names degrade to a Unicode glyph rather
than erroring. The bundler tree-shakes icons: only names referenced in source
are kept. If you pass a raw Lucide name that isn't bundled, add it to
`EXTRA_ICONS` in `bundle.py` (when building from source).

---

## Theming

The accent color drives toggles, sliders, active tabs, buttons, the logo, and
more. Change it any time:

```lua
Window:SetAccent(Color3.fromHex("3b82f6"))
```

Every accent-aware element updates live. The Colorpicker in the built-in
Settings tab is wired to this out of the box.

---

## Teardown

```lua
Window:Destroy()   -- fades out, disconnects input listeners, destroys the GUI
```

The close (×) button only *hides* the window; `Destroy()` fully unloads it. The
built-in Settings tab's "Unload coreui" button calls `Destroy()`.
