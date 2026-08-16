--!strict
-- components/Group.lua — titled card with a collapsible body.
-- Header toggles the card's visibility; the card hosts the control surface.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)
local Collapse = require(script.Parent.Parent.util.Collapse)
local Controls = require(script.Parent.Controls)

-- `scope` is the tab's identity, threaded down from components/Tab.lua: a group
-- is only unique *within* a tab, and the pair is what the window's persisted
-- collapse map is keyed on (see Context:RegisterGroup).
return function(ctx: any, column: Frame, opts: any, scope: string?)
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

	-- NOTE: the header does NOT use a UIListLayout. A UIListLayout manages its
	-- children's transforms and suppresses their Rotation, so a chevron laid out
	-- by one never visually spins. Title + chevron are positioned manually so the
	-- chevron is free to rotate (matches a bare ImageLabel, which rotates fine).
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
	})

	Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -18, 0, 0), -- leaves room for the chevron flush right
		Text = opts.Title or "Group",
		TextColor3 = colors.text_muted,
		TextSize = 13,
		FontFace = Theme.Font.Medium,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = head,
	})

	local chevron = Icons.new("chev", 14, colors.text_dim)
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, 0, 0.5, 0)
	chevron.Rotation = collapsed and 180 or 0;
	(chevron :: any).Parent = head

	local card = Create("Frame", {
		Name = "Card",
		BackgroundColor3 = colors.card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Create.corner(Theme.Metrics.cardRadius),
		Create.stroke(colors.border),
		Create.padding(2, 14),
		Create.listLayout({}),
	})

	-- A clipping holder owns the card's height so collapse/expand slides the panel
	-- open/closed instead of snapping its visibility.
	local holder, setCollapsed = Collapse.wrap(card, collapsed)
	holder.LayoutOrder = 2
	holder.Parent = group

	-- `any` for the same reason components/Window.lua types its tab handle that
	-- way: the control surface grows the two collapse methods below, and under
	-- --!strict the inferred table type wouldn't take them.
	-- `Parent` on the card makes every bindable control inside it a sub-option of
	-- that feature for the bind HUD (util/Bind.lua's tree) — a group of Aimbot
	-- options says it once here rather than on every toggle.
	local handle: any = Controls.new(ctx, card, opts.Parent)

	-- Everything the titlebar search needs to filter this group, handed over as
	-- direct references.
	--
	-- The filter used to live in components/Window.lua and re-derive all three
	-- from instance NAMES on every keystroke — `page:GetDescendants()` for the
	-- groups, then a recursive `FindFirstChild("Card")` that searched each card's
	-- entire subtree (every control in it) before finding it. That put this file's
	-- layout — that the card is called "Card", that it sits under a "Collapse"
	-- holder, that the title is "Head"/"Title" — into a module that has no other
	-- reason to know any of it, where a rename here would have silently filtered
	-- nothing. The title is lowercased once, at build time, because the search
	-- compares against it lowercased on every keystroke.
	handle._search = {
		group = group,
		card = card,
		title = string.lower(opts.Title or "Group"),
	}

	-- Whether a group is folded is state the user set, and it had no
	-- representation anywhere: not readable, not settable, not in any config. The
	-- window persists it (`uranium_window`), and a host that wants to drive it —
	-- fold everything but the group its feature lives in — needs the same pair.
	function handle:IsCollapsed(): boolean
		return collapsed
	end

	-- `animate = false` snaps, which is what a restore wants: the window shouldn't
	-- play a fold animation for state the user set in a previous session.
	function handle:SetCollapsed(value: boolean, animate: boolean?)
		value = value == true
		if value == collapsed then
			return
		end
		collapsed = value
		if animate == false then
			chevron.Rotation = collapsed and 180 or 0
		else
			Tween.play(chevron, Tween.Spin, { Rotation = collapsed and 180 or 0 })
		end
		setCollapsed(collapsed, animate ~= false)
		ctx:WindowStateChanged()
	end

	head.Activated:Connect(function()
		ctx:User(function()
			handle:SetCollapsed(not collapsed)
		end)
	end)

	-- Registered even when the window isn't persisting anything: the registry is
	-- what assigns the stable key, and a group that only becomes interesting once
	-- a host asks for the snapshot would otherwise have no name to appear under.
	ctx:RegisterGroup(scope or "Tab", opts.Id or opts.Title or "Group", handle)

	return handle
end
