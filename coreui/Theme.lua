--!strict
-- Theme.lua — design tokens (colors, metrics, fonts).
-- Values mirror reference/coreui.css 1:1. Offset pixels map directly to Roblox.

local Theme = {}

-- ── Colors ────────────────────────────────────────────────────────────────
Theme.Colors = {
	bg          = Color3.fromHex("0C0C0E"), -- window body
	chrome      = Color3.fromHex("131315"), -- titlebar / sidebar / status bar
	card        = Color3.fromHex("161618"), -- group card fill
	pop         = Color3.fromHex("18181B"), -- dropdown / colorpicker / toast
	control     = Color3.fromHex("1B1B1F"), -- input / dropdown / button fill
	control_hi  = Color3.fromHex("232328"), -- hovered control
	toggle_off  = Color3.fromHex("2C2C31"), -- toggle track (off) + slider track
	knob        = Color3.fromHex("D6D6DB"), -- toggle knob (off)
	border      = Color3.fromHex("262629"), -- card / control borders, dividers
	border_soft = Color3.fromHex("1F1F22"), -- between-field dividers
	text        = Color3.fromHex("EDEDF0"), -- primary text
	text_muted  = Color3.fromHex("8C8C94"), -- secondary text / descriptions
	text_dim    = Color3.fromHex("5F5F67"), -- placeholders, inactive icons, chevrons
	accent      = Color3.fromHex("F2680C"), -- active nav, toggle-on, accent button, focus
	accent_2    = Color3.fromHex("FF8A3D"), -- accent hover / gradient top
	white       = Color3.fromHex("FFFFFF"),
	danger      = Color3.fromHex("FF6B6B"), -- close-button hover
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
