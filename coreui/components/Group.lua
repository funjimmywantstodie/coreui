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
--
-- `section` is the tab's *name* — what the bind HUD groups this card's binds
-- under. Deliberately not `scope`: that one is frozen at creation so configs on
-- disk keep resolving (SetName doesn't re-key it), and a HUD header wants the
-- name the user actually sees on the tab.
return function(ctx: any, column: Frame, opts: any, scope: string?, section: string?)
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

	-- The SHELL is the one bordered surface: header strip on top, the collapsing
	-- body under it, one fill, one edge, one radius. The title used to float
	-- above the card as a muted caption — the HTML mock's `.coreui-group-head` —
	-- and a page of those read as a form: grey labels, then boxes. With the title
	-- inside, a group is a panel with a name, the same miniature-of-the-window
	-- shape the bind HUD and the status page already have, and collapsing one
	-- leaves a titled bar behind rather than a caption over nothing.
	local shell = Create("Frame", {
		Name = "Shell",
		BackgroundColor3 = colors.card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = group,
	}, {
		Create.corner(Theme.Metrics.cardRadius),
		Create.stroke(colors.border),
		-- Centered so the inset `Rule` below lands centered too (a layout-managed
		-- child ignores its own Position); the header and body are full-width, so
		-- it changes nothing for them.
		Create.listLayout({ HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})

	-- NOTE: the header does NOT use a UIListLayout. A UIListLayout manages its
	-- children's transforms and suppresses their Rotation, so a chevron laid out
	-- by one never visually spins. Title + chevron are positioned manually so the
	-- chevron is free to rotate (matches a bare ImageLabel, which rotates fine).
	-- The fold caret's whole row is the tap target, so on a phone it's padded out
	-- to ~44px; the desktop keeps a 40px strip. Per call, re-applied when the
	-- device answer moves (Context:OnTouch).
	local headPad = Create.padding(12, 14, 11, 14)
	local head = Create("TextButton", {
		Name = "Head",
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = shell,
	}, {
		headPad,
	})
	local function fitHead()
		local touch = ctx:IsTouch()
		headPad.PaddingTop = UDim.new(0, touch and 14 or 12)
		headPad.PaddingBottom = UDim.new(0, touch and 14 or 11)
	end
	fitHead()
	local unsubscribeTouch = ctx:OnTouch(fitHead)
	group.Destroying:Connect(unsubscribeTouch)

	Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -22, 0, 0), -- leaves room for the chevron flush right
		Text = opts.Title or "Group",
		-- Full text weight: it's the panel's name now, not a caption over it.
		TextColor3 = colors.text,
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
	-- The header is a button, and the chevron is what says so; it brightens under
	-- the pointer the way every other idle icon in the window does.
	head.MouseEnter:Connect(function()
		Icons.tween(chevron, Tween.Fast, colors.text_muted)
	end)
	head.MouseLeave:Connect(function()
		Icons.tween(chevron, Tween.Fast, colors.text_dim)
	end)

	-- Hairline between the header and its body. Hidden while collapsed: a folded
	-- group is a bar, and a bar with a rule along its bottom edge reads as a table
	-- header waiting for rows. Toggled with the fold rather than faded, so it
	-- vanishes the frame the body starts sliding up under the header.
	local rule = Create("Frame", {
		Name = "Rule",
		Size = UDim2.new(1, -28, 0, 1), -- inset to the header's text edge
		BackgroundColor3 = colors.border_soft,
		BorderSizePixel = 0,
		Visible = not collapsed,
		LayoutOrder = 2,
		Parent = shell,
	})

	-- The body — still called "Card", because that's the frame controls mount into
	-- and the titlebar search walks (`handle._search.card` below). Transparent: the
	-- shell carries the fill and the edge now.
	local card = Create("Frame", {
		Name = "Card",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Create.padding(1, 14, 5, 14),
		Create.listLayout({}),
	})

	-- A clipping holder owns the body's height so collapse/expand slides the panel
	-- open/closed instead of snapping its visibility.
	local holder, setCollapsed = Collapse.wrap(card, collapsed)
	holder.LayoutOrder = 3
	holder.Parent = shell

	-- `any` for the same reason components/Window.lua types its tab handle that
	-- way: the control surface grows the two collapse methods below, and under
	-- --!strict the inferred table type wouldn't take them.
	-- `Parent` on the card makes every bindable control inside it a sub-option of
	-- that feature for the bind HUD (util/Bind.lua's tree) — a group of Aimbot
	-- options says it once here rather than on every toggle.
	-- The card's own title is handed down as the auto roll-up hint (see
	-- Controls.new): with no explicit `Parent`, a "Triggerbot" card whose first
	-- switch is Triggerbot rolls its sub-options up into that one HUD row.
	local handle: any = Controls.new(ctx, card, opts.Parent,
		(type(opts.Section) == "string" and opts.Section ~= "") and opts.Section or section,
		(opts.Parent == nil and type(opts.Title) == "string") and opts.Title or nil)

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
		rule.Visible = not collapsed
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
