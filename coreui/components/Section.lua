--!strict
-- components/Section.lua — a nested collapsible group (indented, left rule).
-- Returns the section frame plus the inner body that controls mount into.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)

return function(ctx: any, opts: any): (Frame, Frame)
	local colors = Theme.Colors
	local collapsed = opts.Collapsed == true

	local section = Create("Frame", {
		Name = "Section",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
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
		Parent = section,
	}, {
		Create.padding(9, 2),
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
		Text = opts.Title or "Section",
		TextColor3 = colors.text,
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

	local bodyWrap = Create("Frame", {
		Name = "BodyWrap",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = not collapsed,
		LayoutOrder = 2,
		Parent = section,
	})

	local body = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -14, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = bodyWrap,
	}, {
		Create.padding(1, 0, 8, 0),
		Create.listLayout({}),
	})

	-- left rule, height tracked to the body so AutomaticSize stays stable.
	local rule = Create("Frame", {
		Name = "Rule",
		Position = UDim2.fromOffset(2, 1),
		Size = UDim2.fromOffset(1, 0),
		BackgroundColor3 = colors.border,
		BorderSizePixel = 0,
		Parent = bodyWrap,
	})
	body:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		rule.Size = UDim2.fromOffset(1, body.AbsoluteSize.Y)
	end)

	head.Activated:Connect(function()
		collapsed = not collapsed
		Tween.play(chevron, Tween.Spin, { Rotation = collapsed and 180 or 0 })
		if collapsed then
			task.delay(0.12, function()
				if collapsed then
					bodyWrap.Visible = false
				end
			end)
		else
			bodyWrap.Visible = true
		end
	end)

	return section, body
end
