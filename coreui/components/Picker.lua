--!strict
-- components/Picker.lua — the item gallery.
--
-- A searchable, filterable grid (or list) of pickable things with a thumbnail
-- each: skins, weapons, pets, maps — a few hundred cosmetics the user picks ONE
-- of. Every hub that shipped one of these built it out of components/DataGrid,
-- which is a data *table*: it has columns, not pictures, and no idea what
-- "selected" means. Six things had to be hand-rolled around it every time, and
-- all six are the component's job:
--
--   * a search Input above the grid, wired to a filter re-run per keystroke
--   * a rarity Dropdown doing the same thing again
--   * a fake row (`id = "_"`) standing in for an empty state, which the click
--     handler then has to special-case
--   * "which one is equipped" faked by swapping an action icon, because a table
--     has no selected-row state
--   * a manual cap at 80 rendered rows plus a "80 of 312" label, because
--     :SetRows builds one frame per row
--   * no thumbnail at all — a cosmetic picker without pictures is a spreadsheet
--
-- The cap is why this VIRTUALISES rather than pooling the way DataGrid does.
-- Cells are pooled *and* only the ones inside the viewport (plus a row of
-- overscan) are mounted at all, at manual positions inside a manually-sized
-- canvas — so :SetItems takes the whole catalogue and the instance count is
-- bounded by the window, not by the list. That rules out a UIListLayout in the
-- viewport: the layout owns its children's Position, and a virtualised canvas
-- has to own it instead.
--
--   local picker = Group:Picker({
--       Name = "Swords", Height = 260, Search = true,
--       Filters = { "All", "Legendary", { Name = "Favourites", Match = isFav } },
--       Items = { { id = "ghost", Title = "Ghost", Subtitle = "Legendary",
--                   Image = "https://…/ghost.png", Badge = "Dual" } },
--       Callback = function(id) equip(id) end,
--   })

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)
local Asset = require(script.Parent.Parent.util.Asset)
local Log = require(script.Parent.Parent.util.Log)
local Field = require(script.Parent.Field)

export type ActionDef = { Name: string, Text: string?, Icon: string? }
export type Item = {
	id: any,
	Title: string?,
	Subtitle: string?,
	Image: any?,
	Badge: string?,
	Tags: { string }?,
	Filter: string?,
	Selected: boolean?,
	Actions: { ActionDef }?,
}
export type FilterDef = { Name: string, All: boolean?, Match: ((Item) -> boolean)? }

-- `Layout` is typed `string` here and *valued* by normalizeLayout below — the
-- same split components/Tab.lua uses for Pin/Style: a wrong type is a mistake
-- about the API and fails, a wrong string is a typo and warns.
local SCHEMA: Log.Schema = {
	{ "Items", "table" },
	{ "Filters", "table" },
	{ "Layout", "string" },
	{ "Search", { "boolean", "string" } },
	{ "Height", "number" },
	{ "TileSize", "number" },
	{ "Empty", "string" },
	{ "Count", "boolean" },
	{ "OnAction", "function" },
}

local LAYOUTS: { [string]: boolean } = { tiles = true, rows = true }

local PAD = 2          -- inset between the viewport edge and the first cell
local GAP = 8          -- between cells, both axes
local SCROLL_W = 6     -- gutter kept clear of the scrollbar
local OVERSCAN = 1     -- extra cell rows mounted above and below the viewport
local ROW_H = 44       -- a "rows" cell
local TILE_TEXT_H = 34 -- the title/subtitle band under a tile's picture
local TILE_PAD = 6
local CHIP_H = 24
local CHIP_GAP = 6
local ACTION = 22
local THUMB = 32
local BADGE_H = 18

local function normalizeLayout(value: any, where: string): string
	if value == nil then
		return "tiles"
	end
	local wanted = if type(value) == "string" then value:lower() else nil
	if wanted and LAYOUTS[wanted] then
		return wanted
	end
	Log.warn(where, ('Layout must be "tiles" or "rows", got %s — using "tiles".')
		:format(if type(value) == "string" then ('"%s"'):format(value) else typeof(value)))
	return "tiles"
end

-- A chip is a name plus a rule. A string chip matches an item whose own `Filter`,
-- `Subtitle` or `Tags` name it — the shape a rarity or a category already has in
-- the data. A table chip may carry a `Match` predicate instead, which is the only
-- way to express "Favourites": that isn't a property of the item, it's a property
-- of the user, and the host is the only one who knows it.
local function chipSpec(value: any, index: number, where: string): FilterDef?
	if type(value) == "string" then
		return { Name = value, All = value:lower() == "all" }
	end
	if type(value) == "table" and type(value.Name) == "string" then
		local all = value.All
		if all == nil then
			all = value.Name:lower() == "all"
		end
		return { Name = value.Name, All = all == true, Match = value.Match }
	end
	Log.warn(where, ('filter #%d must be a string or { Name = ..., Match = ... }, got %s — skipped.')
		:format(index, typeof(value)))
	return nil
end

local function named(item: Item, want: string): boolean
	if type(item.Filter) == "string" and (item.Filter :: string):lower() == want then
		return true
	end
	if type(item.Subtitle) == "string" and (item.Subtitle :: string):lower() == want then
		return true
	end
	if type(item.Tags) == "table" then
		for _, tag in item.Tags :: { string } do
			if type(tag) == "string" and tag:lower() == want then
				return true
			end
		end
	end
	return false
end

type Cell = {
	frame: TextButton,
	stroke: UIStroke,
	image: ImageLabel,
	placeholder: GuiObject,
	check: Frame,
	badge: Frame,
	badgeText: TextLabel,
	actions: Frame,
	title: TextLabel,
	sub: TextLabel,
	setHover: (Color3, Color3) -> (),
	syncRow: () -> (),
	item: any,
	source: any,
}

return function(ctx: any, opts: any): (Frame, any, boolean)
	local colors = Theme.Colors
	opts = opts or {}
	local where = Log.where("Picker", opts.Name)
	Log.check(where, opts, SCHEMA)

	local layout = normalizeLayout(opts.Layout, where)
	local tiles = layout == "tiles"
	local tileTarget = math.max(48, math.floor(tonumber(opts.TileSize) or 84))
	local bodyHeight = math.max(80, math.floor(tonumber(opts.Height) or 260))
	local showCount = opts.Count ~= false
	local searchOn = opts.Search ~= nil and opts.Search ~= false

	local f = Field.new(ctx, opts, true)
	if not opts.Name and not opts.Desc then
		-- Nothing to draw on the name row, and an empty child still earns the
		-- field layout's 9px gap. UIListLayout skips invisible children.
		f.row.Visible = false
	end

	-- ── state ─────────────────────────────────────────────────────────────────
	local items: { Item } = {}    -- accepted, in order — the caller's own tables
	local byId: { [any]: Item } = {}
	local view: { Item } = {}     -- `items` after the active chip and the query
	local selectedId: any = nil
	local query = ""
	local filters: { FilterDef } = {}
	local activeFilter = 1

	-- Lowercased haystack per item, built once and dropped whenever that item's
	-- data can have moved (SetItems / UpdateItem). Weak keys, so a replaced list
	-- doesn't pin its old tables until the next reset.
	local textCache: { [any]: string } = setmetatable({}, { __mode = "k" }) :: any

	local function haystack(item: Item): string
		local hit = textCache[item]
		if hit then
			return hit
		end
		local parts = { tostring(item.id) }
		for _, value in { item.Title, item.Subtitle, item.Badge, item.Filter } do
			if type(value) == "string" then
				table.insert(parts, value :: string)
			end
		end
		if type(item.Tags) == "table" then
			for _, tag in item.Tags :: { string } do
				if type(tag) == "string" then
					table.insert(parts, tag)
				end
			end
		end
		local text = table.concat(parts, " "):lower()
		textCache[item] = text
		return text
	end

	local function passesFilter(item: Item): boolean
		local chip = filters[activeFilter]
		if not chip or chip.All then
			return true
		end
		if chip.Match then
			local ok, keep = pcall(chip.Match, item)
			if not ok then
				-- A host predicate throwing must not blank the gallery: it's their
				-- bug, but the list is ours.
				Log.warn(where, ('filter "%s" errored — item kept: %s'):format(chip.Name, tostring(keep)))
				return true
			end
			return keep == true
		end
		return named(item, chip.Name:lower())
	end

	local function rebuildView()
		table.clear(view)
		for _, item in items do
			if passesFilter(item) and (query == "" or string.find(haystack(item), query, 1, true) ~= nil) then
				table.insert(view, item)
			end
		end
	end

	-- ── toolbar: the search box and the count ─────────────────────────────────
	local countLabel: TextLabel? = nil
	local searchBox: TextBox? = nil
	if searchOn or showCount then
		local toolbar = Create("Frame", {
			Name = "Toolbar",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 32),
			LayoutOrder = 2,
			Parent = f.field,
		}) :: Frame

		if showCount then
			countLabel = Create("TextLabel", {
				Name = "Count",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 16),
				Text = "",
				TextColor3 = colors.text_dim,
				TextSize = 12,
				FontFace = Theme.Font.Regular,
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = toolbar,
			}) :: TextLabel
		end

		if searchOn then
			local searchField = Create("Frame", {
				Name = "Search",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundColor3 = colors.control,
				ClipsDescendants = true,
				Parent = toolbar,
			}, {
				Create.corner(Theme.Metrics.controlRadius),
				Create.stroke(colors.border),
				Create.padding(0, 10),
				Create.listLayout({
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
				}),
			}) :: Frame
			local searchIcon = Icons.new("search", 14, colors.text_dim)
			searchIcon.LayoutOrder = 1;
			(searchIcon :: any).Parent = searchField

			local box = Create("TextBox", {
				Name = "Box",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -22, 1, 0),
				Text = "",
				PlaceholderText = if type(opts.Search) == "string" then opts.Search else "Search",
				PlaceholderColor3 = colors.text_dim,
				TextColor3 = colors.text,
				TextSize = 13,
				FontFace = Theme.Font.Regular,
				TextXAlignment = Enum.TextXAlignment.Left,
				ClearTextOnFocus = false,
				LayoutOrder = 2,
				Parent = searchField,
			}) :: TextBox
			searchBox = box

			local searchStroke = searchField:FindFirstChildOfClass("UIStroke") :: UIStroke
			box.Focused:Connect(function()
				Tween.play(searchStroke, Tween.Fast, { Color = ctx.Accent })
			end)
			box.FocusLost:Connect(function()
				Tween.play(searchStroke, Tween.Fast, { Color = colors.border })
			end)

			-- The count sits at the right end of the same row, so the box gives up
			-- exactly the width the count measures — the "subtract the measured
			-- sibling" trick components/Field.lua uses, rather than an estimate that
			-- would clip one of the two.
			local label = countLabel
			if label then
				local function fitSearch()
					local reserve = label.AbsoluteSize.X
					searchField.Size = UDim2.new(1, if reserve > 0 then -(reserve + 12) else 0, 1, 0)
				end
				label:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitSearch)
				fitSearch()
			end
		end
	end

	-- ── filter chips ──────────────────────────────────────────────────────────
	-- Wrapped by hand. `UIListLayout.Wraps` is a recent property and this library
	-- runs on whatever engine the client is on; a horizontal layout without it
	-- pushes the last rarity past the card's edge with no way to reach it.
	local chipRow: Frame? = nil
	local chipButtons: { { def: FilterDef, button: TextButton, label: TextLabel } } = {}

	local function layoutChips()
		local row = chipRow
		if not row then
			return
		end
		local width = row.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local x, y = 0, 0
		for _, chip in chipButtons do
			local w = math.ceil(chip.button.AbsoluteSize.X)
			if w <= 0 then
				w = 48 -- not measured yet; its own AbsoluteSize signal re-runs this
			end
			if x > 0 and x + w > width then
				x, y = 0, y + CHIP_H + CHIP_GAP
			end
			chip.button.Position = UDim2.fromOffset(x, y)
			x += w + CHIP_GAP
		end
		row.Size = UDim2.new(1, 0, 0, y + CHIP_H)
	end

	local paintChips: () -> ()
	local refresh: (boolean?) -> ()

	local function buildChips(list: { any }?)
		for _, chip in chipButtons do
			chip.button:Destroy()
		end
		table.clear(chipButtons)

		local specs: { FilterDef } = {}
		for i, value in list or {} do
			local spec = chipSpec(value, i, where)
			if spec then
				table.insert(specs, spec)
			end
		end
		filters = specs
		activeFilter = 1
		if #specs == 0 then
			if chipRow then
				chipRow.Visible = false
			end
			return
		end

		local row = chipRow
		if not row then
			row = Create("Frame", {
				Name = "Filters",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, CHIP_H),
				LayoutOrder = 3,
				Parent = f.field,
			}) :: Frame
			chipRow = row
			row:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutChips)
		end
		row.Visible = true

		for i, spec in filters do
			local button = Create("TextButton", {
				Name = spec.Name,
				AutoButtonColor = false,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, CHIP_H),
				BackgroundColor3 = colors.control,
				Text = "",
				Parent = row,
			}, {
				Create.corner(999),
				Create.padding(0, 10),
			}) :: TextButton
			local label = Create("TextLabel", {
				Name = "Label",
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				Text = spec.Name,
				TextColor3 = colors.text_muted,
				TextSize = 12,
				FontFace = Theme.Font.Medium,
				Parent = button,
			}) :: TextLabel

			button:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutChips)
			local index = i
			button.Activated:Connect(function()
				if activeFilter == index then
					return
				end
				activeFilter = index
				paintChips()
				rebuildView()
				refresh(true)
			end)
			table.insert(chipButtons, { def = spec, button = button, label = label })
		end
		layoutChips()
	end

	paintChips = function()
		for i, chip in chipButtons do
			local on = i == activeFilter
			chip.button.BackgroundColor3 = if on then ctx.AccentSoft else colors.control
			chip.label.TextColor3 = if on then ctx.Accent else colors.text_muted
		end
	end

	-- ── viewport ──────────────────────────────────────────────────────────────
	-- `body` exists only to give the empty label a parent whose box is the
	-- viewport's: a scale position inside the ScrollingFrame resolves against the
	-- CANVAS, which is exactly zero-height at the one moment that label shows.
	local body = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, bodyHeight),
		LayoutOrder = 4,
		Parent = f.field,
	}) :: Frame

	-- The canvas is sized by hand (no AutomaticCanvasSize): only the cells inside
	-- the view exist, so there is nothing for the engine to measure.
	local viewport = Create("ScrollingFrame", {
		Name = "Items",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors.control,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = colors.text_dim,
		ScrollBarImageTransparency = 0.35,
		Parent = body,
	}, {
		Create.corner(Theme.Metrics.controlRadius),
		Create.stroke(colors.border),
	}) :: ScrollingFrame

	-- A real empty state, so a caller never has to smuggle one in as a fake item
	-- and then special-case it in the click handler.
	local empty = Create("TextLabel", {
		Name = "Empty",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 0, 18),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = colors.text_dim,
		TextSize = 13,
		FontFace = Theme.Font.Regular,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false,
		ZIndex = 2,
		Parent = body,
	}) :: TextLabel

	-- ── cells ─────────────────────────────────────────────────────────────────
	local cols, cellW, cellH = 0, 0, 0
	local mounted: { [number]: Cell } = {}
	local pool: { Cell } = {}
	local need: { [number]: boolean } = {}
	local firstMounted, lastMounted = 0, -1

	-- The selected cell is an accent-tinted tile with an accent border and a check
	-- over its art — the active-nav treatment, not a second accent per row.
	local function paintSelected(cell: Cell, on: boolean)
		cell.check.Visible = on
		cell.check.BackgroundColor3 = ctx.Accent
		cell.stroke.Color = if on then ctx.Accent else colors.border
		-- Rows carry no idle border (44 of them, each hair-lined, reads as noise);
		-- tiles do, because a tile without one has no edge at all.
		cell.stroke.Transparency = if on then 0 elseif tiles then 0 else 1
		cell.setHover(
			if on then ctx.AccentSoft else colors.control,
			if on then ctx.AccentSoft else colors.control_hi
		)
	end

	local function select(id: any, fire: boolean)
		selectedId = id
		for _, cell in mounted do
			local item = cell.item
			if item then
				paintSelected(cell, item.id == selectedId)
			end
		end
		if fire and opts.Callback then
			task.spawn(opts.Callback, id, byId[id])
		end
	end

	local function buildCell(): Cell
		local frame = Create("TextButton", {
			Name = "Cell",
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = colors.control,
			ClipsDescendants = true,
		}, {
			Create.corner(if tiles then 8 else 6),
			Create.stroke(colors.border),
		}) :: TextButton
		local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke

		-- The picture. In "tiles" it's square: the frame is `cellW` wide and
		-- `cellW + TILE_TEXT_H` tall, so taking the text band and the padding off
		-- the height leaves exactly the width back — no cellW in the expression, so
		-- a resize doesn't have to reach in here.
		local art = Create("Frame", {
			Name = "Art",
			AnchorPoint = if tiles then Vector2.new(0, 0) else Vector2.new(0, 0.5),
			Position = if tiles then UDim2.fromOffset(TILE_PAD, TILE_PAD) else UDim2.new(0, 8, 0.5, 0),
			Size = if tiles
				then UDim2.new(1, -TILE_PAD * 2, 1, -(TILE_TEXT_H + TILE_PAD * 2))
				else UDim2.fromOffset(THUMB, THUMB),
			BackgroundColor3 = colors.control_hi,
			ClipsDescendants = true,
			Parent = frame,
		}, { Create.corner(6) }) :: Frame

		local image = Create("ImageLabel", {
			Name = "Picture",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = "",
			ScaleType = Enum.ScaleType.Crop,
			Parent = art,
		}) :: ImageLabel
		-- Never hidden by the load result, only covered by it: an ImageLabel the
		-- engine isn't rendering never loads at all (util/Asset.lua).
		local placeholder = Icons.new("image", if tiles then 20 else 14, colors.text_dim)
		placeholder.AnchorPoint = Vector2.new(0.5, 0.5)
		placeholder.Position = UDim2.fromScale(0.5, 0.5);
		(placeholder :: any).Parent = art

		local checkSize = if tiles then 20 else 16
		local check = Create("Frame", {
			Name = "Check",
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(checkSize, checkSize),
			BackgroundColor3 = ctx.Accent,
			Visible = false,
			Parent = art,
		}, { Create.corner(999) }) :: Frame
		local checkIcon = Icons.new("check", if tiles then 12 else 10, colors.knockout)
		checkIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		checkIcon.Position = UDim2.fromScale(0.5, 0.5);
		(checkIcon :: any).Parent = check

		-- In "tiles" the badge and the actions overlay the picture; in "rows" they
		-- share a right-hand cluster that the text block makes room for.
		local right: Frame? = nil
		local cluster: Instance = art
		if not tiles then
			right = Create("Frame", {
				Name = "Right",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(0, ACTION),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				Parent = frame,
			}, {
				Create.listLayout({
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, CHIP_GAP),
				}),
			}) :: Frame
			cluster = right :: Frame
		end

		local badge = Create("Frame", {
			Name = "Badge",
			AnchorPoint = if tiles then Vector2.new(0, 1) else Vector2.new(0, 0),
			Position = if tiles then UDim2.new(0, 4, 1, -4) else UDim2.new(),
			Size = UDim2.fromOffset(0, BADGE_H),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = ctx.AccentSoft,
			Visible = false,
			LayoutOrder = 1,
			Parent = cluster,
		}, {
			Create.corner(999),
			Create.padding(0, 7),
		}) :: Frame
		local badgeText = Create("TextLabel", {
			Name = "Text",
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			Text = "",
			TextColor3 = ctx.Accent,
			TextSize = 11,
			FontFace = Theme.Font.Medium,
			Parent = badge,
		}) :: TextLabel

		local actions = Create("Frame", {
			Name = "Actions",
			AnchorPoint = if tiles then Vector2.new(1, 0) else Vector2.new(0, 0),
			Position = if tiles then UDim2.new(1, -4, 0, 4) else UDim2.new(),
			Size = UDim2.fromOffset(0, ACTION),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Visible = false,
			LayoutOrder = 2,
			Parent = cluster,
		}, {
			Create.listLayout({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 4),
			}),
		}) :: Frame

		-- One vertical layout for the two lines in both modes, centred: an item
		-- with no Subtitle then draws its title on the cell's centre line instead
		-- of hanging above an empty second row.
		local texts = Create("Frame", {
			Name = "Texts",
			BackgroundTransparency = 1,
			Position = if tiles
				then UDim2.new(0, TILE_PAD, 1, -(TILE_TEXT_H + TILE_PAD - 4))
				else UDim2.new(0, 8 + THUMB + 10, 0, 0),
			Size = if tiles
				then UDim2.new(1, -TILE_PAD * 2, 0, TILE_TEXT_H - 4)
				else UDim2.new(1, -(8 + THUMB + 10 + 8), 1, 0),
			Parent = frame,
		}, {
			Create.listLayout({
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 1),
			}),
		}) :: Frame

		local title = Create("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 15),
			Text = "",
			TextColor3 = colors.text,
			TextSize = 13,
			FontFace = Theme.Font.Medium,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 1,
			Parent = texts,
		}) :: TextLabel
		local sub = Create("TextLabel", {
			Name = "Subtitle",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 13),
			Text = "",
			TextColor3 = colors.text_muted,
			TextSize = 11,
			FontFace = Theme.Font.Regular,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Visible = false,
			LayoutOrder = 2,
			Parent = texts,
		}) :: TextLabel

		local _, setHover = Create.hover(frame, "BackgroundColor3", colors.control, colors.control_hi)

		-- A row's text block ends where the badge/action cluster starts, and that
		-- cluster is AutomaticSize.X — so its width is measured, never estimated.
		local function syncRow()
			local holder = right
			if tiles or not holder then
				return
			end
			local reserve = 8 + THUMB + 10 + 8
			local rightW = holder.AbsoluteSize.X
			if rightW > 0 then
				reserve += rightW + 10
			end
			texts.Size = UDim2.new(1, -reserve, 1, 0)
		end
		if right then
			(right :: Frame):GetPropertyChangedSignal("AbsoluteSize"):Connect(syncRow)
		end

		local cell: Cell = {
			frame = frame,
			stroke = stroke,
			image = image,
			placeholder = placeholder,
			check = check,
			badge = badge,
			badgeText = badgeText,
			actions = actions,
			title = title,
			sub = sub,
			setHover = setHover,
			syncRow = syncRow,
			item = nil,
			source = nil,
		}

		frame.Activated:Connect(function()
			local item = cell.item
			if item and item.id ~= nil then
				-- Tagged as user-driven for Context:OnFlagChanged; handle:Select
				-- reaches the same state through its own path and keeps its own tag.
				ctx:User(select, item.id, true)
			end
		end)

		return cell
	end

	-- Action buttons are reused by Name across the items a cell is recycled
	-- through, and repainted for whatever that action now is — the rule
	-- components/DataGrid.lua's renderActions follows, for the same reason: a
	-- "fav" button whose icon flips star → star-off has to actually repaint.
	local function paintActionButton(btn: TextButton, action: ActionDef)
		local iconOnly = action.Icon ~= nil
		btn.Size = if iconOnly then UDim2.fromOffset(ACTION, ACTION) else UDim2.new(0, 0, 0, ACTION)
		btn.AutomaticSize = if iconOnly then Enum.AutomaticSize.None else Enum.AutomaticSize.X
		btn.Text = if iconOnly then "" else (action.Text or action.Name)
		if btn:GetAttribute("icon") == action.Icon then
			return
		end
		btn:SetAttribute("icon", action.Icon)
		local old = btn:FindFirstChild("Icon")
		if old then
			-- Rebuilt rather than Icons.apply'd: apply no-ops on an unknown name and
			-- can't cross between the ImageLabel and the glyph-TextLabel fallback.
			old:Destroy()
		end
		if action.Icon then
			local icon = Icons.new(action.Icon, 13, colors.text_muted)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5);
			(icon :: any).Parent = btn
		end
	end

	local function renderActions(cell: Cell, list: { ActionDef }?)
		local actions = list or {}
		local seen: { [string]: boolean } = {}
		local count = 0
		for i, action in actions do
			if type(action) == "table" and type(action.Name) == "string" then
				count += 1
				local child = cell.actions:FindFirstChild(action.Name)
				local btn: TextButton
				if child and child:IsA("TextButton") then
					btn = child :: TextButton
				else
					btn = Create("TextButton", {
						Name = action.Name,
						AutoButtonColor = false,
						BackgroundColor3 = colors.control,
						-- Over the art in tiles, so it lifts off the picture without
						-- hiding it.
						BackgroundTransparency = if tiles then 0.1 else 0,
						Size = UDim2.fromOffset(ACTION, ACTION),
						Text = "",
						TextColor3 = colors.text_muted,
						TextSize = 11,
						FontFace = Theme.Font.Medium,
						Parent = cell.actions,
					}, {
						Create.corner(6),
						Create.padding(0, 7),
					}) :: TextButton
					Create.hover(btn, "BackgroundColor3", colors.control, colors.control_hi)
					local name = action.Name
					-- A GuiButton over the cell absorbs the click, so pressing an action
					-- never also selects the item it belongs to.
					btn.Activated:Connect(function()
						local item = cell.item
						if item and item.id ~= nil and opts.OnAction then
							task.spawn(opts.OnAction, item.id, name, item)
						end
					end)
				end
				paintActionButton(btn, action)
				btn.LayoutOrder = i
				seen[action.Name] = true
			end
		end
		cell.actions.Visible = count > 0
		for _, child in cell.actions:GetChildren() do
			if child:IsA("GuiObject") and not seen[child.Name] then
				child:Destroy()
			end
		end
	end

	local function paintImage(cell: Cell, source: any)
		if cell.source == source then
			return -- scrolled back onto the same art, or repainted for a re-theme
		end
		cell.source = source
		cell.placeholder.Visible = true
		-- Cleared on rebind (never because a load failed — see util/Asset.lua):
		-- the cell is recycled, so leaving the previous item's art up would show
		-- the wrong picture under the new name until the new one resolves.
		cell.image.Image = ""
		if source == nil or source == "" then
			return
		end
		Asset.load(cell.image, source, function(loaded)
			if cell.source ~= source then
				return -- recycled while the fetch was in flight
			end
			cell.placeholder.Visible = not loaded
		end)
	end

	local function paint(cell: Cell, item: Item)
		cell.item = item
		cell.title.Text = tostring(item.Title or item.id)
		cell.sub.Text = if type(item.Subtitle) == "string" then item.Subtitle :: string else ""
		cell.sub.Visible = cell.sub.Text ~= ""
		local badge = item.Badge
		cell.badge.Visible = badge ~= nil
		if badge ~= nil then
			cell.badgeText.Text = tostring(badge)
			cell.badge.BackgroundColor3 = ctx.AccentSoft
			cell.badgeText.TextColor3 = ctx.Accent
		end
		paintSelected(cell, item.id == selectedId)
		paintImage(cell, item.Image)
		renderActions(cell, item.Actions)
		cell.syncRow()
	end

	local function place(cell: Cell, index: number)
		local zero = index - 1
		local row = zero // cols
		local col = zero % cols
		cell.frame.Size = UDim2.fromOffset(cellW, cellH)
		cell.frame.Position = UDim2.fromOffset(PAD + col * (cellW + GAP), PAD + row * (cellH + GAP))
		if cell.frame.Parent ~= viewport then
			cell.frame.Parent = viewport
		end
	end

	local function release(cell: Cell)
		cell.item = nil
		cell.frame.Parent = nil
		table.insert(pool, cell)
	end

	-- Columns and cell size come off the viewport's real width, so tiles fill the
	-- row evenly instead of leaving a ragged gutter: `TileSize` is the width a
	-- tile aims for, not one it always gets.
	local function measure(): boolean
		local width = math.floor(viewport.AbsoluteSize.X) - PAD * 2 - SCROLL_W
		if width < 40 then
			return false -- not laid out yet; the AbsoluteSize signal comes back
		end
		local nc, w, h
		if tiles then
			nc = math.max(1, math.floor((width + GAP) / (tileTarget + GAP)))
			w = math.floor((width - (nc - 1) * GAP) / nc)
			h = w + TILE_TEXT_H
		else
			nc, w, h = 1, width, ROW_H
		end
		if nc == cols and w == cellW and h == cellH then
			return false
		end
		cols, cellW, cellH = nc, w, h
		return true
	end

	local function updateCanvas()
		local rowCount = if cols > 0 then math.ceil(#view / cols) else 0
		local height = if rowCount > 0 then PAD * 2 + rowCount * cellH + (rowCount - 1) * GAP else 0
		viewport.CanvasSize = UDim2.fromOffset(0, height)
	end

	-- The virtual window: mount the cell rows the viewport is actually showing
	-- (plus OVERSCAN either side), release everything else back to the pool.
	local function repaint(force: boolean?)
		if cellW <= 0 or cellH <= 0 or cols <= 0 then
			return
		end
		local n = #view
		local rowCount = math.ceil(n / cols)
		local stride = cellH + GAP
		local top = viewport.CanvasPosition.Y
		local firstRow = math.max(1, math.floor((top - PAD) / stride) + 1 - OVERSCAN)
		local lastRow = math.min(rowCount, math.ceil((top + viewport.AbsoluteSize.Y - PAD) / stride) + OVERSCAN)
		-- Scrolling fires CanvasPosition every frame, and most of those frames are
		-- still showing the same rows.
		if not force and firstRow == firstMounted and lastRow == lastMounted then
			return
		end
		firstMounted, lastMounted = firstRow, lastRow

		table.clear(need)
		for row = firstRow, lastRow do
			local base = (row - 1) * cols
			for col = 1, cols do
				local index = base + col
				if index <= n then
					need[index] = true
				end
			end
		end
		for index, cell in mounted do
			if not need[index] then
				release(cell)
				mounted[index] = nil
			end
		end
		for index in need do
			local cell = mounted[index]
			if not cell then
				cell = table.remove(pool) or buildCell()
				mounted[index] = cell
			end
			place(cell, index)
			local item = view[index]
			-- Identity, not equality: a pooled cell reused for a different item
			-- repaints, and one that scrolled off and back doesn't.
			if force or cell.item ~= item then
				paint(cell, item)
			end
		end
	end

	local function countText(): string
		local shown, total = #view, #items
		if shown == total then
			return ("%d item%s"):format(total, if total == 1 then "" else "s")
		end
		return ("%d of %d"):format(shown, total)
	end

	local function emptyText(): string
		if #items == 0 then
			return if type(opts.Empty) == "string" then opts.Empty else "Nothing here yet"
		end
		if query ~= "" then
			return ('No match for "%s"'):format(query)
		end
		return "Nothing matches"
	end

	refresh = function(force: boolean?)
		local moved = measure()
		updateCanvas()
		empty.Visible = #view == 0
		if empty.Visible then
			empty.Text = emptyText()
		end
		if countLabel then
			countLabel.Text = countText()
		end
		repaint(force == true or moved)
	end

	local function setItems(list: { Item }?)
		table.clear(items)
		table.clear(byId)
		local dropped, firstBad, dupes = 0, 0, 0
		for i, item in list or {} do
			if type(item) ~= "table" or item.id == nil then
				-- One malformed entry used to take a hand-rolled gallery's whole
				-- render down; here it costs itself and nothing else.
				dropped += 1
				if firstBad == 0 then
					firstBad = i
				end
			elseif byId[item.id] ~= nil then
				-- Two items under one id means :Select, :UpdateItem and the check mark
				-- all disagree about which one they mean.
				dupes += 1
			else
				byId[item.id] = item
				table.insert(items, item)
				textCache[item] = nil
				if item.Selected == true then
					selectedId = item.id
				end
			end
		end
		if dropped > 0 then
			Log.warn(where, ("%d item(s) have no `id` (first at #%d) — skipped."):format(dropped, firstBad))
		end
		if dupes > 0 then
			Log.warn(where, ("%d item(s) repeat an `id` already in the list — skipped."):format(dupes))
		end
	end

	-- ── wiring ────────────────────────────────────────────────────────────────
	if searchBox then
		local box = searchBox :: TextBox
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local typed = box.Text:lower()
			if typed == query then
				return
			end
			query = typed
			rebuildView()
			-- Back to the top: the old scroll offset points into a list that no
			-- longer has those rows, so it lands on an arbitrary part of the results.
			viewport.CanvasPosition = Vector2.new(0, 0)
			refresh(true)
		end)
	end

	viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		refresh()
	end)
	viewport:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		repaint()
	end)

	ctx:RegisterAccent(function()
		paintChips()
		for _, cell in mounted do
			if cell.item then
				paint(cell, cell.item)
			end
		end
	end)

	buildChips(opts.Filters)
	paintChips()
	setItems(opts.Items)
	if opts.Default ~= nil then
		selectedId = opts.Default
	end
	rebuildView()
	-- The viewport has no measured width until it has been laid out, so the first
	-- real fill happens a step later; everything above is state, not paint.
	task.defer(function()
		if viewport.Parent then
			refresh(true)
		end
	end)

	local handle = {}

	-- Replace the catalogue. Item tables are held by reference (UpdateItem writes
	-- into them), the scroll offset is left where the user put it, and an item
	-- carrying `Selected = true` becomes the selection — otherwise the current one
	-- is kept even if it isn't in the new list, so a list that comes and goes
	-- doesn't forget what's equipped.
	function handle:SetItems(list: { Item }?)
		setItems(list)
		rebuildView()
		refresh(true)
	end

	-- Patch one item in place — the "toggle a favourite" path, which otherwise
	-- means handing the whole catalogue back to redraw one star. Selection moved
	-- this way is data, not a pick, so it doesn't fire `Callback`.
	function handle:UpdateItem(id: any, patch: { [string]: any })
		local item = byId[id]
		if not item or type(patch) ~= "table" then
			return
		end
		for key, value in patch do
			if key ~= "id" then -- moving an id would orphan the item in byId
				item[key] = value
			end
		end
		textCache[item] = nil
		if patch.Selected == true then
			selectedId = id
		elseif patch.Selected == false and selectedId == id then
			selectedId = nil
		end
		rebuildView() -- a patched Title/Tags can change whether it still matches
		refresh(true)
	end

	-- Replace the chip row. The active chip is kept if the new list still has one
	-- by that name, so a host refreshing its categories doesn't yank the user back
	-- to "All" mid-browse.
	function handle:SetFilters(list: { any }?)
		local previous = filters[activeFilter]
		buildChips(list)
		if previous then
			for i, spec in filters do
				if spec.Name == previous.Name then
					activeFilter = i
					break
				end
			end
		end
		paintChips()
		rebuildView()
		refresh(true)
	end

	-- Fires `Callback`, like every other control's `:Set`.
	function handle:Select(id: any)
		select(id, true)
	end

	function handle:GetSelected(): (any, Item?)
		return selectedId, byId[selectedId]
	end

	-- The Flag pair. A picker's value is which item is picked, so `Get`/`Set` are
	-- the selection under the names Context:GetConfig / LoadConfig look for.
	function handle:Get(): any
		return selectedId
	end
	function handle:Set(id: any)
		select(id, true)
	end

	-- The accepted items, in view order-independent build order — what SetItems
	-- kept after the `id` checks, which is not necessarily what was handed in.
	function handle:GetItems(): { Item }
		return items
	end

	-- Opt-in build-time fire: `Default` on its own never runs `Callback`
	-- (see COMMON_SCHEMA in components/Controls.lua for why it stays opt-in).
	if opts.FireDefault == true and opts.Callback then
		task.spawn(opts.Callback, selectedId, byId[selectedId])
	end

	return f.field, handle, true
end
