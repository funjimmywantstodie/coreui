# coreui — Roblox Luau UI component library

A dark-theme UI component library for Roblox experiences. This folder is a
**complete, working reference implementation in HTML/CSS/JS** plus this spec.
The task is to port it into a **Luau `ModuleScript`** that returns a library
table scripts can `require()` to build menus.

The reference API was written to map 1:1 onto Luau. Reproduce the API and the
exact visuals using native Roblox instances — do **not** render HTML in Roblox.

## Files
- `reference/coreui-demo.html` — open in a browser to see the finished UI and play with every component.
- `reference/coreui.js` — library logic; **source of truth for the API and per-component behavior** (small, direct functions — read it top to bottom).
- `reference/coreui.css` — **source of truth for styling** (every token, size, radius, animation).
- `example.lua` — the demo rewritten in the target Luau API. **Build the library until this runs and looks like the HTML.**
- `PROMPT.txt` — the kickoff prompt.

## Fidelity
High-fidelity. The pixel values below are final and map 1:1 to Roblox offset
pixels. Match them exactly.

## Mounting
Create one `ScreenGui` (`IgnoreGuiInset = true`, `ResetOnSpawn = false`,
`ZIndexBehavior = Sibling`) and parent it to
`game.Players.LocalPlayer.PlayerGui`. Make the title bar draggable.

---

## Target API (reproduce this)

```lua
local coreui = require(path.to.coreui)

local Window = coreui:CreateWindow({
    Title = "coreui", Subtitle = "component kit", Version = "v1.0.0",
})

local Tab   = Window:CreateTab({ Name = "Home", Icon = "home" })
local Group = Tab:CreateGroup({ Title = "Profile", Column = 1 })  -- 1 = left, 2 = right

-- stateful controls return a handle with :Get() / :Set()
local t = Group:Toggle({ Name = "Enable", Default = true, Callback = function(on) end })
t:Set(false);  print(t:Get())
```

**Window**: `:CreateTab({Name, Icon})` → Tab · `:Notify({Title, Text, Duration})` · `:Select(i)` · `:SetAccent(Color3)`
**Tab**: `:CreateGroup({Title, Column, Collapsed})` → Group
**Group / Section** (a Section is a nested collapsible Group — same methods):

| Method | Handle | Options |
|---|---|---|
| `:Section({Title, Collapsed})` | container | nested collapsible |
| `:Button({Name?, Desc?, Label, Accent?, Callback})` | – | titled or bare |
| `:ButtonRow({ {Label,Callback}, ... })` | – | side-by-side |
| `:Toggle({Name, Desc?, Default, Callback})` | bool | |
| `:Slider({Name, Desc?, Min, Max, Step?, Default, Suffix?, Callback})` | number | |
| `:Dropdown({Name, Desc?, Options, Default?, Width?, Stack?, Callback})` | string | single |
| `:MultiDropdown({Name, Desc?, Options, Default?, Stack?, Callback})` | array | multi |
| `:Input({Name, Desc?, Placeholder?, Default?, Callback, OnEnter?})` | string | TextBox |
| `:Keybind({Name, Desc?, Default, Callback})` | KeyCode | |
| `:Colorpicker({Name, Desc?, Default, Presets?, Callback})` | Color3 | |
| `:Paragraph({Title?, Body})` | – | |
| `:Label({Key, Value?})` | `:Set(v)` | key/value row |
| `:Divider()` | – | |
| `:List({ {Name?, Value?, Text?, Dim?} })` | – | bullet list |
| `:Player({Username, DisplayName?, UserId?, Badge?, Avatar?})` | – | info panel |

---

## Design tokens (exact)

### Colors
| Name | Hex | Use |
|---|---|---|
| bg | `#0C0C0E` | window body |
| chrome | `#131315` | titlebar / sidebar / status bar |
| card | `#161618` | group card fill |
| pop | `#18181B` | dropdown / colorpicker / toast |
| control | `#1B1B1F` | input / dropdown / button fill |
| control_hi | `#232328` | hovered control |
| toggle_off | `#2C2C31` | toggle track (off) + slider track |
| knob | `#D6D6DB` | toggle knob off (slider/on knob = `#FFFFFF`) |
| border | `#262629` | card/control borders, dividers |
| border_soft | `#1F1F22` | between-field dividers |
| text | `#EDEDF0` | primary text |
| text_muted | `#8C8C94` | secondary text / descriptions |
| text_dim | `#5F5F67` | placeholders, inactive icons, chevrons |
| accent | `#F2680C` | active nav, toggle-on, accent button, focus |
| accent_2 | `#FF8A3D` | accent hover / gradient top |

`accent` is themeable — `Window:SetAccent(c)` stores it and recolors all
accent-using instances live (the demo's first color picker does this).

### Metrics (offset px, 1:1)
| Element | Value |
|---|---|
| Window | 780 × 560, corner radius 12 |
| Titlebar 50 · Status bar 34 · Sidebar 64 | |
| Nav button | 40 × 40, radius 11; active = accent fill + white icon + soft accent glow |
| Content padding | 18 / 22 / 26 |
| Two columns | even split, 1px `border_soft` divider, 24px gap |
| Group card | radius 9, 1px `border` stroke, 14px side padding |
| Group title | 13px / 500 / `text_muted`, chevron right |
| Field | 10px vertical padding, 1px `border_soft` bottom divider (none on last) |
| Field name 13px `text` · desc 11.5px `text_muted` (3px below) | |
| Control radius (input/dropdown/button) | 7 |
| Toggle | 42 × 23 pill, knob 17, travel +19px |
| Slider | track 6 pill, fill = accent, knob 15 white |
| Dropdown box | height 32; menu radius 8, max-height 210 |
| Input 36 · Button 36 | |
| Avatar | 56 × 56, radius 14, accent gradient |

### Type & animation
- UI font **Inter** → use `Enum.Font.Gotham` family (`GothamBold` titles, `GothamMedium` labels) or `Font.fromName("Inter")` if available.
- Mono (keybind/hex) → `Enum.Font.Code`.
- All tweens ease-out ~0.12–0.18s via `TweenService`:
  - Toggle: tween knob `Position` + track `BackgroundColor3` (0.18s).
  - Dropdown/colorpicker: show popover below at high `ZIndex`; chevron rotates 180°.
  - Slider: live drag via `UserInputService` (no tween).
  - Collapse: toggle card/section `.Visible`; chevron rotates 180°.
  - Toast: slide+fade in 0.22s, auto-dismiss after `Duration` (default 3.2s), slide out 0.25s, then `Destroy()`.

### Icons
The reference keys icons by name (`home, layers, cursor, input, list, palette,
person, gear, search, min, max, close, chevron, caret, check, avatar`). Replace
with `ImageLabel`s using Roblox asset ids (or an icon sheet). Sidebar icon 20px,
tinted `text_dim` inactive / white active.

---

## Component → Roblox instances
- **Window**: `ScreenGui` → main `Frame` (`UICorner` 12, `UIStroke`) → titlebar / body / status bar. Body = sidebar `Frame` + content `ScrollingFrame` (`AutomaticCanvasSize = Y`, `CanvasSize = 0`).
- **Sidebar**: vertical `UIListLayout`; nav items are `TextButton` (40×40, `UICorner` 11) with an `ImageLabel`.
- **Columns**: a row container with two `Frame`s, each a vertical `UIListLayout` + `AutomaticSize = Y`; 1px divider `Frame` between.
- **Group**: `Frame` → header `TextButton` (title + chevron) + card `Frame` (`UICorner` 9, `UIStroke`, `UIListLayout` + `UIPadding`). Header toggles card `.Visible`.
- **Field**: `Frame` with a left text block (name + desc `TextLabel`s) and the control on the right; stacked variants put the control full-width below.
- **Toggle**: track `Frame` + knob `Frame`, both full `UICorner`; tween on click.
- **Slider**: track `Frame`, fill `Frame` (X = pct), knob `Frame`; drag via `UserInputService`; clamp + step; update value `TextLabel`.
- **Dropdown / MultiDropdown**: box `TextButton`; popover `Frame` (high `ZIndex`) with a `UIListLayout` of option `TextButton`s. Single sets value + closes; multi toggles a check `ImageLabel` per option, stays open. Close on outside click.
- **Input**: `TextBox` (`ClearTextOnFocus = false`); accent stroke on focus; `Callback` on text change; `OnEnter` on `FocusLost(enterPressed)`.
- **Keybind**: `TextButton`; on click show "...", connect one-shot `UserInputService.InputBegan`, capture `input.KeyCode`.
- **Colorpicker**: swatch `TextButton` + popover with preset `TextButton`s (`UIGridLayout`) and hex `TextLabel`.
- **Notification**: bottom-right container `Frame` (high `ZIndex`) + vertical `UIListLayout`; each toast a `Frame` with a left accent bar.

## Suggested module layout
```
coreui/
  init.lua            -- library table; CreateWindow
  Theme.lua           -- token tables above
  Icons.lua           -- name -> rbxassetid
  util/Create.lua     -- instance factory
  util/Tween.lua      -- shared tween presets
  components/
    Window.lua Tab.lua Group.lua
    Toggle.lua Slider.lua Dropdown.lua Input.lua
    Keybind.lua Colorpicker.lua Button.lua
    Paragraph.lua Label.lua Player.lua Notify.lua
```
Build until `example.lua` runs and matches `reference/coreui-demo.html`.
