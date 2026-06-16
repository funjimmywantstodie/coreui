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
local Tab = require(script.Parent.Tab)
local Notify = require(script.Parent.Notify)

local M = Theme.Metrics

return function(opts: any)
	opts = opts or {}
	local colors = Theme.Colors

	-- where configs are saved on disk + which key shows/hides the window
	local configFolder = opts.ConfigFolder or "coreui"
	local toggleKey: Enum.KeyCode = opts.ToggleKey or Enum.KeyCode.RightShift
	local notificationsEnabled = true
	-- UserInputService connections live past the ScreenGui's lifetime, so they're
	-- tracked here and disconnected by Window:Destroy.
	local connections: { RBXScriptConnection } = {}

	-- ── ScreenGui + window frame ────────────────────────────────────────────
	local screenGui = Create("ScreenGui", {
		Name = "coreui",
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
	local SHADOW_PAD = 200 -- how far the soft tail bleeds past each edge (bigger = more gradual falloff)
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
	-- (centered) instead of spilling content off the right/bottom edge.
	local function fitWindow()
		local vp = screenGui.AbsoluteSize
		if vp.X <= 0 then
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
		Create("Frame", { -- top inset highlight — the CSS `inset` lit edge that
			Name = "Highlight",            -- catches light and lifts the window
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = colors.white,
			BackgroundTransparency = 0.94,
			BorderSizePixel = 0,
		}),
	})

	-- logo
	local logo = Create("Frame", {
		Name = "Logo",
		Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, M.sidebar / 2, 0.5, 0),
		BackgroundColor3 = colors.accent,
		Parent = titlebar,
	}, {
		Create.corner(8),
	})
	local logoGradient = Create("UIGradient", {
		Color = ColorSequence.new(colors.accent_2, colors.accent),
		Rotation = 135,
		Parent = logo,
	})
	Create("Frame", { -- ring
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(13, 13),
		BackgroundTransparency = 1,
		Parent = logo,
	}, { Create.corner(999), Create.stroke(colors.white, 2) })
	Create("Frame", { -- dot
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = colors.white,
		Parent = logo,
	}, { Create.corner(999) })

	Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = opts.Title or "coreui",
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
		ScrollBarImageColor3 = Color3.fromHex("2A2A2E"),
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
		TextColor3 = colors.text_muted,
		TextSize = 12,
		FontFace = Theme.Font.Regular,
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

	-- logo follows accent
	ctx:RegisterAccent(function(accent, accentHover)
		logo.BackgroundColor3 = accent
		logoGradient.Color = ColorSequence.new(accentHover, accent)
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
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			main.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
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
					for _, item in card:GetChildren() do
						if item:IsA("GuiObject") and item.Name ~= "Separator" then
							local matches = groupMatch
								or string.find(collectText(item), query, 1, true) ~= nil
							item.Visible = matches
							if matches then
								anyVisible = true
							end
						end
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
		if gameProcessed then
			return
		end
		if toggleKey ~= Enum.KeyCode.Unknown and input.KeyCode == toggleKey then
			setMinimized(not minimized)
		end
	end))

	-- ── maximize toggle ─────────────────────────────────────────────────────────
	local maximized = false
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
	winBtns.close.Activated:Connect(function()
		-- same shrink+fade as minimize, but disable the gui once it's gone
		Tween.play(mainScale, Tween.MenuOut, { Scale = 0.9 })
		Tween.play(shadow, Tween.MenuOut, { ImageTransparency = 1 })
		local t = Tween.play(main, Tween.MenuOut, { GroupTransparency = 1 })
		t.Completed:Once(function()
			screenGui.Enabled = false
			mainScale.Scale = 1 -- reset in case it's ever re-enabled
			main.GroupTransparency = 0
			shadow.ImageTransparency = SHADOW_T
		end)
	end)

	function window:CreateTab(tabOpts: any)
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
		select(index)
	end

	function window:Notify(notifyOpts: any)
		if not notificationsEnabled then
			return
		end
		Notify(ctx, toasts, notifyOpts)
	end

	function window:SetAccent(color: Color3)
		ctx:SetAccent(color)
	end

	-- ── settings: theme / keybind / notifications ─────────────────────────────
	function window:SetToggleKey(key: Enum.KeyCode)
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

	function window:SaveConfig(name: string): boolean
		return Config.save(configFolder, name, ctx:GetConfig())
	end
	function window:LoadConfig(name: string): boolean
		local data = Config.load(configFolder, name)
		if data then
			ctx:LoadConfig(data)
			return true
		end
		return false
	end
	function window:DeleteConfig(name: string): boolean
		return Config.delete(configFolder, name)
	end
	function window:ListConfigs(): { string }
		return Config.list(configFolder)
	end

	-- ── teardown ───────────────────────────────────────────────────────────────
	-- Disconnect the lingering UserInputService listeners, then fade the window
	-- out and destroy the ScreenGui (close() only hides it; this fully unloads).
	function window:Destroy()
		Tween.play(mainScale, Tween.MenuOut, { Scale = 0.9 })
		Tween.play(shadow, Tween.MenuOut, { ImageTransparency = 1 })
		local t = Tween.play(main, Tween.MenuOut, { GroupTransparency = 1 })
		t.Completed:Once(function()
			for _, conn in connections do
				conn:Disconnect()
			end
			table.clear(connections)
			ctx:ClosePopover()
			screenGui:Destroy()
		end)
	end

	-- ── built-in Settings tab ───────────────────────────────────────────────────
	-- A drop-in panel: accent color, the toggle keybind, a notifications switch,
	-- and full config save / load / delete + auto-load. Call it LAST so the
	-- auto-load pass sees every flagged control your other tabs registered.
	function window:CreateSettingsTab(settingsOpts: any?)
		settingsOpts = settingsOpts or {}
		local tab = window:CreateTab({
			Name = settingsOpts.Name or "Settings",
			Icon = settingsOpts.Icon or "gear",
		})

		-- Interface ──────────────────────────────────────────────────────────────
		local iface = tab:CreateGroup({ Title = "Interface", Column = 1 })
		iface:Colorpicker({
			Name = "Accent Color",
			Desc = "Re-themes the whole UI.",
			Flag = "coreui_accent",
			Default = ctx.Accent,
			Callback = function(c)
				window:SetAccent(c)
			end,
		})
		iface:Keybind({
			Name = "Toggle UI",
			Desc = "Show or hide the window.",
			Flag = "coreui_togglekey",
			Default = toggleKey,
			Callback = function(k)
				window:SetToggleKey(k)
			end,
		})
		iface:Toggle({
			Name = "Notifications",
			Desc = "Show toast notifications.",
			Flag = "coreui_notifications",
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
			Label = "Unload coreui",
			Callback = function()
				window:Destroy()
			end,
		})

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

	return window
end
