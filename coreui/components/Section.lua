--!strict
-- components/Section.lua — a nested collapsible group (indented, left rule).
-- Returns the section frame plus the inner body that controls mount into.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)
local Collapse = require(script.Parent.Parent.util.Collapse)

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

	-- No UIListLayout on the header: a layout-managed child won't render its
	-- Rotation, so the chevron is positioned manually to keep it free to spin.
	-- Thumb-sized fold target on a phone, the design's own on a desktop — same
	-- deal as components/Group.lua's header.
	local headPad = Create.padding(9, 2)
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
		headPad,
	})
	local function fitHead()
		local pad = ctx:IsTouch() and 12 or 9
		headPad.PaddingTop = UDim.new(0, pad)
		headPad.PaddingBottom = UDim.new(0, pad)
	end
	fitHead()
	local unsubscribeTouch = ctx:OnTouch(fitHead)
	section.Destroying:Connect(unsubscribeTouch)

	Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -18, 0, 0), -- leaves room for the chevron flush right
		Text = opts.Title or "Section",
		-- One step under the group's own title (components/Group.lua: `text`, 13),
		-- so a nested section reads as a subdivision of the card, not a second card.
		TextColor3 = colors.text_muted,
		TextSize = 12,
		FontFace = Theme.Font.Medium,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = head,
	})

	local chevron = Icons.new("chev", 14, colors.text_dim)
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, 0, 0.5, 0)
	chevron.Rotation = collapsed and 180 or 0;
	(chevron :: any).Parent = head

	local bodyWrap = Create("Frame", {
		Name = "BodyWrap",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
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

	-- Left rule. Scale height (1,0 on Y) fills bodyWrap natively; scale-sized
	-- children are ignored by AutomaticSize, so the rule can't feed back into
	-- bodyWrap's height and cause AbsoluteSizeChanged re-entrancy.
	Create("Frame", {
		Name = "Rule",
		Position = UDim2.fromOffset(2, 1),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = colors.border,
		BorderSizePixel = 0,
		Parent = bodyWrap,
	})

	-- Clipping holder owns the body's height so it slides open/closed.
	local holder, setCollapsed = Collapse.wrap(bodyWrap, collapsed)
	holder.LayoutOrder = 2
	holder.Parent = section

	head.Activated:Connect(function()
		collapsed = not collapsed
		Tween.play(chevron, Tween.Spin, { Rotation = collapsed and 180 or 0 })
		setCollapsed(collapsed, true)
	end)

	return section, body
end
