--!strict
-- components/Field.lua — the row scaffold every control sits on.
--
-- Layout mirrors `.coreui-field` from the CSS: 10px vertical padding, a flex
-- row with a name/description block on the left and the control on the right.
-- "Stacked" fields (slider, input, full-width dropdown/button) drop the control
-- to its own full-width line below the row.
--
-- `Desc` has two ways to reach the user and the WINDOW picks between them
-- (`CreateWindow{ Descriptions = ... }`, live via `Window:SetDescriptions` →
-- `ctx.Descriptions`):
--
--   "inline"  a second line of prose under the name. Exactly what every control
--             used to do unconditionally, which is why a card of eight controls
--             was three screens tall.
--   "hover"   the default. The prose moves into components/Info.lua's popover,
--             behind a small glyph immediately after the name.
--   "both"    both, for a menu that wants the long form in the popover and a
--             one-liner on the row.
--
-- Everything mode-dependent is built by `apply` below and nothing else, so a
-- runtime switch re-lays out the fields already on screen rather than only the
-- ones built after it.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Log = require(script.Parent.Parent.util.Log)
local Info = require(script.Parent.Info)

-- Gap between the name and its info glyph. Tight on purpose: the glyph belongs to
-- the label, not to the row.
local GLYPH_GAP = 5

-- `Desc` is checked HERE rather than in components/Controls.lua's COMMON_SCHEMA
-- because this is the file that reads it — and because Button / ButtonRow reach a
-- field without going through `mount`, so a schema there would miss them.
local SCHEMA: Log.Schema = {
	{ "Desc", "string" },
	-- `false` opts one control out of the glyph: its description is inline in every
	-- mode. Same shape as `Toggle{ Keybind = false }`, and for the same reason —
	-- the window-wide default is a default, not a ban.
	{ "Info", { "table", "boolean" } },
}

local Field = {}

export type Field = {
	field: Frame, -- the whole field (parent for stacked controls)
	row: Frame,   -- the name | control row (parent for inline controls)
	main: Frame?, -- the name/description block, if a Name was given
}

function Field.new(ctx: any, opts: { Name: string?, Desc: string? }, stack: boolean?): Field
	local colors = Theme.Colors
	Log.check(Log.where("Control", opts.Name), opts, SCHEMA)

	local field = Create("Frame", {
		Name = "Field",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Create.padding(10, 2),
		Create.listLayout({ Padding = UDim.new(0, 9) }),
	})

	local ROW_GAP = 14
	local row = Create("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = field,
	}, {
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, ROW_GAP),
		}),
	})

	local main: Frame? = nil
	if opts.Name then
		local block = Create("Frame", {
			Name = "Main",
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = row,
		}, {
			Create.listLayout({ Padding = UDim.new(0, 3) }),
		})

		-- The mode-dependent half: either the title alone (LayoutOrder 1 in `block`,
		-- exactly as it always was) or a title row carrying the info glyph, plus the
		-- inline Desc line when the mode asks for one. `apply` owns all three.
		local titleTop: Instance? = nil
		local info: any = nil
		local syncMain: () -> ()

		local function makeTitle(parent: Instance, reserve: number): TextLabel
			return Create("TextLabel", {
				Name = "Title",
				BackgroundTransparency = 1,
				-- Offset-only width in both cases, so the glyph's gutter comes out of
				-- the wrap width rather than out of the layout.
				Size = UDim2.new(1, -reserve, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = opts.Name,
				TextColor3 = colors.text,
				TextSize = 13,
				FontFace = Theme.Font.Regular,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true,
				LayoutOrder = 1,
				Parent = parent,
			})
		end

		local function apply()
			if info then
				info:Destroy()
				info = nil
			end
			if titleTop then
				titleTop:Destroy()
				titleTop = nil
			end
			local descLine = block:FindFirstChild("Desc")
			if descLine then
				descLine:Destroy()
			end

			local mode = ctx.Descriptions
			-- `Info.spec` is the authority on "is there anything to show?", not a
			-- guess from `Desc ~= nil`: `Info = { Title = "x" }` has nothing a label
			-- doesn't already say, and a glyph that opens an empty card is worse than
			-- no glyph. Asking first is also what lets the Desc fall back to inline.
			local spec = if mode == "inline" then nil else Info.spec(opts)

			if spec then
				-- A plain frame, not a UIListLayout: the glyph is positioned at the end
				-- of the name's first LINE (see `placeGlyph`), which a layout can't do —
				-- it only knows the label's box, which is the full width.
				local titleRow = Create("Frame", {
					Name = "TitleRow",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = 1,
					Parent = block,
				})
				local title = makeTitle(titleRow, Info.Size + GLYPH_GAP)
				info = Info.attach(ctx, titleRow, spec)
				-- Hovering the NAME opens it too — the glyph is 13px and the label is
				-- the thing the user is actually reading.
				info:Watch(title)

				local slot = info.Slot
				local function placeGlyph()
					local room = title.AbsoluteSize.X
					local x = title.TextBounds.X + GLYPH_GAP
					if room > 0 then
						-- A wrapped title reports its widest line, which is ~the label
						-- width, so this parks the glyph in the reserved gutter instead of
						-- pushing it into the control beside it.
						x = math.min(x, room + GLYPH_GAP)
					end
					slot.Position = UDim2.fromOffset(math.max(0, math.floor(x)), 0)
				end
				placeGlyph()
				title:GetPropertyChangedSignal("TextBounds"):Connect(placeGlyph)
				title:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeGlyph)
				titleTop = titleRow
			else
				titleTop = makeTitle(block, 0)
			end

			-- Inline unless the glyph took the job. With no glyph (mode "inline", or
			-- `Info = false`, or nothing worth a popover) the description has nowhere
			-- else to be, so it stays on the row — a `Desc` never silently vanishes.
			if opts.Desc ~= nil and (mode ~= "hover" or spec == nil) then
				Create("TextLabel", {
					Name = "Desc",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = opts.Desc,
					TextColor3 = colors.text_muted,
					TextSize = 12,
					FontFace = Theme.Font.Regular,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextWrapped = true,
					LineHeight = 1.1,
					LayoutOrder = 2,
					Parent = block,
				})
			end

			syncMain()
		end
		main = block

		-- No flexbox: the label block consumes the row's leftover width so the
		-- control (added by the caller into `row`) lands flush right. Width is
		-- the row minus every sibling's measured width and the gap to each.
		syncMain = function()
			local used, others = 0, 0
			for _, child in row:GetChildren() do
				-- Visible siblings only: the layout skips a hidden one (a bind chip
				-- stood down on touch), so the name block gets its width back too.
				if child:IsA("GuiObject") and child ~= block and child.Visible then
					used += child.AbsoluteSize.X
					others += 1
				end
			end
			local avail = row.AbsoluteSize.X - used - others * ROW_GAP
			block.Size = UDim2.new(0, math.max(0, avail), 0, 0)
		end
		row:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncMain)
		row.ChildAdded:Connect(function(child)
			if child:IsA("GuiObject") then
				child:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncMain)
				child:GetPropertyChangedSignal("Visible"):Connect(syncMain)
			end
			task.defer(syncMain)
		end)
		task.defer(syncMain)

		apply()
		-- A live switch has to re-lay out what's already drawn, which is the whole
		-- reason a host can offer it as a setting. The subscription dies with the
		-- Context (one per window), so a field never outlives it.
		local unsubscribe = ctx:OnDescriptions(function()
			apply()
		end)
		field.Destroying:Connect(function()
			unsubscribe()
			if info then
				info:Destroy()
				info = nil
			end
		end)
	end

	return { field = field, row = row, main = main }
end

return Field
