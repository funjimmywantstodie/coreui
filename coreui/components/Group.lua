--!strict
-- components/Group.lua — titled card with a collapsible body.
-- Header toggles the card's visibility; the card hosts the control surface.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)
local Controls = require(script.Parent.Controls)

return function(ctx: any, column: Frame, opts: any)
	local colors = Theme.Colors
	local collapsed = opts.Collapsed == true

	local group = Create("Frame", {
		Name = "Group",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = column,
	}, {
		Create.listLayout({}),
	})

	local head = Create("TextButton", {
		Name = "Head",
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = group,
	}, {
		Create.padding(2, 4, 8, 4),
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})

	Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -14, 0, 0), -- leaves the 14px chevron flush right
		Text = opts.Title or "Group",
		TextColor3 = colors.text_muted,
		TextSize = 13,
		FontFace = Theme.Font.Medium,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = head,
	})

	local chevron = Icons.rotatable("chev", 14, colors.text_dim)
	chevron.LayoutOrder = 2
	chevron.Rotation = collapsed and 180 or 0
	chevron.Parent = head

	local card = Create("Frame", {
		Name = "Card",
		BackgroundColor3 = colors.card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = not collapsed,
		LayoutOrder = 2,
		Parent = group,
	}, {
		Create.corner(Theme.Metrics.cardRadius),
		Create.stroke(colors.border),
		Create.padding(2, 14),
		Create.listLayout({}),
	})

	head.Activated:Connect(function()
		collapsed = not collapsed
		-- Spin the chevron; reveal the card on expand, hide it once the spin
		-- has played on collapse so the rotation reads before it vanishes.
		Tween.play(chevron, Tween.Spin, { Rotation = collapsed and 180 or 0 })
		if collapsed then
			task.delay(0.12, function()
				if collapsed then
					card.Visible = false
				end
			end)
		else
			card.Visible = true
		end
	end)

	return Controls.new(ctx, card)
end
