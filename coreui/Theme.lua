--!strict
-- Theme.lua — design tokens (colors, metrics, fonts).
-- Offset pixels map directly to Roblox offsets.
--
-- Palette: **Uranium (Uranium Glass)**. Flat fills only — no gradients, no
-- glows — and at most one accent element per row. Anything sitting *on* a solid
-- accent fill (button text, the toggle-on knob) uses `knockout`, not white.
--
-- Two rules keep the green from taking the UI over:
--
-- 1. **The surfaces are near-neutral.** They carry only a whisper of green
--    (~10% saturation). The old ramp was a flat olive (#18220F) which, sat
--    under a screaming yellow-green accent, read muddy — two greens
--    fighting instead of one green on grey. Neutral ground is also what makes
--    the accent look bright; tinting the ground just spends the contrast.
--    The ramp is a real elevation ladder — chrome < bg < card < control <
--    control_hi — so a field reads as a field even sitting inside a card.
-- 2. **The accent has three weights, by area.** A colour that looks right as a
--    6px slider fill is a searing slab at button size, so bigger area = lower
--    value:
--      `accent`      small marks — slider fill, toggle track, icons, focus
--                    strokes, text. Bright, because it's tiny.
--      `accent_fill` large solid fills (primary buttons). Deeper; hovers *up*
--                    to `accent`, so the interaction reads as lighting up.
--      `accent_soft` accent laid into a surface (~13%) for tinted tiles — the
--                    active nav, avatar placeholders, badges. Reads as "this is
--                    accent-coloured" without putting neon on the screen.
--    util/Context.lua derives the last two from the live accent, so a caller's
--    `SetAccent` keeps all three in step.

local Theme = {}

-- ── Brand ─────────────────────────────────────────────────────────────────
-- `assets` is the **uranium-public** repo — the author's asset host, a separate
-- thing from this UI library (which lives in the `coreui` repo and is only
-- public so the loadstring works). `coreui` keeps its old name on purpose: the
-- loadstring URL is pinned to that path and renaming it breaks every shipped
-- loader. The art host is NOT pinned that way — nothing but this line points at
-- it — so it moved off the old `Krypton` name, and that path now 404s. Art the
-- UI ships with goes in that repo, not here; drop a file in its `Assets/` folder
-- and reference it as `Theme.Brand.assets .. "name.png"` (or
-- `Uranium.Asset.url("name.png")`).
--
-- If the mark ever comes up as the `atom` fallback glyph, check this URL first:
-- that fallback is what a 404 looks like, and it looks identical to "no file
-- access", so it reads as an executor problem when it's really a dead link.
--
-- The logo is a fallback chain — util/Asset.lua walks it in order, so
-- `Window{ Logo = ... }` can be a single source or a chain of its own.
--
-- The PNG comes FIRST on purpose — that's the Infinite Yield approach. It's
-- downloaded once, cached on disk, and handed to the engine via getcustomasset,
-- so it sidesteps every Roblox asset rule: no moderation wait, no Asset Privacy
-- restriction, no decal-vs-image id confusion. An uploaded asset id would be the
-- fallback for executors with no file access — there isn't one for the Uranium
-- mark yet, so those fall through to the tinted tile + Lucide `atom` glyph the
-- titlebar draws underneath the art (components/Window.lua, components/Screen.lua)
-- — a spritesheet slice, so it needs neither network nor file access. Add the id
-- here once it's uploaded and every client gets the real art unconditionally.
local ASSETS = "https://raw.githubusercontent.com/funjimmywantstodie/uranium-public/main/Assets/"

Theme.Brand = {
	name   = "Uranium",
	assets = ASSETS,
	logo = {
		ASSETS .. "uranium-orbitals-512-square.png", -- 512×512 square mark
	},
	radius = 8, -- rounded off with a UICorner
	-- The mark is a full-bleed tile, not a transparent glyph: the orbitals only
	-- span the middle ~58% and the rest is flat #0B0F0A margin baked into the
	-- PNG. Drawn 1:1 that reads as a tiny logo floating in a box. So the holder
	-- clips and the art is drawn `zoom`× oversized inside it — the dead margin
	-- is cropped away and the glyph fills ~82% of the holder instead of 58%.
	-- The tile's background is exactly `Colors.chrome` (#0B0F0A), so its edges
	-- vanish into the titlebar and the crop is invisible — which is why `chrome`
	-- is pinned to that value and the rest of the ramp moved around it.
	-- 1 = draw the source untouched (the default for a caller-supplied Logo,
	-- which we can't assume has margin).
	zoom = 1.42,
}

-- ── Colors ────────────────────────────────────────────────────────────────
Theme.Colors = {
	-- Elevation ladder, darkest → lightest. Each step is a real, visible lift,
	-- so depth comes from the fills themselves and the hairlines only have to
	-- draw the edge (they used to carry the whole separation on their own).
	chrome      = Color3.fromHex("0B0F0A"), -- titlebar / sidebar / status bar (the frame)
	bg          = Color3.fromHex("10150E"), -- window body — lifts off the chrome
	card        = Color3.fromHex("171D15"), -- group card fill
	pop         = Color3.fromHex("1A2118"), -- dropdown / colorpicker / toast (floats above cards)
	control     = Color3.fromHex("1D241B"), -- input / dropdown / button fill, on a card
	control_hi  = Color3.fromHex("262E23"), -- hovered control — one step lighter, nothing else
	-- Toggle / slider track: one step above `control` again, so an unfilled
	-- track still reads against the field it sits in.
	toggle_off  = Color3.fromHex("2B3428"),
	knob        = Color3.fromHex("6E7C69"), -- toggle knob (off)
	border      = Color3.fromHex("2B3427"), -- every 1px line
	border_soft = Color3.fromHex("1F271D"), -- between-field dividers (quieter than an edge)
	text        = Color3.fromHex("E9F2E5"), -- primary text / headings
	text_muted  = Color3.fromHex("98A394"), -- descriptions, placeholders, readouts
	text_dim    = Color3.fromHex("616D5D"), -- small caps headers, hints, idle icons
	-- Accent, by area — see the header. Small marks / large fills / tinted tiles.
	accent      = Color3.fromHex("7BE04A"), -- slider fill, toggle-on, focus stroke, icons
	accent_2    = Color3.fromHex("96EC69"), -- accent hover
	accent_fill = Color3.fromHex("5EB832"), -- large solid fills (primary buttons)
	accent_soft = Color3.fromHex("22331A"), -- accent tinted into a surface (~13%)
	accent_dim  = Color3.fromHex("4E9B2B"), -- pressed / disabled accent
	knockout    = Color3.fromHex("08140A"), -- text + icons ON a solid accent fill
	scroll      = Color3.fromHex("2B3427"), -- scrollbar thumb
	white       = Color3.fromHex("FFFFFF"),
	danger      = Color3.fromHex("FF6B6B"), -- destructive buttons + notify "error"
	success     = Color3.fromHex("7BE04A"), -- notify "success"
	warning     = Color3.fromHex("FFC53D"), -- risky toggles + notify "warning"
	info        = Color3.fromHex("98A394"), -- notify "info" (neutral, off-accent)
}

-- ── Metrics (offset px) ───────────────────────────────────────────────────
Theme.Metrics = {
	windowWidth   = 780,
	windowHeight  = 560,
	windowRadius  = 12,
	titlebar      = 50,
	logo          = 30, -- titlebar brand mark (square)
	statusbar     = 34,
	sidebar       = 64,
	navButton     = 40,
	navRadius     = 11,
	navIcon       = 20,
	cardRadius    = 9,
	controlRadius = 7,
	columnGap     = 24,
	groupGap      = 18,
}

-- ── Fonts ─────────────────────────────────────────────────────────────────
-- UI font "Inter" → Gotham family. Mono (keybind/hex) → Roboto Mono.
--
-- These are FontFace objects (set via the `FontFace` property, NOT `Font`).
-- The legacy `Enum.Font.*` values render from fixed-size bitmap atlases —
-- Roblox scales the nearest baked size to your TextSize, which is what made
-- the text look soft / rough / "pixelated". FontFace uses the SDF text
-- renderer, so glyphs stay crisp at any size.
local GOTHAM = "rbxasset://fonts/families/GothamSSm.json"
Theme.Font = {
	Bold    = Font.new(GOTHAM, Enum.FontWeight.Bold),                          -- titles
	Medium  = Font.new(GOTHAM, Enum.FontWeight.Medium),                        -- labels / weighted text
	Regular = Font.new(GOTHAM, Enum.FontWeight.Regular),                       -- body
	Mono    = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular), -- keybind / hex
}

return Theme
