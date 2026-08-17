--!strict
-- components/Info.lua — a control's description, as a popover behind a glyph.
--
-- Why this exists: `Desc` used to be a second line of prose under every control's
-- name, unconditionally, so a card with eight controls was three screens tall and
-- the panel read as documentation with switches buried in it. The prose is worth
-- keeping — it's the difference between a menu you can use and one you guess at —
-- so it moves behind a glyph instead of being deleted. Which mode a window is in
-- is `ctx.Descriptions` (`CreateWindow{ Descriptions = ... }`,
-- `Window:SetDescriptions`); components/Field.lua is the only caller.
--
-- Four things hold this up:
--
-- * **The glyph is the entire affordance.** There is no `cursor: help` in Roblox
--   and no hover at all on touch, so a row with something to say has to *look*
--   like one — otherwise the description isn't hidden, it's gone. It's dim, 13px,
--   and sits immediately after the name, inside the label rather than on the row:
--   a description must not cost a pixel of row height, which is the whole reason
--   this feature exists. A control with nothing to say gets no glyph and no gap.
-- * **Tone is not decoration.** `Note.Tone` tints the glyph amber / red, which is
--   the point of having tones at all: a row hiding a performance cost or a footgun
--   advertises that it does, instead of looking identical to one hiding "Skip
--   teammates."
-- * **Pinning is load-bearing, not a nicety.** Hover alone can't survive the user
--   moving the mouse onto the slider the description is *about*, and on touch
--   there is no hover to survive — `MouseEnter` never fires there, so the tap that
--   pins is the only way in at all. That's also why the hitbox is 24px around a
--   13px glyph: the drawn size is a typographic decision, the target size isn't.
-- * **Pinned goes through `ctx:OpenPopover`, hover does not.** That manager
--   installs a full-overlay click catcher, which is exactly right for a pinned
--   panel (click anywhere = dismiss, and on touch that's the only dismiss) and
--   exactly wrong for a hover one — it would eat the click on the control the
--   description is describing.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Fade = require(script.Parent.Parent.util.Fade)
local Icons = require(script.Parent.Parent.Icons)
local Log = require(script.Parent.Parent.util.Log)

local Info = {}

-- The glyph as drawn, matched to the 13px Name label it follows.
Info.Size = 13
-- One line of that label. The SLOT is this tall (not the hitbox's 24), because the
-- slot is what the field measures — see the hitbox note in `Info.attach`.
local LINE = 15
-- The touch/click target around it. 13px is not a target.
local HIT = 24
-- Hover dwell before the popover appears. Long enough that dragging the cursor
-- across a card doesn't strobe every glyph it passes; short enough to feel like a
-- tooltip rather than a timeout.
local DELAY = 0.3
local WIDTH = 260
local MIN_WIDTH, MAX_WIDTH = 160, 420

-- Everything the `Info` table accepts. Declared here, not at the call site, for
-- the reason util/Log.lua spells out: the shape belongs next to the code reading it.
local SCHEMA: Log.Schema = {
	{ "Title", "string" },
	{ "Text", "string" },
	{ "Bullets", "table" },
	{ "Fields", "table" },
	{ "Note", { "table", "string" } },
	{ "Icon", "string" },
	{ "Width", "number" },
	{ "Tone", "string" },
}

local TONE_ICON: { [string]: string } = {
	info = "info",
	warning = "warning",
	danger = "error",
}

-- Tones are matched case-insensitively, and the two aliases the rest of the
-- library already accepts ("warn" for warning, "error" for danger — see
-- components/Notify.lua) work here too. Anything unrecognized is `info`: a
-- misspelled tone must not be the reason a footgun goes unannounced, so it
-- degrades to a described row rather than to no row.
local function toneOf(value: any): string
	local tone = type(value) == "string" and value:lower() or "info"
	if tone == "warn" then
		tone = "warning"
	elseif tone == "error" then
		tone = "danger"
	end
	if tone ~= "warning" and tone ~= "danger" then
		tone = "info"
	end
	return tone
end

-- The glyph's idle / hovered colours. `info` is the DIM text colour and
-- deliberately not the accent: the glyph lands on every describable row in the
-- menu, and a green dot on half of them is noise, not emphasis. The two tones
-- that mean something keep their semantic colour, because that's the message.
local function glyphColors(tone: string): (Color3, Color3)
	local colors = Theme.Colors
	if tone == "warning" then
		return colors.warning, colors.warning:Lerp(colors.white, 0.22)
	elseif tone == "danger" then
		return colors.danger, colors.danger:Lerp(colors.white, 0.22)
	end
	return colors.text_dim, colors.text
end

local function str(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

-- ── content ─────────────────────────────────────────────────────────────────
-- Resolve `opts.Desc` + `opts.Info` into what the popover will actually draw, or
-- `nil` when that's nothing. Nothing here is required: every field runs through
-- `str()` / a type test and simply doesn't produce a row when it's unusable, the
-- same contract components/Screen.lua holds itself to. A `Title` on its own
-- resolves to nil, because a title is the label the glyph is already sitting next
-- to — a popover that only repeats it says nothing.
function Info.spec(opts: any): any?
	if opts == nil or opts.Info == false then
		return nil
	end
	local raw = type(opts.Info) == "table" and opts.Info or nil
	if raw == nil and str(opts.Desc) == nil then
		return nil
	end
	if raw then
		Log.check(Log.where("Info", opts.Name), raw, SCHEMA)
	end

	local spec: any = {
		title = (raw and str(raw.Title)) or str(opts.Name),
		-- `Text` defaults to `Desc` and overrides it, so a popover can read longer
		-- than the inline line the same control shows in "inline"/"both" mode.
		text = (raw and str(raw.Text)) or str(opts.Desc),
		bullets = nil,
		fields = nil,
		note = nil,
		icon = (raw and str(raw.Icon)) or "info",
		width = WIDTH,
		tone = "info",
	}

	if raw then
		if type(raw.Bullets) == "table" then
			local out: { string } = {}
			for _, value in raw.Bullets do
				local text = str(value)
				if text then
					table.insert(out, text)
				end
			end
			spec.bullets = #out > 0 and out or nil
		end
		if type(raw.Fields) == "table" then
			local out: { { string } } = {}
			for _, pair in raw.Fields do
				if type(pair) == "table" then
					-- `{ "Cost", "1 ray" }` is the documented form; the named one is
					-- accepted because it's what someone writes without checking.
					local key = str(pair[1]) or str(pair.Key)
					local value = str(pair[2]) or str(pair.Value)
					if key then
						table.insert(out, { key, value or "" })
					end
				end
			end
			spec.fields = #out > 0 and out or nil
		end
		local note: any = raw.Note
		if type(note) == "string" then
			note = { Text = note }
		end
		if type(note) == "table" then
			local text = str(note.Text)
			if text then
				spec.note = { text = text, tone = toneOf(note.Tone) }
			end
		end
		-- What the glyph advertises: an explicit `Tone` wins, otherwise the note's.
		-- A footgun stated in the note is exactly the thing the glyph should be
		-- carrying out to the row.
		spec.tone = toneOf(raw.Tone or (spec.note and spec.note.tone))
		local width = tonumber(raw.Width)
		if width then
			spec.width = math.clamp(math.floor(width), MIN_WIDTH, MAX_WIDTH)
		end
	end

	if not (spec.text or spec.bullets or spec.fields or spec.note) then
		return nil
	end
	return spec
end

-- Every text row in the popover is the same label with two or three fields
-- changed, so the shared half is written once.
local function label(props: { [string]: any }): TextLabel
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 12,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	}
	for key, value in props do
		merged[key] = value
	end
	return Create("TextLabel", merged)
end

local function stack(name: string, order: number, parent: Instance, padding: number): Frame
	return Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	}, {
		Create.listLayout({ Padding = UDim.new(0, padding) }),
	})
end

-- The panel itself: a `pop` card with one border and the window's own radius, so
-- it reads as the same object family as a dropdown menu rather than a tooltip
-- bolted on. Fixed width (auto-height) — wrapped prose needs a width to wrap at,
-- and a popover that sizes to its longest line is a 500px ribbon.
local function build(ctx: any, spec: any): (Frame, { () -> () })
	local colors = Theme.Colors
	local cleanup: { () -> () } = {}

	local menu = Create("Frame", {
		Name = "InfoPopover",
		Visible = false,
		BackgroundColor3 = colors.pop,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(spec.width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 60,
	}, {
		Create.corner(9),
		Create.stroke(colors.border),
		Create.padding(10, 12),
		Create.listLayout({ Padding = UDim.new(0, 7) }),
	})

	local n = 0
	local function order(): number
		n += 1
		return n
	end

	if spec.title then
		label({
			Name = "Title",
			Text = spec.title,
			TextColor3 = colors.text,
			FontFace = Theme.Font.Medium,
			LayoutOrder = order(),
			Parent = menu,
		})
	end

	if spec.text then
		label({
			Name = "Text",
			Text = spec.text,
			TextColor3 = colors.text_muted,
			LineHeight = 1.15,
			LayoutOrder = order(),
			Parent = menu,
		})
	end

	if spec.bullets then
		local list = stack("Bullets", order(), menu, 4)
		for index, text in spec.bullets do
			-- The dot is placed, not prefixed to the text: a wrapped bullet has to
			-- hang-indent under its first line, and "• " .. text wraps flush left.
			local row = Create("Frame", {
				Name = "Bullet",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = index,
				Parent = list,
			})
			label({
				Name = "Dot",
				Text = "•",
				TextColor3 = colors.text_dim,
				Size = UDim2.fromOffset(8, LINE),
				AutomaticSize = Enum.AutomaticSize.None,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = row,
			})
			label({
				Name = "Text",
				Text = text,
				TextColor3 = colors.text_muted,
				Size = UDim2.new(1, -12, 0, 0),
				Position = UDim2.fromOffset(12, 0),
				Parent = row,
			})
		end
	end

	if spec.fields then
		local list = stack("Fields", order(), menu, 4)
		for index, pair in spec.fields do
			local row = Create("Frame", {
				Name = "Field",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = index,
				Parent = list,
			})
			-- Both halves are scale-sized in X and offset (auto) in Y, so each still
			-- feeds the row's AutomaticSize.Y — the axis being measured — while the
			-- value can hug the right edge without a layout.
			label({
				Name = "Key",
				Text = pair[1],
				TextColor3 = colors.text_dim,
				Size = UDim2.new(0.42, -6, 0, 0),
				Parent = row,
			})
			label({
				Name = "Value",
				Text = pair[2],
				TextColor3 = colors.text,
				FontFace = Theme.Font.Medium,
				Size = UDim2.new(0.58, 0, 0, 0),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = row,
			})
		end
	end

	if spec.note then
		local tone = spec.note.tone
		-- nil for `info` — see the accent branch below.
		local tint: Color3? = if tone == "warning"
			then colors.warning
			elseif tone == "danger" then colors.danger
			else nil
		local tile = Create("Frame", {
			Name = "Note",
			BackgroundColor3 = colors.pop,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order(),
			Parent = menu,
		}, {
			Create.corner(7),
			Create.padding(7, 9),
		})
		local icon = Icons.new(TONE_ICON[tone], 13, tint or ctx.Accent)
		icon.Position = UDim2.fromOffset(0, 1)
		icon.Parent = tile
		label({
			Name = "Text",
			Text = spec.note.text,
			TextColor3 = colors.text,
			Size = UDim2.new(1, -20, 0, 0),
			Position = UDim2.fromOffset(20, 0),
			LineHeight = 1.15,
			Parent = tile,
		})
		-- A tinted tile, never a painted one: the icon carries the colour and the
		-- surface only leans toward it, the same rule the active nav tile follows.
		local function paint(color: Color3)
			tile.BackgroundColor3 = colors.pop:Lerp(color, 0.13)
			Icons.tint(icon, color)
		end
		if tint then
			paint(tint)
		else
			-- An `info` note has no colour of its own, so it takes the ACCENT — the
			-- same call components/Screen.lua makes for its `info` tone, for the same
			-- reason: grey on grey at this size is no mark at all. Live, so the
			-- subscription has to come off when the popover is destroyed (a mode
			-- switch does destroy it) or a dead closure fires on every SetAccent.
			table.insert(cleanup, ctx:RegisterAccent(paint))
		end
	end

	return menu, cleanup
end

-- ── the glyph ───────────────────────────────────────────────────────────────
-- One info popover at a time per window. The manager is a single slot on the
-- Context (like `ctx._binds`) rather than a module-level table, so two windows
-- can't close each other's popovers and neither keeps the other alive.
local function manager(ctx: any): any
	local state = ctx._info
	if not state then
		state = { open = nil }
		ctx._info = state
	end
	return state
end

-- Drop whatever is showing. Window calls this alongside `Tab:_hideFlyout` when it
-- minimizes or unloads: a glyph that vanishes from under the cursor never fires
-- MouseLeave, so the popover would sit in the window fade's snapshot and come
-- back on restore with nothing pointing at it.
function Info.hide(ctx: any)
	local state = ctx._info
	if state and state.open then
		state.open:Hide()
	end
end

-- Build the glyph into `parent` and wire it up. `parent` gets a `Slot` frame of
-- exactly `Info.Size` × one text line; the caller positions it (Field puts it at
-- the end of the name's first line) and may `Watch` further hover targets.
function Info.attach(ctx: any, parent: Instance, spec: any): any
	local idle, lit = glyphColors(spec.tone)

	local slot = Create("Frame", {
		Name = "Info",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Info.Size, LINE),
		Parent = parent,
	})
	local icon = Icons.new(spec.icon, Info.Size, idle)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = slot
	-- The hitbox is a CHILD of the slot and bigger than it. AutomaticSize measures
	-- a container's direct children by their own size, so the slot's 13×15 is what
	-- the title row sees while the button still offers ~24px to a thumb — growing
	-- the slot instead would grow the row, which is the one thing this feature
	-- must not do.
	local hit = Create("TextButton", {
		Name = "Hit",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(HIT, HIT),
		ZIndex = 2,
		Parent = slot,
	})

	local conns: { RBXScriptConnection } = {}
	local cleanup: { () -> () } = {}
	local menu: Frame? = nil
	local fade: any = nil
	local unanchor: (() -> ())? = nil
	local pinned = false
	-- How many watched targets the pointer is inside, and a token that cancels a
	-- scheduled open. Both are needed: the glyph and the label are separate
	-- objects, so crossing from one to the other fires a leave and an enter in the
	-- same frame, in no guaranteed order.
	local inside = 0
	local seq = 0

	local handle: any = {}
	handle.Slot = slot

	local function ensure(): Frame
		local built = menu
		if not built then
			local created, teardown = build(ctx, spec)
			for _, fn in teardown do
				table.insert(cleanup, fn)
			end
			created.Parent = ctx.overlay
			menu = created
			fade = Fade.new(created)
			built = created
		end
		return built
	end

	-- Land the fade back on its resting values and hide. Never leave it mid-fade:
	-- the next open snapshots the tree it finds, and a half-faded snapshot becomes
	-- the new baseline (util/Fade.lua).
	local function rest()
		if unanchor then
			unanchor()
			unanchor = nil
		end
		if fade then
			fade:Set(0)
		end
		if menu then
			menu.Visible = false
		end
	end

	-- `handle` rather than `self` throughout: the closures below (`show`, `pin`, the
	-- deferred leave) are plain locals, and mixing the two reads as if they could
	-- ever differ.
	function handle:Hide()
		seq += 1
		local state = manager(ctx)
		if pinned then
			-- The catcher's owner closes it, which calls back into `onClose` below.
			ctx:ClosePopover()
			return
		end
		rest()
		if state.open == handle then
			state.open = nil
		end
	end

	-- Whatever else is showing goes first: one description at a time per window.
	local function claim(): Frame
		local state = manager(ctx)
		if state.open and state.open ~= handle then
			state.open:Hide()
		end
		return ensure()
	end

	local function show()
		local built = claim()
		if unanchor then
			unanchor() -- never stack two trackers on one menu
			unanchor = nil
		end
		unanchor = ctx:AnchorTo(built, slot)
		built.Visible = true
		fade:Set(1)
		fade:To(Tween.Pop, 0)
		manager(ctx).open = handle
	end

	-- Click / tap → pin it open, so the description survives the pointer moving
	-- onto the control it describes (and is reachable at all on touch).
	local function pin()
		local built = claim()
		-- Hand the tree over at rest: ctx:OpenPopover takes its own snapshot, and
		-- one taken over our half-played hover fade would bake those values in as
		-- the resting ones and leave the panel permanently washed out.
		rest()
		ctx:OpenPopover(built, slot, function()
			pinned = false
			local state = manager(ctx)
			if state.open == handle then
				state.open = nil
			end
		end)
		pinned = true
		manager(ctx).open = handle
	end

	function handle:Watch(target: GuiObject)
		table.insert(conns, target.MouseEnter:Connect(function()
			inside += 1
			Icons.tween(icon, Tween.Fast, lit)
			if pinned then
				return
			end
			seq += 1
			local token = seq
			task.delay(DELAY, function()
				if seq ~= token or inside <= 0 or pinned then
					return
				end
				show()
			end)
		end))
		table.insert(conns, target.MouseLeave:Connect(function()
			inside = math.max(0, inside - 1)
			-- Deferred, for the label→glyph crossing described above: by the next
			-- resumption `inside` has counted every enter that came with this leave.
			task.defer(function()
				if inside > 0 then
					return
				end
				Icons.tween(icon, Tween.Fast, idle)
				if pinned then
					return -- a pinned panel is dismissed by clicking, not by leaving
				end
				seq += 1
				if manager(ctx).open == handle then
					handle:Hide()
				end
			end)
		end))
	end

	handle:Watch(hit)
	table.insert(conns, hit.Activated:Connect(pin))

	function handle:Destroy()
		seq += 1
		if pinned and menu and ctx:IsOpen(menu) then
			ctx:ClosePopover()
		end
		local state = ctx._info
		if state and state.open == handle then
			state.open = nil
		end
		for _, conn in conns do
			conn:Disconnect()
		end
		table.clear(conns)
		for _, fn in cleanup do
			fn()
		end
		table.clear(cleanup)
		if fade then
			fade:Destroy()
			fade = nil
		end
		if menu then
			menu:Destroy()
			menu = nil
		end
		slot:Destroy()
	end

	return handle
end

return Info
