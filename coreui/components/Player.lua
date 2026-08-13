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
	local avatar = Create("Frame", {
		Name = "Avatar",
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = colors.accent,
		ClipsDescendants = true,
		LayoutOrder = 1,
		Parent = panel,
	}, {
		Create.corner(14),
		Create.stroke(colors.border),
	})

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
		local icon = Icons.new("avatar", 34, colors.knockout)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5);
		(icon :: any).Parent = avatar
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
		badge = Create("TextLabel", {
			Name = "Badge",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 16),
			BackgroundTransparency = 1,
			Text = string.upper(opts.Badge),
			TextColor3 = colors.accent,
			TextSize = 10,
			FontFace = Theme.Font.Bold,
			LayoutOrder = 2,
			Parent = nameRow,
		}, {
			Create.corner(999),
			Create.stroke(colors.accent),
			Create.padding(1, 6),
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
		avatar.BackgroundColor3 = accent
		if badge then
			badge.TextColor3 = accent
			local badgeStroke = badge:FindFirstChildOfClass("UIStroke")
			if badgeStroke then
				badgeStroke.Color = accent
			end
		end
	end)

	return panel, {}, false
end
