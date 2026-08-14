# Uranium — documentation

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
local Uranium = loadstring(game:HttpGet(URL))()
```

If you want to guard the network/load step, wrap it in `pcall` — but mind the
return order: **`pcall` returns `(ok, result)`, so the library is the *second*
value, not the first.** Getting this backwards is the most common load bug (you
end up with `Uranium = true` and every `Uranium:Method(...)` call throws "attempt
to index boolean"):

```lua
local ok, Uranium = pcall(function()
    return loadstring(game:HttpGet(URL))()
end)
if not ok then
    warn("[Uranium] failed to load:", Uranium) -- on failure, `Uranium` holds the error
    return
end
-- Uranium is the library table here
```

> Tip: `raw.githubusercontent.com` CDN-caches each path for ~5 min and ignores
> `?` query busters on the *same* path. To always get a fresh build, load the
> **commit-pinned** URL (`…/<sha>/coreui.bundle.lua`) that `push.py` copies to
> your clipboard, not the `…/main/…` branch URL.

### As a ModuleScript (Studio / Rojo)

Drop the `coreui/` tree into your place and `require` its `init`:

```lua
local Uranium = require(path.to.coreui)
```

The bundle prints `[Uranium] build <timestamp> <sha>` on load so you can confirm
the build that's actually running.

---

## Quick start

```lua
local Window = Uranium:CreateWindow({
    Title    = "Uranium",
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
Window                         Uranium:CreateWindow{...}
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
local Window = Uranium:CreateWindow({
    Title        = "Uranium",                -- titlebar title           (default "Uranium")
    Subtitle     = "script hub",             -- status-bar left text     (default "")
    Version      = "v1.0.0",                 -- status-bar right text    (default "")
    ConfigFolder = "uranium",                -- on-disk config folder    (default "uranium")
    ToggleKey    = Enum.KeyCode.RightShift,  -- show/hide key            (default RightShift)
    Accent       = Color3.fromHex("7be04a"), -- initial accent color     (default theme accent)
    Logo         = 74808640463075,           -- titlebar mark            (default Uranium logo)
    LogoRadius   = 8,                        -- corner radius on the mark(default 8)
    LogoZoom     = 1,                        -- crop a margin baked into the art (default 1)
    AllowMultiple = false,                   -- skip the single-instance guard (default false)
    Hud          = true,                     -- floating bind HUD (default off; see below)
    Keybinds     = true,                     -- toggles carry a bind chip (default true)
    OnFlag       = function(name, kind) end, -- called as each Flag registers (see Config & flags)
})
```

`ConfigFolder` may be a nested path (`"uranium/games/12345"`) — every folder on
it is created — and `Window:SetConfigFolder(path)` re-scopes it later.

`Keybinds = false` takes the bind chip off every toggle window-wide (see
[Toggle](#toggle)). It's the default, not a ban: a control that asks for a
keybind explicitly still gets one.

The window is draggable by its titlebar, has minimize / maximize / close
buttons and a search field in the titlebar (filters the active tab as you type).
It's parented to `LocalPlayer.PlayerGui` (or `CoreGui` in Studio).

**Close fully unloads.** The ✕ button runs `Window:Destroy()` — listeners are
disconnected and the ScreenGui is destroyed, exactly like the Settings tab's
*Unload*. To hide the window temporarily use minimize (or the toggle key).

### Single instance

`CreateWindow` publishes a record on the shared executor env:

```lua
getgenv()._URANIUM_LOADED = { Name = "Uranium", Window = ..., ScreenGui = ..., Unload = fn }
```

Re-running the loadstring finds that record, unloads the old window (instantly,
no fade) and then builds the new one — so the loader **refreshes in place**
instead of stacking a second UI. The key is cleared on `Window:Destroy()`, and a
stale record can't wedge you: the guard also sweeps any leftover ScreenGui named
`Uranium`. Pass `AllowMultiple = true` to opt a window out of both halves (it
neither unloads the existing window nor claims the slot).

```lua
if Uranium:IsLoaded() then ... end   -- same as testing getgenv()._URANIUM_LOADED
Uranium:Unload()                     -- tear down the live window; true if there was one
```

### Window methods

| Method | Description |
| --- | --- |
| `Window:CreateTab(opts)` | Add a tab. Returns a **Tab**. See below. |
| `Window:CreateSettingsTab(opts?)` → `tab, controls` | Add the built-in settings panel. Call **last**. |
| `Window:Notify(opts)` | Show a toast notification (bottom-right). |
| `Window:Select(index)` | Switch to tab `index` (1-based). |
| `Window:SetAccent(color)` | Re-theme the whole UI to `color` (a `Color3`), live. |
| `Window:GetAccent()` → `Color3` | The live accent. |
| `Window:SetLogo(source, zoom?)` | Swap the titlebar mark (asset id, url, or file path). |
| `Window:SetToggleKey(key)` | Re-bind the show/hide key (`Enum.KeyCode`). |
| `Window:GetToggleKey()` → `Enum.KeyCode` | The current show/hide key. |
| `Window:SetNotificationsEnabled(bool)` | Enable/disable toasts globally. |
| `Window:GetNotificationsEnabled()` → `bool` | Whether toasts are on. |
| `Window:CreateHud(opts?)` | Build (or fetch) the floating bind HUD. See below. |
| `Window:GetHud()` | The HUD handle, or `nil` if there isn't one. |
| `Window:SetHudVisible(bool)` | Show/hide it, building it on first use. |
| `Window:OnHudVisible(fn)` → `unsub` | Mirror the HUD's visibility. Fires now + on every change. |
| `Window:GetConfig()` → `table` | Snapshot every flag — what `SaveConfig` serializes. |
| `Window:ApplyConfig(table)` → `applied, skipped` | Apply a flag table — what `LoadConfig` applies. |
| `Window:GetFlags()` → `{[name]=kind}` | Every registered flag and its codec kind. |
| `Window:RegisterFlag(name, handle, kind)` | Register your own non-control state as a flag. |
| `Window:OnFlag(fn)` → `unsub` | `fn(name, kind)` as each flag registers, synchronously. |
| `Window:SaveConfig(name, meta?)` → `bool, reason?` | Save all flagged values to `<name>.json`, optionally stamped with `meta`. |
| `Window:LoadConfig(name)` → `bool, reason?` | Load + apply a saved config. |
| `Window:DeleteConfig(name)` → `bool, reason?` | Delete a saved config. |
| `Window:ListConfigs()` → `{string}` | List saved config names. |
| `Window:ConfigInfo(name)` → `meta?, reason?` | Read a config's `meta` **without** applying it. |
| `Window:GetAutoload()` / `:SetAutoload(name?)` | Read / write the auto-load pointer (`nil` clears it). |
| `Window:GetConfigFolder()` / `:SetConfigFolder(path)` | Read / re-scope where configs live. |
| `Window:OnConfigFolder(fn)` → `unsub` | Fires now + whenever the folder is re-scoped. |
| `Window:Destroy(immediate?)` | Fade out and fully unload (disconnects listeners, frees the singleton slot). `immediate` skips the fade. |

`Window.ConfigSupported` (`boolean`) tells you whether the executor exposes file
functions. In Studio / unsupported executors, config calls no-op safely. It's a
plain field: set it to `false` yourself and the built-in Configuration group
stands down (useful when your hub owns persistence).

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

### Bind HUD

A small draggable panel that answers *"what's on right now?"* without opening the
menu — every bind you've named, its key and mode, lit while it's live, plus FPS
and ping.

```
┌────────────────────────────────┐
│ ▍ Active Binds               ⌃ │   drag anywhere · caret collapses it
├────────────────────────────────┤
│ ● Auto Parry         F · toggle│   ← lit: running right now
│ ○ Aim Assist         E · hold  │
│ ● ESP                X · always│
└────────────────────────────────┘
┌────────────────────────────────┐
│ 142 FPS   38 MS                │   ← its own bar: stays up when collapsed
└────────────────────────────────┘
```

The readout is a **separate card**, not a row in the list — it isn't a bind, and
keeping it outside the panel means collapsing the binds away (the caret) leaves
your frames and ping on screen. Both cards drag as one.

It's **off by default**. Turn it on with `Hud = true` at build time, from the
Settings tab's *Keybind HUD* switch, or in code:

```lua
Uranium:CreateWindow({ Hud = true })      -- defaults
Uranium:CreateWindow({ Hud = {            -- or tune it
    Title    = "Active Binds",  -- header text     (default "Active Binds")
    X        = 16,              -- offset from the left  (default 16)
    Y        = 140,             -- offset from the top   (default 140)
    MaxRows  = 10,              -- rows before "+N more" (default 10)
    Visible  = true,            -- start shown           (default true)
    Collapsed = false,          -- start collapsed to the header (default false)
    Stats    = true,            -- the FPS / ping bar    (default true)
    Fps      = true,            -- FPS readout           (default true)
    Ping     = true,            -- ping readout          (default true)
} })
```

**You don't register anything with it.** It reads the same keybind router the
controls use, so a bind appears the moment it has a key on it — as long as it
has a name to be listed under:

| Where the bind comes from | What the HUD calls it |
| --- | --- |
| `Group:Toggle{ Name = "Aim" }`, once the user binds a key to its chip | the toggle's `Name` |
| `Group:Keybind{ Name = "Sprint", Mode = "Hold" }` | the keybind's `Name` |
| `Window:Bind({ Key = ..., Mode = "Toggle", Label = "Fly" })` | its `Label` |

Three things stay out, so the panel is a short list of what you actually use
rather than an inventory of the whole menu:

- **anything with no key on it** — an unbound feature is a `— · toggle` row that
  tells you nothing, and since [every toggle carries a chip](#toggle) a hub full
  of them would bury the binds you set. The one exception is an **`Always`**
  bind that's on: it ignores its key by design and may well have none, and a
  feature pinned on has to be visible or the HUD is lying. (Being *on* is not
  itself enough — otherwise the panel becomes a list of every feature you have
  enabled.);
- a bind with **no name** (nothing to call it);
- a **key picker** — a `Keybind` with no `Mode`, which holds a key but never
  activates.

Pass `Hud = true` / `Hud = false` on any of the three sources above to override
all of it.

It lives beside the window rather than inside it, so **minimizing the window (or
hitting the toggle key) leaves the HUD up** — which is the point of having one.
Closing/unloading the window takes it with it.

```lua
local hud = Window:GetHud()          -- nil until something builds one
hud:SetVisible(true)  hud:Show()  hud:Hide()  hud:IsVisible()
hud:SetCollapsed(true)               -- collapse to just the header
hud:SetPosition(20, 200)  hud:GetPosition()   -- → Vector2
hud:SetTitle("Binds")
hud:SetStat("PLRS", 12)              -- add/update a pill next to FPS / MS
hud:SetStat("PLRS", nil)             -- and remove it
hud:Destroy()
```

The HUD is captured by config save/load under the flag `uranium_hud` (whether
it's up, whether it's collapsed, and where you dragged it), so a saved config
puts it back exactly where you left it.

---

## Tab

```lua
local Tab = Window:CreateTab({
    Name  = "Home",   -- flyout label            (default "Tab")
    Icon  = "home",   -- Lucide icon short-name  (default "gear")
    Desc  = nil,      -- second flyout line
    Badge = nil,      -- small chip in the flyout, in the tab's colour
})
```

The sidebar is icon-only, so the **hover flyout is the tab's label**: hovering
the button shows `Name`, then `Desc`, then a `Badge` chip. It's placed beside the
button, flips inside the window when there's no room, and wraps at 200px.

### Making one tab read differently from another

A hub usually has two classes of tab — mods that work anywhere, and mods for the
game you're in — and by default they look like the same stack of grey glyphs.
These options exist to separate them:

```lua
local Universal = Window:CreateTab({
    Name      = "Player Mods",
    Icon      = "person",
    Desc      = "Universal — works in any game.",
    Badge     = "Global",
    Color     = Color3.fromHex("4AA8E0"),  -- this tab's own accent
    Dot       = true,                      -- always-on marker in that colour
    Separator = true,                      -- hairline above it in the rail
    Pin       = "top",                     -- "top" (default) | "bottom"
})
```

| Option | Default | Description |
| --- | --- | --- |
| `Pin` | `"top"` | Which end of the sidebar it sits at. The bottom cluster grows upward from the bottom edge — where a settings / chrome tab belongs. |
| `Color` | window accent | A per-tab accent for the active tile, the rail, the dot and the flyout badge. It's ramped exactly like the window accent (mark / fill / tint). A tab with its own `Color` ignores `SetAccent`; without one it re-themes live. |
| `Style` | `"tile"` | How the active state draws. `"tile"` = tinted tile + coloured icon (the tuned default). `"solid"` = filled tile with the icon knocked out — loud, for the one tab that's a different *kind* of thing. `"plain"` = no tile, icon + rail only. |
| `Dot` | `nil` | `true` for a small marker in the tab's colour, or a `Color3` of its own. Visible while the tab is **not** selected — it's how you tell tabs apart without hovering or clicking. |
| `Rail` | `true` | `false` drops the 3×18px accent rail in the sidebar gutter. |
| `Separator` | `false` | A hairline above the button, breaking the rail into clusters. |
| `Order` | creation order | Sort position within its cluster. |
| `Visible` | `true` | `false` builds the tab but keeps it out of the sidebar — for a game-specific tab you only reveal once you know the game. |
| `Callback` | `nil` | `f(tab)` on every select. Use it to refresh whatever the tab shows. |

| Method | Description |
| --- | --- |
| `Tab:CreateGroup(opts)` | Add a card. Returns a **Group** control surface. |
| `Tab:Select()` | Open this tab. |
| `Tab:IsActive()` | Is it the open one? |
| `Tab:SetVisible(bool)` / `Tab:IsVisible()` | Show/hide the nav button. Hiding the open tab falls through to the next visible one. |
| `Tab:SetName(text)` · `SetDesc(text)` · `SetBadge(text)` | The flyout's three lines. |
| `Tab:SetIcon(name)` | Swap the icon (any Lucide short-name). |
| `Tab:SetColor(color3\|nil)` / `Tab:GetColor()` | Set/clear the per-tab accent. `nil` goes back to following the window accent. |
| `Tab:SetStyle(style)` · `SetDot(v)` · `SetRail(bool)` · `SetPin(pin)` | The rest of the above, at runtime. |

Everything is settable after the fact, so a hub can react to what it finds —
rename and reveal the game tab once it recognizes the place, dot the tab that has
features running, colour a tab red when its game isn't supported.

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

**Every toggle is bindable.** It carries a [bind chip](#keybind-on-a-toggle) in
its row with nothing bound and the mode set to `Toggle`, so the user picks a key
whenever they want one — the call site doesn't have to decide up front. An
unbound chip stays out of the [bind HUD](#bind-hud), so this costs nothing on
screen but the pill itself.

```lua
Group:Toggle({ Name = "Fly" })                  -- chip: `None │ toggle`
Group:Toggle({ Name = "Fly", Keybind = false }) -- no chip on this one
Uranium:CreateWindow({ Keybinds = false })      -- no chip on any toggle
```

Presetting a key with `Keybind = Enum.KeyCode.B` is still supported and still
means what it did — but it also puts the feature in the bind HUD from first
launch, as a bind the user never chose. Leave it unset unless the key is genuinely
part of the feature.

With a `Flag` set and no explicit `KeybindFlag`, the key + mode persist under
`<flag>_key` (see [Keybind on a Toggle](#keybind-on-a-toggle)).

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

Click the chip, then press the key you want bound. While it's listening
(`...`):

| Input | Result |
| --- | --- |
| any key | binds it |
| right / middle click **on the chip** | binds `MB2` / `MB3` |
| `Escape` | cancels — keeps the current bind |
| `Backspace` / `Delete` | clears the bind |
| a click anywhere **else** | abandons |

Left click isn't bindable from the UI — it's what you click the chip *with* — but
`h:Set(Enum.UserInputType.MouseButton1)` binds it if you really want it.

#### Modes

By default a Keybind is a pure key **picker**: nothing is bound, and `Callback`
just tells you the key changed. Pass a `Mode` and it becomes a real activation
bind — `Callback(active, info)` fires whenever the key drives the value, with
`info = { Key, Mode, KeyName }`:

| `Mode` | Behaviour |
| --- | --- |
| `"None"` *(default)* | no activation — just picks a key |
| `"Toggle"` | press flips the value |
| `"Hold"` | true only while the key is held |
| `"Press"` | one-shot command, carries no state |
| `"Always"` | pinned on; the key is ignored |

When a bind has more than one mode to choose from, the chip grows a second
half labelled with the current mode — **click it to cycle**
`toggle → hold → always`. Pass `Modes` to choose what it cycles through.

```lua
Group:Keybind({
    Name = "Speed Boost",
    Default = Enum.KeyCode.LeftAlt,
    Mode  = "Hold",                          -- chip reads `LAlt │ hold`
    Modes = { "Toggle", "Hold" },            -- what clicking the mode half offers
    Flag  = "speed_key",
    Callback  = function(active) print("boost:", active) end,
    OnChanged = function(key, mode) print("rebound:", key, mode) end,
})
```

A `Flag` on a bind persists the **key and the mode** together, so a saved config
restores "hold LAlt", not just the key.

#### Keybind on a Toggle

Every `Toggle` carries the same chip inline instead of being wired to a separate
Keybind control — by default with no key and `Toggle` mode. The toggle's value
stays the source of truth, so a click and a keypress can't disagree:

```lua
Group:Toggle({
    Name = "Fly", Flag = "fly",
    Keybind      = Enum.KeyCode.B,   -- preset a key (or `false` — no chip at all)
    KeybindMode  = "Hold",           -- Toggle | Hold | Always  (default Toggle)
    KeybindModes = { "Toggle", "Hold", "Always" },
    KeybindFlag  = "fly_key",        -- persists the key + mode separately
    Callback = function(on) print(on) end,
})
```

| Option | Effect |
| --- | --- |
| *(nothing)* | an empty chip in `Toggle` mode — the default |
| `Keybind = <key>` | presets the key (and puts it in the HUD from launch) |
| `Keybind = false` | no chip on this control |
| `CreateWindow{ Keybinds = false }` | no chip on any toggle; an explicit `Keybind` / `KeybindMode` / `KeybindModes` overrides it back on |

**The key persists with the toggle.** With a `Flag` and no `KeybindFlag`, the
chip registers itself under `<flag>_key` — `Flag = "fly"` → `fly_key` — which is
the convention hubs were already writing by hand, so derived names match the
configs people have already saved. An explicit `KeybindFlag` still wins.

`handle.Bind` exposes the chip's handle (`:Get()` / `:Set(key)` / `:GetMode()` /
`:SetMode(m)`), or is `nil` on a toggle that opted out.

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
    Default = Color3.fromHex("7be04a"),
    Presets = { "96ec69", "3b82f6", ... },  -- optional hex grid (12 defaults)
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
- Every one of these returns `(result, reason)` — `reason` is a short phrase
  (`"no such config"`, `"corrupt JSON"`, `"no file access"`, `"applied nothing"`,
  `"invalid name"`) meant to be pasted into a message.

### Owning persistence yourself

`SaveConfig`/`LoadConfig` are the flag registry plus a file. If you want the
registry *without* the file — your own layout on disk, remote or shared configs,
in-memory profiles, a "reset to defaults" button — take the two primitives:

```lua
local snapshot = Window:GetConfig()      -- exactly what SaveConfig serializes
Window:ApplyConfig(snapshot)             -- exactly what LoadConfig applies
```

`ApplyConfig` returns `applied, skipped`. **Keys with no registered flag are
skipped, on purpose** — that's a promised part of the format, so a config can
carry data that isn't a control value, and a file written by a build with more
controls than yours still applies the flags you do have.

`Uranium.Config` is the file layer itself (`util/Config.lua`), if you want to
read another folder's configs or check a name:

```lua
Uranium.Config.sanitize(name) == name    -- will this name round-trip? (see below)
Uranium.Config.list(folder)              -- another folder's config names
Uranium.Config.info(folder, name)        -- its metadata, without applying it
Uranium.Config.MetaKey                   -- "__uranium" — where that metadata lives
```

> **Config names are filtered.** A name is stripped to `[A-Za-z0-9-_ ]` and
> trimmed before it becomes a filename, and the saved-config list matches names
> by string equality afterwards. So any name you display has to survive the strip
> **unchanged** — no parentheses, `@`, `·`, emoji. `Config.sanitize(n) == n` is
> the check.

### Metadata (provenance)

```lua
Window:SaveConfig("main", { place = game.PlaceId, game = "Blox Fruits", v = 2 })

local meta = Window:ConfigInfo("main")   -- reads it WITHOUT applying anything
if meta and meta.place ~= game.PlaceId then
    Window:Notify({ Title = "Config", Text = "That config is from another game." })
end
```

`meta` is stored under `Config.MetaKey` (`"__uranium"`) alongside the flags and
skipped on load like any unregistered key. `ConfigInfo` is the read a "which game
does this belong to?" check actually wants — no decoding the whole file to look
at four fields.

### Flag introspection & the registration hook

```lua
local before = Window:GetFlags()          -- { username = "input", volume = "slider", ... }
buildGameSpecificTab(Window)
local after  = Window:GetFlags()          -- the difference is that module's flags
```

For the same thing without the diff, watch registration as it happens.
`fn(name, kind)` fires **synchronously** from inside the registration, so it can
attribute each flag to whatever your loader is building at that instant:

```lua
local phase = "core"
local Window = Uranium:CreateWindow({
    Title  = "Uranium",
    OnFlag = function(name, kind) origin[name] = phase end,
})
-- ...later, per-place:
phase = "game:" .. game.PlaceId
```

`Window:OnFlag(fn)` installs the same hook later and returns an unsubscribe; the
`OnFlag` window option is just the one that's early enough to catch every flag
the menu ever registers, including the Settings tab's own.

`Window:RegisterFlag(name, handle, kind)` puts your own non-control state in the
same config file. `handle` needs `:Get()`/`:Set(v)` — or `:GetFlag()`/`:SetFlag(v)`
when the persisted value isn't the primary one — and `kind` names the codec
(`"toggle"`, `"slider"`, `"input"`, `"dropdown"`, `"colorpicker"`, `"bind"`,
`"playerselect"`, `"code"`, `"hud"`).

### Per-place / per-profile configs

`ConfigFolder` is free-form and **nested paths are created recursively**, so
scoping is a folder:

```lua
Window:SetConfigFolder("uranium/games/" .. game.PlaceId)
```

Anything showing a config list is notified through `Window:OnConfigFolder(fn)`
(the built-in Settings tab refreshes its dropdown from it), so re-scoping at
runtime — a profile switch, a place you only recognize after boot — is safe.

### Built-in Settings tab

```lua
local tab, controls = Window:CreateSettingsTab({
    Name = "Settings",  -- tab label (default "Settings")
    Icon = "gear",      -- tab icon  (default "gear")
    Pin  = "bottom",    -- every CreateTab option is forwarded (see Tab)

    Sections = { Interface = true, Config = false, Danger = true },  -- drop sections
    Notify   = false,   -- silence the panel's own config toasts
    Config   = { AutoLoad = false },  -- per-section options (Title, Column, Group, …)
})
```

A drop-in panel that wires up: accent color picker, the toggle-UI keybind, a
notifications switch, a **Keybind HUD** switch (see [Bind HUD](#bind-hud)), and
config **save / load / delete / refresh** plus an **Auto Load** toggle and an
**Unload** button.

The second return is every handle the panel built, also on `tab.Controls`:

| Key | What |
| --- | --- |
| `Accent` `ToggleKey` `Notifications` `Hud` | The Interface controls. |
| `Name` `List` `AutoLoad` | The config name box, the saved-config dropdown, the auto-load switch. |
| `Refresh` `Save` `Load` `Delete` | The button callbacks, so you can drive them yourself. |
| `Interface` `Configuration` `Danger` | The groups, to add your own controls to. |
| `Unload` | The unload button. |

```lua
local _, c = Window:CreateSettingsTab({ Pin = "bottom" })
Window:SaveConfig("main", { place = game.PlaceId })
c.Refresh()                    -- pick up a config you wrote yourself
print(c.List:Get())            -- what's selected
c.Configuration:Button({ Label = "Import into this game", Callback = ... })
```

If you wrap the window's config methods to add your own rules, return
`false, "handled"` from the wrapper when you've already told the user why —
the panel skips its own toast for that call. `Notify = false` silences it
entirely.

Each group is also public, so you can compose your own settings tab instead:

```lua
local tab = Window:CreateTab({ Name = "Settings", Icon = "gear" })
Uranium.Settings.InterfaceGroup(Window, tab)          -- accent / key / toasts / HUD
myOwnConfigGroup(Window, tab)                         -- ...and your own persistence UI
Uranium.Settings.DangerGroup(Window, tab)
```

`InterfaceGroup` / `ConfigGroup` / `DangerGroup` all take `(window, tab, opts?)`,
where `opts` may carry `Title`, `Column`, or `Group` (an existing group to build
into instead of creating one). They're written against the public window API
only — nothing in them reaches past what your own code can call.

> **Call it last.** Its auto-load pass runs deferred and only sees flags that
> were registered *before* it. Create all your other tabs and controls first.
> (`Config = { AutoLoad = false }` turns that pass off if you'd rather decide
> what to apply on boot yourself.)

---

## Icons

`Icon` fields take a Lucide icon **short-name** (e.g. `"home"`, `"layers"`,
`"gear"`, `"search"`, `"user"`) **or any raw [Lucide](https://lucide.dev/icons/)
name** — `"globe"`, `"zap"`, `"gamepad-2"`, `"shield-check"`. The full 1573-icon
Lucide set ships in the bundle, so nothing needs registering ahead of time.
A name that still doesn't match (typo, or an icon added to Lucide after this
build) degrades to a `•` glyph rather than erroring.

---

## Images & assets

Roblox's `Image` property only accepts content URLs, which is why every image
field in Uranium (the `Image` control, `Player.Avatar`, a MediaPlayer track's
`Cover`, the window `Logo`) runs its value through `Uranium.Asset.resolve`
first. That means all of these work, interchangeably:

| You pass | What happens |
| --- | --- |
| `74808640463075` | bare id → `rbxassetid://74808640463075` |
| `"rbxassetid://…"`, `"rbxthumb://…"` | used as-is |
| `"https://roblox.com/library/123/x"` | id pulled out of the link |
| `"myhub/logo.png"` | local file → `getcustomasset` (executor only) |
| `"https://example.com/logo.png"` | downloaded once, cached on disk, then loaded |

### Fallback chains (the reliable way to ship art)

Any image field also takes an **array** of sources, tried in order until one
actually loads:

```lua
Group:Image({ Image = {
    Uranium.Asset.url("uranium-orbitals-512-square.png"), -- preferred: hosted PNG
    "rbxassetid://74808640463075",                      -- fallback: uploaded asset id
} })
```

`Asset.url(name)` resolves a bare filename against `Asset.Base` — the public
[art repo](https://github.com/funjimmywantstodie/Krypton) (still named `Krypton`
— the raw asset URLs are pinned to that path), which is separate from the UI
library's own repo. Commit a file to its `Assets/` folder
and it's referenceable by name; pass an absolute URL and it's returned as-is.
Point `Uranium.Asset.Base` somewhere else to host art yourself.

Put the **URL first**. It's downloaded once, cached on disk, and handed to the
engine through `getcustomasset` — so it never touches Roblox's asset pipeline:
no moderation wait, no Asset Privacy restriction, no decal-vs-image id
confusion. The asset id behind it covers executors with no file access. This is
how Infinite Yield ships its icons, and it's what `Theme.Brand.logo` uses.

Downloads are validated by magic bytes before they're cached, so a 404 page
can't poison the cache as a `.png`.

```lua
local Asset = Uranium.Asset

Asset.resolve(74808640463075)                  -- → "rbxassetid://74808640463075"
Asset.fromFile("myhub/logo.png")               -- → content id, or nil
Asset.fromUrl("https://example.com/art.png")   -- downloads + caches, → content id
Asset.headshot(userId, 150)                    -- → rbxthumb avatar url
Asset.preload({ id1, url2, "art/x.png" })      -- warm them off-thread

Asset.CacheFolder = "myhub/images"  -- where downloads land (default "uranium/images")
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

Uranium ships the **Uranium Glass** palette: a `#7BE04A` accent on a
near-neutral ramp that only whispers green (`#0B0F0A` chrome, `#10150E` body,
`#171D15` cards, `#1D241B` controls, `#2B3427` lines), with `#08140A` knocked
out of anything sitting on a solid accent fill. Flat fills only — no gradients
or glows, and at most one accent element per row.

The accent is applied at three weights depending on how much area it covers: the
accent itself for small marks (slider fill, toggle track, icons, focus strokes),
a deeper shade for large solid fills like primary buttons — which hover *up* to
the full accent — and a ~13% tint of it laid into the surface for tiles that
should read as accent-coloured without putting neon on screen (the active nav
button, avatar placeholders, badges). All three move together when you change the
accent, so there's nothing extra to set.

The accent color drives toggles, sliders, active tabs, buttons, and more. Change
it any time:

```lua
Window:SetAccent(Color3.fromHex("3b82f6"))
```

Every accent-aware element updates live. The Colorpicker in the built-in
Settings tab is wired to this out of the box. The full token table is
`Uranium.Theme.Colors`, and the brand mark lives in `Uranium.Theme.Brand`.

---

## Teardown

```lua
Window:Destroy()   -- fades out, disconnects input listeners, destroys the GUI
```

The close (×) button only *hides* the window; `Destroy()` fully unloads it. The
built-in Settings tab's "Unload Uranium" button calls `Destroy()`.
