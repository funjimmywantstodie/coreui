--!strict
-- Theme.lua — design tokens (colors, metrics, fonts).
-- Offset pixels map directly to Roblox offsets.
--
-- Palette: **Uranium (Uranium Glass)**. Greyscale-green everywhere, one accent
-- element per row at most, flat fills only — no gradients, glows or accent
-- washes behind large areas. Anything sitting *on* an accent fill (button text,
-- the active nav icon, the toggle-on knob) uses `knockout`, not white.
--
-- The accent is a very bright yellow-green; used widely it stops being readable,
-- so it's rationed to one element per row (toggle-on track, slider fill left of
-- the knob, active nav, focus stroke, primary button, links).

local Theme = {}

-- ── Brand ─────────────────────────────────────────────────────────────────
-- `assets` is the **Krypton public repo** — the author's asset host, a separate
-- thing from this UI library (which lives in the `coreui` repo and is only
-- public so the loadstring works). Both keep their old names on purpose: the
-- loadstring URL and the raw asset URLs are pinned to those paths, and renaming
-- either breaks every shipped loader. The rebrand to Uranium is user-visible
-- strings + palette only. Art the UI ships with goes in that repo, not here;
-- drop a file in its `Assets/` folder and reference it as
-- `Theme.Brand.assets .. "name.png"` (or `Uranium.Asset.url("name.png")`).
--
-- The logo is a fallback chain — util/Asset.lua walks it in order, so
-- `Window{ Logo = ... }` can be a single source or a chain of its own.
--
-- The PNG comes FIRST on purpose — that's the Infinite Yield approach. It's
-- downloaded once, cached on disk, and handed to the engine via getcustomasset,
-- so it sidesteps every Roblox asset rule: no moderation wait, no Asset Privacy
-- restriction, no decal-vs-image id confusion. An uploaded asset id would be the
-- fallback for executors with no file access — there isn't one for the Uranium
-- mark yet, so those fall through to the accent square + "U" initial instead of
-- showing the old Krypton art. Add the id here once it's uploaded.
local ASSETS = "https://raw.githubusercontent.com/funjimmywantstodie/Krypton/main/Assets/"

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
	-- The tile's background is exactly `Colors.bg`, so its edges vanish into the
	-- titlebar and the crop is invisible. 1 = draw the source untouched (the
	-- default for a caller-supplied Logo, which we can't assume has margin).
	zoom = 1.42,
}

-- ── Colors ────────────────────────────────────────────────────────────────
Theme.Colors = {
	bg          = Color3.fromHex("0B0F0A"), -- window body   (background)
	chrome      = Color3.fromHex("0B0F0A"), -- titlebar / sidebar / status bar
	card        = Color3.fromHex("18220F"), -- group card fill        (surface)
	pop         = Color3.fromHex("18220F"), -- dropdown / colorpicker / toast
	control     = Color3.fromHex("18220F"), -- input / dropdown / button fill
	control_hi  = Color3.fromHex("212D16"), -- hovered control  (surface hover)
	-- Toggle / slider track. The spec calls it "surface", but cards are surface
	-- too — one step lighter is what keeps the track readable on the card.
	toggle_off  = Color3.fromHex("212D16"),
	knob        = Color3.fromHex("5A6B52"), -- toggle knob (off) — text faint
	border      = Color3.fromHex("2C3A24"), -- every 1px line
	border_soft = Color3.fromHex("2C3A24"), -- between-field dividers
	text        = Color3.fromHex("E9F5E4"), -- primary text / headings
	text_muted  = Color3.fromHex("909C96"), -- descriptions, placeholders, readouts
	text_dim    = Color3.fromHex("5A6B52"), -- small caps headers, hints, idle icons
	accent      = Color3.fromHex("7CFF3B"), -- toggle-on, slider fill, active nav, focus
	accent_2    = Color3.fromHex("9BFF6B"), -- accent hover
	accent_dim  = Color3.fromHex("46801F"), -- pressed / disabled accent
	knockout    = Color3.fromHex("0A1604"), -- text + icons ON an accent fill
	scroll      = Color3.fromHex("2C3A24"), -- scrollbar thumb
	white       = Color3.fromHex("FFFFFF"),
	danger      = Color3.fromHex("FF5E5E"), -- destructive buttons + notify "error"
	success     = Color3.fromHex("7CFF3B"), -- notify "success"
	warning     = Color3.fromHex("FFD400"), -- risky toggles + notify "warning"
	info        = Color3.fromHex("909C96"), -- notify "info" (neutral, off-accent)
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
