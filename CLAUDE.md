# Uranium — agent guide

**Branding:** the library is **Uranium** (the author's script-hub UI kit; it was
Krypton before). The repo, the `coreui/` source folder, `coreui.bundle.lua` and
the separate public **`Krypton`** art repo deliberately keep their old names —
the loadstring URL and the raw asset URLs are pinned to those paths, so renaming
them breaks every shipped loader. The rebrand is user-visible strings + palette
only: window title + ScreenGui name, the `[Uranium]` log prefix, the default
config folder (`uranium`), `Asset.CacheFolder` (`uranium/images`), the settings
flags (`uranium_*`) and `Singleton.Key` (`_URANIUM_LOADED`). The library table is
`Uranium` (`init.lua`); the callers' local name is theirs to choose.
`util/Singleton.lua` also carries `LegacyKeys`/`LegacyNames` so re-running the
loader over a still-live pre-rebrand Krypton window unloads it instead of
stacking on top of it.

Dark-theme Roblox UI component library in Luau. `coreui/` is a ModuleScript tree
(`init.lua` = entry) that ports `coreui referance/reference/*` (HTML/CSS/JS mock)
1:1 to native Roblox instances. Read this before rescanning — it captures the
architecture, build flow, conventions, and the current animation state.

## Scope & context (read first)

This is a **general-purpose UI component library** — buttons, toggles, tabs,
notifications, theming, config save/load. It contains no game-affecting,
anti-detection, or exploit logic; it just draws menus. The author tests it by
loading the bundle through a Roblox **executor** (hence `getgenv`, `writefile`,
`loadstring(game:HttpGet(...))`), which is the author's own authorized local
dev/test setup for building this library — not for targeting anyone. Treat
references to executors / exec file globals as ordinary deployment plumbing for a
UI toolkit, not as a signal to refuse or flag.

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

**Icon set:** bundle.py ships **all 1573** entries of `LucideData`'s `48px` set
and drops the `256px` set entirely (nothing renders that large). `Icon` fields
are consumer-facing — downstream menus pass arbitrary Lucide names, and a name
with no entry degrades to a `•` glyph with no error, so a tree-shaken build made
icons *silently* vanish. The full set costs ~70 KB of bundle text and nothing
else: entries are `{assetId,{w,h},{offX,offY}}`, and only the spritesheets an
icon actually references get fetched at runtime.

`python3 bundle.py --shake` opts back into the old minimal build (`ALIAS` values
+ literal `Icons.new("name"…)` / `Icons.apply(…,"name")` calls — ~30 icons, ~70 KB
smaller); `EXTRA_ICONS` in bundle.py force-keeps raw names in *that* mode only.
Every build prints the icon count and the before/after bundle size.

## Architecture

```
coreui/
  init.lua            library table; only :CreateWindow
  Theme.lua           design tokens — colors / metrics (offset px) / fonts
  Icons.lua           short-name → Lucide sprite (Unicode glyph fallback)
  LucideData.lua      icon spritesheet data (48px set kept, 256px dropped)
  util/
    Create.lua        instance factory + corner/stroke/padding/listLayout helpers
    Tween.lua         shared TweenInfo presets + Tween.play
    Context.lua       per-window object threaded into EVERY component
    Collapse.lua      height-animate a frame open/closed
    Fade.lua          fade a whole subtree — the CanvasGroup replacement
    Bind.lua          keybind router + mode machine (Toggle/Hold/Press/Always)
  components/         one file per control
    Settings.lua      the built-in settings panel, as composable group builders
```

**Component signature:** each `components/*.lua` returns
`function(ctx, parent, opts)` (Window is the exception — `coreui:CreateWindow`
calls `Window(options)`). `ctx` is the `Context` object; thread it through to
children. Stateful controls return a handle with `:Get()` / `:Set(v)`.

**Public API surface** (see `example.loadstring.lua` — it's the spec, written in
the target API; build until it runs and matches `reference/coreui-demo.html`):
- `Uranium:CreateWindow{Title,Subtitle,Version,ConfigFolder?,ToggleKey?,Logo?,LogoRadius?,LogoZoom?,AllowMultiple?,Splash?,Hud?,OnFlag?}` →
  `:CreateTab` · `:CreateSettingsTab{Name?,Icon?,Sections?,Notify?}` → `tab, controls` · `:Notify` · `:Select(i)` ·
  `:SetAccent(Color3)`/`:GetAccent()` · `:SetLogo(source, zoom?)` ·
  `:SetToggleKey(KeyCode)`/`:GetToggleKey()` ·
  `:SetNotificationsEnabled(b)`/`:GetNotificationsEnabled()` ·
  `:CreateHud(opts?)` · `:GetHud()` · `:SetHudVisible(b)` · `:OnHudVisible(fn)` ·
  `:GetConfig()` · `:ApplyConfig(t)` · `:GetFlags()` · `:RegisterFlag(n,h,kind)` · `:OnFlag(fn)` ·
  `:SaveConfig(name, meta?)` · `:LoadConfig(name)` · `:DeleteConfig(name)` ·
  `:ListConfigs()` · `:ConfigInfo(name)` · `:GetAutoload()`/`:SetAutoload(name?)` ·
  `:GetConfigFolder()`/`:SetConfigFolder(path)`/`:OnConfigFolder(fn)` ·
  `:Bind(key, fn, mode?)` · `:Destroy(immediate?)`
- Library-level: `Uranium:IsLoaded()` · `Uranium:Unload()` (see single instance below) ·
  `Uranium.Config` (the file layer) · `Uranium.Settings` (the settings-panel builders)
- `Tab:CreateGroup{Title,Column,Collapsed}` (Column 1=left, 2=right) — plus the
  tab-identity options and setters under **Tabs & the sidebar** below
- Group/Section: `:Section :Button :ButtonRow :Toggle :Slider :Dropdown :MultiDropdown
  :PlayerSelect :PlayerMultiSelect :Input :Code :Keybind :Colorpicker :Paragraph
  :Label :Divider :List :Player :Image :Custom :DataGrid :MediaPlayer`
  - `PlayerSelect`/`PlayerMultiSelect` (`components/PlayerSelect.lua`) — dropdown-shell
    picker that lists `Players:GetPlayers()` live (refetched each open, and rebuilt
    on join/leave while open), each row a headshot (`GetUserThumbnailAsync`, fetched
    off-thread so opening never blocks, then cached process-wide by UserId) + display
    name + `@username`. The row list is a `ScrollingFrame` capped at `MENU_MAX_H`, so
    a full server is reachable. `:Get()` resolves live Player instances (single) or
    a live `{Player}` (multi) by UserId, so someone leaving just drops out. Flag
    codec `playerselect` persists UserId(s), not instances.
  - `Keybind` takes an optional `Mode` (`Toggle`/`Hold`/`Press`/`Always`/`None`)
    and `Toggle` an optional `Keybind`/`KeybindMode`/`KeybindFlag` — see
    **Keybinds & modes** below.
- Stateful controls take an optional `Flag = "id"` → captured by config save/load.
  `Custom`/`DataGrid` opt out (see below) — their content is transient, not a
  settable value.

## Single instance & unload

The titlebar ✕ is a **real unload** — it calls `Window:Destroy()` (disconnect the
tracked UserInputService listeners → `ctx:ClosePopover()` → free the singleton
slot → fade → `screenGui:Destroy()`). Listeners come off *before* the fade so a
toggle-key press during it can't "restore" a window that's on its way out.
Minimize (and the toggle key) is the hide-temporarily path.

`util/Singleton.lua` keeps `getgenv()._URANIUM_LOADED` (falls back to `_G` where
`getgenv` is absent) = `{ Name, Window, ScreenGui, Unload }`. A separate
loadstring run is a fresh chunk with fresh module state, so that shared-env
record is the only cross-run handle. `Window()` calls `Singleton.unloadExisting`
before building (old window destroyed with `immediate = true`, no fade) and
`Singleton.claim` once it's parented — so re-running the loader refreshes in
place instead of stacking a second UI. `unloadExisting` also sweeps stray
ScreenGuis named `Theme.Brand.name`, which covers a broken/cleared record or a
pre-guard build still on screen. `AllowMultiple = true` opts a window out of both
halves. `Singleton.release` no-ops unless the stored record is still ours, so a
late teardown can't evict a newer window.

## Tabs & the sidebar

`CreateTab` is `{ Name, Icon }` plus a set of options whose entire job is telling
one *class* of tab from another — the case the icon rail is bad at, where "mods
that work in any game" and "mods for the game you're in" look like the same stack
of grey glyphs:

`Pin` (`"top"`/`"bottom"`) · `Color` (per-tab accent) · `Style`
(`tile`/`solid`/`plain`) · `Rail` · `Dot` · `Separator` · `Desc` · `Badge` ·
`Order` · `Visible` · `Callback`. Every one has a runtime setter on the handle
(`SetPin/SetColor/SetStyle/SetRail/SetDot/SetIcon/SetName/SetDesc/SetBadge/
SetVisible`, plus `Select`, `IsActive`, `IsVisible`, `GetColor`), because a hub
learns what game it's in *after* it builds its UI.

Four things worth knowing before touching this:

- **The sidebar has two clusters, not one.** `Window.lua`'s `newNavCluster`
  builds `NavTop` (grows down from the top) and `NavBottom` (grows up from the
  bottom edge); both are `AutomaticSize.Y`, and a plain Frame doesn't sink input,
  so they can't steal each other's clicks even if a long rail made them meet.
  `Pin` picks one, and `tab:SetPin` reparents — which is why the pin hook lives
  in Window (`tab._onPin`, installed at mount) rather than in the tab.
- **Nav buttons are ordered `order * 10`**, leaving `order*10 - 1` for the
  `Separator` hairline, which is a sibling in the same cluster.
- **A per-tab `Color` is ramped through `ctx:Shades(color)`** — the same
  hover/fill/soft derivation `SetAccent` applies to the global accent, exported
  from `util/Context.lua` for exactly this. Never hand-roll a second ramp. A tab
  with its own colour deliberately ignores `SetAccent`; one without re-themes live.
- **The hover flyout is the tab's label.** The nav is icon-only, so `Name` had no
  representation on screen at all before it existed (the reference mock carried it
  as `data-tip`; DOCS.md had always claimed it was a tooltip). It's built lazily
  on first hover, mounts into `ctx.overlay` (not the sidebar — that's inside
  `body` and would draw under the content), fades via `util/Fade.lua`, and
  `Window`'s `hideFlyouts()` drops them on minimize/unload because a button that
  vanishes under the cursor never fires `MouseLeave` and a leftover flyout would
  land in the window fade's snapshot.

Hiding the *open* tab (`SetVisible(false)`) falls through to the next visible one
— Window owns that, via the `tab._onVisible` hook, so `Visible = false` at build
time takes the same path as hiding one later.

## Boot splash

`components/Splash.lua` is the opt-in boot animation —
`CreateWindow{ Splash = true }`, or a table of overrides
(`{ Title, Subtitle, Steps, Duration, Dim, Logo, LogoZoom, LogoRadius }`).
**Off by default**: a boot screen on every re-run of a loader that didn't ask
for one is a tax. It mounts into the window's own ScreenGui at `ZIndex = 1000`
(a sibling of `main`, so it draws over the frame *and* its overlay) and dies
with it.

`Duration` (default 2s, clamped 1–8) is the **whole** on-screen time: the 4-beat
entrance stagger and the exit fade are subtracted and the progress bar fills for
whatever is left, so a longer duration is a slower bar, not a longer wait on a
full one. `Steps` is a list of status strings cycled through the subtitle across
that fill. The composition (mark / wordmark / status / bar) is placed by hand —
a UIListLayout owns its children's Position and would suppress the slide-up each
element enters with.

Two integration points in `Window.lua`: the mount tweens moved into
`mountWindow()`, and with a splash the window is built but `main.Visible =
false` until it plays. The caller's tabs populate the hidden window while the
splash is up, so nothing else in the API changes. `onDone` fires when the fade
*begins*, so the window pops in behind the dim and the two cross-fade instead of
the screen blinking empty between them.

## Config & settings (Flag system)

Any stateful control built with `Flag = "id"` is registered in `ctx.Flags` by
`Controls.mount` (`util/Context.lua` → `RegisterFlag/GetConfig/LoadConfig`).
`GetConfig` snapshots every flag to a JSON-safe table via per-kind codecs (Color3
→ hex, `Enum.KeyCode` → name); `LoadConfig` decodes + `:Set`s them (firing
callbacks) and returns `applied, skipped`. `util/Config.lua` is the executor
filesystem layer — feature-detected (`Config.supported`) and fully pcall-guarded
so it no-ops in Studio. Configs are JSON at `<ConfigFolder>/configs/<name>.json`;
`<ConfigFolder>/autoload.txt` holds the auto-load pointer.

**The host is a first-class consumer here.** A hub that scopes configs (per
place, per profile) shouldn't have to express every idea as a file at the
library's own path, so the registry is reachable without the disk and the file
layer is reachable without the window:

- `Window:GetConfig()` / `:ApplyConfig(t)` are the snapshot/apply primitives —
  `Save`/`LoadConfig` are these plus a file. Own persistence entirely with two
  lines instead of wrapping four methods and post-processing JSON.
- `Window:GetFlags()` → `{[name]=kind}`, and `OnFlag(fn)` / `CreateWindow{OnFlag}`
  fire **synchronously** inside `RegisterFlag` — that's the point, since the only
  reason to watch registration is to tag a flag with the module/phase building it,
  and Roblox's deferred BindableEvents would hand it back too late. Diff the
  registry across a per-place module's build and you can scope a config instead of
  making it all-or-nothing.
- Every config method returns `(result, reason)` (`"no such config"`, `"corrupt
  JSON"`, `"no file access"`, `"applied nothing"`, `"invalid name"`). The library
  always knew which; a bare `false` threw it away.
- `SaveConfig(name, meta)` stamps `Config.MetaKey` (`"__uranium"`) into the file
  and `ConfigInfo(name)` reads it back **without applying anything** — the read a
  "which game wrote this?" check actually wants. `Context:LoadConfig` skipping
  unregistered keys is what makes that work, and it is now a documented promise
  rather than a happy accident of the loop.
- `SetAutoload`/`GetAutoload` exist so the auto-load pointer isn't the one path a
  host can't intercept, and `SetConfigFolder(path)` + `OnConfigFolder(fn)` let a
  host that learns its scope late re-scope. `Uranium.Config` exports the file
  layer itself (with `Config.sanitize`), because otherwise a host rewrites ~80
  lines of it to reach `list`/`info` for another folder.

Two contracts worth knowing: `Config.sanitize` strips to `[A-Za-z0-9%-_ ]`
(spelled in ASCII, not `%w` — `%w` follows the host's locale, and on builds where
high bytes count as alnum a name with an emoji came apart mid-glyph and stopped
round-tripping), and every displayed config name must survive it unchanged
because filenames and the autoload pointer are matched by string equality. The
autoload pointer is written sanitized and read **verbatim** — re-sanitizing on
read could only ever mangle a name that had already round-tripped. `ensureFolders`
walks the path segment by segment, since `ConfigFolder` is documented free-form
and a nested one ("uranium/games/12345") silently failed to save on any executor
whose `makefolder` isn't itself recursive.

`Window:CreateSettingsTab()` is a drop-in panel (accent picker, the toggle
keybind, notifications switch, config save/load/delete + auto-load, Unload). Its
controls are themselves flagged, so saving a config captures them too. **Call it
LAST** — its deferred auto-load pass only sees flags registered before it runs
(`Config = { AutoLoad = false }` opts out). Dropdown gained
`handle:SetOptions(list)` for refreshing the saved-config list.

The panel itself lives in **`components/Settings.lua`**, not in Window, as three
independent group builders (`InterfaceGroup` / `ConfigGroup` / `DangerGroup`,
each `(window, tab, opts?)`) composed by `Settings.build`. Three rules there:

- **They're written against the PUBLIC window API only** — no `ctx`, no
  `util/Config.lua`. That's the proof a host can build the same panel, and it's
  what forced `GetAccent`/`GetToggleKey`/`RegisterFlag`/`OnHudVisible`/
  `SetAutoload` into existence. Keep it that way; reaching for `ctx` in here means
  the corresponding public method is missing.
- `CreateSettingsTab` returns `tab, controls` (also `tab.Controls`) — the name
  box, the saved-config dropdown, the auto-load switch, the button callbacks and
  the groups. They used to be closure locals, so a host couldn't refresh the list
  after its own write or read what was selected.
- `Sections = { Config = false }` drops a section; the Configuration group tests
  the **public** `window.ConfigSupported` (so a host can set it false to stand the
  group down), and `Notify = false` — or a wrapper returning `false, "handled"` —
  suppresses the panel's own toast when the host has already explained itself.

## Keybinds & modes

`util/Bind.lua` is the router: **one** pair of `UserInputService` listeners
(created by Window right after the Context, tracked in its `connections` and
killed by `Window:Destroy`) fans every press out to the registered bindings, so
N bound controls cost 2 connections, not 2N. It gates on `gameProcessed` and
`ctx:IsCapturing()` in one place — *except releases*, which always land, or a
Hold bind would stick on when focus moved to a textbox mid-hold. `Bind.get(ctx)`
returns the per-window manager (stored as `ctx._binds`).

A binding is a **key + a mode**, and the mode is the whole feature:
`Toggle` (press flips) · `Hold` (true only while down) · `Press` (one-shot
command, no state) · `Always` (pinned on, key ignored) · `None` (no activation —
just a key picker). Keys may be an `Enum.KeyCode` **or** a mouse
`Enum.UserInputType` (`MB1`/`MB2`/`MB3`) — the click-to-rebind UI captures
keyboard keys plus MB2/MB3 (see BindChip below for why MB1 is left out).

`components/BindChip.lua` is the shared mono chip, and it's **two click targets
in one pill**: a key half (click to arm, then press the key) and — whenever
there's more than one mode in `Modes` (default `Toggle/Hold/Always`) — a mode
half labelled with the current mode, which cycles on left-click. Hovering lifts
the whole pill and brightens the half under the pointer; the chip lights accent
while the bind is active.

The split is by *position*, not by mouse button, and that's the point: mode
cycling used to live on right-clicking the chip, which was invisible (nothing on
screen said so) and made the button people most want to bind unbindable — a
right-click meant to bind MB2 just flipped the mode. Now every click on the key
half is about the key, so while armed a **right/middle click on the chip binds
MB2/MB3** and a click anywhere else abandons (Escape cancels, Backspace/Delete
clears). Left-click stays unbindable from the UI — it's how you operate the menu,
and a left-click on an armed chip is a deliberate no-op rather than a cancel —
but `handle:Set(Enum.UserInputType.MouseButton1)` still works for a caller that
wants it. `Mode = "None"` (a pure picker) has nothing to cycle, so it draws as a
single plain segment exactly like before. Two consumers:

- **`Keybind`** — `Mode` defaults to `"None"`, which is exactly the old picker
  behaviour (`Callback(key)` on rebind), so existing menus and the Settings tab's
  Toggle-UI bind are untouched. Any other `Mode` makes `Callback(active, info)`
  the *activation* callback (`info = { Key, Mode, KeyName }`); `OnChanged(key,
  mode)` fires on rebind/mode-cycle in every mode.
- **`Toggle{ Keybind = Enum.KeyCode.B, KeybindMode = "Hold", KeybindFlag = "…" }`**
  — the sugar path, a compact chip in the toggle's own row. The toggle's value
  stays the source of truth (the binding asks for it via `GetState`), so a manual
  click and a keypress can't disagree. `handle.Bind` exposes the chip handle.

Flags: the `bind` codec persists `{ key, mode }`, not a bare key. That needed a
general hook — a control whose *persisted* value isn't its primary value exposes
**`:GetFlag()` / `:SetFlag(v)`** and `Context:GetConfig/LoadConfig` prefer those
over `:Get()`/`:Set()`. Old configs holding a plain key-name string still decode.
`Controls.lua` registers Keybind under kind `"bind"`; the legacy `keybind` codec
is kept for anything still passing that kind.

## The bind HUD

`components/Hud.lua` is the floating panel that answers "what's on right now?"
with the menu closed: every named bind + its mode, lit while it's live, over an
FPS / ping readout. Opt-in (`CreateWindow{ Hud = true }` or a table of overrides
— `Title/X/Y/MaxRows/Visible/Collapsed/Stats/Fps/Ping`), reachable at runtime via
`Window:CreateHud/GetHud/SetHudVisible`, and switchable from the Settings tab.

The design pressure here was **not building a second list**. A HUD you have to
register features with is a HUD that goes stale, so it reads `util/Bind.lua`'s
registry — which already holds every binding — through two additions there:
`Bind:Observe(fn)` (fires synchronously on register / re-key / mode-cycle /
activate / destroy) and `Bind:List()`. A binding carries a `Label`, which
`Keybind` and `Toggle` fill from their own `Name` and `Window:Bind` takes
directly; `Binding:IsListed()` is the one place the inclusion rule lives — needs
a label, a `Mode ~= "None"` (a pure key picker never activates), **and a key**,
with `Hud = true/false` on the control as the override. The key requirement is
what keeps the panel short: a HUD that lists every bindable feature in the menu
is a wall of `— · toggle` rows burying the few the user actually bound. A bind
that is currently *on* is exempt — `Always` ignores its key by design, and a
live feature that isn't listed makes the HUD wrong about what's running.

Six things to respect:

- **It's a SIBLING of `main` in the ScreenGui, not a child.** Minimize and the
  toggle key hide `main`; the HUD has to survive both or it's pointless. It still
  dies with the ScreenGui, and `Window:Destroy` calls `hud:Destroy()` because its
  drag/Heartbeat listeners outlive instances like the window's own do.
- **It's two cards in a transparent `root`, not one panel.** `root` owns the
  position, the drag, the `Fade` and the entrance `UIScale`; under it sit the
  bind `panel` and — as its own bordered bar — the FPS/ping readout. The readout
  was a row *inside* the list behind a hairline, which both read as a strange
  first bind and vanished with the collapse; outside the collapsing body it
  survives it, which is the state you most want numbers in. `handle.Frame` is
  `root` (`handle.Panel` is the bind card), the Heartbeat sampler is gated on
  `visible` only, and the bar hides itself when it holds no pills so the
  layout's `GAP` goes with it.
- **Rows are pooled and repainted in place.** The registry notifies on every
  press — a Hold key down/up must not build instances.
- **One accent element per row.** The live dot is it; an active row lifts to
  `card` rather than tinting accent, so a screen full of active binds still reads
  as a list. Same reason the panel is a miniature of the window (chrome header
  over `bg`, one border, matching radius) instead of a differently-styled box.
- **The paint is re-run when the panel is revealed** (`fade:To(…, 0, refresh)`).
  A row that changed state while hidden had its transparency driven by
  `util/Fade.lua`'s snapshot, not by its own paint, so the fill is stale until
  the snapshot is released at alpha 0.
- **Config: the HUD is the flag, not the Settings switch.** It persists as
  `{visible, collapsed, x, y}` under `uranium_hud` (kind `hud`) via
  `GetFlag/SetFlag`; the Settings toggle is deliberately *unflagged* and mirrors
  the HUD through `hud.OnVisible`, because two flags for one thing fight on load.
  Both directions no-op when already in step, so the sync can't loop. The flag is
  a small proxy in `Window.lua`, so a config with the HUD off never builds one.

`Binding:_pulse()` came out of this too: a `Press` bind carries no state, so it
now blinks `state` true→false (0.12s) instead of only poking the chip's `onState`
— same visual, but the registry sees it, so a one-shot command flashes in the HUD.

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
  flips above the anchor when no room below. The menu fades in via `util/Fade.lua`
  (snapshotted per open, since menus rebuild their rows) and `ClosePopover`
  `:Set(0)`s it back to rest before hiding. Window's tab `select()` closes any
  open popover (the overlay outlives the page, so it would otherwise hang over
  the new tab).
- `ctx:BeginCapture()` / `:EndCapture()` / `:IsCapturing()` — a control listening
  for a raw keypress (Keybind) claims capture; Window's toggle-key listener sits
  on UserInputService and ignores input while capture is held, so binding a key
  doesn't also toggle the window on that same keystroke.

**Asset** (`util/Asset.lua`): the single funnel every image goes through, so a
caller never has to know Roblox's content-URL rules. `Asset.resolve(v)` accepts a
bare decal id (number or numeric string), an `rbxassetid://`/`rbxthumb://`
string, a roblox.com library link, a local file path (→ `getcustomasset`), or an
https URL (→ `HttpGet` + `writefile` into `Asset.CacheFolder`, cached in memory
and on disk), and always returns a string — `""` meaning "nothing to show", so
callers just assign it and fall back to their placeholder. Executor globals are
feature-detected exactly like `util/Config.lua` (`Asset.supported`,
`Asset.canDownload`), so Studio degrades instead of erroring. Also
`Asset.headshot(userId, size?, kind?)` (rbxthumb) and `Asset.preload(list)`.
**Any new image-bearing option should go through `Asset.resolve`** — the window
`Logo`, `Image`, `Player.Avatar` and MediaPlayer track `Cover` already do.
Resolving can hit the network, so components call it inside `task.spawn`.

Every source also accepts an **array = fallback chain**, walked in order until
one loads. Prefer `{ "https://…/art.png", "rbxassetid://…" }`: the URL is cached
to disk and loaded via `getcustomasset`, which sidesteps moderation, Asset
Privacy and decal-vs-image ids entirely (the Infinite Yield approach);
`Theme.Brand.logo` is exactly that. Downloads are magic-byte checked so a 404
body can't be cached as a `.png`.

**Two repos, don't conflate them.** This one (`coreui`) is the library source +
bundle, public only so the loadstring resolves. Art is hosted in the separate
public **`Krypton`** repo (`Assets/`, still under the old name), whose raw base
is `Theme.Brand.assets`;
`init.lua` copies it into `Asset.Base`, so `Asset.url("name.png")` builds the
full URL and shipping new art is just committing the file there.

**`Asset.load(image, source, onDone)` — two rules, both learned the hard way:**
1. Never use `ContentProvider:PreloadAsync` to decide whether an image loaded.
   It doesn't work on ImageLabels and misreports constantly; `IsLoaded` is the
   only honest signal (and an unparented/hidden ImageLabel never loads at all,
   because the engine only fetches what it renders).
2. Detection is **advisory** — never clear or hide the image because of it. Move
   a *placeholder* instead. Hiding the image was what made the logo invisible.

**Fade** (`util/Fade.lua`) — **and the CanvasGroup rule that comes with it.**

> **Never put text under a `CanvasGroup`.** A CanvasGroup rasterizes its whole
> subtree into an offscreen buffer and draws that buffer, so text stops being
> SDF-rendered at display resolution and becomes a resampled bitmap. The result
> is soft, smeared type that nothing on the user's end fixes — graphics quality
> doesn't help, resizing doesn't help, and it gets *worse* as the group grows
> (maximizing / fullscreen was the worst case). This is the second half of the
> blurry-text story; `FontFace` vs `Font` is the first.

CanvasGroup was the obvious way to fade a panel (one `GroupTransparency` tween)
and it was used for the window, popovers, toasts, the search field and the
splash — which meant essentially every glyph in the UI came through a buffer.
`Fade` replaces it: snapshot every transparency property in the subtree once,
then drive them all from one tweened `NumberValue`. Same easing, same "moves as
one unit" look, real text.

```lua
local fade = Fade.new(panel)
fade:Set(1)                       -- instantly invisible
fade:To(Tween.Normal, 0)          -- fade in
fade:To(Tween.MenuOut, 1, done)   -- fade out, then `done`
```

Alpha 0 = "as built" (each instance back at *its own* resting transparency,
which isn't necessarily 0), 1 = invisible. Three things to respect:
- **Snapshot at rest.** The base values are read on the first `Set`/`To` after
  the subtree is fully visible, and released again whenever it lands back on
  alpha 0. Never take a fresh snapshot mid-fade — it would bake the faded
  values in as the new baseline (this is why `ClosePopover` calls `:Set(0)`).
- **Snapshot late.** The window's mount fade runs on a deferred pass so the
  caller's tabs already exist; a toast builds its fade last.
- **Don't write a transparency a fade is driving.** Anything async that reveals
  or hides art (an `Asset.load` callback) must toggle `Visible` instead — which
  is why the window logo's accent square and the splash's are their own layer
  rather than the holder's own background.

Hidden subtrees (an inactive tab page) are pruned from the snapshot, so a window
fade only touches what's actually on screen.

**Whole-pixel snapping** is the third sharpness rule, in `Window.lua`
(`snapToPixels`) and `Splash.lua` (`centerStack`): the window is centered with a
*scale* position + `AnchorPoint(0.5, 0.5)`, so any odd viewport or window
dimension lands its top-left on a half pixel and rasterizes every glyph half a
pixel off the display grid. Both round the top-left back onto integers on drag
and on every resize. (The splash keeps both stack dimensions even for the same
reason.)

**Collapse** (`util/Collapse.lua`): `Collapse.wrap(content, startCollapsed)` →
`(holder, set)`. `content` must be `(1,0)` wide with `AutomaticSize.Y`. Holder
clips + owns the animated height; tracks content via AutomaticSize while open,
switches to manual offset height during the tween. `set(collapsed, animate?)`.

## Adding a new control

One file per control in `components/`, `--!strict`, signature
`function(ctx, opts) -> (Instance, handle, bordered)` — `Controls.lua`'s
`mount()` parents `Instance` into the card/section, appends the trailing
separator hairline iff `bordered`, and (if `opts.Flag` + a `kind` string were
passed to `mount`) registers `handle` for config save/load. `handle` is `{}`
for display-only controls; stateful ones expose at least `:Get()`/`:Set(v)`.

- **Height reporting has no explicit API** — it's pure `AutomaticSize.Y`
  propagation. Either the control is `AutomaticSize.Y` end to end (`List.lua`),
  or — for content that needs a fixed, scrollable viewport — a fixed-size
  `ScrollingFrame` (`AutomaticCanvasSize` for its inner content) sits inside an
  `AutomaticSize.Y` wrapper frame (`Code.lua`, `DataGrid.lua`). Either way, the
  card/`Collapse.wrap` machinery needs zero changes to host it.
- **Theming**: call `ctx:RegisterAccent(fn)` for anything that stays
  accent-colored while idle (it fires once immediately + on every
  `Window:SetAccent`, so don't also paint once by hand). Colors only shown
  transiently on focus/hover (e.g. an input's focus stroke) can just read
  `ctx.Accent` live at the moment they're applied — no subscription needed
  (see `Input.lua`).
- **Two manual wiring points** activate a new control kind — there's no
  runtime auto-discovery inside Luau (`require` needs a real `script.Parent.X`
  reference, unlike e.g. a JS registry that can `readdirSync` a folder):
  1. `components/Controls.lua` — `local Foo = require(script.Parent.Foo)` +
     one `function api:Foo(o) return mount(Foo, o, "foo") end` line.
  2. *Optional* — `util/Context.lua`'s local `Codec` table gets a
     `foo = { encode = ..., decode = ... }` entry if the control's value
     should round-trip through config Flags. Skip this (pass `kind = nil` to
     `mount`) for transient/caller-owned content — see `Custom`/`DataGrid`.
- `bundle.py` needs **no edit** for a new file — it walks the whole `coreui/`
  tree and picks up any `.lua` module automatically. Any Lucide icon name is
  already bundled, so a new control can reach for one freely (`EXTRA_ICONS`
  only matters under `--shake`).

**`Group:Custom(builder)` / `Section:Custom(builder)`** (`components/Custom.lua`)
is the escape hatch for parenting arbitrary Instances — `builder(ctx, frame)`
gets a `frame` that already satisfies the height-reporting contract above;
parent whatever you want into it and theme it yourself via `ctx:RegisterAccent`
if needed.

```lua
Group:Custom(function(ctx, frame)
	local box = Create("Frame", { Size = UDim2.fromOffset(0, 40), Parent = frame })
end)
```

**`Group:Image{...}` / `Section:Image{...}`** (`components/Image.lua`) is the
picture primitive: a clipped, rounded, bordered frame with a placeholder icon
until its source resolves. `Image` takes anything `Asset.resolve` handles, so a
bare decal id is enough. Options: `Image`/`Source`, `Height` (140), `Width`
(omit = full width), `Fit` (`cover`/`contain`/`stretch`/`tile`), `Corner`,
`Caption`, `Name`/`Desc` (uses the standard stacked Field), `Callback` (adds a
click target). Handle: `:Set(source)` / `:Get()` / `:SetCaption(t)`. Transient
like `Custom`/`DataGrid` — no Flag codec.

```lua
Group:Image({ Name = "Banner", Image = 74808640463075, Height = 160, Fit = "contain" })
```

**`Group:DataGrid{...}` / `Section:DataGrid{...}`** (`components/DataGrid.lua`)
is a dense row grid built on the same escape hatch, for tools shaped like a
data table (memory/value scanner, traffic log, instance browser). Row frames
are pooled and reused across `:SetRows` calls, and only cells whose value
changed get touched — sized for a few hundred live rows updating several
times a second, not a one-shot render.

```lua
local grid = Group:DataGrid({
	Name = "Results",
	Columns = {
		{ Key = "path",    Title = "Path",  Width = 0.45 },
		{ Key = "value",   Title = "Value", Width = 0.20, Editable = true },
		{ Key = "actions", Title = "",      Width = 0.35, Type = "actions" },
	},
	Height = 200,
	RowHeight = 27,
})
grid:SetRows({
	{ id = "row1", path = "Humanoid.WalkSpeed", value = "16",
	  actions = { { Name = "lock", Icon = "lock" }, { Name = "info", Icon = "info" } } },
})
grid:UpdateRow("row1", { value = "24" })
grid:RemoveRow("row1")
grid.RowEdited:Connect(function(id, columnKey, newText) end)
grid.RowAction:Connect(function(id, actionName) end)
```

**`Group:MediaPlayer{...}` / `Section:MediaPlayer{...}`** (`components/MediaPlayer.lua`)
is a cover-art + title/artist + draggable scrub timeline + transport (shuffle /
prev / play·pause / next / repeat) + volume bar. Three ways to drive it, mixable
per track: give a `SoundId` (or a `Queue` of them) and it owns real
`Instance.new("Sound")`s and actually plays them, driving the timeline off
`Sound.TimePosition`; pass an existing `Sound` instance and it drives that one
without owning/destroying it; or give neither and it's a pure remote — every
action just fires `Callback(action, payload)` + a matching event, and you push
state back with `:SetProgress`/`:SetPlaying`/`:SetDuration`. Transient like
`Custom`/`DataGrid` — no `Flag`/config codec.

**Currently left out of `example.loadstring.lua`** at the author's request — the
component, its `Controls.lua` wiring and its bundling are all untouched, the demo
just doesn't show it off right now. Don't delete it; re-add the demo group when
asked.

```lua
local player = Group:MediaPlayer({
	Name = "Now Playing",
	Queue = {
		{ Title = "Song One", Artist = "Artist", SoundId = "rbxassetid://123" },
		{ Title = "Song Two", Artist = "Artist", SoundId = "rbxassetid://456" },
	},
	ShowVolume = true, ShowShuffle = true, ShowLoop = true,
	Callback = function(action, payload) print(action, payload.Title) end,
})
player.TrackChanged:Connect(function(track) print("now playing:", track.Title) end)
```

## Conventions

- `--!strict` at top of every Luau module (generated/data files use `--!nocheck`).
- Colors via `Color3.fromHex(...)`; pull from `Theme.Colors`, never hardcode.
- **Palette: Uranium / Uranium Glass.** `#7BE04A` accent on a *near-neutral*
  ramp that only whispers green — chrome `#0B0F0A` < bg `#10150E` < card
  `#171D15` < pop `#1A2118` < control `#1D241B` < hover `#262E23`, lines
  `#2B3427` (edges) / `#1F271D` (inner dividers), text `#E9F2E5` / `#98A394` /
  `#616D5D`. Two things were retuned away from the first Uranium pass and both
  matter: the surfaces used to be a flat olive (`#18220F`, all three of card /
  pop / control at once), which read muddy under the accent and gave a field no
  way to stand out inside its card; and the accent was `#7CFF3B`, bright enough
  that any sizable fill of it took the window over.
  **The accent now has three weights, chosen by area** — `accent` for small
  marks (slider fill, toggle track, icons, focus strokes, text), `accent_fill`
  (`#5EB832`, deeper) for large solid fills like primary buttons, which hover
  *up* to `accent`, and `accent_soft` (`#22331A`, accent at ~13% into the
  surface) for tinted tiles — the active nav, avatar placeholders, badge chips —
  where the icon/text on top carries the real colour. `util/Context.lua` derives
  `ctx.AccentFill` / `ctx.AccentSoft` from the live accent, so `SetAccent` moves
  all three; read them off `ctx` inside a `RegisterAccent` callback, never
  recompute them. Anything drawn **on a solid accent fill** uses `knockout`
  (`#08140A`), never white. Flat fills only: no gradients, no glows, at most one
  accent element per row; hover shifts a fill one step lighter and nothing else.
  Three deliberate exceptions: slider / MediaPlayer knobs use `text` (at value 0
  the knob sits off the accent fill, where a knockout knob would vanish), the
  active nav button carries an accent rail (3×18px, in the sidebar gutter) as
  well as its tinted tile, and the window keeps its neutral black drop shadow as
  elevation. `Theme.Brand` holds the mark
  (`{ name, logo = <source chain>, radius, zoom }`) and `Theme.Metrics.logo` its
  size. `zoom` exists because the shipped PNG is a full-bleed tile with dead
  margin baked around the glyph: the titlebar holder clips and draws the art
  `zoom`× oversized to crop that margin off. Caller-supplied `Logo` art defaults
  to `zoom = 1` — we can't assume someone else's mark has margin to trim.
- **Fonts: set `FontFace` (NOT `Font`).** `Font` uses bitmap atlases → soft/
  pixelated scaling; `FontFace` uses the SDF renderer → crisp at any size. Use
  `Theme.Font.{Bold,Medium,Regular,Mono}`.
- **No `CanvasGroup`, ever** — it rasterizes text into a buffer and blurs the
  whole subtree. Fade with `util/Fade.lua` instead; see the Fade section above.
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
