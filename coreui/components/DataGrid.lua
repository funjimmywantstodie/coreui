--!strict
-- components/DataGrid.lua — dense, high-refresh-rate row grid (memory/value
-- scanner, traffic log, instance browser, leaderboard...). Built on the same
-- "fixed-height viewport inside an AutomaticSize.Y field" pattern as Code.lua,
-- so the card/Collapse machinery needs no changes to host it.
--
-- Row frames are pooled and reused across :SetRows calls — only cells whose
-- value actually changed get a property write — since the intended workload
-- is a few hundred live rows updating several times a second, not a one-shot
-- render.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)
local Log = require(script.Parent.Parent.util.Log)
local Field = require(script.Parent.Field)

export type ActionDef = { Name: string, Text: string?, Icon: string? }
export type ColumnDef = {
	Key: string,
	Title: string?,
	Width: number, -- fraction (0..1) of the grid's content width
	Editable: boolean?,
	Type: ("text" | "actions")?,
}

local PAD = 12
local CELL_GAP = 10

-- Inner offset-based inset so column math sits in an unambiguous coordinate
-- space — avoids relying on how UIPadding does or doesn't interact with
-- Scale-positioned siblings (untested combination elsewhere in this codebase).
local function makeContent(parent: Instance): Frame
	return Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PAD, 0),
		Size = UDim2.new(1, -PAD * 2, 1, 0),
		Parent = parent,
	}) :: Frame
end

return function(ctx: any, opts: any): (Frame, any, boolean)
	local colors = Theme.Colors
	local where = Log.where("DataGrid", opts.Name)
	local f = Field.new(ctx, opts, true)

	local columns: { ColumnDef } = opts.Columns or {}
	local rowHeight = opts.RowHeight or 27
	local bodyHeight = opts.Height or 200

	local offsets: { number } = {}
	do
		local x = 0
		for i, col in columns do
			offsets[i] = x
			x += col.Width
		end
	end

	-- ── header ────────────────────────────────────────────────────────────────
	local header = Create("Frame", {
		Name = "Header",
		BackgroundColor3 = colors.control,
		Size = UDim2.new(1, 0, 0, rowHeight),
		LayoutOrder = 2,
		Parent = f.field,
	}, {
		Create.corner(Theme.Metrics.controlRadius),
		Create.stroke(colors.border),
	})
	local headerContent = makeContent(header)
	for i, col in columns do
		Create("TextLabel", {
			Name = "Head_" .. col.Key,
			BackgroundTransparency = 1,
			Position = UDim2.new(offsets[i], 0, 0, 0),
			Size = UDim2.new(col.Width, -CELL_GAP, 1, 0),
			Text = col.Title or col.Key,
			TextColor3 = colors.text_muted,
			TextSize = 12,
			FontFace = Theme.Font.Medium,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = headerContent,
		})
	end

	-- ── body (fixed-height scrolling viewport — the Code.lua pattern) ─────────
	local body = Create("ScrollingFrame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, bodyHeight),
		BackgroundColor3 = colors.control,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = colors.text_dim,
		ScrollBarImageTransparency = 0.35,
		LayoutOrder = 3,
		Parent = f.field,
	}, {
		Create.corner(Theme.Metrics.controlRadius),
		Create.stroke(colors.border),
		Create.listLayout({}),
	})

	local rowEdited = Instance.new("BindableEvent")
	local rowAction = Instance.new("BindableEvent")

	type RowEntry = {
		frame: Frame,
		id: any,
		data: { [string]: any },
		lastValues: { [string]: any },
		cells: { [string]: TextLabel | TextBox },
		actionHolders: { [string]: Frame },
	}

	-- Paint a button's face. Separate from the build because renderActions reuses
	-- a button by Name across renders, so an action that swaps its Icon ("lock" →
	-- "unlock") or its Text has to actually repaint instead of keeping whatever
	-- it was first built with. The icon name is stashed as an attribute so the
	-- common case — same action re-sent every tick — costs one comparison rather
	-- than a rebuilt instance.
	local function paintActionButton(btn: TextButton, action: ActionDef)
		-- Icon takes priority when both are given — a fixed-size icon button,
		-- Text unused. Text alone renders as an auto-width label pill.
		local iconOnly = action.Icon ~= nil
		btn.Size = iconOnly and UDim2.fromOffset(22, 22) or UDim2.new(0, 0, 0, 22)
		btn.AutomaticSize = iconOnly and Enum.AutomaticSize.None or Enum.AutomaticSize.X
		btn.Text = iconOnly and "" or (action.Text or action.Name)

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
			local icon = Icons.new(action.Icon, 14, colors.text_dim)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.Parent = btn
		end
	end

	local function buildActionButton(action: ActionDef): TextButton
		local btn = Create("TextButton", {
			Name = action.Name,
			AutoButtonColor = false,
			BackgroundColor3 = colors.control,
			Size = UDim2.fromOffset(22, 22),
			Text = "",
			TextColor3 = colors.text,
			TextSize = 12,
			FontFace = Theme.Font.Medium,
		}, {
			Create.corner(6),
			Create.padding(0, 8),
		}) :: TextButton

		Create.hover(btn, "BackgroundColor3", colors.control, colors.control_hi)
		return btn
	end

	-- Reuses buttons keyed by action Name across renders (repainting each for the
	-- action it now carries) and drops ones no longer present.
	local function renderActions(entry: RowEntry, key: string, actions: { ActionDef })
		local holder = entry.actionHolders[key]
		local seen: { [string]: boolean } = {}
		for i, action in actions do
			local child = holder:FindFirstChild(action.Name)
			local btn: TextButton
			if child and child:IsA("TextButton") then
				btn = child :: TextButton
			else
				btn = buildActionButton(action)
				btn.Parent = holder
				local name = action.Name
				btn.Activated:Connect(function()
					if entry.id ~= nil then
						rowAction:Fire(entry.id, name)
					end
				end)
			end
			paintActionButton(btn, action)
			btn.LayoutOrder = i
			seen[action.Name] = true
		end
		for _, child in holder:GetChildren() do
			if child:IsA("GuiObject") and not seen[child.Name] then
				child:Destroy()
			end
		end
	end

	local function buildRowFrame(): RowEntry
		local frame = Create("Frame", {
			Name = "Row",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, rowHeight),
		}) :: Frame
		Create("Frame", {
			Name = "Sep",
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.new(0, 0, 1, -1),
			BackgroundColor3 = colors.border_soft,
			BorderSizePixel = 0,
			Parent = frame,
		})
		local content = makeContent(frame)

		local entry: RowEntry = {
			frame = frame,
			id = nil,
			data = {},
			lastValues = {},
			cells = {},
			actionHolders = {},
		}

		for i, col in columns do
			local pos = UDim2.new(offsets[i], 0, 0, 0)
			local size = UDim2.new(col.Width, -CELL_GAP, 1, 0)

			if col.Type == "actions" then
				local holder = Create("Frame", {
					Name = "Cell_" .. col.Key,
					BackgroundTransparency = 1,
					Position = pos,
					Size = size,
					Parent = content,
				}, {
					Create.listLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 6),
					}),
				}) :: Frame
				entry.actionHolders[col.Key] = holder
			elseif col.Editable then
				local box = Create("TextBox", {
					Name = "Cell_" .. col.Key,
					Position = pos,
					Size = size,
					BackgroundColor3 = colors.control,
					ClearTextOnFocus = false,
					Text = "",
					TextColor3 = colors.text,
					TextSize = 12,
					FontFace = Theme.Font.Mono,
					TextXAlignment = Enum.TextXAlignment.Left,
					ClipsDescendants = true,
					Parent = content,
				}, {
					Create.corner(4),
					Create.stroke(colors.border),
					Create.padding(0, 6),
				}) :: TextBox
				local stroke = box:FindFirstChildOfClass("UIStroke") :: UIStroke
				-- The row this edit belongs to is captured when it starts, not read
				-- at blur: the frame is pooled, so an edit left open while :SetRows
				-- recycles it would otherwise commit the typed text against whichever
				-- id inherited the frame.
				local editingId: any = nil
				box.Focused:Connect(function()
					editingId = entry.id
					Tween.play(stroke, Tween.Fast, { Color = ctx.Accent })
				end)
				box.FocusLost:Connect(function()
					Tween.play(stroke, Tween.Fast, { Color = colors.border })
					local id = editingId
					editingId = nil
					if id ~= nil and id == entry.id then
						rowEdited:Fire(id, col.Key, box.Text)
					end
				end)
				entry.cells[col.Key] = box
			else
				local label = Create("TextLabel", {
					Name = "Cell_" .. col.Key,
					BackgroundTransparency = 1,
					Position = pos,
					Size = size,
					Text = "",
					TextColor3 = colors.text,
					TextSize = 12,
					FontFace = Theme.Font.Regular,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Parent = content,
				}) :: TextLabel
				entry.cells[col.Key] = label
			end
		end

		return entry
	end

	-- Writes `data` onto `entry`, touching only the cells whose value actually
	-- changed since the last render — the perf-critical path for fast tickers.
	local function applyRowData(entry: RowEntry, id: any, data: { [string]: any })
		entry.id = id
		entry.data = data
		for _, col in columns do
			local raw = data[col.Key]
			if entry.lastValues[col.Key] ~= raw then
				if col.Type == "actions" then
					entry.lastValues[col.Key] = raw
					renderActions(entry, col.Key, (raw :: { ActionDef }?) or {})
				else
					local cell = entry.cells[col.Key]
					local focused = col.Editable and (cell :: TextBox):IsFocused()
					if not focused then
						-- Only record the value once it's actually on screen. Marking
						-- it applied while the user was mid-edit made the skipped
						-- update permanent: the cell kept the stale text after blur.
						entry.lastValues[col.Key] = raw
						cell.Text = raw ~= nil and tostring(raw) or ""
					end
				end
			end
		end
	end

	local rowsById: { [any]: RowEntry } = {}
	local pool: { RowEntry } = {}

	local function acquireRow(): RowEntry
		local entry = table.remove(pool)
		if entry then
			return entry
		end
		return buildRowFrame()
	end

	local function releaseRow(entry: RowEntry)
		-- Cleared first, so the FocusLost below sees a row that no longer has an id
		-- and drops the half-finished edit instead of committing it.
		entry.id = nil
		entry.data = {}
		-- Drop the change-detection cache with the row: a pooled frame reused for a
		-- different id must repaint every cell, not diff against the old row's data.
		-- Blanking the cells is the other half of that — clearing the cache alone
		-- left the previous row's text and buttons on screen for any column the
		-- next row omits, because applyRowData compares `nil ~= nil` and skips.
		table.clear(entry.lastValues)
		for _, cell in entry.cells do
			if cell:IsA("TextBox") and cell:IsFocused() then
				cell:ReleaseFocus(false)
			end
			cell.Text = ""
		end
		for _, holder in entry.actionHolders do
			for _, child in holder:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
		end
		entry.frame.Parent = nil
		table.insert(pool, entry)
	end

	local grid = {}
	grid.RowEdited = rowEdited.Event
	grid.RowAction = rowAction.Event

	function grid:SetRows(rows: { { [string]: any } })
		local newIds: { [any]: { [string]: any } } = {}
		local order: { any } = {}
		for i, data in rows do
			local id = data.id
			if id == nil then
				-- One malformed row used to take the whole call down with "table index
				-- is nil" — for a grid refilled several times a second, that's the
				-- entire view gone over one bad entry.
				Log.warn(where, ("row #%d has no `id` — skipped."):format(i))
			else
				newIds[id] = data
				table.insert(order, id)
			end
		end

		for id, entry in rowsById do
			if not newIds[id] then
				releaseRow(entry)
				rowsById[id] = nil
			end
		end

		for i, id in order do
			local entry = rowsById[id]
			if not entry then
				entry = acquireRow()
				rowsById[id] = entry
				entry.frame.Parent = body
			end
			entry.frame.LayoutOrder = i
			applyRowData(entry, id, newIds[id])
		end
	end

	function grid:UpdateRow(id: any, patch: { [string]: any })
		local entry = rowsById[id]
		if not entry then
			return
		end
		local data = entry.data
		for k, v in patch do
			data[k] = v
		end
		applyRowData(entry, id, data)
	end

	function grid:RemoveRow(id: any)
		local entry = rowsById[id]
		if not entry then
			return
		end
		releaseRow(entry)
		rowsById[id] = nil
	end

	return f.field, grid, false
end
