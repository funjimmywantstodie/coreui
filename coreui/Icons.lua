--!strict
-- Icons.lua — name → Lucide vector icon.
--
-- The reference keys icons by short names ("home", "gear", "chev"…). Lucide
-- ships them as solid white glyphs packed into spritesheets; `LucideData.luau`
-- maps each Lucide name to {assetId, {w,h}, {offX,offY}}. We use the "48px"
-- set (plenty for 14–34px UI icons, far lighter than "256px") and translate
-- our short names through ALIAS. Because the glyphs are white on transparent,
-- `ImageColor3` recolors them freely — text_dim for inactive, white for active.

local Create = require(script.Parent.util.Create)
local Theme = require(script.Parent.Theme)
local Tween = require(script.Parent.util.Tween)
local LucideData = require(script.Parent.LucideData)

local SET = LucideData["48px"]

-- our short name → Lucide name
local ALIAS: { [string]: string } = {
	home   = "home",        cursor = "mouse-pointer",
	input  = "text-cursor-input", list = "list",
	palette = "palette",    layers = "layers",
	bug    = "bug",         person = "user",
	gear   = "settings",    search = "search",
	min    = "minus",       max    = "square",
	close  = "x",           chev   = "chevron-up",
	caret  = "chevron-down", ddchev = "chevron-down",
	check  = "check",       avatar = "circle-user",
	image  = "image",
	-- notify types
	success = "circle-check", info    = "info",
	warning = "triangle-alert", error = "circle-x",
}

-- Unicode fallbacks for any name with no Lucide entry (keeps the UI legible
-- if a name is misspelled or the data file is swapped out).
local GLYPH: { [string]: string } = {
	home = "⌂", layers = "▤", cursor = "➤", input = "⌨", list = "≣",
	palette = "◑", person = "☺", gear = "⚙", search = "⌕", avatar = "☻",
	min = "—", max = "▢", close = "✕", chev = "⌄", caret = "⌄", check = "✓",
	image = "▣",
	success = "✓", info = "ℹ", warning = "⚠", error = "✕",
}

local Icons = {}

local function entryFor(name: string)
	return SET[ALIAS[name] or name]
end

-- Build an icon instance sized `size`, tinted `color`. Returns an ImageLabel
-- when the icon resolves, otherwise a glyph TextLabel fallback.
function Icons.new(name: string, size: number, color: Color3): GuiObject
	local entry = entryFor(name)
	if entry then
		return Create("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size, size),
			Image = "rbxassetid://" .. entry[1],
			ImageRectSize = Vector2.new(entry[2][1], entry[2][2]),
			ImageRectOffset = Vector2.new(entry[3][1], entry[3][2]),
			ImageColor3 = color,
			ScaleType = Enum.ScaleType.Stretch,
		})
	end
	return Create("TextLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Text = GLYPH[name] or "•",
		TextColor3 = color,
		TextSize = size,
		FontFace = Theme.Font.Medium,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
end

-- Apply an icon onto an existing ImageLabel/ImageButton (matches the design's
-- `Icons.apply` helper). No-op for unknown names — and no-op on an instance
-- that isn't an image at all, because `Icons.new` hands back a glyph TextLabel
-- for any name with no Lucide entry and callers hold the result as one variable
-- they later `apply` a *different* name to (MediaPlayer's play↔pause,
-- repeat↔repeat-1, the three volume icons). Writing `.Image` on a TextLabel is a
-- hard error, so one unresolved name used to take the whole control down the
-- first time its icon changed rather than just leaving the glyph in place.
function Icons.apply(image: GuiObject, name: string)
	if not (image:IsA("ImageLabel") or image:IsA("ImageButton")) then
		return
	end
	local entry = entryFor(name)
	if not entry then
		return
	end
	local img = image :: ImageLabel
	img.Image = "rbxassetid://" .. entry[1]
	img.ImageRectSize = Vector2.new(entry[2][1], entry[2][2])
	img.ImageRectOffset = Vector2.new(entry[3][1], entry[3][2])
end

-- Tint an icon regardless of whether it resolved to an ImageLabel or a glyph.
function Icons.tint(icon: GuiObject, color: Color3)
	if icon:IsA("ImageLabel") or icon:IsA("ImageButton") then
		icon.ImageColor3 = color
	elseif icon:IsA("TextLabel") then
		icon.TextColor3 = color
	end
end

-- `Icons.tint`, animated. Same reason it exists: the colour property differs
-- between the two shapes `Icons.new` can return, so a caller tweening
-- `{ ImageColor3 = ... }` by hand errors the moment it's handed a glyph
-- fallback. Callers that animate an icon's colour should use this, not
-- Tween.play directly.
function Icons.tween(icon: GuiObject, info: TweenInfo, color: Color3)
	if icon:IsA("ImageLabel") or icon:IsA("ImageButton") then
		Tween.play(icon, info, { ImageColor3 = color })
	elseif icon:IsA("TextLabel") then
		Tween.play(icon, info, { TextColor3 = color })
	end
end

return Icons
