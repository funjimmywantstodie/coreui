--!strict
-- components/Player.lua — avatar + name/badge + @username · ID info panel.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)

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

	local placeholder: GuiObject? = nil -- Icons.new may resolve to a glyph TextLabel
	if opts.Avatar then
		Create("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = opts.Avatar,
			ScaleType = Enum.ScaleType.Crop,
			Parent = avatar,
		})
	else
		local icon = Icons.new("avatar", 34, colors.accent)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5);
		(icon :: any).Parent = avatar
		placeholder = icon
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
		if placeholder then
			Icons.tint(placeholder, accent)
		end
		if badge then
			badge.BackgroundColor3 = ctx.AccentSoft
			badge.TextColor3 = accent
		end
	end)

	return panel, {}, false
end
