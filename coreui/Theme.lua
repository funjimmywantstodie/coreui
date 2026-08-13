--!strict
-- Theme.lua — design tokens (colors, metrics, fonts).
-- Offset pixels map directly to Roblox offsets.
--
-- Palette: **Krypton (Deep Emerald)**. Greyscale-green everywhere, one accent
-- element per row at most, flat fills only — no gradients, glows or accent
-- washes behind large areas. Anything sitting *on* an accent fill (button text,
-- the active nav icon, the toggle-on knob) uses `knockout`, not white.

local Theme = {}

-- ── Brand ─────────────────────────────────────────────────────────────────
-- The titlebar logo. `Window{ Logo = ... }` overrides it, and it goes through
-- util/Asset.lua, so an asset id, a URL or a local file path all work.
Theme.Brand = {
	name   = "Krypton",
	logo   = "rbxassetid://91296376944710", -- 512×512 square mark
	radius = 8,                              -- rounded off with a UICorner
}

-- ── Colors ────────────────────────────────────────────────────────────────
Theme.Colors = {
	bg          = Color3.fromHex("0A100C"), -- window body   (background)
	chrome      = Color3.fromHex("0A100C"), -- titlebar / sidebar / status bar
	card        = Color3.fromHex("142019"), -- group card fill        (surface)
	pop         = Color3.fromHex("142019"), -- dropdown / colorpicker / toast
	control     = Color3.fromHex("142019"), -- input / dropdown / button fill
	control_hi  = Color3.fromHex("1B2A21"), -- hovered control  (surface hover)
	-- Toggle / slider track. The spec calls it "surface", but cards are surface
	-- too — one step lighter is what keeps the track readable on the card.
	toggle_off  = Color3.fromHex("1B2A21"),
	knob        = Color3.fromHex("5A6862"), -- toggle knob (off) — text faint
	border      = Color3.fromHex("1A2B20"), -- every 1px line
	border_soft = Color3.fromHex("1A2B20"), -- between-field dividers
	text        = Color3.fromHex("E4EEE8"), -- primary text / headings
	text_muted  = Color3.fromHex("8A9A90"), -- descriptions, placeholders, readouts
	text_dim    = Color3.fromHex("5A6862"), -- small caps headers, hints, idle icons
	accent      = Color3.fromHex("00C46A"), -- toggle-on, slider fill, active nav, focus
	accent_2    = Color3.fromHex("1FE087"), -- accent hover
	accent_dim  = Color3.fromHex("0A6B3E"), -- pressed / disabled accent
	knockout    = Color3.fromHex("04150C"), -- text + icons ON an accent fill
	scroll      = Color3.fromHex("22362A"), -- scrollbar thumb
	white       = Color3.fromHex("FFFFFF"),
	danger      = Color3.fromHex("FF5E5E"), -- destructive buttons + notify "error"
	success     = Color3.fromHex("00C46A"), -- notify "success"
	warning     = Color3.fromHex("FFC24D"), -- risky toggles + notify "warning"
	info        = Color3.fromHex("8A9A90"), -- notify "info" (neutral, off-accent)
}

-- ── Metrics (offset px) ───────────────────────────────────────────────────
Theme.Metrics = {
	windowWidth   = 780,
	windowHeight  = 560,
	windowRadius  = 12,
	titlebar      = 50,
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
