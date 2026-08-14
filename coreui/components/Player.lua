--!strict
-- components/Player.lua — avatar + name/badge + @username · ID info panel.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)
local Asset = require(script.Parent.Parent.util.Asset)

return function(ctx: any, opts: any)
	local colors = Theme.Colors

	local panel = Create("Frame", {
		Name = "Player",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Create.padding(12, 2),
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 14),
		}),
	})

	-- avatar ───────────────────────────────────────────────────────────────
	-- The placeholder tile is accent-*tinted*, with the accent carried by the
	-- icon on top. A 56px solid-accent square was the biggest block of colour
	-- on the Home tab and it wasn't even real content.
	local avatar = Create("Frame", {
		Name = "Avatar",
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = colors.accent_soft,
		ClipsDescendants = true,
		LayoutOrder = 1,
		Parent = panel,
	}, {
		Create.corner(14),
		Create.stroke(colors.border),
	})

	local picture = Create("ImageLabel", {
		Name = "Image",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = "",
		ScaleType = Enum.ScaleType.Crop,
		Parent = avatar,
	}) :: ImageLabel

	-- The glyph is always built and only toggled, never swapped for the picture:
	-- `Avatar` goes through Asset.resolve (bare id / url / file path / fallback
	-- chain), so there's a window with a source but nothing drawn yet, and a
	-- source that never loads should leave the icon up rather than an empty tile.
	-- The picture itself is never hidden — an ImageLabel the engine isn't
	-- rendering never loads in the first place.
	local placeholder: GuiObject = Icons.new("avatar", 34, colors.accent) -- may be a glyph TextLabel
	placeholder.AnchorPoint = Vector2.new(0.5, 0.5)
	placeholder.Position = UDim2.fromScale(0.5, 0.5);
	(placeholder :: any).Parent = avatar

	if opts.Avatar then
		-- Off-thread: resolving an https avatar downloads + caches it on first
		-- use, which must not stall the window build.
		task.spawn(function()
			Asset.load(picture, opts.Avatar, function(loaded)
				placeholder.Visible = not loaded
			end)
		end)
	end

	-- info ─────────────────────────────────────────────────────────────────
	local info = Create("Frame", {
		Name = "Info",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -70, 0, 0), -- fills past the 56px avatar + 14px gap
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = panel,
	}, {
		Create.listLayout({ Padding = UDim.new(0, 2) }),
	})

	local nameRow = Create("Frame", {
		Name = "NameRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = info,
	}, {
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
	})

	Create("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Text = opts.DisplayName or opts.Username or "Player",
		TextColor3 = colors.text,
		TextSize = 16,
		FontFace = Theme.Font.Medium,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = nameRow,
	})

	local badge: TextLabel? = nil
	if opts.Badge then
		-- A filled chip (tinted surface + accent text) rather than an outlined
		-- one: an accent hairline that small reads as a stray line at a glance,
		-- and the fill gives the label something to sit on.
		badge = Create("TextLabel", {
			Name = "Badge",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(17, 17),
			BackgroundColor3 = colors.accent_soft,
			Text = string.upper(opts.Badge),
			TextColor3 = colors.accent,
			TextSize = 10,
			FontFace = Theme.Font.Bold,
			LayoutOrder = 2,
			Parent = nameRow,
		}, {
			Create.corner(999),
			Create.padding(1, 7),
		})
	end

	local sub = "@" .. (opts.Username or "player")
	if opts.UserId and opts.UserId ~= 0 then
		sub = sub .. "  ·  ID " .. tostring(opts.UserId)
	end
	Create("TextLabel", {
		Name = "Sub",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = sub,
		TextColor3 = colors.text_muted,
		TextSize = 12,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
		Parent = info,
	})

	ctx:RegisterAccent(function(accent)
		avatar.BackgroundColor3 = ctx.AccentSoft
		Icons.tint(placeholder, accent)
		if badge then
			badge.BackgroundColor3 = ctx.AccentSoft
			badge.TextColor3 = accent
		end
	end)

	return panel, {}, false
end
