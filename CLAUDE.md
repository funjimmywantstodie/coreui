# coreui — agent guide

Dark-theme Roblox UI component library in Luau. `coreui/` is a ModuleScript tree
(`init.lua` = entry) that ports `coreui referance/reference/*` (HTML/CSS/JS mock)
1:1 to native Roblox instances. Read this before rescanning — it captures the
architecture, build flow, conventions, and the current animation state.

## Build & push — DO NOT hand-edit the bundle

`coreui.bundle.lua` is **generated**. Never edit it directly. Source of truth is
the `coreui/` tree.

- `python3 bundle.py` → flattens `coreui/` into `coreui.bundle.lua`.
- `python3 push.py "msg"` → runs bundle.py, `git add -A`, commit, push, then
  copies a **commit-pinned** loadstring (`…/<sha>/coreui.bundle.lua`) to the
  clipboard. Use the per-commit URL, not the branch URL: raw.githubusercontent
  CDN-caches each path ~5 min and ignores `?` busters, so `…/main/…` goes stale.

After any change to `coreui/`, rebuild with `bundle.py` (or `push.py` to ship).
The bundle prints `[coreui] build <timestamp> <sha>[-dirty]` on load so you can
confirm the executor is running the fresh build.

**How the bundle works:** `loadstring` runs one chunk, so bundle.py wraps each
module in `__modules[key] = function() … end`, rewrites every
`require(script.Parent.X)` → `__require("resolved.key")`, and returns
`__require("")` (root = init.lua). Module keys: `init.lua`→`""`,
`components/Window.lua`→`"components.Window"`.

**Icon tree-shaking:** bundle.py parses `Icons.lua`'s `ALIAS` table + literal
`Icons.new("name"…)` / `Icons.apply(…,"name")` calls, keeps only those entries
from `LucideData`'s `48px` set, and drops the `256px` set entirely (~2/3 of the
raw size). A name with no 48px entry degrades to a Unicode glyph (no error). If a
consumer passes a raw Lucide name not present in source, add it to `EXTRA_ICONS`
in bundle.py.

## Architecture

```
coreui/
  init.lua            library table; only :CreateWindow
  Theme.lua           design tokens — colors / metrics (offset px) / fonts
  Icons.lua           short-name → Lucide sprite (Unicode glyph fallback)
  LucideData.lua      icon spritesheet data (tree-shaken at bundle time)
  util/
    Create.lua        instance factory + corner/stroke/padding/listLayout helpers
    Tween.lua         shared TweenInfo presets + Tween.play
    Context.lua       per-window object threaded into EVERY component
    Collapse.lua      height-animate a frame open/closed
  components/         one file per control
```

**Component signature:** each `components/*.lua` returns
`function(ctx, parent, opts)` (Window is the exception — `coreui:CreateWindow`
calls `Window(options)`). `ctx` is the `Context` object; thread it through to
children. Stateful controls return a handle with `:Get()` / `:Set(v)`.

**Public API surface** (see `example.lua` — it's the spec, written in the target
API; build until it runs and matches `reference/coreui-demo.html`):
- `coreui:CreateWindow{Title,Subtitle,Version,ConfigFolder?,ToggleKey?}` →
  `:CreateTab` · `:CreateSettingsTab{Name?,Icon?}` · `:Notify` · `:Select(i)` ·
  `:SetAccent(Color3)` · `:SetToggleKey(KeyCode)` · `:SetNotificationsEnabled(b)` ·
  `:SaveConfig(name)` · `:LoadConfig(name)` · `:DeleteConfig(name)` ·
  `:ListConfigs()` · `:Destroy()`
- `Tab:CreateGroup{Title,Column,Collapsed}` (Column 1=left, 2=right)
- Group/Section: `:Section :Button :ButtonRow :Toggle :Slider :Dropdown :MultiDropdown :Input :Keybind :Colorpicker :Paragraph :Label :Divider :List :Player`
- Stateful controls take an optional `Flag = "id"` → captured by config save/load.

## Config & settings (Flag system)

Any stateful control built with `Flag = "id"` is registered in `ctx.Flags` by
`Controls.mount` (`util/Context.lua` → `RegisterFlag/GetConfig/LoadConfig`).
`GetConfig` snapshots every flag to a JSON-safe table via per-kind codecs (Color3
→ hex, `Enum.KeyCode` → name); `LoadConfig` decodes + `:Set`s them (firing
callbacks). `util/Config.lua` is the executor filesystem layer — feature-detected
(`Config.supported`) and fully pcall-guarded so it no-ops in Studio. Configs are
JSON at `<ConfigFolder>/configs/<name>.json`; `<ConfigFolder>/autoload.txt` holds
the auto-load pointer.

`Window:CreateSettingsTab()` is a drop-in panel (accent picker, the toggle
keybind, notifications switch, config save/load/delete + auto-load, Unload). Its
controls are themselves flagged, so saving a config captures them too. **Call it
LAST** — its deferred auto-load pass only sees flags registered before it runs.
Dropdown gained `handle:SetOptions(list)` for refreshing the saved-config list.

## Key utilities

**Create** (`util/Create.lua`): `Create(className, props, children)`. Props
assigned in order, `Parent` applied LAST (children exist first). Helpers:
`Create.corner(r)`, `Create.stroke(color, thickness?)` (round joins — avoids
jagged corners), `Create.padding(t,r?,b?,l?)`, `Create.listLayout(props?)`.

**Context** (`util/Context.lua`): carries live `Accent`/`AccentHover`, an accent
subscription registry, and the single-popover manager.
- `ctx:RegisterAccent(fn)` — `fn(accent, hover)` runs now + on every SetAccent
  (used for live re-theming via the Colorpicker → `Window:SetAccent`). Don't
  duplicate the initial paint; RegisterAccent already calls fn once.
- `ctx:OpenPopover(menu, anchor, onClose?)` / `:ClosePopover()` / `:IsOpen(menu)`
  — dropdowns & colorpickers mount their menu into the high-ZIndex `overlay` so
  it escapes the scrolling content's clipping. Auto-clamps to window bounds and
  flips above the anchor when no room below. A `CanvasGroup` menu fades in via
  one `GroupTransparency` tween.

**Collapse** (`util/Collapse.lua`): `Collapse.wrap(content, startCollapsed)` →
`(holder, set)`. `content` must be `(1,0)` wide with `AutomaticSize.Y`. Holder
clips + owns the animated height; tracks content via AutomaticSize while open,
switches to manual offset height during the tween. `set(collapsed, animate?)`.

## Conventions

- `--!strict` at top of every Luau module (generated/data files use `--!nocheck`).
- Colors via `Color3.fromHex(...)`; pull from `Theme.Colors`, never hardcode.
- **Fonts: set `FontFace` (NOT `Font`).** `Font` uses bitmap atlases → soft/
  pixelated scaling; `FontFace` uses the SDF renderer → crisp at any size. Use
  `Theme.Font.{Bold,Medium,Regular,Mono}`.
- Metrics in `Theme.Metrics` are offset px (map 1:1 to Roblox offsets).
- Recent layout work moved frame sizing toward **scale** dimensions for layout
  stability (see git log).
- A chevron/icon that must rotate cannot be inside a `UIListLayout` (the layout
  suppresses child Rotation) — position it manually. See Group.lua header.

## Animation state (already tuned — leave unless asked)

`Tween.lua` presets, all ease-out unless noted:
`Fast 0.12` (hovers/borders) · `Normal 0.18` (toggle/chevron) · `Spin 0.26 Back`
(collapse chevrons, slight overshoot) · `Spring 0.28 Back` (knobs/pops) ·
`Press 0.09` (button squash) · `Pop 0.16 Back` (popovers/window-in) ·
`Slide 0.22 Quint` (panel collapse/expand, search reveal — no overshoot) ·
`MenuOut`/`ToastOut` (accelerate-in, leaving) · `Toast 0.22 Quint`.

Already animated, considered good: hover fades, toggle knob slide, button press
squash, dropdown menu fade-in, chevron spins, toast slide/fade, window
mount/minimize/close, nav button crossfade + icon pop.
