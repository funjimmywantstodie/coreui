# coreui

A dark-theme Roblox UI component library, written in Luau. `coreui/` is a
ModuleScript folder (`init.lua` is the entry point) that returns a library
table. The visuals and behavior port `../coreui referance` 1:1 to native Roblox
instances.

## Install

Sync the folder into your place with Rojo (or paste it in so the folder becomes
a `ModuleScript` named `coreui` whose children are `Theme`, `Icons`, `util/`,
`components/`). Put `example.lua` in a `LocalScript` beside it.

```
ReplicatedStorage/
  coreui/        ← this folder (ModuleScript)
StarterPlayerScripts/
  Demo (LocalScript)  →  require(path.to.coreui)
```

## Usage

```lua
local coreui = require(path.to.coreui)

local Window = coreui:CreateWindow({ Title = "coreui", Subtitle = "kit", Version = "v1.0.0" })
local Tab    = Window:CreateTab({ Name = "Home", Icon = "home" })
local Group  = Tab:CreateGroup({ Title = "Profile", Column = 1 }) -- 1 = left, 2 = right

local t = Group:Toggle({ Name = "Enable", Default = true, Callback = function(on) end })
t:Set(false)  print(t:Get())
```

- **Window** — `:CreateTab{Name,Icon}` · `:Notify{Title,Text,Type,Duration}` (Type: `success`/`info`/`warning`/`error`) · `:Select(i)` · `:SetAccent(Color3)`
- **Tab** — `:CreateGroup{Title,Column,Collapsed}`
- **Group / Section** — `:Section` `:Button` `:ButtonRow` `:Toggle` `:Slider` `:Dropdown`
  `:MultiDropdown` `:Input` `:Keybind` `:Colorpicker` `:Paragraph` `:Label` `:Divider`
  `:List` `:Player`

Stateful controls return a handle with `:Get()` / `:Set()`.

## Structure

```
init.lua            library table; CreateWindow
Theme.lua           color / metric / font tokens
Icons.lua           name → icon (asset id, Unicode glyph fallback)
util/Create.lua     instance factory + UI helpers
util/Tween.lua      shared tween presets
util/Context.lua    accent registry + popover manager (threaded to components)
components/          one file per component
```

## Icons

Icons are [Lucide](https://lucide.dev) vectors, packed into spritesheets in
`LucideData.lua` (the "48px" set). `Icons.lua` exposes them under short names
via an `ALIAS` table (e.g. `gear → settings`, `chev → chevron-up`,
`avatar → circle-user`). Lucide glyphs are solid white on transparent, so
`ImageColor3` recolors them freely — `text_dim` inactive, white active.

```lua
local icon = Icons.new("home", 20, Theme.Colors.text_dim) -- ImageLabel
Icons.tint(icon, Theme.Colors.white)                      -- recolor
Icons.apply(existingImageLabel, "search")                 -- onto an existing image
```

Short names: `home, layers, cursor, input, list, palette, person, gear, search,
avatar, min, max, close, chev, caret, ddchev, check`. Any unknown name falls
back to a Unicode glyph. To use a Lucide icon directly, pass its real name
(e.g. `Icons.new("zap", 16, color)`).
