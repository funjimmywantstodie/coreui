--!strict
-- components/Paragraph.lua — optional title + body copy.
--
-- `handle:Set(body)` / `handle:SetTitle(title)` rewrite the copy in place, so a
-- paragraph can carry changing prose (a status line, a scan summary) without the
-- caller reaching for a Label and losing the wrap.
--
-- The title label is built lazily: most paragraphs never have one, and an empty
-- TextLabel in the layout is a stray 0-height child plus the list's 5px gap.
-- `SetTitle` builds it the first time it's given one and hides it again when
-- it's given nothing — UIListLayout skips invisible children, so the gap goes
-- with it.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)

return function(ctx: any, opts: any)
	local colors = Theme.Colors

	local p = Create("Frame", {
		Name = "Paragraph",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Create.padding(11, 2),
		Create.listLayout({ Padding = UDim.new(0, 5) }),
	})

	local title: TextLabel? = nil
	local function setTitle(text: any)
		local str = (text == nil or text == "") and "" or tostring(text)
		if str == "" then
			if title then
				title.Visible = false
			end
			return
		end
		if not title then
			title = Create("TextLabel", {
				Name = "Title",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = "",
				TextColor3 = colors.text,
				TextSize = 13,
				FontFace = Theme.Font.Medium,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				LayoutOrder = 1,
				Parent = p,
			})
		end
		local label = title :: TextLabel
		label.Text = str
		label.Visible = true
	end

	if opts.Title then
		setTitle(opts.Title)
	end

	local body = Create("TextLabel", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = opts.Body or "",
		TextColor3 = colors.text_muted,
		TextSize = 12,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		LineHeight = 1.3,
		LayoutOrder = 2,
		Parent = p,
	})

	local handle = {}
	-- Replace the body copy.
	function handle:Set(text: any)
		body.Text = text == nil and "" or tostring(text)
	end
	-- Replace (or, with nil / "", drop) the title above it.
	function handle:SetTitle(text: any)
		setTitle(text)
	end

	return p, handle, true
end
