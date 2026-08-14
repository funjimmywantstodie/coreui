--!strict
-- components/Window.lua — the window shell: titlebar, sidebar, scrolling content,
-- status bar and overlay. Owns the Context, the tab list, notifications and the
-- live accent. Mounts a ScreenGui to the LocalPlayer's PlayerGui.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)
local Context = require(script.Parent.Parent.util.Context)
local Config = require(script.Parent.Parent.util.Config)
local Asset = require(script.Parent.Parent.util.Asset)
local Log = require(script.Parent.Parent.util.Log)
local Singleton = require(script.Parent.Parent.util.Singleton)
local Tab = require(script.Parent.Tab)
local Notify = require(script.Parent.Notify)

local M = Theme.Metrics

return function(opts: any)
	opts = opts or {}
	local colors = Theme.Colors

	-- Validate the window options up front so a wrong type surfaces here (naming
	-- the field) rather than as a mystery error much later when it's first used.
	Log.field("CreateWindow", "Title", opts.Title, "string")
	Log.field("CreateWindow", "ToggleKey", opts.ToggleKey, "EnumItem")
	Log.field("CreateWindow", "Accent", opts.Accent, "Color3")
	Log.field("CreateWindow", "ConfigFolder", opts.ConfigFolder, "string")
	Log.field("CreateWindow", "LogoRadius", opts.LogoRadius, "number")
	Log.field("CreateWindow", "LogoZoom", opts.LogoZoom, "number")
	Log.field("CreateWindow", "AllowMultiple", opts.AllowMultiple, "boolean")

	-- where configs are saved on disk + which key shows/hides the window
	local configFolder = opts.ConfigFolder or "uranium"
	local toggleKey: Enum.KeyCode = opts.ToggleKey or Enum.KeyCode.RightShift
	local notificationsEnabled = true
	-- UserInputService connections live past the ScreenGui's lifetime, so they're
	-- tracked here and disconnected by Window:Destroy.
	local connections: { RBXScriptConnection } = {}

	-- ── single instance ───────────────────────────────────────────────────────
	-- Only one Uranium on screen at a time: re-running the loadstring unloads the
	-- window the previous run left behind (util/Singleton.lua — the handle lives
	-- on getgenv()._URANIUM_LOADED so it survives across chunks), then builds
	-- fresh below. That way the loader refreshes the UI instead of stacking a
	-- second copy over the first. `AllowMultiple = true` opts out of both halves.
	local singleton = opts.AllowMultiple ~= true
	local record: any = nil
	if singleton and Singleton.unloadExisting(Theme.Brand.name) then
		print("[Uranium] already loaded — unloaded the previous window and refreshing.")
	end

	-- ── ScreenGui + window frame ────────────────────────────────────────────
	local screenGui = Create("ScreenGui", {
		Name = Theme.Brand.name,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	-- CanvasGroup (not Frame) so minimize/close can fade the *entire* window as a
	-- single unit via GroupTransparency — a plain Frame can only fade its own
	-- background, which is why scaling-then-hiding looked like a snap.
	local main = Create("CanvasGroup", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(M.windowWidth, M.windowHeight),
		BackgroundColor3 = colors.bg,
		ClipsDescendants = true,
		Parent = screenGui,
	}, {
		Create.corner(M.windowRadius),
		Create.stroke(Color3.new(0, 0, 0)),
		Create("UIScale", {}),
	})
	local mainScale = main:FindFirstChildOfClass("UIScale") :: UIScale

	-- ── drop shadow ─────────────────────────────────────────────────────────
	-- The reference window floats: `box-shadow: 0 30px 80px -20px rgba(0,0,0,.8)`.
	-- A 9-sliced soft-shadow image behind the window gives it that elevation. It
	-- lives in the ScreenGui (a sibling behind `main`, not a child — `main`
	-- clips, and the shadow has to bleed past the window edges) and tracks the
	-- window as it's dragged / resized.
	-- A *radial* shadow image (one smooth centre→edge gradient) stretched behind
	-- the window. A 9-slice shadow only softens its ~49px border and stretches a
	-- solid core, so it reads as a hard dark band that ends abruptly — this fades
	-- gradually the whole way out instead. Big PAD = the gradient's soft tail is
	-- what shows past the window edge; the dark middle stays hidden behind it.
	local SHADOW_PAD = 60 -- how far the soft tail bleeds past each edge (bigger = more gradual falloff)
	local SHADOW_DROP = 8  -- nudge down so the light reads as coming from above (kept small so the bottom doesn't read heavy)
	local SHADOW_T = 0.82  -- resting image transparency (high = faint, barely-there shadow)
	local shadow = Create("ImageLabel", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = main.Position,
		Size = UDim2.fromOffset(M.windowWidth + SHADOW_PAD, M.windowHeight + SHADOW_PAD),
		BackgroundTransparency = 1,
		Image = "rbxassetid://1316045217", -- soft radial blur
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 1, -- faded in on mount, alongside the window
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 0,
		Parent = screenGui,
	})
	local function syncShadow()
		shadow.Position = main.Position + UDim2.fromOffset(0, SHADOW_DROP)
		shadow.Size = UDim2.new(
			main.Size.X.Scale, main.Size.X.Offset + SHADOW_PAD,
			main.Size.Y.Scale, main.Size.Y.Offset + SHADOW_PAD
		)
	end
	main:GetPropertyChangedSignal("Position"):Connect(syncShadow)
	main:GetPropertyChangedSignal("Size"):Connect(syncShadow)

	-- Never exceed the viewport — on small screens the window shrinks to fit
	-- (centered) instead of spilling content off the right/bottom edge. Skipped
	-- while maximized, which owns the size itself (this used to fight it and snap
	-- a maximized window back to its default size on any viewport change).
	local maximized = false
	local function fitWindow()
		local vp = screenGui.AbsoluteSize
		if vp.X <= 0 then
			return
		end
		if maximized then
			main.Size = UDim2.fromOffset(
				math.max(M.windowWidth, vp.X - 24),
				math.max(M.windowHeight, vp.Y - 24)
			)
			return
		end
		main.Size = UDim2.fromOffset(
			math.min(M.windowWidth, vp.X - 24),
			math.min(M.windowHeight, vp.Y - 24)
		)
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitWindow)
	task.defer(fitWindow)

	-- ── titlebar ───────────────────────────────────────────────────────────
	local titlebar = Create("Frame", {
		Name = "Titlebar",
		Size = UDim2.new(1, 0, 0, M.titlebar),
		BackgroundColor3 = colors.chrome,
		Parent = main,
	}, {
		-- Round the top corners to match the window. main's ClipsDescendants
		-- clips to a rectangle (not the rounded shape), so without this the
		-- square chrome corners poke past main's rounded corners.
		Create.corner(M.windowRadius),
		Create("Frame", { -- square off the bottom so only the top corners round
			Name = "SquareFill",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, M.windowRadius),
			BackgroundColor3 = colors.chrome,
			BorderSizePixel = 0,
		}),
		Create("Frame", { -- bottom hairline
			Name = "Border",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = colors.border_soft,
			BorderSizePixel = 0,
		}),
	})

	-- logo — the brand mark, square art rounded off by the holder's UICorner.
	-- `Logo` accepts anything util/Asset.lua resolves (id, url, file path); the
	-- accent square with the brand initial is the fallback while it loads or if
	-- it never resolves (Studio without executor globals, bad id, …).
	local logo = Create("Frame", {
		Name = "Logo",
		Size = UDim2.fromOffset(M.logo, M.logo),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, M.sidebar / 2, 0.5, 0),
		BackgroundColor3 = colors.accent,
		ClipsDescendants = true,
		Parent = titlebar,
	}, {
		Create.corner(opts.LogoRadius or Theme.Brand.radius),
	})
	local brandName = opts.Title or Theme.Brand.name
	local logoFallback = Create("TextLabel", {
		Name = "Initial",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = brandName:sub(1, 1):upper(),
		TextColor3 = colors.knockout,
		TextSize = 17,
		FontFace = Theme.Font.Bold,
		Parent = logo,
	})
	-- Fit, not Crop: a brand mark must never lose an edge or change proportion.
	-- Fit letterboxes non-square art inside the square holder; the zoom below is
	-- what fills the holder, and it's a scale on both axes so it can't stretch.
	local logoImage = Create("ImageLabel", {
		Name = "Mark",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Image = "",
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		Parent = logo,
	}) :: ImageLabel
	-- `zoom` > 1 draws the art oversized inside the clipping holder, trimming a
	-- margin baked into the source (see Theme.Brand.zoom). nil = draw it 1:1.
	local function setLogo(source: any, zoom: number?)
		local z = tonumber(zoom) or 1
		if z <= 0 then
			z = 1
		end
		logoImage.Size = UDim2.fromScale(z, z)
		-- The mark is ALWAYS visible — it has to be, or the engine never fetches
		-- the texture — and it's drawn over the accent square, which stays put as
		-- a backdrop. So the art covers the square when it loads, and if it never
		-- loads you're left with the accent square + initial. Never a hole,
		-- whatever the load check believes.
		logoImage.Visible = true
		logoFallback.Visible = true
		logo.BackgroundTransparency = 0
		Asset.load(logoImage, source, function(loaded)
			-- Only the fallback reacts; the image is left alone.
			logoFallback.Visible = not loaded
			logo.BackgroundTransparency = loaded and 1 or 0
			if not loaded and source ~= nil then
				Log.warn("CreateWindow", ("Logo %s hasn't loaded — the fallback mark is showing. "
					.. "Check the id is an image/decal, that it passed moderation, and that "
					.. "it isn't Restricted in Creator Dashboard."):format(tostring(source)))
			end
		end)
	end
	-- `Logo = false` means "no art at all" — keep the accent square + initial.
	-- The built-in mark gets Theme.Brand.zoom (its margin is known); art the
	-- caller supplied is drawn 1:1 unless they ask for a zoom themselves.
	if opts.Logo == false then
		setLogo(nil)
	elseif opts.Logo ~= nil then
		setLogo(opts.Logo, opts.LogoZoom)
	else
		setLogo(Theme.Brand.logo, opts.LogoZoom or Theme.Brand.zoom)
	end

	-- Wordmark: uppercase with wide letter-spacing. Roblox has no tracking /
	-- letter-spacing property on TextLabel, so the spacing is literal — a space
	-- between every glyph. A word break becomes three spaces, which still reads
	-- as a wordmark. Short brand names only; that's what a titlebar title is.
	local function wordmark(s: string): string
		local out = {}
		for _, c in utf8.codes(s:upper()) do
			table.insert(out, utf8.char(c))
		end
		return table.concat(out, " ")
	end

	Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = wordmark(brandName),
		TextColor3 = colors.text,
		TextSize = 16,
		FontFace = Theme.Font.Bold,
		Parent = titlebar,
	})

	-- Right cluster holds a collapsible search field followed by the window
	-- buttons; the horizontal list keeps them packed against the right edge.
	local rightCluster = Create("Frame", {
		Name = "RightCluster",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(0, M.titlebar),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = titlebar,
	}, {
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 14),
		}),
	})

	-- search field — hidden until the search button is clicked. A CanvasGroup so
	-- its width can slide open while every child fades in together; ClipsDescendants
	-- keeps the icon/box from spilling out while it's narrower than its content.
	local SEARCH_W = 180
	local searchField = Create("CanvasGroup", {
		Name = "Search",
		Visible = false,
		Size = UDim2.fromOffset(SEARCH_W, 30),
		BackgroundColor3 = colors.control,
		ClipsDescendants = true,
		LayoutOrder = 1,
		Parent = rightCluster,
	}, {
		Create.corner(M.controlRadius),
		Create.stroke(colors.border),
		Create.padding(0, 10),
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
	})
	local searchIcon = Icons.new("search", 14, colors.text_dim)
	searchIcon.LayoutOrder = 1;
	(searchIcon :: any).Parent = searchField
	local searchBox = Create("TextBox", {
		Name = "Box",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -22, 1, 0),
		Text = "",
		PlaceholderText = "Search",
		PlaceholderColor3 = colors.text_dim,
		TextColor3 = colors.text,
		TextSize = 13,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		LayoutOrder = 2,
		Parent = searchField,
	})

	local winButtons = Create("Frame", {
		Name = "WinButtons",
		Size = UDim2.fromOffset(0, M.titlebar),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = rightCluster,
	}, {
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 15),
		}),
	})

	local winBtns: { [string]: TextButton } = {}
	for i, name in { "search", "min", "max", "close" } do
		local btn = Create("TextButton", {
			Name = name,
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(16, 16),
			Text = "",
			LayoutOrder = i,
			Parent = winButtons,
		})
		local icon = Icons.new(name, 16, colors.text_muted)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5);
		(icon :: any).Parent = btn

		local over = name == "close" and colors.danger or colors.text
		btn.MouseEnter:Connect(function()
			Tween.play(icon, Tween.Fast, { ImageColor3 = over })
		end)
		btn.MouseLeave:Connect(function()
			Tween.play(icon, Tween.Fast, { ImageColor3 = colors.text_muted })
		end)
		winBtns[name] = btn
	end

	-- ── body: sidebar + content ─────────────────────────────────────────────
	local body = Create("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, M.titlebar),
		Size = UDim2.new(1, 0, 1, -(M.titlebar + M.statusbar)),
		BackgroundColor3 = colors.bg,
		Parent = main,
	})

	local sidebar = Create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, M.sidebar, 1, 0),
		BackgroundColor3 = colors.chrome,
		Parent = body,
	}, {
		Create("Frame", {
			Name = "Border",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = colors.border_soft,
			BorderSizePixel = 0,
		}),
	})

	-- Nav buttons live in their own frame so the sidebar's UIListLayout never
	-- tries to lay out the full-height Border hairline (which would otherwise
	-- consume the whole column and push the nav buttons off-screen).
	local nav = Create("Frame", {
		Name = "Nav",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = sidebar,
	}, {
		Create.padding(16, 0),
		Create.listLayout({
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
	})

	local content = Create("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.fromOffset(M.sidebar, 0),
		Size = UDim2.new(1, -M.sidebar, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = colors.scroll,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = body,
	}, {
		-- Vertical padding only. Horizontal insets are applied to each page
		-- explicitly (below) so column widths never depend on the executor's
		-- handling of scale-width children + scrollbar inside a ScrollingFrame.
		Create.padding(18, 0, 26, 0),
	})
	local CONTENT_PAD_X = 22

	-- ── status bar ───────────────────────────────────────────────────────────
	local status = Create("Frame", {
		Name = "StatusBar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, M.statusbar),
		BackgroundColor3 = colors.chrome,
		Parent = main,
	}, {
		-- Round the bottom corners to match the window (see titlebar note).
		Create.corner(M.windowRadius),
		Create("Frame", { -- square off the top so only the bottom corners round
			Name = "SquareFill",
			Size = UDim2.new(1, 0, 0, M.windowRadius),
			BackgroundColor3 = colors.chrome,
			BorderSizePixel = 0,
		}),
		Create("Frame", {
			Name = "Border",
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = colors.border_soft,
			BorderSizePixel = 0,
		}),
		Create.padding(0, 22),
	})

	local clock = Create("TextLabel", {
		Name = "Clock",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.4, 1),
		Text = "—",
		TextColor3 = colors.text_muted,
		TextSize = 12,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = status,
	})
	Create("TextLabel", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = opts.Subtitle or "",
		TextColor3 = colors.text_muted,
		TextSize = 12,
		FontFace = Theme.Font.Regular,
		Parent = status,
	})
	Create("TextLabel", {
		Name = "Version",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.4, 1),
		Text = opts.Version or "",
		TextColor3 = colors.text_dim,
		TextSize = 12,
		FontFace = Theme.Font.Mono,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = status,
	})

	-- live clock
	task.spawn(function()
		while clock.Parent do
			local t = os.date("*t")
			local h = t.hour % 12
			if h == 0 then
				h = 12
			end
			local ap = t.hour >= 12 and "PM" or "AM"
			clock.Text = ("%d:%02d %s"):format(h, t.min, ap)
			task.wait(10)
		end
	end)

	-- ── overlay (popovers + toasts) ──────────────────────────────────────────
	local overlay = Create("Frame", {
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = false,
		ZIndex = 100,
		Parent = main,
	})
	local toasts = Create("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -46),
		Size = UDim2.fromOffset(260, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = overlay,
	}, {
		Create.listLayout({
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 9),
		}),
	})

	local ctx = Context.new(Theme, overlay, opts.Accent or colors.accent)

	-- the logo's accent square is only visible behind the fallback initial, but
	-- it still needs to track SetAccent for that case
	ctx:RegisterAccent(function(accent)
		logo.BackgroundColor3 = accent
	end)

	-- ── titlebar dragging ────────────────────────────────────────────────────
	local dragging, dragStart, startPos
	titlebar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
		end
	end)
	-- Keep the window reachable: a drag can't push the titlebar off the top or
	-- shove the window so far past an edge that there's nothing left to grab.
	local KEEP_ON_SCREEN = 80
	local function clampToViewport(pos: UDim2): UDim2
		local vp = screenGui.AbsoluteSize
		local size = main.AbsoluteSize
		if vp.X <= 0 or size.X <= 0 then
			return pos
		end
		local halfX, halfY = size.X / 2, size.Y / 2
		local cx = pos.X.Scale * vp.X + pos.X.Offset
		local cy = pos.Y.Scale * vp.Y + pos.Y.Offset
		cx = math.clamp(cx, KEEP_ON_SCREEN - halfX, vp.X - KEEP_ON_SCREEN + halfX)
		cy = math.clamp(cy, halfY, math.max(halfY, vp.Y - KEEP_ON_SCREEN + halfY))
		return UDim2.new(
			pos.X.Scale, cx - pos.X.Scale * vp.X,
			pos.Y.Scale, cy - pos.Y.Scale * vp.Y
		)
	end

	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			main.Position = clampToViewport(UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			))
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	-- ── public API ───────────────────────────────────────────────────────────
	local tabs = {}
	local activeIndex = 1
	local window = {}
	local applySearch -- forward declaration (used by select)

	local searchOpen = false
	local function currentQuery(): string
		return searchOpen and searchBox.Text or ""
	end

	local function select(index: number)
		activeIndex = index
		-- Popovers live in the overlay, not in the page, so an open dropdown would
		-- otherwise hang around over the tab you just switched to.
		ctx:ClosePopover()
		for i, tab in tabs do
			tab:_setActive(i == index)
		end
		content.CanvasPosition = Vector2.new(0, 0)
		applySearch(currentQuery()) -- keep the filter consistent across tabs
	end

	-- ── search ────────────────────────────────────────────────────────────────
	-- Concatenate every bit of text under an instance, lowercased, for matching.
	local function collectText(inst: Instance): string
		local parts = {}
		for _, d in inst:GetDescendants() do
			if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and d.Text ~= "" then
				table.insert(parts, d.Text)
			end
		end
		return string.lower(table.concat(parts, " "))
	end

	-- Filter the active tab: show a group if its title matches, otherwise show
	-- only the fields whose text matches (hiding groups left with nothing).
	applySearch = function(query: string)
		query = string.lower(query or "")
		local tab = tabs[activeIndex]
		if not tab then
			return
		end
		for _, group in tab.page:GetDescendants() do
			if group:IsA("Frame") and group.Name == "Group" then
				local head = group:FindFirstChild("Head")
				-- card now sits inside a collapse holder, so search recursively
				local card = group:FindFirstChild("Card", true)
				local titleLabel = head and head:FindFirstChild("Title")
				local titleText = (titleLabel and titleLabel:IsA("TextLabel"))
					and string.lower(titleLabel.Text) or ""
				local groupMatch = query == "" or string.find(titleText, query, 1, true) ~= nil

				local anyVisible = false
				if card then
					-- Fields and their trailing hairlines are siblings ordered
					-- field, separator, field, separator… so filter the fields first,
					-- then re-derive each separator: visible only when the field
					-- above it survived AND some field still follows it. (Leaving
					-- separators alone stranded hairlines wherever a field was
					-- hidden; showing them all put one under the last row.)
					local ordered: { GuiObject } = {}
					for _, child in card:GetChildren() do
						if child:IsA("GuiObject") then -- skip UICorner/UIStroke/UIPadding/UIListLayout
							table.insert(ordered, child)
						end
					end
					table.sort(ordered, function(a, b)
						return a.LayoutOrder < b.LayoutOrder
					end)
					for _, item in ordered do
						if item.Name ~= "Separator" then
							local matches = groupMatch
								or string.find(collectText(item), query, 1, true) ~= nil
							item.Visible = matches
							if matches then
								anyVisible = true
							end
						end
					end
					local previousVisible = false
					local lastSeparator: GuiObject? = nil
					for _, item in ordered do
						if item.Name == "Separator" then
							item.Visible = previousVisible
							if previousVisible then
								lastSeparator = item
							end
						else
							if item.Visible and lastSeparator then
								lastSeparator = nil -- a field follows it, so it stays
							end
							previousVisible = item.Visible
						end
					end
					if lastSeparator then
						lastSeparator.Visible = false -- trailing hairline, nothing below
					end
				end
				group.Visible = query == "" or groupMatch or anyVisible
			end
		end
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		applySearch(searchBox.Text)
	end)
	winBtns.search.Activated:Connect(function()
		searchOpen = not searchOpen
		if searchOpen then
			-- slide + fade open from a zero-width sliver, then focus the box
			searchField.Visible = true
			searchField.Size = UDim2.fromOffset(0, 30)
			searchField.GroupTransparency = 1
			Tween.play(searchField, Tween.Slide, {
				Size = UDim2.fromOffset(SEARCH_W, 30),
				GroupTransparency = 0,
			})
			searchBox:CaptureFocus()
		else
			searchBox.Text = "" -- fires the Text signal → clears the filter
			-- slide + fade closed, then hide once it's fully collapsed
			local t = Tween.play(searchField, Tween.Slide, {
				Size = UDim2.fromOffset(0, 30),
				GroupTransparency = 1,
			})
			t.Completed:Once(function()
				if not searchOpen then
					searchField.Visible = false
				end
			end)
		end
	end)

	-- ── minimize / restore (toggle key) ────────────────────────────────────────
	local restoreHint = Create("Frame", {
		Name = "MinimizedHint",
		Visible = false,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(220, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.pop,
		Parent = screenGui,
	}, {
		Create.corner(9),
		Create.stroke(colors.border),
		Create.padding(11, 14),
		Create.listLayout({ Padding = UDim.new(0, 3) }),
	})
	Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "UI Minimized",
		TextColor3 = colors.text,
		TextSize = 13,
		FontFace = Theme.Font.Medium,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = restoreHint,
	})
	local restoreHintText = Create("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = ("Press %s to show it again."):format(toggleKey.Name),
		TextColor3 = colors.text_muted,
		TextSize = 12,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = 2,
		Parent = restoreHint,
	})

	local minimized = false
	local function setMinimized(value: boolean)
		minimized = value
		if value then
			-- shrink + fade the whole window away together, then hide it once the
			-- fade has fully played (no abrupt cut — it's already invisible).
			Tween.play(mainScale, Tween.MenuOut, { Scale = 0.9 })
			Tween.play(shadow, Tween.MenuOut, { ImageTransparency = 1 })
			local t = Tween.play(main, Tween.MenuOut, { GroupTransparency = 1 })
			t.Completed:Once(function()
				if minimized then
					main.Visible = false
				end
			end)
			restoreHint.Visible = true
		else
			-- restore from the shrunk/faded state: pop the scale, ease the fade in
			main.Visible = true
			mainScale.Scale = 0.9
			main.GroupTransparency = 1
			Tween.play(mainScale, Tween.Pop, { Scale = 1 })
			Tween.play(main, Tween.Normal, { GroupTransparency = 0 })
			Tween.play(shadow, Tween.Normal, { ImageTransparency = SHADOW_T })
			restoreHint.Visible = false
		end
	end
	winBtns.min.Activated:Connect(function()
		setMinimized(true)
	end)
	-- The toggle key hides AND restores (a single press flips the window's state),
	-- ignored while the player is typing into a textbox / capturing a keybind.
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or ctx:IsCapturing() then
			return -- typing in a textbox, or a Keybind is listening for this press
		end
		if toggleKey ~= Enum.KeyCode.Unknown and input.KeyCode == toggleKey then
			-- Defensive: if anything disabled the ScreenGui, flipping the minimize
			-- state would just toggle an invisible window and the UI would look
			-- permanently gone. Re-enable it instead. (Close no longer takes this
			-- path — it destroys the ScreenGui outright.)
			if not screenGui.Enabled then
				screenGui.Enabled = true
				minimized = false
				main.Visible = true
				restoreHint.Visible = false
				return
			end
			setMinimized(not minimized)
		end
	end))

	-- ── maximize toggle ─────────────────────────────────────────────────────────
	winBtns.max.Activated:Connect(function()
		maximized = not maximized
		if maximized then
			local vp = screenGui.AbsoluteSize
			Tween.play(main, Tween.Normal, {
				Size = UDim2.fromOffset(
					math.max(M.windowWidth, vp.X - 24),
					math.max(M.windowHeight, vp.Y - 24)
				),
			})
		else
			local vp = screenGui.AbsoluteSize
			Tween.play(main, Tween.Normal, {
				Size = UDim2.fromOffset(
					math.min(M.windowWidth, vp.X - 24),
					math.min(M.windowHeight, vp.Y - 24)
				),
			})
		end
	end)

	-- ── close ────────────────────────────────────────────────────────────────
	-- Close is a real unload, not a hide: same shrink+fade as minimize, but the
	-- listeners come off, the ScreenGui is destroyed and the singleton slot is
	-- freed. Use the minimize button (or the toggle key) to stash it temporarily.
	winBtns.close.Activated:Connect(function()
		window:Destroy()
	end)

	function window:CreateTab(tabOpts: any)
		if tabOpts ~= nil and type(tabOpts) ~= "table" then
			Log.fail("CreateTab", ("options must be a table like { Name = ..., Icon = ... }, got %s"
				.. " — if you meant a title, write CreateTab({ Name = %s })")
				:format(typeof(tabOpts), type(tabOpts) == "string" and ('"%s"'):format(tabOpts) or "..."))
		end
		Log.field("CreateTab", "Name", tabOpts and tabOpts.Name, "string")
		Log.field("CreateTab", "Icon", tabOpts and tabOpts.Icon, "string")
		local tab = Tab(ctx, tabOpts or {})
		tab.button.Parent = nav
		tab.page.Parent = content

		-- Inset the page explicitly and size it to the scroll area's *visible*
		-- width (AbsoluteWindowSize excludes the scrollbar). This guarantees the
		-- right column keeps its margin regardless of executor quirks.
		tab.page.Position = UDim2.fromOffset(CONTENT_PAD_X, 0)
		local function fitPage()
			local avail = content.AbsoluteWindowSize.X
			if avail <= 0 then
				avail = content.AbsoluteSize.X
			end
			tab.page.Size = UDim2.new(0, math.max(0, avail - CONTENT_PAD_X * 2), 0, 0)
		end
		content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPage)
		content:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(fitPage)
		task.defer(fitPage)

		local index = #tabs + 1
		tab.button.LayoutOrder = index
		table.insert(tabs, tab)
		tab.button.Activated:Connect(function()
			select(index)
		end)
		if index == 1 then
			select(1)
		end
		return tab
	end

	function window:Select(index: number)
		if type(index) ~= "number" or index < 1 or index > #tabs or index % 1 ~= 0 then
			Log.warn("Select", ("no tab #%s (there %s %d tab%s) — ignoring.")
				:format(tostring(index), #tabs == 1 and "is" or "are", #tabs, #tabs == 1 and "" or "s"))
			return
		end
		select(index)
	end

	function window:Notify(notifyOpts: any)
		if notifyOpts ~= nil and type(notifyOpts) ~= "table" then
			Log.fail("Notify", ("options must be a table like { Title = ..., Text = ... }, got %s")
				:format(typeof(notifyOpts)))
		end
		if not notificationsEnabled then
			return
		end
		Notify(ctx, toasts, notifyOpts)
	end

	-- Swap the brand mark at runtime — same source types as the Logo option
	-- (asset id, https url, local file path). `zoom` crops a margin baked into
	-- the art (see Theme.Brand.zoom); omit it and the art is drawn 1:1.
	function window:SetLogo(source: any, zoom: number?)
		setLogo(source, zoom)
	end

	function window:SetAccent(color: Color3)
		if typeof(color) ~= "Color3" then
			Log.fail("SetAccent", ("expects a Color3, got %s (try Color3.fromHex(\"7be04a\"))")
				:format(typeof(color)))
		end
		ctx:SetAccent(color)
	end

	-- ── settings: theme / keybind / notifications ─────────────────────────────
	function window:SetToggleKey(key: Enum.KeyCode)
		if key ~= nil and typeof(key) ~= "EnumItem" then
			Log.fail("SetToggleKey", ("expects an Enum.KeyCode, got %s (try Enum.KeyCode.RightShift)")
				:format(typeof(key)))
		end
		toggleKey = key or Enum.KeyCode.Unknown
		restoreHintText.Text = toggleKey ~= Enum.KeyCode.Unknown
			and ("Press %s to show it again."):format(toggleKey.Name)
			or "Re-bind a toggle key to show it again."
	end

	function window:SetNotificationsEnabled(enabled: boolean)
		notificationsEnabled = enabled ~= false
	end

	-- ── settings: config persistence ──────────────────────────────────────────
	-- These read/write the flag registry (any control built with a `Flag`).
	window.ConfigSupported = Config.supported

	local function badConfigName(where: string, name: any): boolean
		if type(name) ~= "string" or name == "" then
			Log.warn(where, ("config name must be a non-empty string, got %s — ignoring.")
				:format(name == "" and '""' or typeof(name)))
			return true
		end
		return false
	end

	function window:SaveConfig(name: string): boolean
		if badConfigName("SaveConfig", name) then
			return false
		end
		local snapshot = ctx:GetConfig()
		local ok = Config.save(configFolder, name, snapshot)
		local n = 0
		for _ in snapshot do
			n += 1
		end
		print(("[Uranium] SaveConfig(%q) -> %s  (%d flags)"):format(tostring(name), tostring(ok), n))
		return ok
	end
	function window:LoadConfig(name: string): boolean
		if badConfigName("LoadConfig", name) then
			return false
		end
		local data = Config.load(configFolder, name)
		print(("[Uranium] LoadConfig(%q) -> %s"):format(tostring(name), tostring(data ~= nil)))
		if data then
			ctx:LoadConfig(data)
			return true
		end
		return false
	end
	function window:DeleteConfig(name: string): boolean
		if badConfigName("DeleteConfig", name) then
			return false
		end
		return Config.delete(configFolder, name)
	end
	function window:ListConfigs(): { string }
		return Config.list(configFolder)
	end

	-- ── teardown ───────────────────────────────────────────────────────────────
	-- Full unload: the lingering UserInputService listeners come off, the popover
	-- overlay closes, the singleton slot is freed and the ScreenGui is destroyed.
	-- This is what both the close button and the Settings tab's Unload run.
	--
	-- The listeners are disconnected UP FRONT rather than in the tween callback —
	-- during the ~0.16s fade the window is on its way out, and a toggle-key press
	-- landing in that gap would otherwise "restore" a window about to be deleted.
	-- `immediate` skips the fade entirely (used when a re-run is unloading us to
	-- take our place — the new window shouldn't wait on the old one's animation).
	local destroyed = false
	function window:Destroy(immediate: boolean?)
		if destroyed then
			return
		end
		destroyed = true
		for _, conn in connections do
			conn:Disconnect()
		end
		table.clear(connections)
		ctx:ClosePopover()
		Singleton.release(record)

		if immediate then
			screenGui:Destroy()
			return
		end
		Tween.play(mainScale, Tween.MenuOut, { Scale = 0.9 })
		Tween.play(shadow, Tween.MenuOut, { ImageTransparency = 1 })
		local t = Tween.play(main, Tween.MenuOut, { GroupTransparency = 1 })
		t.Completed:Once(function()
			screenGui:Destroy()
		end)
	end

	-- ── built-in Settings tab ───────────────────────────────────────────────────
	-- A drop-in panel: accent color, the toggle keybind, a notifications switch,
	-- and full config save / load / delete + auto-load. Call it LAST so the
	-- auto-load pass sees every flagged control your other tabs registered.
	function window:CreateSettingsTab(settingsOpts: any?)
		settingsOpts = settingsOpts or {}
		print(("[Uranium] CreateSettingsTab: building (config supported=%s)"):format(tostring(Config.supported)))
		local tab = window:CreateTab({
			Name = settingsOpts.Name or "Settings",
			Icon = settingsOpts.Icon or "gear",
		})

		-- Interface ──────────────────────────────────────────────────────────────
		local iface = tab:CreateGroup({ Title = "Interface", Column = 1 })
		iface:Colorpicker({
			Name = "Accent Color",
			Desc = "Re-themes the whole UI.",
			Flag = "uranium_accent",
			Default = ctx.Accent,
			Callback = function(c)
				window:SetAccent(c)
			end,
		})
		iface:Keybind({
			Name = "Toggle UI",
			Desc = "Show or hide the window.",
			Flag = "uranium_togglekey",
			Default = toggleKey,
			Callback = function(k)
				window:SetToggleKey(k)
			end,
		})
		iface:Toggle({
			Name = "Notifications",
			Desc = "Show toast notifications.",
			Flag = "uranium_notifications",
			Default = true,
			Callback = function(on)
				window:SetNotificationsEnabled(on)
			end,
		})

		-- Configuration ────────────────────────────────────────────────────────────
		local cfg = tab:CreateGroup({ Title = "Configuration", Column = 2 })
		if not Config.supported then
			cfg:Paragraph({
				Title = "Unavailable",
				Body = "Your executor doesn't expose file functions, so configs can't "
					.. "be saved. Everything else here still works.",
			})
		else
			local nameBox = cfg:Input({ Name = "Config Name", Placeholder = "my config" })
			local list = cfg:Dropdown({
				Name = "Saved Configs",
				Placeholder = "None saved",
				Stack = true,
				Options = window:ListConfigs(),
			})
			local function refresh()
				list:SetOptions(window:ListConfigs())
			end

			cfg:ButtonRow({
				{
					Label = "Save",
					Callback = function()
						local n = nameBox:Get()
						if n == nil or n == "" then
							window:Notify({ Title = "Config", Text = "Enter a name first." })
							return
						end
						if window:SaveConfig(n) then
							refresh()
							list:Set(n)
							window:Notify({ Title = "Config", Text = ('Saved "%s".'):format(n) })
						else
							window:Notify({ Title = "Config", Text = "Save failed." })
						end
					end,
				},
				{
					Label = "Load",
					Callback = function()
						local n = list:Get()
						if not n then
							window:Notify({ Title = "Config", Text = "Pick a config to load." })
							return
						end
						if window:LoadConfig(n) then
							window:Notify({ Title = "Config", Text = ('Loaded "%s".'):format(n) })
						end
					end,
				},
			})
			cfg:ButtonRow({
				{
					Label = "Delete",
					Callback = function()
						local n = list:Get()
						if not n then
							return
						end
						window:DeleteConfig(n)
						refresh()
						window:Notify({ Title = "Config", Text = ('Deleted "%s".'):format(n) })
					end,
				},
				{ Label = "Refresh", Callback = refresh },
			})
			cfg:Toggle({
				Name = "Auto Load",
				Desc = "Apply the selected config on launch.",
				Default = Config.getAutoload(configFolder) ~= nil,
				Callback = function(on)
					Config.setAutoload(configFolder, on and list:Get() or nil)
				end,
			})

			-- Apply the auto-load config once the rest of the UI has finished
			-- building (this tab is meant to be created last, so all flags exist).
			task.defer(function()
				local auto = Config.getAutoload(configFolder)
				if auto then
					list:Set(auto)
					window:LoadConfig(auto)
				end
			end)
		end

		cfg:Divider()
		cfg:Button({
			Name = "Danger Zone",
			Label = "Unload " .. Theme.Brand.name,
			Callback = function()
				window:Destroy()
			end,
		})

		local flagCount = 0
		for _ in ctx.Flags do
			flagCount += 1
		end
		print(("[Uranium] CreateSettingsTab: done (%d flags registered)"):format(flagCount))
		return tab
	end

	-- mount — pop the window in from a touch smaller and faded so it eases in
	-- rather than just appearing
	mainScale.Scale = 0.92
	main.GroupTransparency = 1
	syncShadow()
	task.defer(function()
		Tween.play(mainScale, Tween.Pop, { Scale = 1 })
		Tween.play(main, Tween.Normal, { GroupTransparency = 0 })
		Tween.play(shadow, Tween.Normal, { ImageTransparency = SHADOW_T })
	end)

	local localPlayer = Players.LocalPlayer
	if localPlayer then
		screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
	elseif RunService:IsStudio() then
		screenGui.Parent = game:GetService("CoreGui")
	end

	-- Claim the global slot LAST, once this window is actually on screen — the
	-- next run of the loadstring finds this record and unloads us before it
	-- builds. `Unload` tears down without the fade: the replacement window is
	-- already being built and shouldn't overlap the outgoing one.
	if singleton then
		record = Singleton.claim({
			Name = Theme.Brand.name,
			Window = window,
			ScreenGui = screenGui,
			Unload = function()
				window:Destroy(true)
			end,
		})
	end

	return window
end
