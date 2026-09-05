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

### Console output (off by default)

The library prints **nothing** on a normal load. Everything chatty — the build
banner, the detected file-API capabilities, `SaveConfig`/`LoadConfig` results,
the settings-tab lines — is gated, because a game reading `LogService` gets a
free fingerprint out of every branded line the client prints. Real problems
(`Log.warn` / `Log.fail`) still surface.

```lua
local Window = Uranium:CreateWindow({ Verbose = true })  -- per window
Uranium.setVerbose(true)                                 -- library-wide, any time
Uranium.setLogPrefix("[hub]")                            -- one place; every line follows
```

A few lines happen at *require* time, before `CreateWindow` can be reached. To
catch those too, set the flag before the loadstring runs:

```lua
getgenv().URANIUM_VERBOSE = true
local Uranium = loadstring(game:HttpGet(URL))()
```

With output on, the bundle stamps `[Uranium] build <timestamp> <sha>` so you can
confirm the build that's actually running (also `Uranium.Build`).

### Passing a service cache

The bundle takes one optional argument: a table of pre-resolved services. A host
that already built its own (`cloneref`'d) cache passes it in and the library uses
those same references instead of making a second set:

```lua
local Uranium = loadstring(game:HttpGet(URL))(MyHub.Services)
```

Standalone works exactly as before — with no argument the library builds its own
cache, `cloneref`-wrapped where the executor provides it, so its service handles
are never the ones the place gets from its own `game:GetService`. It's reachable
as `Uranium.Services`.

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

Screen                         Uranium:Screen{...}       -- needs no window
```

Controls are added to a **Group** (or a **Section** inside a group). A Group is a
titled card; Sections are indented, collapsible sub-blocks. Both expose the same
control methods.

[`Screen`](#screen-status-page) is the exception to all of that: a
full-screen page for something that has to be read, built without a window and
usable when there will never be one.

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
    Descriptions = "hover",                  -- where control `Desc` is drawn (default "hover")
    MinimizeHint = true,                     -- click-to-reopen card (default true)
    MinimizeHintStyle = "auto",              -- "auto" / "card" / "logo" (default "auto")
    Touch        = nil,                      -- pin the phone layout on/off (default: per device, see below)
    OnFlag       = function(name, kind) end, -- called as each Flag registers (see Config & flags)
    OnFlagChanged = function(name, value, kind, source) end, -- ...and as each one changes
    PersistWindow = true,                    -- persist position/size/tab/folded groups (default true)
    WindowFlag   = "uranium_window",         -- rename that flag        (default "uranium_window")
    Parent       = someContainer,            -- where the ScreenGui goes (default: resolved, see below)
    GuiName      = "…",                      -- pin the ScreenGui's name (default: random per load)
    Verbose      = false,                    -- console output          (default false)
})
```

`ConfigFolder` may be a nested path (`"uranium/games/12345"`) — every folder on
it is created — and `Window:SetConfigFolder(path)` re-scopes it later.

`Keybinds = false` takes the bind chip off every toggle window-wide (see
[Toggle](#toggle)). It's the default, not a ban: a control that asks for a
keybind explicitly still gets one.

`Descriptions` picks where every control's `Desc` is drawn — `"hover"` (behind an
info glyph), `"inline"` (a second line of prose under the name) or `"both"`. See
[Descriptions](#descriptions-desc--info).

The window is draggable by its titlebar, has minimize / maximize / close
buttons and a search field in the titlebar (filters the active tab as you type).

### On a phone

Most of Uranium's users are on a phone, so the window has a second layout it
picks **per device**: a touch screen **and no keyboard** (a touchscreen laptop
has both and gets the desktop layout). It's re-resolved on every decision rather
than cached at build, because an executor can run before the input devices have
reported themselves — and if the answer moves later, everything re-lays out.

What changes, nothing of which is visible on a desktop:

| | Desktop | Phone |
| --- | --- | --- |
| Window | windowed, 24px of air around it | opens **maximized**, 8px of air. A saved `uranium_window` record still wins. |
| Chrome | 50px titlebar, 34px status bar | 40px titlebar, **no status bar** — a clock and a version string aren't worth 34px of a 280px body |
| Sidebar | icons only; the tab's name is its hover flyout | the **name is drawn under each icon**; the flyout shows on press and carries only `Desc` and the badge |
| Sidebar overflow | never measured | the two clusters never overlap: padding and gap tighten first, then the tiles shrink (40 → 32px), then the top cluster **scrolls** above the bottom one |
| Columns | two, always | **one** below ~600px of content width — column 2 stacks under column 1 in build order |
| Targets | design sizes | ≥ 40px: the window buttons, dropdown rows, group / section fold rows, the slider's grab area |
| Sliders | value in the box | also in a **bubble over the knob** while dragged, and a horizontal drag doesn't scroll the page |
| Keyboard | — | the window **slides up** to keep a focused box above the on-screen keyboard and back on focus lost |
| Toasts | bottom-right | **top-right**, and a tap dismisses one (that works on a desktop too) |
| Bind chips | key + mode | the **key half is a pin** (nothing can ever fill it with a key): tap to pin the feature to the HUD; a key picker's key half is inert |
| Bind HUD | keys, rows clickable | the chip says the **state** and the rows are the buttons — see [Bind HUD](#bind-hud) |
| Minimized | the card | the logo tile; **long-press** it to toggle the HUD without opening the window |
| Settings | full | no **Toggle UI** key row |

```lua
Uranium:CreateWindow({ Touch = true })   -- force the phone layout (Studio's emulator reports a keyboard)
Window:IsTouch()                          -- → boolean, the answer right now
Window:SetTouch(nil)                      -- back to asking the engine; true / false pins it, live
Window:OnTouch(function(isTouch) end)     -- → unsub; fires when the answer changes
```

### Where the ScreenGui goes

`PlayerGui` is the one container any LocalScript in the place can walk, so it's
the *last* resort, not the default. The parent is resolved in this order, and the
instance is parented **once**, at whichever wins:

1. `Parent` — an Instance you pass to `CreateWindow`. A host that already
   resolved a container gets to keep using it.
2. `gethui()` — the executor's hidden container.
3. `CoreGui`.
4. `LocalPlayer.PlayerGui` — Studio, and executors with neither global.

`protect_gui` / `syn.protect_gui` runs first where the global exists, since some
executors want to do the reparent themselves.

The ScreenGui gets a **neutral, random name each load** (`GuiName = "..."` pins
one) rather than a fixed brand-shaped string, and identity is an attribute
(`__urn`) instead — the single-instance sweep matches on that, so nothing depends
on the name. The window frame and the HUD are direct children of it, so they're
named the same way.

`Window.ScreenGui` is the instance itself, so a host can check where it landed,
re-parent it, or re-protect it. `Uranium.Gui` exposes the same resolution helpers
(`Gui.mount`, `Gui.roots`, `Gui.rname`, `Gui.Attribute`).

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
stale record can't wedge you: the guard also sweeps leftover ScreenGuis of ours
out of `gethui()`, `CoreGui` **and** `PlayerGui` — matched by the `__urn`
attribute (plus the old brand names, for builds that predate it), since the name
itself is random per load. Pass `AllowMultiple = true` to opt a window out of
both halves (it neither unloads the existing window nor claims the slot).

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
| `Window:SetMinimizeHint(bool)` | Show/hide the minimized card — the branded chip that reopens the window when clicked or tapped. The full card rests bottom right, the logo tile top centre, and either can be dragged anywhere on screen. Applied live. |
| `Window:GetMinimizeHint()` → `bool` | Whether the card is on. |
| `Window:SetMinimizeHintStyle(style)` → `string` | How that card is drawn: `"card"` (mark + "<Title> Minimized" + the reopen line), `"logo"` (the mark on its own), or `"auto"` — a logo on a touch device with no keyboard, a card everywhere else, resolved per device. Applied live; returns the style in force afterwards, and an unrecognized one warns and changes nothing. |
| `Window:GetMinimizeHintStyle()` → `string` | The style that was set — `"auto"`, not what auto resolved to. |
| `Window:SetNotificationsEnabled(bool)` | Enable/disable toasts globally. |
| `Window:GetNotificationsEnabled()` → `bool` | Whether toasts are on. |
| `Window:SetDescriptions(mode)` → `string` | `"hover"` / `"inline"` / `"both"`, applied live to the fields already on screen. Returns the mode in force afterwards. |
| `Window:GetDescriptions()` → `string` | The current description mode. |
| `Window:CreateHud(opts?)` | Build (or fetch) the floating bind HUD. See below. |
| `Window:GetHud()` | The HUD handle, or `nil` if there isn't one. |
| `Window:SetHudVisible(bool)` | Show/hide it, building it on first use. |
| `Window:OnHudVisible(fn)` → `unsub` | Mirror the HUD's visibility. Fires now + on every change. |
| `Window:OnHudChanged(fn)` → `unsub` | Fires whenever anything the HUD *persists* moves (dragged, folded, shown). No argument, no initial call. |
| `Window:GetPosition()` / `:SetPosition(x, y)` | The window's top-left in screen pixels. Setting clamps on-screen. |
| `Window:GetSize()` / `:SetSize(w, h)` | Its layout size. Setting is still clamped to the viewport. |
| `Window:IsMaximized()` / `:SetMaximized(bool, animate?)` | The maximize state. |
| `Window:GetSelected()` → `number` | Which tab is open (1-based). |
| `Window:IsTouch()` → `bool` | Is the phone layout in force — a touch screen and no keyboard, read now. See [On a phone](#on-a-phone). |
| `Window:SetTouch(bool?)` | Pin the phone layout on / off, or `nil` to ask the engine again. Applied live. |
| `Window:OnTouch(fn)` → `unsub` | `fn(isTouch)` whenever that answer changes. No initial call. |
| `Window:GetConfig()` → `table` | Snapshot every flag — what `SaveConfig` serializes. |
| `Window:ApplyConfig(table, opts?)` → `applied, skipped` | Apply a flag table — what `LoadConfig` applies. `opts.Filter(name, kind)` applies only part of it. |
| `Window:GetFlags()` → `{[name]=kind}` | Every registered flag and its codec kind. |
| `Window:RegisterFlag(name, handle, kind)` | Register your own non-control state as a flag. |
| `Window:OnFlag(fn)` → `unsub` | `fn(name, kind)` as each flag registers, synchronously. |
| `Window:OnFlagChanged(fn)` → `unsub` | `fn(name, value, kind, source)` as each flag's **value** changes. |
| `Window:NotifyFlag(name, source?)` | Announce that a flag you registered yourself has moved. |
| `Window:SaveConfig(name, meta?)` → `bool, reason?` | Save all flagged values to `<name>.json`, optionally stamped with `meta`. |
| `Window:LoadConfig(name, opts?)` → `bool, reason?` | Load + apply a saved config. `opts.Filter(name, kind)` applies only part of it. |
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

A click or tap on a toast dismisses it early. The stack sits bottom-right on a
desktop and **top-right on a phone**, where the bottom-right corner is the jump
button (see [On a phone](#on-a-phone)).

A toast is for something the user may miss. For something they must not — the
hub failing to load, a ban — use [`Uranium:Screen`](#screen-status-page),
which needs no window at all.

### Bind HUD

A small draggable panel that answers *"what's on right now?"* without opening the
menu. It is exactly two things:

> **everything you asked for by name** — a **key** on a desktop, a **pin** on a
> phone — **plus every top-level feature that's running.**

Each row is a name and one chip. On a desktop the chip is the **key** (with the
mode after it when the mode changes what the key does); on a phone, where nothing
can press a key, it's the **state**. Either way it lights in the accent while the
bind is live, exactly like the chip on the control it came from — and tapping
the row does what the mode says, on both devices.

```
┌────────────────────────────────┐
│ ▍ Keybinds                   ⌃ │   drag it · caret collapses it
├────────────────────────────────┤
│ Auto Parry              [ F ]  │   ← lit: running right now
│ Aim Assist         [ E hold ]  │   hold E
│ Aimbot +3           [ always ] │   ← on, +3 sub-options rolled up
│   Wall Check            [ V ]  │   ← a sub-option you gave a key
│ Infinite Jump          [ on ]  │   ← on, never bound to a key
└────────────────────────────────┘
┌────────────────────────────────┐
│ 142 FPS   38 MS                │   ← its own bar: stays up when collapsed
└────────────────────────────────┘
```

The readout is a **separate card**, not a row in the list — it isn't a bind, and
keeping it outside the panel means collapsing the binds away (the caret) leaves
your frames and ping on screen. Both cards drag as one.

**Rows do what their mode says.** A click or tap on a `Toggle` row flips it, on a
`Press` row fires it once; press-and-hold a `Hold` row holds it and lifting
releases it — including a finger that slides off the row. An `Always` row is on
and stays on (change its mode from the menu). It reaches `OnFlagChanged` as
`source = "user"`, exactly like the key. A press that **stays put is a tap; one
that moves drags the panel** — the same rule the window has, with nothing on a
timer. (Inside a phone's list a moving press scrolls it instead; the panel drags
by its header and the FPS bar there.)

**It can be tucked off the screen edge.** Drag the panel past the left or right
edge and it keeps going — a grab strip (44px on a phone, 28px on a desktop)
stays behind to pull it back with, so a hotbar that's in the way can be parked
against the edge instead of collapsed away. Downward it stops with its header
showing; upward it stops at the top edge, because the header is the part you
drag and a panel tucked past it could not be recovered. Only a panel *someone
placed* may be tucked — a drag, `SetPosition`, `X`/`Y`, or a restored config
(so a tuck survives a reload). Defaults and screen rotations always land the
whole panel on screen.

**The list is capped by height and scrolls.** `MaxRows` says how many rows
*exist* on a desktop (and therefore what `+N more` counts); how many you see at
once is whatever fits between the panel header and the bottom of the screen, so
the panel never runs off the edge of a small window or a phone. Past that the
bind list scrolls — the `+N more` line sits *below* the scroll area, so the line
telling you there's more is never itself the part you can't see.

It's **off by default**. Turn it on with `Hud = true` at build time, from the
Settings tab's *Keybind HUD* switch, or in code:

```lua
Uranium:CreateWindow({ Hud = true })      -- defaults
Uranium:CreateWindow({ Hud = {            -- or tune it
    Title    = "Keybinds",      -- header text     (default "Keybinds")
    X        = 16,              -- offset from the left  (default 16; on a phone: the right edge, near the top)
    Y        = 140,             -- offset from the top   (default 140)
    MaxRows  = 10,              -- desktop only: rows before "+N more" (default 10)
    Visible  = true,            -- start shown           (default true)
    Collapsed = false,          -- start collapsed to the header (default false)
    Stats    = true,            -- the FPS / ping bar    (default true)
    Fps      = true,            -- FPS readout           (default true)
    Ping     = true,            -- ping readout          (default true)
} })
```

**You don't register anything with it.** It reads the same keybind router the
controls use, so a feature appears the moment it has a key or a pin on it **or**
is switched on — as long as it has a name to be listed under:

| Where the bind comes from | What the HUD calls it |
| --- | --- |
| `Group:Toggle{ Name = "Aim" }`, once it's enabled, keyed or pinned | the toggle's `Name` |
| `Group:Keybind{ Name = "Sprint", Mode = "Hold" }` | the keybind's `Name` |
| `Window:Bind({ Key = ..., Mode = "Toggle", Label = "Fly" })` | its `Label` |

A keyless feature you turned on from the menu lists with `on` where its key
would be: there isn't one, and it's running anyway. Turn it back off and the row
goes.

Four things stay out, so it stays a short list rather than an inventory of the
whole menu:

- **anything that's off and has neither a key nor a pin** — an idle unbound
  feature is a row that tells you nothing, and since [every toggle carries a
  chip](#toggle) a hub full of them would bury the binds you set;
- **sub-options of a feature that's on** — see below;
- a bind with **no name** (nothing to call it);
- a **key picker** — a `Keybind` with no `Mode`, which holds a key but never
  activates.

Pass `Hud = true` / `Hud = false` on any of the three sources above to override
all of it.

#### On a phone: pin it

A phone has no keys, so the chip's key half becomes a **pin**
([Keybind on a Toggle](#keybind-on-a-toggle)): tap it on any bindable control
and that feature sits in the HUD exactly the way a keyed one does on a desktop —
listed while it's **off**, so the row is how you switch it on with the menu
closed. Unpin it and it lists only while it's running, like everything else. The
pin persists with the key and mode in the control's `<flag>_key` flag, so a
saved config restores the hotbar.

The rows are built for a thumb (see [On a phone](#on-a-phone) for the device
rule):

- **Thumb-sized tiles** (44px, with air between them) and a **state chip** on
  the right instead of the key: `ON` / `OFF` for a switch, `HOLD` for a hold
  bind, `TAP` for a one-shot, `ALWAYS` for a bind pinned on. A running row lights
  its chip in the accent and lifts a surface step:

  ```
  ┌──────────────────────────────┐
  │ GLOBAL                       │
  │ Fly                   [ OFF] │   ← pinned, off — tap to turn on
  │ Aim                   [HOLD] │   ← pinned, press and keep pressing
  │ Auto Parry            [ ON ] │   ← not pinned, listed because it's running
  └──────────────────────────────┘
  ```
- **Every listed bind is reachable.** `MaxRows` and `+N more` are a desktop cap;
  on a phone the row is the only way to switch a feature on at all, so every one
  is drawn and the height cap turns the overflow into a scroll. The list also
  stops at a bit over half the viewport height — the rest of the display is the
  game.
- **Pinned rows sort above running-only ones**, inside each section, and that is
  the only reordering a phone's list does. What you pinned is the hotbar; what's
  merely switched on is listed under it, so turning five things on from the menu
  can't scatter your buttons through them. Both halves stay in registration
  order, and a tap on a row never moves it — only the chip's pin half changes a
  pin, and that's in the menu, not under your thumb. (A desktop does the
  opposite: an over-long list floats what's *running* to the top, and pins do
  nothing.) The panel also rests against the **top** of the screen rather than
  centred, so a list that grows grows *downward*.
- **Default position** is the right edge, near the top (the desktop's `(16, 140)`
  lands on the left thumbstick). A position you pass, drag to, or restore from a
  config wins over it.
- The minimized **logo tile** toggles the HUD on a **long-press**, so the panel
  comes up without opening the window.

#### Sections — which part of the menu a row came from

With twenty-odd rows the panel is every feature in the hub in the order it was
built, and those come from unrelated places: the tools that work in any game, the
ones that only exist because of the game you're in, the preferences. The HUD
groups them under a dim header each, **in the order the tabs were created**:

```
┌────────────────────────────────┐
│ ▍ Active Binds               ⌃ │
├────────────────────────────────┤
│ GLOBAL                         │
│ ● Auto Parry         F · toggle│
│ ○ Fly                — · toggle│
│ THIS GAME                      │
│ ● Aimbot +3          X · always│
│  ◦ Wall Check        V · toggle│
└────────────────────────────────┘
```

**Nothing is declared for this.** A control's section is the **name of the tab**
it was built under, threaded down through the tab → group → control the same way
[`Parent`](#sub-options-parent) is. Headers only appear when there is **more than
one** section on screen; a section with no rows draws nothing.

Override it per card or per control with `Section`, and give a headless
`Window:Bind` one the same way (it has no tab behind it, so without one it sits
with the unheaded rows at the top):

```lua
local tab = Window:CreateTab({ Name = "Global", Icon = "globe" })
tab:CreateGroup({ Title = "Movement" })                      -- section "Global"
tab:CreateGroup({ Title = "Local", Section = "This game" })  -- ...or say otherwise

Window:Bind({ Key = Enum.KeyCode.F, Label = "Fly", Mode = "Toggle", Section = "Global" })
```

A parent and the sub-options rolled up under it never split across a header, and
when a desktop list is over `MaxRows` the active binds float to the top
**within** their own section rather than jumping into another one. (On touch
nothing is reordered at all — see the phone notes above.)

#### Sub-options (`Parent`)

Turning Aimbot on means turning on the handful of switches that make it work,
and each of those is a toggle that is now *running* — so without this the panel
fills with `Sticky Aim`, `Wall Check`, `Auto Fire` rows saying nothing the
`Aimbot` row above them didn't.

Say which feature a control belongs to and it rolls up into that feature's row
instead:

```lua
Group:Toggle({ Name = "Aimbot", Flag = "aimbot" })
Group:Toggle({ Name = "Sticky Aim", Flag = "aim_sticky", Parent = "aimbot" })
Group:Toggle({ Name = "Wall Check", Flag = "aim_walls",  Parent = "aimbot" })
```

`Parent` matches the other control's **`Flag` or its `Name`**, case- and
space-insensitively (`"aimbot"`, `"Aimbot"` and `"aim bot"` all find it), so it's
a name you already wrote down. A handle works too (`Parent = aimbotToggle`), and
a name that resolves to nothing is simply ignored — the control stays top-level
rather than disappearing.

**You usually don't have to say any of this.** With no `Parent` anywhere, a card
whose **first switch shares the card's title** is read as one feature with
sub-options, and everything bindable after it in that card rolls up into it:

```lua
local G = Tab:CreateGroup({ Title = "Triggerbot" })
G:Toggle({ Name = "Triggerbot", Flag = "trigger" })  -- the feature — the HUD row
G:Toggle({ Name = "Show FOV" })                      -- rolled up
G:Toggle({ Name = "Team Check" })                    -- rolled up
```

A switch called `Enabled` (or `Enable` / `Master`) counts as the card's own too,
and is listed under the **card's title** rather than under the word "Enabled":

```lua
local G = Tab:CreateGroup({ Title = "Triggerbot" })
G:Toggle({ Name = "Enabled", Flag = "trigger" })     -- the HUD row says "Triggerbot"
```

The title match is the safety catch. A card called `Misc` whose first switch is
`Infinite Jump` is a **list of unrelated features**, not one feature with
sub-options — nothing rolls up there, and Noclip and Fly keep their own rows. A
section inside such a card gets the same treatment on its own heading.

Override any of it explicitly: `HudLabel = "..."` on a control renames its HUD
row, `Hud = true` / `Hud = false` forces one in or out, and `Parent` (below) says
outright which feature a control belongs to.

Declare it **once for a whole card or section** instead of per line:

```lua
-- every bindable control in the card belongs to "aimbot"
local G = Tab:CreateGroup({ Title = "Aimbot", Parent = "aimbot" })

-- ...or let the FIRST bindable control in the container be the feature:
local G = Tab:CreateGroup({ Title = "Aimbot", Parent = true })
G:Toggle({ Name = "Aimbot", Flag = "aimbot" })  -- the feature
G:Toggle({ Name = "Sticky Aim" })               -- sub-option
G:Toggle({ Name = "Wall Check" })               -- sub-option
Group:Section({ Title = "Advanced", Parent = "aimbot" })  -- same, on a section
```

What that changes in the HUD:

| Sub-option | In the panel |
| --- | --- |
| off | not listed (same as before) |
| on, no key | not listed — counted as `+n` on the parent's row |
| has a key | listed, **indented** under its parent — you asked for it by name |
| `Hud = true` on it | listed regardless |

An on sub-option of an **off** parent stays out too: a sub-option of a feature
that isn't running isn't running either.

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

## Screen (status page)

A toast needs a window, and a window needs everything to have worked. `Screen`
is for the other case: a full-screen page for something the user has to read,
shown **with or without a window** — the hub's own scripts erroring on the way
up, a loader that's out of date, a ban. Those used to be a `warn()` behind
whatever else was in the executor console, which is to say invisible.

```lua
local page = Uranium:Screen({
    Title       = "You've been banned",         -- default "Something went wrong"
    Text        = "Reason: reselling builds.",  -- body copy, wraps
    Code        = "BANNED",                     -- small mono line under the title
    Icon        = "ban",                        -- Lucide name (default "triangle-alert")
    Tone        = "error",                      -- "error" | "warning" | "info"
    Detail      = debug.traceback(),            -- folded away behind "Details"
    Footer      = "Uranium · build 2026-08-15", -- small muted line at the bottom
    Discord     = "discord.gg/uranium",         -- adds a Copy button + selectable text
    Dismissable = true,                         -- default true (Esc + a × button)
    OnClose     = function(page, how) end,      -- fires once — see below
    Parent      = someInstance,                 -- same meaning as CreateWindow.Parent
    Input       = nil,                          -- a text entry block — see below
    Actions     = {
        { Label = "Reload", Icon = "refresh-cw", Primary = true,
          Close = true, Callback = function(page) Hub:Reload() end },
    },
})
```

```
        ┌──────────────────────────────────────────┐
        │ ▣  U R A N I U M                      ×  │   ← chrome titlebar: the mark
        ├──────────────────────────────────────────┤     + wordmark, like the window
        │  ┌────┐  You've been banned              │
        │  │ ⛔ │  BANNED                          │   ← chip takes the tone colour
        │  └────┘                                  │
        │  ────────────────────────────────────────│   ← hairline, same tone
        │  Reason: reselling builds.               │
        │  ┌──────────────────────────────────────┐│
        │  │ 💬  discord.gg/uranium               ││   ← selectable, not editable
        │  └──────────────────────────────────────┘│
        │  ▸ Details                               │
        │  [ Reload ]  [ Copy Discord ]            │
        │  Copied discord.gg/uranium               │   ← the flash line, ~3s
        │  ──────────────────────────────────────  │
        │  Uranium · build 2026-08-15              │
        └──────────────────────────────────────────┘
```

| Method | |
|---|---|
| `page:Close()` | Fade out and destroy. Reports `"dismiss"` to `OnClose`. |
| `page:Set(opts)` | Patch any of the options above, in place. |
| `page:Flash(text)` | Transient status line under the buttons (~3s). |
| `page.ScreenGui` | The `ScreenGui`, if you want to re-parent it yourself. |
| `page.Input` | The entry block's handle — **absent unless you passed `Input`**. |

Everything is optional and nothing here throws on junk input — a value that
isn't usable text hides its own row and the page still comes up. That's the
whole point: this is the code that runs when everything else already failed.

**The card is a small window.** Window radius, a chrome titlebar carrying the
brand mark and wordmark over a `bg` body, one border, a soft shadow under it —
the same miniature-of-the-window shape the [bind HUD](#bind-hud) takes, so a
page that appears before any window does still reads as the same product. The
mark is the shipped logo where it can be fetched, and a tinted tile with
Lucide's `atom` glyph — the same nucleus-and-orbits shape — where it can't. That
fallback is a spritesheet slice, so it needs no network and no file access at
all; it is never a letter in a green box.

**Tone tints, it doesn't repaint.** Only the icon chip and the hairline take the
colour; the surfaces stay the library's own, with the same radius, accent and
type scale as the window. `"error"` is red, `"warning"` amber, `"info"` the
accent (Notify's neutral grey vanishes at this size).

**`Discord` is an option, not an action you build.** Give it an invite and the
page grows a *Copy Discord* button after your own `Actions` (and becomes the
accent button if you passed none), which copies via `setclipboard` and flashes a
confirmation. The invite is also on the page as selectable text, so an executor
with no clipboard still hands the user something they can read out.

**Actions** get the page handle as their argument. `Primary = true` picks the
accent button; `Close` defaults to `true`, so a button dismisses the page unless
you say otherwise.

**`Dismissable = false`** removes Esc and the × — the only way out is re-running
the loadstring. That's deliberate for a ban.

**`OnClose(page, how)`** fires **exactly once**, whichever path took the page
down, with `how` saying which one:

| `how` | |
|---|---|
| `"dismiss"` | Esc, the × in the titlebar, or a bare `page:Close()`. |
| `"action"` | An `Actions` button that closes (`Close ~= false`). |
| `"replaced"` | A second `Uranium:Screen`, `Uranium:Unload()`, `CreateWindow`, or any other singleton sweep — the page was taken down without being answered. |

That last one is the reason this is a callback and not a return value. A key
gate has to know the difference between *the user answered* and *something took
the page away*, and the sweep destroys the `ScreenGui` without going through
`page:Close()` at all — so the once-guard hangs off `Destroying`, which is the
one signal that covers every path. It runs on its own `pcall`'d thread: a
callback that errors or yields can't take the teardown, or whatever triggered
it, down with it.

```lua
local answered = false
Uranium:Screen({
    Title = "Key System",
    Input = { Placeholder = "Paste your key" },
    Actions = { { Label = "Continue", Primary = true, Callback = function(page)
        answered = true
        Hub:Check(page.Input:Get())
    end } },
    OnClose = function(page, how)
        if not answered then
            -- "dismiss" → they walked away; "replaced" → the loader re-ran.
            Hub:Abort(how)
        end
    end,
})
```

### `Input` — taking a value back

A page can also *ask* for something. The case it's built for is a key gate: the
hub refusing to load until the user types a key, with this page as the only UI on
screen. Pass an `Input` table and the card grows an entry block between the body
text and the Discord row — so the reading order is *what went wrong → what to
type → where to get one → the buttons*.

```lua
local page = Uranium:Screen({
    Title = "Key required",
    Text  = "Uranium needs a key to run. Enter yours to unlock it.",
    Code  = "NO KEY",
    Icon  = "key",
    Tone  = "warning",
    Discord = "discord.gg/uranium",
    Dismissable = true,
    Input = {
        Label       = "Your key",              -- small caps caption above the box
        Placeholder = "XXXX-XXXX-XXXX-XXXX",
        Value       = "",                      -- prefill
        Button      = "Unlock",                -- submit label      (default "Continue")
        Paste       = true,                    -- a paste chip in the row, if the
                                               --   executor can read the clipboard
        MaxLength   = 64,                      -- clamped AFTER Filter
        Filter      = function(text) return text:upper() end,  -- live, every keystroke
        Submit      = function(value, ui) end, -- Enter, or the button
    },
})
```

```
        │  YOUR KEY                                │   ← Label, small caps, muted
        │  ┌────────────────────────┐ ┌──────────┐ │
        │  │ XXXX-XXXX-XXXX-XXXX  📋│ │  Unlock  │ │   ← box + paste, then submit
        │  └────────────────────────┘ └──────────┘ │
        │  That key isn't one we've issued.        │   ← the Error / Success line
```

Everything but `Submit` is optional. On a narrow viewport the button wraps under
the box rather than squeezing it — a key has to stay readable.

| `page.Input` | |
|---|---|
| `:Get()` | Current text. |
| `:Set(text)` | Set it (runs `Filter`, then `MaxLength`). |
| `:Focus()` | Focus the box. |
| `:Clear()` | Empty it. |
| `:Busy(true/false)` | Disable the box and button and dim them; `false` restores both with the text still in place. |
| `:Error(text)` | Red line under the box, and the caret goes back in the box. Clears on the next edit. |
| `:Success(text)` | Accent line under the box. |

**`page.Input` is `nil` when no `Input` block was passed**, and that absence is
the capability probe — check it before assuming the page can take a value, and
fall back to a clipboard button if it can't:

```lua
if type(page.Input) ~= "table" then
    page:Set({ Text = "Copy your key, then press Paste key." })
end
```

The same object is handed to `Submit` as its second argument, so a caller that
never kept the page handle can still report back:

```lua
Submit = function(value, ui)
    task.spawn(function()
        ui:Busy(true)
        local ok, why = redeem(value)
        if not ok then
            ui:Busy(false)
            ui:Error(why)          -- "That key isn't one we've issued."
            return
        end
        ui:Success("Key accepted — loading.")
    end)
end,
```

Behaviour worth knowing:

- **Enter submits**, same as the button, and an **empty submit does nothing** —
  no callback, no error flash for something the user hasn't done yet.
- **An error never clears the box.** Someone who typed nineteen characters and
  got one wrong should be editing, not retyping, so `Error` puts the caret back
  where they left it. `Error` and `Success` share one line; the second replaces
  the first, and an error clears itself as soon as the user edits.
- **`Busy(true)` blocks re-entry** — the box stops being editable and the button
  stops responding and visibly dims. `Busy(false)` restores both, text intact.
- **`Paste = true`** draws a small chip in the row that reads the clipboard
  (`getclipboard` / `getclipboardtext` / `toclipboard`, whichever exists), fills
  the box and submits. Where the executor exposes none, the chip isn't drawn at
  all rather than drawn dead.
- **Nothing is logged.** No `print`, no `warn` carrying the value — this is a
  licence key and the console is readable by the game.
- **`page:Set` works over a live input page**, which is how a gate rewords itself
  mid-attempt. Patching `Text` or `Title` leaves the box alone; `Value` is only
  re-applied when you pass a *new* `Input` table, so a reword can't wipe what the
  user has typed. An `Input` passed once is never torn down — dropping it from a
  later patch only hides the block.
- **Escape with the box focused** is the engine's first: it releases text capture
  and the page closes on the second press. Taking Escape off the `gameProcessed`
  guard would mean a game that consumes it closes the page out from under itself.

Only one page exists at a time: a second `Uranium:Screen` replaces the first, and
both `Uranium:Unload()` and the next `CreateWindow` take a live page down with
them (a stale ban page still on screen after the user re-runs a *fixed* loader is
the failure this exists to prevent). A page never claims the singleton slot, so
`Uranium:IsLoaded()` keeps meaning *"is there a window"*.

### Before the library exists: `ui/screen.lua`

The same page is built a second time as a standalone artifact with **no
dependency on the rest of the library** — for code that has to explain itself
*before* `coreui.bundle.lua` is ever fetched, which is exactly the case a
delivery server refusing a client is in. The chunk's value is the function:

```lua
local ok, show = pcall(function() return (function(...)
    -- contents of ui/screen.lua
end)() end)
if ok and type(show) == "function" and pcall(show, {
    Title = "Outdated loader",
    Text  = "This loadstring is from an older release. Grab a fresh one.",
    Code  = "OUTDATED",
    Icon  = "download",
    Tone  = "warning",
    Discord = "discord.gg/uranium",
}) then
    return
end
warn("[Uranium] outdated loader") -- fall back if the page couldn't be shown
```

It takes the same options minus `Detail` — **`Input` included**, which is the
build the key gate actually runs — parents its own `ScreenGui` (`gethui` →
`CoreGui` → `PlayerGui`, each guarded), never touches the delivery API that just
refused the client, and is generated by `bundle.py` from the *same source* as
`Uranium:Screen` — see CLAUDE.md for how the two builds share one body.

Its titlebar carries the real mark: the page does the same four steps
`util/Asset.lua` does — disk cache → `getcustomasset`, and on a miss `HttpGet`
the PNG from the art host, magic-byte check it, `writefile` it to the same cache
path the library uses, then hand it over. That runs **off-thread after the page
is already on screen**, so the `atom` fallback mark is what you see first and
the art replaces it a moment later — or never, on an executor with no file
access, which is the whole point of drawing a real mark first. It's the one
network call on the page; an uploaded `rbxassetid://` in `Theme.Brand.logo`'s
chain would remove the need for it.

---

## Tab

```lua
local Tab = Window:CreateTab({
    Name  = "Home",   -- flyout label            (default "Tab")
    Icon  = "home",   -- Lucide icon short-name  (default "gear")
    Desc  = nil,      -- second flyout line
    Badge = nil,      -- small chip in the flyout, in the tab's colour
    Id    = nil,      -- stable identity for persisted group state (default: Name)
})
```

`Id` only matters for [window state](#window-state-uranium_window): it's what the
folded-group map is keyed on, so give a tab one when its `Name` is duplicated or
gets renamed at runtime (`SetName` deliberately does **not** re-key it — that
would orphan every group under it in configs already on disk).

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
    Id        = nil,        -- stable identity for persisted state (default: Title)
    Parent    = nil,        -- bind-HUD feature every control here belongs to
                            -- (a name, or `true` = the first bindable control)
    Section   = nil,        -- bind-HUD header these binds sit under
                            -- (default: the tab's Name — see Bind HUD § Sections)
})
```

The header is clickable — it collapses/expands the card. The returned object is a
**control surface**: call the control methods below on it. The same surface is
returned by `Group:Section{}`.

Two methods live on the surface itself rather than being controls:

| Method | Description |
| --- | --- |
| `Group:IsCollapsed()` → `bool` | Is the card folded? |
| `Group:SetCollapsed(bool, animate?)` | Fold / unfold it. `animate == false` snaps. |

Which groups are folded is persisted with the window (see
[Window state](#window-state-uranium_window)), keyed on `"<tab>::<Id or Title>"` —
`Id` is there for when two groups in a tab share a title, or a title changes.

---

## Section (nested group)

```lua
local Sub = Group:Section({
    Title     = "Advanced",  -- section header   (default "Section")
    Collapsed = true,        -- start collapsed  (default false)
    Parent    = nil,         -- bind-HUD feature these controls belong to
                             -- (see Sub-options; inherits the card's if unset)
})
Sub:Toggle({ Name = "Verbose logging" })
```

Returns a nested control surface (indented, with a left rule and its own
collapse chevron). Add controls to it exactly like a Group.

---

## Controls

All controls below are methods on a **Group** or **Section** surface.

### Common conventions

- **`Name`** — the field label (left side). **`Desc`** — optional description; by
  default it lives in a hover popover behind a small glyph after the name rather
  than on the row (see [Descriptions](#descriptions-desc--info)). Omitting `Name`
  on a Button makes it a bare full-width button.
- **`Info`** — a richer description for that popover (title, body, bullets,
  key/value rows, a toned note). `Info = false` keeps this control's `Desc` inline.
- **`Callback`** — fired on every value change with the new value.
- **`Default`** — initial value. **`Default` does not fire `Callback`.** Building
  a control with `Default = true` sets the switch and nothing else; the callback
  runs on the first *change*. See `FireDefault` below for the opt-in that closes
  the gap.
- **`FireDefault = true`** — run `Callback` once at construction with the value
  the control was built at, so a feature's state is applied by the same line that
  declares it.
- **`Section`** — which bind-HUD header this control's bind sits under. Inherited
  from the tab (and overridable on the card), so nothing normally passes it —
  see [Sections](#sections--which-part-of-the-menu-a-row-came-from).
- **`Flag = "id"`** — registers the control for config save/load. The value is
  captured on `SaveConfig` and restored on `LoadConfig` / auto-load. See
  [Config & flags](#config--flags). Only stateful controls support flags
  (Toggle, Slider, Dropdown, MultiDropdown, Input, Code, Keybind, Colorpicker,
  PlayerSelect, PlayerMultiSelect, Picker).

Stateful controls return a **handle** with `:Get()` and `:Set(value)`. `:Set`
fires the callback.

Every mounted control's handle also has **`:SetVisible(bool)`** / `:IsVisible()`,
which hides or shows the whole row — the field and the hairline under it — so a
control that means nothing in some situation (a key picker on a phone) can stand
down without leaving a stray separator. A control that already had its own
`SetVisible` keeps it.

#### `FireDefault` — applying the default at build time

Without it, every default is written twice — once as `Default`, once as the
module state the callback would have set — and nothing catches the two drifting
apart:

```lua
local espOn = true                                    -- ...and here
Group:Toggle({
    Name = "ESP", Default = true,                     -- the default lives here...
    Callback = function(on) espOn = on; refresh() end,
})
```

```lua
Group:Toggle({
    Name = "ESP", Default = true, FireDefault = true,  -- Callback runs now, with `true`
    Callback = function(on) espOn = on; refresh() end,
})
```

Supported on every stateful control: `Toggle`, `Slider`, `Dropdown`,
`MultiDropdown`, `Input`, `Code`, `Colorpicker`, `Keybind`, `PlayerSelect`,
`PlayerMultiSelect`, `Picker`. The callback is handed exactly what it would receive from
the first real change — including `Keybind`'s two shapes, so a picker
(`Mode = "None"`) is fired with its key and an activation bind with
`(active, info)`.

Three things to know about the timing:

- It fires **during** the `Group:Toggle{…}` call, before that call returns. A
  callback that reaches back into the control has to go through the handle it
  was *passed*, not the local it is being assigned to — that local is still nil.
- It is **not** a flag change. `Window:OnFlagChanged` is not raised (a control
  taking its default hasn't changed), and the flag is registered normally
  afterwards, so `SaveConfig` and `LoadConfig` are unaffected.
- It runs on its own thread (`task.spawn`), so a callback that yields doesn't
  stall the rest of the menu being built.

**Why it's opt-in.** Wrappers around this library commonly apply their own
default at build time — `if opts.Default then apply(true) end` — and firing
unconditionally would run every one of those twice. Making it the default
behaviour is possible, but only **in lockstep** with those wrappers dropping
their own line; ship the two together or don't ship either.

---

### Descriptions (`Desc` / `Info`)

A `Desc` used to be a second line of prose under every control's name,
unconditionally — which meant a card with eight described controls was three
screens tall and the panel read as documentation with switches buried in it. It
isn't printed on the row by default any more:

```lua
Uranium:CreateWindow({ Descriptions = "hover" })   -- default
```

| Mode | What a described control looks like |
| --- | --- |
| `"hover"` | A dim info glyph immediately after the name. The text is in a popover. **Default.** |
| `"inline"` | The old behaviour — `Desc` as a second line under the name, no glyph. |
| `"both"` | Glyph *and* inline line, so the popover can read longer than the row does. |

`Window:SetDescriptions(mode)` switches it at runtime and re-lays out the fields
that are already on screen, so a hub can offer it as a switch in its own settings
panel. It returns the mode in force afterwards — an unrecognized one warns and
changes nothing, so you can echo the result back into your control instead of
assuming the write landed.

**Reaching the popover.** Hover the glyph *or* the name and it opens after ~300ms,
closing as soon as you leave. **Click the glyph to pin it** — it then stays up
until you click somewhere else, which is what lets you read it while dragging the
slider it's describing. On touch there is no hover at all, so tapping the glyph
(a ~24px target around the 13px mark) or **long-pressing the name** is the way
in, and tapping anywhere else closes it.

A control with neither `Desc` nor `Info` gets no glyph and no gap. `Info = false`
opts one control out entirely: its `Desc` stays on the row in every mode.

**`Info` — when a sentence isn't enough.** Every field is optional, and anything
unusable is simply dropped rather than erroring:

```lua
Group:Toggle({
    Name = "Visible Only",
    Desc = "Skip anyone with something between you.",  -- popover body, and the
                                                       -- inline line in "inline"/"both"
    Info = {
        Title   = nil,      -- default: the control's `Name`
        Text    = nil,      -- body; default: `Desc`. Set both when the popover
                            -- should read longer than the inline line.
        Bullets = { "Ignores your own character", "Re-checks every frame" },
        Fields  = { { "Cost", "1 ray per candidate" } },  -- key/value, value right-aligned
        Note    = { Tone = "warn", Text = "Costs a raycast per candidate." },
        Icon    = "info",   -- Lucide short-name for the glyph
        Width   = nil,      -- px, default 260 (clamped 160–420)
        Tone    = nil,      -- tint the glyph without a Note
    },
})
```

`Note.Tone` (or `Info.Tone`) **tints the glyph**: `"warn"` amber, `"danger"` red,
`"info"` the default dim. That's the point of having tones — a row hiding a
performance cost or a footgun advertises that it does, instead of looking
identical to one hiding "Skip teammates." (`"warning"` and `"error"` are accepted
as aliases, and `Note = "some text"` is shorthand for an `info`-toned one.)

An `Info` table with nothing in it but a `Title` produces no glyph: the title is
the label it would be sitting next to.

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
unbound chip on an *off* toggle stays out of the [bind HUD](#bind-hud), so this
costs nothing on screen but the pill itself. (Switch the toggle on and it does
list, key or no key — the HUD's job is to report what's running.)

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

`Parent = "<feature>"` marks the toggle as a **sub-option** of another control,
which keeps it out of the bind HUD when it's merely switched on — its parent's
row speaks for it. See [Sub-options](#sub-options-parent).

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

On a phone the key half is **inert**: there's no keyboard to listen for, and an
armed chip would sit at `...` with nothing to end it but a tap elsewhere. The
mode half still cycles. See [On a phone](#on-a-phone).

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

`Parent = "<feature>"` works here too — it marks the bind as a sub-option of
another one for the [bind HUD](#sub-options-parent).

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
| `Parent = "<feature>"` | a sub-option of another control — [rolls up in the HUD](#sub-options-parent) |
| `CreateWindow{ Keybinds = false }` | no chip on any toggle; an explicit `Keybind` / `KeybindMode` / `KeybindModes` overrides it back on |

**The key persists with the toggle.** With a `Flag` and no `KeybindFlag`, the
chip registers itself under `<flag>_key` — `Flag = "fly"` → `fly_key` — which is
the convention hubs were already writing by hand, so derived names match the
configs people have already saved. An explicit `KeybindFlag` still wins.

`handle.Bind` exposes the chip's handle (`:Get()` / `:Set(key)` / `:GetMode()` /
`:SetMode(m)` / `:IsPinned()` / `:SetPinned(b)`), or is `nil` on a toggle that
opted out.

**On a phone the chip's key half is a pin.** Nothing the user can press will
ever fill a key half, so instead it shows a pin glyph: tap it and the feature is
**pinned to the [bind HUD](#on-a-phone-pin-it)** — listed there while it's off,
so it can be switched on with the menu closed — and the glyph lights in the
accent. Tap again to unpin. It's the phone's equivalent of putting a key on
something, and it persists with the key and mode (`{ key, mode, pinned }` in the
`<flag>_key` flag). The **mode half stays** wherever there's more than one mode
to cycle, so `Aim Key` can still go `hold → toggle → always`, which is what the
HUD's rows honour. A saved key still round-trips through the flag — it just
isn't drawn. `Keybinds = false` on the window puts nothing new on a phone.

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

### Picker (item gallery)

A searchable, filterable grid of pickable things with a thumbnail each — skins,
weapons, pets, maps, loadouts. It is the control a cosmetic list wants and
[`DataGrid`](#datagrid-data-table) isn't: pictures, a **selected** item, its own
search box and filter chips, a real empty state, and **virtualisation**, so the
whole catalogue goes in as one `Items` array — a few hundred entries cost the
same handful of frames as a dozen.

```lua
local h = Group:Picker({
    Name     = "Swords",
    Desc     = "Pick the one you want equipped.",
    Height   = 260,        -- viewport height in px          (default 260)
    Layout   = "tiles",    -- "tiles" (grid) | "rows" (list) (default "tiles")
    TileSize = 84,         -- tile width to aim for, "tiles" (default 84)
    Search   = true,       -- built-in search box; a string sets its placeholder
    Count    = true,       -- the "312 items" / "12 of 312" readout (default true)
    Empty    = "Nothing owned yet",  -- shown when there are no items at all
    Filters  = { "All", "Legendary", { Name = "Favourites", Match = isFav } },
    Items    = {
        { id = "ghost", Title = "Ghost", Subtitle = "Legendary",
          Image = "rbxassetid://123", Badge = "Dual", Selected = true,
          Tags = { "event" },
          Actions = { { Name = "fav", Icon = "star" } } },
        { id = "iron", Title = "Iron", Subtitle = "Common", Image = 74808640463075 },
    },
    Flag     = "skin",
    Callback = function(id, item) equip(id) end,           -- an item was picked
    OnAction = function(id, name, item) toggleFav(id) end, -- its action was pressed
})
```

**Item shape.** Only `id` is required, and it has to be unique — an item without
one, or repeating one already in the list, is skipped with a warning rather than
taking the render down with it (`id` is what `Callback`, `:Select` and
`:UpdateItem` all speak in, so a duplicate would make them disagree about which
item they mean).

| Field | |
| --- | --- |
| `id` | **required**, unique. What every callback and method identifies the item by. |
| `Title` | the main line. Falls back to the `id` if absent. |
| `Subtitle` | the second, muted line. Doubles as a filter name — see below. |
| `Image` | the thumbnail. **Anything** [`Asset.resolve`](#images--assets) takes: a bare decal id, `rbxassetid://…`, an https url, a local file, or an array as a fallback chain. A placeholder icon shows until it lands. |
| `Badge` | a small accent pill — over the picture in `tiles`, at the right of the row in `rows`. |
| `Tags` | `{ string }`, matched by the filter chips. Never displayed. |
| `Filter` | one explicit filter name, when the category isn't the `Subtitle`. |
| `Selected` | `true` marks this the picked item at build time (or on the `SetItems` that brings it in). |
| `Actions` | `{ { Name = "fav", Icon = "star", Text = "Fav" } }` — small buttons on the item. `Icon` wins over `Text`; pressing one fires `OnAction`, **not** `Callback`. |

**Filters.** Each entry in `Filters` becomes a chip; one is active at a time and
the row wraps onto a second line when it has to. A chip is either a name or a
rule:

| Chip | Matches |
| --- | --- |
| `"All"` (or `{ Name = "…", All = true }`) | everything |
| `"Legendary"` | items whose `Filter`, `Subtitle` or one of whose `Tags` is `"Legendary"`, case-insensitively |
| `{ Name = "Favourites", Match = function(item) return fav[item.id] end }` | whatever the predicate says |

`Match` is the escape hatch, and it's why chips aren't just a list of strings:
"Favourites" is not a property of the item, it's a property of the user, and only
the host knows it. A predicate that errors keeps the item and warns rather than
blanking the gallery.

**The search box** filters on the item's `Title`, `Subtitle`, `Badge`, `Filter`,
`Tags` and `id` together, as a plain case-insensitive substring, and stacks with
the active chip. It scrolls back to the top on every keystroke, since the old
offset points into results that are no longer there.

| Handle | |
| --- | --- |
| `h:GetSelected()` → `id, item` | what's picked (`nil` if nothing is) |
| `h:Select(id)` | pick it. Fires `Callback`, like every other control's `:Set`. `nil` clears. |
| `h:Get()` / `h:Set(id)` | the same thing under the flag names — this is a stateful control |
| `h:SetItems(list)` | replace the catalogue |
| `h:UpdateItem(id, patch)` | patch one item in place — the "toggle a favourite" path |
| `h:SetFilters(list)` | replace the chips |
| `h:GetItems()` | the items that were accepted, in order |

`SetItems` keeps the scroll position and holds the item tables **by reference**
(that's what lets `UpdateItem` write into them). An incoming item carrying
`Selected = true` becomes the selection; otherwise the current one is kept even
if the new list doesn't contain it, so a catalogue that comes and goes doesn't
forget what's equipped. `UpdateItem` moving the selection is data, not a pick, so
it does **not** fire `Callback`.

```lua
-- Flip a favourite without handing the whole catalogue back to redraw one star.
Group:Picker({
    Items = list,
    OnAction = function(id, name)
        if name == "fav" then
            fav[id] = not fav[id]
            h:UpdateItem(id, { Actions = { { Name = "fav", Icon = fav[id] and "star" or "star-off" } } })
        end
    end,
})
```

**With a `Flag`,** the picked `id` is what persists — the items themselves are
content, not value, and never reach the file. A config naming an id the current
catalogue doesn't have restores as that id with nothing highlighted, which is the
honest answer for "the skin you had equipped isn't in this list".

Two things it does *not* do, deliberately: there is no multi-select (a picker
picks one; a set of things is what `MultiDropdown` is for), and `Layout` is fixed
at build time.

---

## Display-only components

These have no persistent value — no `Flag`, and nothing to `:Get()`. Four of them
can still be **refreshed** after they're built, which is what you want for
anything showing live state:

| Component | Update methods |
| --- | --- |
| `Label` | `:Set(value)` |
| `Paragraph` | `:Set(body)` · `:SetTitle(title)` |
| `List` | `:Set(items)` |
| `Image` | `:Set(source)` · `:Get()` · `:SetCaption(text)` |
| `Divider`, `Player` | none — nothing to update |

[`DataGrid`](#datagrid-data-table) is display-only too but carries its own,
larger surface — see its section below. So does `MediaPlayer`
(cover art, transport, timeline, volume), which isn't documented here yet;
read the header of `components/MediaPlayer.lua` for its options.
[`Picker`](#picker-item-gallery) looks like it belongs here and doesn't: it
holds a selection, so it's a stateful control with a `Flag`.

### Label (key / value row)

```lua
local h = Group:Label({ Key = "Status", Value = "Connected" })
h:Set("Disconnected")   -- update the value at runtime
```

### Paragraph

```lua
local h = Group:Paragraph({
    Title = "Welcome",   -- optional
    Body  = "Some explanatory copy that wraps across lines.",
})
h:Set("New copy, rewrapped in place.")   -- replace the body
h:SetTitle("Still Welcome")              -- replace the title
h:SetTitle(nil)                          -- ...or drop it, closing the gap
```

A paragraph built without a `Title` has no title label at all; `:SetTitle` builds
one the first time it's given text, so an untitled paragraph costs nothing until
it needs one.

### Divider

```lua
Group:Divider()   -- a hairline separator
```

### List (bullet list)

```lua
local h = Group:List({
    { Name = "Version", Value = "1.0.0" },  -- "Name:  Value"
    { Text = "Plain bullet line" },          -- free text
    { Text = "Dimmed line", Dim = true },    -- muted color
})

h:Set({                                      -- replace the rows, same item shape
    { Name = "Version", Value = "1.0.1" },
    { Text = "Reconnected", Dim = true },
})
h:Set({})                                    -- ...or empty it
```

`:Set` is the refreshable multi-row surface — a scan result, a session log, a
live inventory. It repaints the rows already on screen and only builds what the
new list needs beyond them, so the card doesn't collapse and jump on the way
through, and a list that cycles between similar lengths stops allocating after
the first pass.

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

### DataGrid (data table)

A dense, fixed-height table for tool output shaped like rows and columns — a
memory or value scanner, a traffic log, an instance browser, a leaderboard. Rows
are pooled and repainted in place, so it's built for a few hundred live rows
updating several times a second rather than for a one-shot render.

```lua
local grid = Group:DataGrid({
    Name      = "Results",       -- optional label above the table
    Desc      = "Matches so far.",
    Height    = 200,             -- viewport height in px (default 200)
    RowHeight = 27,              -- per row, and the header  (default 27)
    Columns   = {
        { Key = "path",    Title = "Path",  Width = 0.45 },
        { Key = "value",   Title = "Value", Width = 0.20, Editable = true },
        { Key = "actions", Title = "",      Width = 0.35, Type = "actions" },
    },
})

grid:SetRows({
    { id = "row1", path = "Humanoid.WalkSpeed", value = "16",
      actions = { { Name = "lock", Icon = "lock" }, { Name = "info", Icon = "info" } } },
    { id = "row2", path = "Humanoid.JumpPower", value = "50", actions = {} },
})

grid:UpdateRow("row1", { value = "24" })   -- patch one row
grid:RemoveRow("row2")

grid.RowEdited:Connect(function(id, columnKey, newText) end)
grid.RowAction:Connect(function(id, actionName) end)
```

**Columns** are declared once, at build time, and can't be changed afterwards.

| Field | |
| --- | --- |
| `Key` | which field of a row this column shows, and the `columnKey` `RowEdited` reports |
| `Title` | the header text. Defaults to `Key` — pass `""` for a heading-less column (an actions column usually wants one). |
| `Width` | a **fraction of the table's width, 0..1** — not pixels. Columns are laid out left to right in declaration order, so the fractions should add up to 1 or less; past that the last columns run off the edge. |
| `Editable` | `true` makes the cell a mono TextBox. See below. |
| `Type` | `"text"` (default) or `"actions"` — a row of small buttons built from that cell's value. |

**Rows** are flat tables: one field per column `Key`, plus an `id`.

- **Every row needs a unique `id`.** It's what `UpdateRow`, `RemoveRow` and both
  events speak in, and it's how a row is matched to the frame already drawing it
  across `SetRows` calls. A row without one is **skipped with a warning** and the
  rest of the call still renders — for a grid refilled several times a second,
  one malformed entry taking the whole view down is not a trade worth making.
- A cell whose value is `nil` renders empty; anything else goes through
  `tostring`.
- Row order is array order.

**`:SetRows` is a diff, not a rebuild.** Rows already on screen keep their frames
(matched by `id`), only cells whose value actually changed get written, rows that
have dropped out go back to the pool, and new ones come off it. Handing the same
list back costs nothing, so a ticker can call it on every sample.

There is **no virtualisation**: every row in the list is a frame, and the
viewport scrolls over them. That's the right trade for a live scanner, where the
row count is bounded by whatever the tool found — but for a long, browsable list
of things a user picks from, reach for [`Picker`](#picker-item-gallery), which
mounts only what's on screen.

**Actions** — a cell in an `actions` column holds `{ ActionDef }`:

```lua
{ Name = "lock", Icon = "lock", Text = "Lock" }
```

`Name` is what `RowAction` reports. **`Icon` wins over `Text`**: with an `Icon`
the button is a fixed 22×22 square and `Text` is unused; with only `Text` it's an
auto-width pill. Any [icon name](#icons) works. Buttons are reused by `Name`
across renders and repainted for whatever that action now is, so flipping
`Icon = "lock"` → `"unlock"` on the next `SetRows` swaps the glyph in place.

**Editable cells** commit on focus loss (click away or press Enter), firing
`RowEdited(id, columnKey, newText)` — the grid does **not** write the value back
itself, so the row shows what you last put in it and it's the handler's job to
`UpdateRow` (or reject the edit by not doing so). Two details worth knowing: the
row an edit belongs to is captured when it *starts*, so a `SetRows` that recycles
the frame mid-edit can't commit the typed text against a different row; and
incoming updates to a cell that's currently focused are held back rather than
overwriting what's being typed, and land once it blurs.

`DataGrid` takes no `Flag` — its content is caller-owned and transient, not a
value to save. Same for `MediaPlayer`, `Image` and `Custom`.

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

#### Applying only part of a config (`Filter`)

By default a config load applies every flag in the file. If your registry is
split — a portable half that applies in any game and a per-place half that only
means something in the game it was written for — pass a predicate and only the
flags it says yes to are applied:

```lua
Window:LoadConfig("main", {
    Filter = function(name, kind)
        return not perPlace[name]        -- apply the portable half only
    end,
})
```

It's the same option on both, so the in-memory half is filterable too:

```lua
Window:ApplyConfig(snapshot, { Filter = function(name, kind) ... end })
```

**One predicate, not a list of names** — the classification a host wants here is
usually computed (which module registered the flag, which place it belongs to),
and enumerating it defeats the point.

- `name` is the flag, `kind` is its codec kind — the same pair `GetFlags()`
  reports.
- **Return `false` and the key counts as skipped, not applied.** So
  `LoadConfig`'s `"applied nothing"` failure still means exactly that: a filter
  that rejects everything in the file is a failed load, not a silent success.
- **The filter never sees a key that isn't a registered flag.** `Config.MetaKey`
  (`"__uranium"`) and any bookkeeping key you keep alongside it are skipped
  before it's consulted, so it doesn't have to know about them.
- A filter that errors skips its flag (with a warning) rather than half-applying
  a config you couldn't classify.
- Omit `Filter` — or the whole options table — and behaviour is unchanged.

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
`"playerselect"`, `"code"`, `"hud"`, `"window"`).

### Watching values change

`OnFlag` says which flags *exist*; `OnFlagChanged` says which one just **moved**.
That's the hook to hang continuous persistence off — without it the only way to
notice a change is to poll `GetConfig()` and diff it, which loses everything
since the last poll whenever the client script dies without a clean unload (a
teleport, a server hop, an alt-F4).

```lua
local unsub = Window:OnFlagChanged(function(name, value, kind, source)
    if source == "config" then return end   -- we're the ones applying it
    snapshot[name] = value                  -- already encoded — file it as-is
    scheduleWrite()                         -- debounce ~1s and save once
end)
```

| Argument | What |
| --- | --- |
| `name` | The flag. |
| `value` | The **encoded** value — byte-for-byte what `GetConfig()` would put in the file under that name, so you can patch a snapshot in place instead of re-reading every flag to find the one that moved. Treat it as read-only; every watcher gets the same table. |
| `kind` | The codec kind, as `GetFlags()` reports it. |
| `source` | `"user"` — a control the user operated · `"code"` — a programmatic `:Set` · `"config"` — inside `ApplyConfig` / `LoadConfig`. |

`source` is the load-bearing one. A config landing 40 flags must not look like 40
edits worth writing back, and the alternative — a re-entrancy flag around your own
`ApplyConfig` call — can't see an autoload the library ran itself.

Four promises:

- **Synchronous**, like `OnFlag`. Note that most controls hand their callback to
  `task.spawn`, so a watcher usually runs on that spawned thread rather than the
  one that caused the change: safe to yield in, never safe to assume you're still
  inside the click handler.
- **Never on registration.** A control taking its `Default` is not a change.
- **Never on a no-op.** A `:Set` that lands on the value already held is silent —
  values are compared *encoded*, so this holds for tables (a bind's key + mode, a
  multi-dropdown's list) as well as scalars.
- **Every flag kind**, including the ones nobody declared: the bind chip a toggle
  gets for free reports under `<flag>_key` when it's re-keyed or its mode is
  cycled, and the HUD reports when it's dragged or folded.

A watcher that throws is `pcall`'d and warned about — your bookkeeping blowing up
never takes the control that moved down with it. `Window:NotifyFlag(name)` is the
other half for state *you* registered with `RegisterFlag`: call it whenever your
own value may have moved, and it stays silent unless it really did.

`CreateWindow{ OnFlagChanged = fn }` installs the same hook early enough to catch
the first change the menu ever makes.

### Window state (`uranium_window`)

Where the window sits, how big it is, which tab is open and which groups are
folded is state the user set with the mouse — so the library persists it itself,
on the same terms as the bind HUD. It's one flag, `uranium_window`, in every
config you save:

```lua
Uranium:CreateWindow({
    PersistWindow = false,             -- opt out entirely
    WindowFlag    = "my_window_state", -- or just rename it
})
```

Restoring is defensive, because a record is written by one session and applied by
another — different viewport, possibly a different set of tabs:

- **Position and size are clamped** exactly the way a drag is, so a record saved
  on a 1440p monitor can't put the window off a laptop screen.
- **A selected tab that no longer exists** — a config saved with a game script's
  tab loaded, restored without it — falls through to the first visible tab
  instead of erroring.
- **Groups are matched by key**, `"<tab>::<group>"`, from the tab's `Name` and the
  group's `Id` (or its `Title`). Anything that doesn't match is left alone, and
  groups built *after* the config is applied keep their own `Collapsed` option —
  the same ordering rule as every other flag.

Give a tab or a group an explicit `Id` when its title is duplicated or likely to
change; a repeated key gets a `#2` suffix, which is stable only as long as the
menu builds in the same order.

The pieces are public too, so a host that wants its own record — or just wants to
put the window somewhere — doesn't need the flag:

```lua
Window:SetPosition(40, 120)          -- top-left, clamped on-screen
Window:SetSize(900, 620)             -- clamped to the viewport
Window:SetMaximized(true)
Window:Select(2)                     -- Window:GetSelected() reads it back
Group:SetCollapsed(true)             -- Group:IsCollapsed() reads it back
```

`Group:SetCollapsed(value, animate?)` snaps when `animate == false`, which is what
a restore wants — no fold animation for state the user set last session. Sections
aren't persisted; only groups are.

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
**Descriptions** picker (see [Descriptions](#descriptions-desc--info)), a
**Minimize Hint** switch with a **Hint Style** picker beside it, a notifications switch, a **Keybind HUD** switch (see [Bind HUD](#bind-hud)), and
config **save / load / delete / refresh** plus an **Auto Load** toggle and an
**Unload** button.

On a phone the **Toggle UI** row is hidden (its flag still registers and
round-trips): it names a key the device can't press, and the minimized logo tile
is the way back there. `controls.TouchWatch` is the unsubscriber for that watch.
See [On a phone](#on-a-phone).

Picking a config in **Saved Configs** also fills the **Config Name** box with it,
so the obvious gesture — pick `main`, press *Save* — overwrites the config you
picked instead of writing a second one under whatever the box still held. It only
fills a box that's empty or still holds the name *it* put there, so text you typed
is never clobbered, and clearing the selection doesn't clear the box.

The second return is every handle the panel built, also on `tab.Controls`:

| Key | What |
| --- | --- |
| `Accent` `ToggleKey` `Descriptions` `MinimizeHint` `MinimizeHintStyle` `Notifications` `Hud` | The Interface controls. |
| `HudMirror` `HudChanges` `TouchWatch` `FolderWatch` | Unsubscribers for the panel's own watches, for a host tearing its settings UI down. |
| `Name` `List` `AutoLoad` | The config name box, the saved-config dropdown, the auto-load switch. |
| `OnSelect(fn)` → `unsub` | `fn(name)` whenever the selection changes. |
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

**`OnSelect`** is the hook for a list whose entries aren't the file names on disk.
If you show `"main - Some Game"` in the dropdown, that's what lands in the name
box; hear about the pick and put the real name there instead:

```lua
local unsub = c.OnSelect(function(name)
    if name == nil then return end          -- selection was dropped
    c.Name:Set(realFileNameFor(name))       -- your name wins over the prefill
end)
```

- `name` is the option that was picked, or `nil` when the selection is dropped
  (deleting the selected config, or a `SetOptions` that pruned it).
- It fires for a **programmatic `List:Set` too**, not just a user pick — so the
  post-save re-select and the auto-load pass both reach you. It's deduped against
  the last name announced, so a `Set` landing on what's already picked is silent.
- Writing `c.Name` from inside the handler is expected: what you write becomes the
  value the prefill treats as its own, so the *next* pick still refills.
- A handler that throws is `pcall`'d and warned about.
- No initial call — nothing is selected when `CreateSettingsTab` returns.

If you wrap the window's config methods to add your own rules, return
`false, "handled"` from the wrapper when you've already told the user why —
the panel skips its own toast for that call. `Notify = false` silences it
entirely.

Each group is also public, so you can compose your own settings tab instead:

```lua
local tab = Window:CreateTab({ Name = "Settings", Icon = "gear" })
Uranium.Settings.InterfaceGroup(Window, tab)          -- accent / key / descriptions / toasts / HUD
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
field in Uranium (the `Image` control, a `Picker` item's `Image`,
`Player.Avatar`, a MediaPlayer track's `Cover`, the window `Logo`) runs its
value through `Uranium.Asset.resolve` first. That means all of these work,
interchangeably:

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
[art repo](https://github.com/funjimmywantstodie/uranium-public), which is
separate from the UI library's own repo. Commit a file to its `Assets/` folder
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