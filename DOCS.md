# Krypton — documentation

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
local Krypton = loadstring(game:HttpGet(URL))()
```

If you want to guard the network/load step, wrap it in `pcall` — but mind the
return order: **`pcall` returns `(ok, result)`, so the library is the *second*
value, not the first.** Getting this backwards is the most common load bug (you
end up with `Krypton = true` and every `Krypton:Method(...)` call throws "attempt
to index boolean"):

```lua
local ok, Krypton = pcall(function()
    return loadstring(game:HttpGet(URL))()
end)
if not ok then
    warn("[Krypton] failed to load:", Krypton) -- on failure, `Krypton` holds the error
    return
end
-- Krypton is the library table here
```

> Tip: `raw.githubusercontent.com` CDN-caches each path for ~5 min and ignores
> `?` query busters on the *same* path. To always get a fresh build, load the
> **commit-pinned** URL (`…/<sha>/coreui.bundle.lua`) that `push.py` copies to
> your clipboard, not the `…/main/…` branch URL.

### As a ModuleScript (Studio / Rojo)

Drop the `coreui/` tree into your place and `require` its `init`:

```lua
local Krypton = require(path.to.coreui)
```

The bundle prints `[Krypton] build <timestamp> <sha>` on load so you can confirm
the build that's actually running.

---

## Quick start

```lua
local Window = Krypton:CreateWindow({
    Title    = "Krypton",
    Subtitle = "script hub",
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
Window                         Krypton:CreateWindow{...}
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
local Window = Krypton:CreateWindow({
    Title        = "Krypton",                -- titlebar title           (default "Krypton")
    Subtitle     = "script hub",             -- status-bar left text     (default "")
    Version      = "v1.0.0",                 -- status-bar right text    (default "")
    ConfigFolder = "krypton",                -- on-disk config folder    (default "krypton")
    ToggleKey    = Enum.KeyCode.RightShift,  -- show/hide key            (default RightShift)
    Accent       = Color3.fromHex("00c46a"), -- initial accent color     (default theme accent)
    Logo         = 74808640463075,           -- titlebar mark            (default Krypton logo)
    LogoRadius   = 8,                        -- corner radius on the mark(default 8)
    AllowMultiple = false,                   -- skip the single-instance guard (default false)
})
```

The window is draggable by its titlebar, has minimize / maximize / close
buttons and a search field in the titlebar (filters the active tab as you type).
It's parented to `LocalPlayer.PlayerGui` (or `CoreGui` in Studio).

**Close fully unloads.** The ✕ button runs `Window:Destroy()` — listeners are
disconnected and the ScreenGui is destroyed, exactly like the Settings tab's
*Unload*. To hide the window temporarily use minimize (or the toggle key).

### Single instance

`CreateWindow` publishes a record on the shared executor env:

```lua
getgenv()._KRYPTON_LOADED = { Name = "Krypton", Window = ..., ScreenGui = ..., Unload = fn }
```

Re-running the loadstring finds that record, unloads the old window (instantly,
no fade) and then builds the new one — so the loader **refreshes in place**
instead of stacking a second UI. The key is cleared on `Window:Destroy()`, and a
stale record can't wedge you: the guard also sweeps any leftover ScreenGui named
`Krypton`. Pass `AllowMultiple = true` to opt a window out of both halves (it
neither unloads the existing window nor claims the slot).

```lua
if Krypton:IsLoaded() then ... end   -- same as testing getgenv()._KRYPTON_LOADED
Krypton:Unload()                     -- tear down the live window; true if there was one
```

### Window methods

| Method | Description |
| --- | --- |
| `Window:CreateTab(opts)` | Add a tab. Returns a **Tab**. See below. |
| `Window:CreateSettingsTab(opts?)` | Add the built-in settings panel. Call **last**. |
| `Window:Notify(opts)` | Show a toast notification (bottom-right). |
| `Window:Select(index)` | Switch to tab `index` (1-based). |
| `Window:SetAccent(color)` | Re-theme the whole UI to `color` (a `Color3`), live. |
| `Window:SetLogo(source)` | Swap the titlebar mark (asset id, url, or file path). |
| `Window:SetToggleKey(key)` | Re-bind the show/hide key (`Enum.KeyCode`). |
| `Window:SetNotificationsEnabled(bool)` | Enable/disable toasts globally. |
| `Window:SaveConfig(name)` → `bool` | Save all flagged values to `<name>.json`. |
| `Window:LoadConfig(name)` → `bool` | Load + apply a saved config. |
| `Window:DeleteConfig(name)` → `bool` | Delete a saved config. |
| `Window:ListConfigs()` → `{string}` | List saved config names. |
| `Window:Destroy(immediate?)` | Fade out and fully unload (disconnects listeners, frees the singleton slot). `immediate` skips the fade. |

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
(success = accent check, info = neutral, warning = amber triangle, error = red).
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

**Input filtering.** `Type` restricts what can be typed — disallowed characters
are stripped live as you type (and on `:Set`), so the box only ever holds a valid
value:

| `Type`           | Accepts                                                        |
| ---------------- | ------------------------------------------------------------- |
| `"number"`       | digits, one leading `-`, one `.` (always `tonumber`-parseable) |
| `"integer"`      | digits + a leading `-`                                          |
| `"alpha"`        | letters only                                                   |
| `"alphanumeric"` | letters and digits                                             |
| *(omitted)*      | unrestricted text (default)                                    |

For a custom rule, pass `Filter = function(text) return cleaned end` — it receives
the raw text and returns the sanitized value. `Filter` wins over `Type`.

```lua
Group:Input({ Name = "Max Amount", Placeholder = "0", Type = "number" })
Group:Input({                       -- up to 6 hex characters
    Name = "Hex", Placeholder = "RRGGBB",
    Filter = function(s) return (s:sub(1, 6):gsub("[^%x]", "")) end,
})
```

`Callback` still fires exactly once per edit, with the already-cleaned value. The
value stored by a `Flag` is the raw (filtered) text.
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
    Default = Color3.fromHex("00c46a"),
    Presets = { "1fe087", "3b82f6", ... },  -- optional hex grid (12 defaults)
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

### Image

Drops a picture into a card. `Image` takes **anything** — see
[Images & assets](#images--assets) for the full list of accepted sources.

```lua
local h = Group:Image({
    Name    = "Banner",        -- optional label above the picture
    Desc    = "Hub artwork.",  -- optional sub-text
    Image   = 74808640463075,  -- id / rbxassetid / https url / local file
    Height  = 160,             -- px (default 140)
    Width   = nil,             -- px; omit for full width
    Fit     = "cover",         -- "cover" | "contain" | "stretch" | "tile"
    Corner  = 7,               -- corner radius (default controlRadius)
    Caption = "512×512",       -- optional muted caption underneath
    Callback = function(source) end,  -- optional; makes the picture clickable
})
h:Set("https://example.com/other.png")  -- swap the source at runtime
h:Get()                                 -- → the source you last set
h:SetCaption("new caption")
```

While the source is empty (or still downloading) the frame shows a placeholder
icon, so a slow or broken image never leaves a hole in the layout.

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

## Images & assets

Roblox's `Image` property only accepts content URLs, which is why every image
field in Krypton (the `Image` control, `Player.Avatar`, a MediaPlayer track's
`Cover`, the window `Logo`) runs its value through `Krypton.Asset.resolve`
first. That means all of these work, interchangeably:

| You pass | What happens |
| --- | --- |
| `74808640463075` | bare id → `rbxassetid://74808640463075` |
| `"rbxassetid://…"`, `"rbxthumb://…"` | used as-is |
| `"https://roblox.com/library/123/x"` | id pulled out of the link |
| `"myhub/logo.png"` | local file → `getcustomasset` (executor only) |
| `"https://example.com/logo.png"` | downloaded once, cached on disk, then loaded |

```lua
local Asset = Krypton.Asset

Asset.resolve(74808640463075)                  -- → "rbxassetid://74808640463075"
Asset.fromFile("myhub/logo.png")               -- → content id, or nil
Asset.fromUrl("https://example.com/art.png")   -- downloads + caches, → content id
Asset.headshot(userId, 150)                    -- → rbxthumb avatar url
Asset.preload({ id1, url2, "art/x.png" })      -- warm them off-thread

Asset.CacheFolder = "myhub/images"  -- where downloads land (default "krypton/images")
Asset.supported                     -- can we load local files? (getcustomasset)
Asset.canDownload                   -- can we fetch + cache remote images?
```

Downloading needs executor globals (`getcustomasset`, `writefile`). Where they're
missing (Studio, locked-down executors) every call degrades to `""`/`nil` instead
of erroring, and the component shows its placeholder. Asset ids always work.

**Uploading your own art:** save the PNG to Roblox (creator dashboard → Decals),
paste the id straight into `Image = <id>`. No `rbxassetid://` prefix needed.

---

## Theming

Krypton ships the **Deep Emerald** palette: `#00C46A` accent on a
greyscale-green ramp (`#0A100C` background, `#142019` surfaces, `#1A2B20`
lines), with `#04150C` knocked out of anything sitting on an accent fill. Flat
fills only — no gradients, glows, or accent washes behind large areas, and at
most one accent element per row.

The accent color drives toggles, sliders, active tabs, buttons, and more. Change
it any time:

```lua
Window:SetAccent(Color3.fromHex("3b82f6"))
```

Every accent-aware element updates live. The Colorpicker in the built-in
Settings tab is wired to this out of the box. The full token table is
`Krypton.Theme.Colors`, and the brand mark lives in `Krypton.Theme.Brand`.

---

## Teardown

```lua
Window:Destroy()   -- fades out, disconnects input listeners, destroys the GUI
```

The close (×) button only *hides* the window; `Destroy()` fully unloads it. The
built-in Settings tab's "Unload Krypton" button calls `Destroy()`.
