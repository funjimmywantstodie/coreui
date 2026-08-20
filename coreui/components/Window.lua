--!strict
-- components/Window.lua — the window shell: titlebar, sidebar, scrolling content,
-- status bar and overlay. Owns the Context, the tab list, notifications and the
-- live accent.
--
-- The ScreenGui is mounted through util/Gui.lua — `opts.Parent` → `gethui()` →
-- `CoreGui` → `PlayerGui`, parented exactly once at whichever wins — and carries
-- a neutral per-load name plus `Gui.Attribute` for identity. It's exposed as
-- `window.ScreenGui` so a host can re-check where it ended up.

local Services = require(script.Parent.Parent.util.Services)

local UserInputService = Services.UserInputService

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)
local Context = require(script.Parent.Parent.util.Context)
local Bind = require(script.Parent.Parent.util.Bind)
local Fade = require(script.Parent.Parent.util.Fade)
local Config = require(script.Parent.Parent.util.Config)
local Asset = require(script.Parent.Parent.util.Asset)
local Log = require(script.Parent.Parent.util.Log)
local Gui = require(script.Parent.Parent.util.Gui)
local Singleton = require(script.Parent.Parent.util.Singleton)
local Tab = require(script.Parent.Tab)
local Info = require(script.Parent.Info)
local Notify = require(script.Parent.Notify)
local Splash = require(script.Parent.Splash)
local SettingsPanel = require(script.Parent.Settings)
-- Three slices of the window's API that have nothing to do with its chrome, each
-- installing its own methods onto the `window` table below. This file was 2178
-- lines and eight jobs; these were the three that came out cleanly.
local WindowConfig = require(script.Parent.WindowConfig)
local WindowHud = require(script.Parent.WindowHud)
local WindowState = require(script.Parent.WindowState)

local M = Theme.Metrics

-- Everything `CreateWindow` accepts. Options belonging to a piece that was split
-- out are still declared here, because this is the entry point that receives
-- them: `ConfigFolder` is read by components/WindowConfig.lua, `Hud` by
-- components/WindowHud.lua, `PersistWindow`/`WindowFlag` by
-- components/WindowState.lua. Every option a TAB takes is declared in
-- components/Tab.lua instead — that one Window only forwards.
local WINDOW_SCHEMA: Log.Schema = {
	{ "Title", "string" },
	{ "ToggleKey", "EnumItem" },
	{ "Accent", "Color3" },
	{ "ConfigFolder", "string" },
	{ "LogoRadius", "number" },
	{ "LogoZoom", "number" },
	{ "AllowMultiple", "boolean" },
	{ "Splash", { "boolean", "table" } },
	{ "Hud", { "boolean", "table" } },
	{ "Keybinds", "boolean" },
	{ "Descriptions", "string" },
	{ "MinimizeHint", "boolean" },
	{ "OnFlag", "function" },
	{ "OnFlagChanged", "function" },
	{ "PersistWindow", "boolean" },
	{ "WindowFlag", "string" },
	{ "Parent", "Instance" },
	{ "GuiName", "string" },
	{ "Verbose", "boolean" },
}

-- `Window:Bind` — a headless keybind, no control attached.
local BIND_SCHEMA: Log.Schema = {
	{ "Key", "EnumItem" },
	{ "Callback", "function" },
	{ "Mode", "string" },
	{ "Label", "string" },
	{ "Id", "string" },
	{ "Parent", { "string", "table" } },
	{ "Hud", "boolean" },
}

return function(opts: any)
	opts = opts or {}
	local colors = Theme.Colors

	-- Validate the window options up front so a wrong type surfaces here (naming
	-- the field) rather than as a mystery error much later when it's first used.
	Log.check("CreateWindow", opts, WINDOW_SCHEMA)

	-- Console output is off by default (see util/Log.lua): a game scraping
	-- LogService gets a free fingerprint out of every branded line we print. This
	-- is set before anything below can log, so `Verbose = true` still catches the
	-- build stamp and the "already loaded" line.
	if opts.Verbose ~= nil then
		Log.setVerbose(opts.Verbose == true)
	end
	Log.banner()
	Log.info(Config.report)

	-- which key shows/hides the window (where configs live is WindowConfig's)
	local toggleKey: Enum.KeyCode = opts.ToggleKey or Enum.KeyCode.RightShift
	local notificationsEnabled = true
	-- The little "UI Minimized" card in the corner. On by default — it's the only
	-- thing on screen telling a first-time user which key brings the menu back —
	-- but it's also the one piece of chrome that outlives the window's own fade,
	-- so anyone recording or screenshotting with the menu hidden wants it gone.
	local minimizeHint = opts.MinimizeHint ~= false
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
	if singleton and Singleton.unloadExisting() then
		Log.info("already loaded — unloaded the previous window and refreshing.")
	end

	-- ── ScreenGui + window frame ────────────────────────────────────────────
	-- Neutral, per-load name (`GuiName` pins it) + an attribute for identity: a
	-- fixed brand-shaped name is the cheapest thing in the whole library for a
	-- place to detect, and the singleton sweep that used to need it now matches
	-- the attribute instead. See util/Gui.lua. The frame names below are random
	-- for the same reason — they're direct children, so they're visible to
	-- anything that can see the ScreenGui at all.
	local screenGui = Create("ScreenGui", {
		Name = opts.GuiName or Gui.rname(),
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	-- A plain Frame, deliberately. This was a CanvasGroup, because one
	-- GroupTransparency tween fades the whole window for mount / minimize /
	-- close. The cost was invisible in Studio and glaring in game: a CanvasGroup
	-- rasterizes everything inside it into an offscreen buffer, so every label in
	-- the UI was a resampled bitmap instead of SDF text — soft at any size, and
	-- worse the bigger the window got (fullscreen was the worst case). The fade
	-- now runs through util/Fade.lua, which drives the real transparency
	-- properties of the subtree instead. Never put text under a CanvasGroup.
	local main = Create("Frame", {
		Name = Gui.rname(),
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
	-- Fades the whole window subtree (see the note above): mount, minimize,
	-- restore and close all go through this.
	local mainFade = Fade.new(main)

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
	-- (centered) instead of spilling content off the right/bottom edge. Maximized
	-- goes through the same reconciliation rather than around it (an earlier
	-- version skipped the clamp entirely while maximized, which is how a maximized
	-- window could end up bigger than the screen it was on).
	local maximized = false
	-- The size the window wants to be, which is the theme's until someone says
	-- otherwise (`Window:SetSize`, or a restored `uranium_window` record). It's the
	-- *unclamped* wish: fitWindow below is what actually reconciles it with the
	-- viewport, so a size saved on a big monitor survives a session on a laptop
	-- instead of being permanently shrunk to fit it.
	local baseWidth, baseHeight = M.windowWidth, M.windowHeight
	-- Below this the sidebar and the two columns stop being a layout.
	local MIN_W, MIN_H = 420, 320
	local VIEWPORT_INSET = 24 -- air left around the window at full size
	-- The size the window should be right now, reconciling the wish (`baseWidth`/
	-- `baseHeight`, or "as big as it goes" while maximized) with the viewport.
	--
	-- One function, because the two callers used to spell the same arithmetic out
	-- separately and disagreed: maximize was `math.max(baseWidth, vp.X - 24)`,
	-- which takes the LARGER of the two — so a window whose saved size came off a
	-- bigger monitor maximized to that saved size on a laptop and hung off the
	-- screen, and `fitWindow` then couldn't pull it back because it took the
	-- maximized branch too. The floor belongs at MIN_W/MIN_H (the point below
	-- which the sidebar and two columns stop being a layout), not at whatever the
	-- window happened to be. Returns nil when the viewport hasn't been measured.
	local function targetSize(): UDim2?
		local vp = screenGui.AbsoluteSize
		if vp.X <= 0 or vp.Y <= 0 then
			return nil
		end
		local availW = math.max(MIN_W, vp.X - VIEWPORT_INSET)
		local availH = math.max(MIN_H, vp.Y - VIEWPORT_INSET)
		if maximized then
			return UDim2.fromOffset(availW, availH)
		end
		return UDim2.fromOffset(math.min(baseWidth, availW), math.min(baseHeight, availH))
	end
	local function fitWindow()
		local size = targetSize()
		if size then
			main.Size = size
		end
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
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = titlebar,
	}, {
		Create.corner(opts.LogoRadius or Theme.Brand.radius),
	})
	-- The accent square is its own layer under the art rather than the holder's
	-- background, so the async load result can hide it with `Visible` alone.
	-- Writing a transparency from a load callback would fight util/Fade.lua if
	-- the asset happened to arrive mid mount/minimize fade.
	-- The fallback is a mark, not a letter. An accent square with the brand's
	-- initial in it is indistinguishable from "the logo failed to load" — which
	-- is what it *was*, for every client whose executor can't fetch the art (and
	-- for a while, for everyone, because the art URL had gone stale). Lucide's
	-- `atom` is a nucleus crossed by two elliptical orbits: the Uranium mark's own
	-- composition, drawn from a spritesheet the engine fetches itself, so it needs
	-- nothing from the executor. Tinted tile + accent glyph is the `accent_soft`
	-- pattern the active nav button uses. components/Screen.lua does the same.
	local logoSquare = Create("Frame", {
		Name = "Square",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors.accent_soft,
		BorderSizePixel = 0,
		Parent = logo,
	}, {
		Create.corner(opts.LogoRadius or Theme.Brand.radius),
	})
	local brandName = opts.Title or Theme.Brand.name
	local logoFallback = Icons.new("atom", 20, colors.accent) :: any
	logoFallback.Name = "Glyph"
	logoFallback.AnchorPoint = Vector2.new(0.5, 0.5)
	logoFallback.Position = UDim2.fromScale(0.5, 0.5)
	logoFallback.Parent = logo
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
		logoSquare.Visible = true
		Asset.load(logoImage, source, function(loaded)
			-- Only the fallback reacts; the image is left alone.
			logoFallback.Visible = not loaded
			logoSquare.Visible = not loaded
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
	-- Resolved into locals because the splash screen shows the same mark.
	local logoSource: any = nil
	local logoZoom: number? = nil
	if opts.Logo == false then
		logoSource = nil
	elseif opts.Logo ~= nil then
		logoSource, logoZoom = opts.Logo, opts.LogoZoom
	else
		logoSource, logoZoom = Theme.Brand.logo, opts.LogoZoom or Theme.Brand.zoom
	end
	setLogo(logoSource, logoZoom)

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

	-- search field — hidden until the search button is clicked. Its width slides
	-- open while the contents fade in together (util/Fade.lua, not a CanvasGroup:
	-- that would blur the text you're typing); ClipsDescendants keeps the
	-- icon/box from spilling out while it's narrower than its content.
	local SEARCH_W = 180
	local searchField = Create("Frame", {
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
	local searchFade = Fade.new(searchField)

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

		-- Icons.tween, not Tween.play: Icons.new falls back to a glyph TextLabel for
		-- any name it can't resolve, which has no ImageColor3 — so hovering a
		-- fallback icon threw rather than just not animating. (Nothing in the
		-- shipped set falls back today; `bundle.py --shake` is where it bites.)
		local over = name == "close" and colors.danger or colors.text
		btn.MouseEnter:Connect(function()
			Icons.tween(icon, Tween.Fast, over)
		end)
		btn.MouseLeave:Connect(function()
			Icons.tween(icon, Tween.Fast, colors.text_muted)
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

	-- Nav buttons live in their own frames so the sidebar's UIListLayout never
	-- tries to lay out the full-height Border hairline (which would otherwise
	-- consume the whole column and push the nav buttons off-screen).
	--
	-- Two clusters, not one: `CreateTab{ Pin = "bottom" }` lands in the bottom one,
	-- which grows *up* from the bottom edge. That's what lets a menu separate a
	-- class of tab from the rest — settings, or a "universal" section — instead of
	-- one undifferentiated stack. Both are AutomaticSize.Y, so each takes only the
	-- height its own buttons need; a plain Frame doesn't sink input either, so
	-- even if a long rail made the two meet in the middle neither can swallow the
	-- other's clicks.
	local function newNavCluster(bottom: boolean): Frame
		return Create("Frame", {
			Name = bottom and "NavBottom" or "NavTop",
			AnchorPoint = bottom and Vector2.new(0, 1) or Vector2.new(0, 0),
			Position = bottom and UDim2.fromScale(0, 1) or UDim2.fromScale(0, 0),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = sidebar,
		}, {
			bottom and Create.padding(0, 0, 16, 0) or Create.padding(16, 0, 0, 0),
			Create.listLayout({
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = bottom and Enum.VerticalAlignment.Bottom
					or Enum.VerticalAlignment.Top,
				Padding = UDim.new(0, 10),
			}),
		})
	end
	local navTop = newNavCluster(false)
	local navBottom = newNavCluster(true)
	local function navFor(pin: string?): Frame
		return pin == "bottom" and navBottom or navTop
	end

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
	-- `Keybinds = false` takes the bind chip off every control that would
	-- otherwise grow one by default (Toggle). A control that asks for a keybind
	-- explicitly still gets it — this is the default, not a ban.
	ctx.Keybinds = opts.Keybinds ~= false
	-- Where every control's `Desc` is drawn: "hover" (the default — behind the info
	-- glyph, components/Info.lua), "inline" (a second line under the name, what the
	-- library used to do unconditionally) or "both". Set before a single control
	-- exists, and switchable later with Window:SetDescriptions.
	if opts.Descriptions ~= nil then
		ctx:SetDescriptions(opts.Descriptions)
	end

	-- `CreateWindow{ OnFlag = function(name, kind) end }` — installed before a
	-- single control exists, so a loader sees every flag the menu ever registers,
	-- in order, including the ones the built-in Settings tab adds. Fires
	-- synchronously from inside the registration (see Context:OnFlag), which is
	-- what makes "tag this flag with the module I'm building right now" work.
	if opts.OnFlag then
		ctx:OnFlag(opts.OnFlag)
	end

	-- `CreateWindow{ OnFlagChanged = function(name, value, kind, source) end }` —
	-- the same hook as `Window:OnFlagChanged`, installed early enough that a host
	-- persisting continuously catches the first change the menu ever makes,
	-- including ones the built-in Settings tab causes while it builds.
	if opts.OnFlagChanged then
		ctx:OnFlagChanged(opts.OnFlagChanged)
	end

	-- The keybind router (util/Bind.lua): one pair of input listeners shared by
	-- every bound control, created here so its connections are tracked and die
	-- with the window like the toggle-key listener below.
	local binds = Bind.get(ctx)
	for _, conn in binds.connections do
		table.insert(connections, conn)
	end

	-- The fallback mark is only on screen when the art hasn't loaded, but it still
	-- has to track SetAccent for that case — the tile off `ctx.AccentSoft`, the
	-- glyph off the accent itself, both derived on the Context so the ramp is
	-- never recomputed here.
	ctx:RegisterAccent(function(accent)
		logoSquare.BackgroundColor3 = ctx.AccentSoft
		Icons.tint(logoFallback, accent)
	end)

	-- ── titlebar dragging ────────────────────────────────────────────────────
	local dragging, dragStart, startPos
	titlebar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			-- ...unless something drawn on top of the window already owns this press.
			-- The bind HUD is a sibling of `main` at a higher ZIndex and drags
			-- itself, and Roblox hands `InputBegan` to every non-sinking object under
			-- the pointer — so grabbing the HUD where it overlapped the titlebar used
			-- to drag both at once, off the same mouse, until the gesture wedged.
			-- See Context:RegisterDragPriority.
			if ctx:DragClaimed(Vector2.new(input.Position.X, input.Position.Y)) then
				return
			end
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

	-- Whole-pixel snapping — the other half of the "why is the text soft" answer
	-- (util/Fade.lua has the first half). The window is centered with a *scale*
	-- position and AnchorPoint (0.5, 0.5), so its top-left lands on a half pixel
	-- whenever the viewport or the window has an odd dimension — and then every
	-- glyph in the UI is rasterized half a pixel off the display grid, which
	-- reads as a soft, faintly smeared version of the same text. Rounding the
	-- top-left costs nothing and puts the whole tree back on integer coordinates.
	local function snapToPixels(pos: UDim2): UDim2
		local vp = screenGui.AbsoluteSize
		local size = main.AbsoluteSize
		if vp.X <= 0 or size.X <= 0 then
			return pos
		end
		local left = pos.X.Scale * vp.X + pos.X.Offset - size.X / 2
		local top = pos.Y.Scale * vp.Y + pos.Y.Offset - size.Y / 2
		return UDim2.new(
			pos.X.Scale, pos.X.Offset + (math.round(left) - left),
			pos.Y.Scale, pos.Y.Offset + (math.round(top) - top)
		)
	end
	-- Re-snap whenever the geometry moves under us: viewport resize, the fit
	-- clamp, maximize. (Setting Position can't change AbsoluteSize, so this
	-- can't feed itself.)
	local function resnap()
		main.Position = snapToPixels(main.Position)
	end
	-- The window's LAYOUT size, which is not `main.AbsoluteSize`: that one is run
	-- through the UIScale, which sits at 0.92 through the mount animation and 0.9
	-- the whole time the window is minimized. Reading the rendered size in those
	-- states and writing it back later restores the window a few percent off
	-- centre — so every geometry read below uses the size the layout actually
	-- asked for. `fitWindow` / `setMaximized` only ever set pure offsets, so the
	-- two halves of the UDim2 are the answer.
	local function layoutSize(): Vector2
		return Vector2.new(main.Size.X.Offset, main.Size.Y.Offset)
	end

	-- The window's TOP-LEFT in screen pixels — the only coordinate worth
	-- persisting, since the live Position is a scale/offset pair carrying whatever
	-- the drag left in it and its numbers mean nothing on a viewport of another
	-- size.
	local function topLeft(): Vector2
		local vp = screenGui.AbsoluteSize
		local pos, size = main.Position, layoutSize()
		return Vector2.new(
			pos.X.Scale * vp.X + pos.X.Offset - size.X / 2,
			pos.Y.Scale * vp.Y + pos.Y.Offset - size.Y / 2
		)
	end

	-- The exact inverse of `topLeft`. The scale halves are preserved rather than
	-- flattened to pure offsets, so a restored window keeps tracking the viewport
	-- exactly like a dragged one does, and the same clamp a drag goes through
	-- guarantees a record saved on a 1440p monitor can't put the window off a
	-- laptop screen.
	local function moveTo(x: number, y: number)
		local vp = screenGui.AbsoluteSize
		local size = layoutSize()
		if vp.X <= 0 or size.X <= 0 then
			return
		end
		local pos = main.Position
		local cx, cy = x + size.X / 2, y + size.Y / 2
		main.Position = snapToPixels(clampToViewport(UDim2.new(
			pos.X.Scale, cx - pos.X.Scale * vp.X,
			pos.Y.Scale, cy - pos.Y.Scale * vp.Y
		)))
	end
	main:GetPropertyChangedSignal("AbsoluteSize"):Connect(resnap)
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resnap)
	task.defer(resnap)

	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			main.Position = snapToPixels(clampToViewport(UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)))
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			local wasDragging = dragging
			dragging = false
			-- On RELEASE, not per frame: the position is part of the persisted window
			-- record, and a host writing on every change would otherwise write once
			-- per mouse move for the length of the drag.
			if wasDragging then
				ctx:User(function()
					ctx:WindowStateChanged()
				end)
			end
		end
	end))

	-- ── public API ───────────────────────────────────────────────────────────
	local tabs = {}
	local activeIndex = 1
	local window = {}
	-- The ScreenGui itself, exposed so a host can re-check where it landed (and
	-- re-parent or re-protect it): the parent is resolved at mount time from
	-- whatever the executor offers, so it isn't knowable up front. Also on the
	-- singleton record.
	window.ScreenGui = screenGui
	local applySearch -- forward declaration (used by select)
	local splash: any = nil -- the boot screen, while it's playing (see the mount)

	-- ── the installed halves ──────────────────────────────────────────────────
	-- `CreateHud` / `GetHud` / `SetHudVisible` / `OnHudVisible` / `OnHudChanged`
	-- (components/WindowHud.lua) and the whole flag + config surface
	-- (components/WindowConfig.lua) are installed onto `window` here. Both are
	-- built before a single tab exists: `CreateWindow{ OnFlag }` has to see every
	-- flag the menu ever registers, and `Hud = true` builds one below.
	--
	-- The window-state flag (components/WindowState.lua) is registered further
	-- down instead, once the geometry helpers it depends on exist.
	local hudApi = WindowHud(window, ctx, screenGui, opts)
	local configApi = WindowConfig(window, ctx, opts)

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

	-- Selecting a tab *deliberately* — a click, `Window:Select`, `tab:Select`. The
	-- plain `select` above is also how the window picks a tab for itself while it
	-- builds (the first tab, or a fallback when the open one is hidden), and
	-- announcing those as window-state changes would report the menu's own
	-- construction as a run of edits worth persisting.
	local function chooseTab(index: number)
		select(index)
		ctx:WindowStateChanged()
	end

	-- ── search ────────────────────────────────────────────────────────────────
	-- The filtering itself is `tab:Filter(query)` (components/Tab.lua). It used to
	-- live here and re-derive the page's entire shape from instance names on every
	-- keystroke — which put Tab's and Group's layout into this file, where a
	-- rename over there would have silently filtered nothing. All that's left here
	-- is the box and which tab is showing.
	applySearch = function(query: string)
		local tab = tabs[activeIndex]
		if tab then
			tab:Filter(query)
		end
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		applySearch(searchBox.Text)
	end)
	winBtns.search.Activated:Connect(function()
		searchOpen = not searchOpen
		if searchOpen then
			-- Drop every tab's collected-text cache: opening the box is the one
			-- moment the menu can have grown or lost controls since the last search,
			-- and it's the cheapest possible invalidation point (once, off the typing
			-- path). All tabs, not just the active one — switching tabs mid-search
			-- filters the new page without reopening the box.
			for _, tab in tabs do
				tab:ResetFilter()
			end
			-- slide + fade open from a zero-width sliver, then focus the box
			searchField.Visible = true
			searchField.Size = UDim2.fromOffset(0, 30)
			searchFade:Set(1)
			Tween.play(searchField, Tween.Slide, { Size = UDim2.fromOffset(SEARCH_W, 30) })
			searchFade:To(Tween.Slide, 0)
			searchBox:CaptureFocus()
		else
			searchBox.Text = "" -- fires the Text signal → clears the filter
			-- slide + fade closed, then hide once it's fully collapsed
			Tween.play(searchField, Tween.Slide, { Size = UDim2.fromOffset(0, 30) })
			searchFade:To(Tween.Slide, 1, function()
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
	-- What the minimized card says. `CreateWindow{ ToggleKey = Enum.KeyCode.Unknown }`
	-- is a legal way to say "no toggle key", and building the label inline printed
	-- the literal "Press None to show it again." for it — a window with no way back
	-- telling the user to press a key that doesn't exist. SetToggleKey already had
	-- the right wording; this is the same answer at build time.
	local function hintText(): string
		if toggleKey == nil or toggleKey == Enum.KeyCode.Unknown then
			return "Re-bind a toggle key to show it again."
		end
		return ("Press %s to show it again."):format(Bind.name(toggleKey))
	end
	local restoreHintText = Create("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = hintText(),
		TextColor3 = colors.text_muted,
		TextSize = 12,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = 2,
		Parent = restoreHint,
	})

	local minimized = false
	-- Nav flyouts don't get a MouseLeave when the window vanishes from under the
	-- cursor, so hiding/unloading drops them explicitly (see Tab:_hideFlyout).
	-- A description popover opened by hovering an info glyph has exactly the same
	-- problem — the toggle key can hide the window while the cursor sits on one —
	-- and the same consequence: it would sit in the window fade's snapshot and come
	-- back on restore with nothing pointing at it.
	local function hideFlyouts()
		for _, tab in tabs do
			tab:_hideFlyout()
		end
		Info.hide(ctx)
	end
	local function setMinimized(value: boolean)
		minimized = value
		if value then
			hideFlyouts()
			-- shrink + fade the whole window away together, then hide it once the
			-- fade has fully played (no abrupt cut — it's already invisible).
			Tween.play(mainScale, Tween.MenuOut, { Scale = 0.9 })
			Tween.play(shadow, Tween.MenuOut, { ImageTransparency = 1 })
			mainFade:To(Tween.MenuOut, 1, function()
				if minimized then
					main.Visible = false
				end
			end)
			restoreHint.Visible = minimizeHint
		else
			-- restore from the shrunk/faded state: pop the scale, ease the fade in
			main.Visible = true
			mainScale.Scale = 0.9
			-- Rest first so the hide's snapshot is released: anything built while the
			-- window was minimized isn't in it, and would pop in fully opaque against
			-- a subtree that's still fading. Set(0) puts the old instances back at
			-- their own resting transparencies and drops the cache, so the Set(1)
			-- below re-reads the tree as it is now.
			mainFade:Set(0)
			mainFade:Set(1)
			Tween.play(mainScale, Tween.Pop, { Scale = 1 })
			mainFade:To(Tween.Normal, 0)
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
		-- Compare against `Bind.of`, not `input.KeyCode`: a mouse press reports
		-- KeyCode.Unknown, so a toggle key bound to MB2/MB3 (which the Settings
		-- tab's chip happily captures) matched nothing and left the window with no
		-- way to be shown again — silently, since the chip still read "MB2".
		local pressed = Bind.of(input)
		if pressed ~= nil and toggleKey ~= Enum.KeyCode.Unknown and pressed == toggleKey then
			-- Defensive: if anything disabled the ScreenGui, flipping the minimize
			-- state would just toggle an invisible window and the UI would look
			-- permanently gone. Re-enable it instead. (Close no longer takes this
			-- path — it destroys the ScreenGui outright.)
			if not screenGui.Enabled then
				-- Run the real restore rather than hand-setting the flags: if the window
				-- was minimized when the ScreenGui went dark, mainFade is parked at
				-- alpha 1 and mainScale at 0.9, so flipping Visible alone hands back a
				-- window that is present and completely invisible — and leaves
				-- `minimized` reading false, which cost two more presses to sort out.
				screenGui.Enabled = true
				minimized = true
				setMinimized(false)
				return
			end
			setMinimized(not minimized)
		end
	end))

	-- ── maximize toggle ─────────────────────────────────────────────────────────
	-- `animate = false` snaps, which is what restoring a saved record wants — the
	-- window shouldn't play the maximize animation for a state the user set in a
	-- previous session.
	local function setMaximized(value: boolean, animate: boolean?)
		value = value == true
		if value == maximized then
			return
		end
		maximized = value
		local size = targetSize()
		if size then
			if animate == false then
				main.Size = size
			else
				Tween.play(main, Tween.Normal, { Size = size })
			end
		end
		ctx:WindowStateChanged()
	end
	winBtns.max.Activated:Connect(function()
		ctx:User(function()
			setMaximized(not maximized)
		end)
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
		-- The option SHAPE is components/Tab.lua's to declare and check (its
		-- `SCHEMA`), since it's the file that reads every one of them. Only the
		-- "you passed something that isn't an options table at all" case is caught
		-- here, because that one has to be caught before the table is indexed.
		--
		-- `any`: the handle grows a Select method below, and the hooks the tab
		-- exposes for us are deliberately untyped.
		local tab: any = Tab(ctx, tabOpts or {})
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
		-- ×10 so a tab's separator hairline can be ordered just above its button
		-- (order*10 - 1) without colliding with the tab before it. `Order` overrides
		-- creation order, for a menu that builds its tabs in a different sequence
		-- from the one it wants them shown in.
		local order = tab.order or index
		tab.button.LayoutOrder = order * 10
		if tab.separator then
			tab.separator.LayoutOrder = order * 10 - 1
		end

		-- Mount into the cluster its Pin asked for; `tab:SetPin` re-runs this,
		-- since the nav frames live here and the tab can't reach them itself.
		local function mountNav(pin: string)
			local cluster = navFor(pin)
			tab.button.Parent = cluster
			if tab.separator then
				tab.separator.Parent = cluster
			end
		end
		mountNav(tab.pin)
		tab._onPin = mountNav

		table.insert(tabs, tab)
		tab.button.Activated:Connect(function()
			ctx:User(chooseTab, index)
		end)
		function tab:Select()
			chooseTab(index)
		end

		-- Hiding the tab that's currently open would otherwise leave its page on
		-- screen with nothing in the sidebar selected, so fall through to the next
		-- visible tab (and re-open this one if it comes back while it's the active
		-- index).
		tab._onVisible = function(visible: boolean)
			if visible then
				-- Claim the selection when it's ours OR when nothing visible holds it —
				-- hiding the last visible tab leaves activeIndex pointing at a hidden
				-- one, and without this second case revealing a *different* tab would
				-- leave the window blank.
				local active = tabs[activeIndex]
				if activeIndex == index or not (active and active:IsVisible()) then
					select(index)
				end
				return
			end
			if activeIndex ~= index then
				return
			end
			for i, other in tabs do
				if i ~= index and other:IsVisible() then
					select(i)
					return
				end
			end
			tab:_setActive(false) -- nothing left to show
		end

		if index == 1 then
			select(1)
		end
		-- Routed through SetVisible rather than hiding the button here, so a tab
		-- built hidden takes the same "select something else" path as one hidden
		-- later (a game-specific tab that only appears in the games it supports).
		if tabOpts and tabOpts.Visible == false then
			tab:SetVisible(false)
		end
		-- ...which is also why the selection is re-checked here rather than only on
		-- `index == 1`: a first tab built hidden ran select(1) above and then hid
		-- itself, and tab 2 never claimed the empty slot — the window opened blank,
		-- with a sidebar showing no active tab. Any tab that arrives while nothing
		-- visible is selected takes the slot.
		local active = tabs[activeIndex]
		if tab:IsVisible() and not (active and active:IsVisible()) then
			select(index)
		end
		return tab
	end

	function window:Select(index: number)
		if type(index) ~= "number" or index < 1 or index > #tabs or index % 1 ~= 0 then
			Log.warn("Select", ("no tab #%s (there %s %d tab%s) — ignoring.")
				:format(tostring(index), #tabs == 1 and "is" or "are", #tabs, #tabs == 1 and "" or "s"))
			return
		end
		chooseTab(index)
	end

	-- Which tab is open, 1-based — the read that makes "restore the menu where the
	-- user left it" expressible at all, whether the window persists it itself or a
	-- host rolls its own record.
	function window:GetSelected(): number
		return activeIndex
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

	-- The live accent. A host building its own settings panel needs it to seed a
	-- colour picker with what the window is actually wearing.
	function window:GetAccent(): Color3
		return ctx.Accent
	end

	-- ── settings: theme / keybind / notifications ─────────────────────────────
	function window:SetToggleKey(key: Enum.KeyCode)
		if key ~= nil and typeof(key) ~= "EnumItem" then
			Log.fail("SetToggleKey", ("expects an Enum.KeyCode, got %s (try Enum.KeyCode.RightShift)")
				:format(typeof(key)))
		end
		toggleKey = key or Enum.KeyCode.Unknown
		restoreHintText.Text = hintText()
	end

	function window:GetToggleKey(): Enum.KeyCode
		return toggleKey
	end

	-- The minimized card, on or off. Applied live: switching it off from the
	-- Settings panel while the window is minimized is impossible (the panel is in
	-- the window), but a host can call this from a keybind at any time, and a card
	-- left on screen after being switched off would be the one bit of UI the
	-- setting visibly failed to reach.
	function window:SetMinimizeHint(enabled: boolean)
		minimizeHint = enabled ~= false
		restoreHint.Visible = minimizeHint and minimized
	end

	function window:GetMinimizeHint(): boolean
		return minimizeHint
	end

	function window:SetNotificationsEnabled(enabled: boolean)
		notificationsEnabled = enabled ~= false
	end

	function window:GetNotificationsEnabled(): boolean
		return notificationsEnabled
	end

	-- Where control descriptions are drawn: "hover" · "inline" · "both". Re-lays
	-- out every field already on screen, not just the ones built afterwards, which
	-- is what makes it worth offering as a switch in a host's own settings panel.
	-- Returns the mode in force afterwards — an unrecognized one warns and changes
	-- nothing, so a caller can echo the result back into its control rather than
	-- assume the write landed.
	function window:SetDescriptions(mode: string): string
		return ctx:SetDescriptions(mode)
	end

	function window:GetDescriptions(): string
		return ctx.Descriptions
	end

	-- ── settings: headless keybinds ───────────────────────────────────────────
	-- A bind with no control attached, for logic the menu doesn't expose:
	--   Window:Bind(Enum.KeyCode.B, function(on) ... end, "Hold")
	--   Window:Bind({ Key = Enum.KeyCode.B, Mode = "Toggle", Callback = fn })
	-- Returns the binding — :SetKey / :SetMode / :GetState / :Destroy. It rides
	-- the same router as the controls, so it honours gameProcessed and pauses
	-- while a Keybind chip is capturing.
	--
	-- Give it a `Label` to have it listed in the bind HUD; without one it's
	-- treated as internal plumbing and stays out (there'd be nothing to call it).
	-- `Parent = "<feature>"` makes it a sub-option of another bind, which keeps it
	-- out of that list while it's merely on (util/Bind.lua's tree).
	function window:Bind(keyOrOpts: any, callback: any, mode: any): any
		local o = keyOrOpts
		if typeof(keyOrOpts) == "EnumItem" then
			o = { Key = keyOrOpts, Callback = callback, Mode = mode }
		elseif type(keyOrOpts) ~= "table" then
			Log.fail("Bind", ("expects a key or an options table, got %s (try Window:Bind(Enum.KeyCode.B, fn, \"Hold\"))")
				:format(typeof(keyOrOpts)))
		end
		Log.check("Bind", o, BIND_SCHEMA)
		return binds:Register(o)
	end

	-- ── settings: window geometry + UI state ──────────────────────────────────
	-- Where the window is, how big it is, which tab is open and which groups are
	-- folded — all of it state the user set with the mouse, none of it readable
	-- until now, so "put the menu back where I left it" wasn't expressible by
	-- anyone, library or host.
	--
	-- Position is the window's TOP-LEFT in screen pixels, matching the HUD's
	-- convention. Setting it clamps the same way a drag does, so a coordinate from
	-- a bigger monitor can't strand the window off-screen.
	function window:GetPosition(): Vector2
		return topLeft()
	end

	function window:SetPosition(x: number, y: number)
		local px, py = tonumber(x), tonumber(y)
		if not px or not py then
			Log.warn("SetPosition", ("expects two numbers (x, y), got %s, %s — ignoring.")
				:format(typeof(x), typeof(y)))
			return
		end
		moveTo(px, py)
		ctx:WindowStateChanged()
	end

	-- The size the window is actually drawn at. `SetSize` sets the size it *wants*
	-- — it's still clamped to the viewport (and overridden while maximized), so a
	-- laptop session doesn't permanently shrink a size set on a bigger screen.
	function window:GetSize(): Vector2
		return layoutSize()
	end

	function window:SetSize(width: number, height: number)
		local w, h = tonumber(width), tonumber(height)
		if not w or not h then
			Log.warn("SetSize", ("expects two numbers (width, height), got %s, %s — ignoring.")
				:format(typeof(width), typeof(height)))
			return
		end
		baseWidth = math.max(MIN_W, math.floor(w))
		baseHeight = math.max(MIN_H, math.floor(h))
		fitWindow()
		ctx:WindowStateChanged()
	end

	function window:IsMaximized(): boolean
		return maximized
	end

	function window:SetMaximized(value: boolean, animate: boolean?)
		setMaximized(value ~= false, animate)
	end

	-- ── the window-state flag ─────────────────────────────────────────────────
	-- `uranium_window` — position, size, maximize, the open tab and every folded
	-- group, in one flag. It lives in components/WindowState.lua and reaches back
	-- in here through this table: a restore has to move real geometry, and that's
	-- the one thing about the window a config can drive. Everything it's handed is
	-- behaviour, never state, so it can't read a field it wasn't given.
	--
	-- `select` is the PLAIN one, not `chooseTab`: restoring a saved record is not
	-- a run of deliberate tab clicks, and announcing it as one would report the
	-- restore back as a fresh change worth persisting.
	WindowState(ctx, opts, {
		topLeft = topLeft,
		wantedSize = function(): Vector2
			return Vector2.new(baseWidth, baseHeight)
		end,
		setSize = function(w: number, h: number)
			window:SetSize(w, h)
		end,
		moveTo = moveTo,
		setMaximized = setMaximized,
		isMaximized = function(): boolean
			return maximized
		end,
		viewportWidth = function(): number
			return screenGui.AbsoluteSize.X
		end,
		tabs = function(): { any }
			return tabs
		end,
		selected = function(): number
			return activeIndex
		end,
		select = select,
	})


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
		binds:Destroy() -- drops every registered binding with the listeners
		ctx:ClosePopover()
		hideFlyouts()
		Singleton.release(record)
		if splash then
			splash:Destroy() -- torn down mid-boot: don't leave the splash on screen
			splash = nil
		end
		-- The HUD's own input listeners outlive the ScreenGui, same as ours.
		hudApi.Destroy()

		if immediate then
			screenGui:Destroy()
			return
		end
		Tween.play(mainScale, Tween.MenuOut, { Scale = 0.9 })
		Tween.play(shadow, Tween.MenuOut, { ImageTransparency = 1 })
		mainFade:To(Tween.MenuOut, 1, function()
			screenGui:Destroy()
		end)
	end

	-- ── built-in Settings tab ───────────────────────────────────────────────────
	-- A drop-in panel: accent color, the toggle keybind, a notifications switch,
	-- and full config save / load / delete + auto-load. Call it LAST so the
	-- auto-load pass sees every flagged control your other tabs registered.
	--
	-- Returns `tab, controls` — the second value is every handle the panel built
	-- (`controls.List`, `.Name`, `.AutoLoad`, `.Accent`, `.Hud`, `.Refresh`, …).
	-- They used to be locals in this closure, which left a host unable to refresh
	-- the saved-config list after its own write, read what was selected, or put its
	-- own button next to it. Also on `tab.Controls`, for callers that want one value.
	--
	-- `Sections = { Config = false }` drops a section; the groups themselves are
	-- public (components/Settings.lua → `Uranium.Settings`) so a host can compose
	-- its own settings tab out of the parts it wants.
	function window:CreateSettingsTab(settingsOpts: any?): (any, any)
		settingsOpts = settingsOpts or {}
		if type(settingsOpts) ~= "table" then
			Log.fail("CreateSettingsTab", ("options must be a table like { Pin = \"bottom\" }, got %s")
				:format(typeof(settingsOpts)))
		end
		Log.field("CreateSettingsTab", "Sections", settingsOpts.Sections, "table")
		Log.field("CreateSettingsTab", "Notify", settingsOpts.Notify, "boolean")
		Log.infof("CreateSettingsTab: building (config supported=%s)", tostring(Config.supported))
		-- Every CreateTab option is forwarded, so the settings tab can be pinned
		-- away from the feature tabs (`CreateSettingsTab{ Pin = "bottom" }`) or
		-- given its own colour like any other. Defaults are unchanged: top of the
		-- rail, window accent.
		local tab = window:CreateTab({
			Name = settingsOpts.Name or "Settings",
			Icon = settingsOpts.Icon or "gear",
			Desc = settingsOpts.Desc,
			Badge = settingsOpts.Badge,
			Pin = settingsOpts.Pin,
			Style = settingsOpts.Style,
			Color = settingsOpts.Color,
			Dot = settingsOpts.Dot,
			Rail = settingsOpts.Rail,
			Separator = settingsOpts.Separator,
			Order = settingsOpts.Order,
		})

		-- The panel itself lives in components/Settings.lua, built entirely on this
		-- window's public API — which is what makes the same groups reusable from a
		-- host's own tab (Uranium.Settings.ConfigGroup(window, tab)).
		local controls = SettingsPanel.build(window, tab, settingsOpts)
		tab.Controls = controls

		local flagCount = 0
		for _ in ctx.Flags do
			flagCount += 1
		end
		Log.infof("CreateSettingsTab: done (%d flags registered)", flagCount)
		return tab, controls
	end

	-- ── bind HUD ──────────────────────────────────────────────────────────────
	-- Opt-in, like the splash: `Hud = true` (or a table of overrides). Built here,
	-- before the caller has created a single control — it fills itself in from the
	-- bind registry as the binds are registered, so ordering doesn't matter.
	if opts.Hud ~= nil and opts.Hud ~= false then
		window:CreateHud()
	end

	-- mount — pop the window in from a touch smaller and faded so it eases in
	-- rather than just appearing.
	--
	-- It's hidden with `Visible` (not a fade) until then, because the fade has to
	-- snapshot the window's resting transparencies and the caller hasn't built
	-- its tabs yet — this runs on a deferred pass, by which point the whole tree
	-- exists and the snapshot covers it.
	mainScale.Scale = 0.92
	main.Visible = false
	syncShadow()
	local function mountWindow()
		if destroyed then
			return -- unloaded while the splash was still playing
		end
		main.Visible = true
		mainFade:Set(1)
		Tween.play(mainScale, Tween.Pop, { Scale = 1 })
		mainFade:To(Tween.Normal, 0)
		Tween.play(shadow, Tween.Normal, { ImageTransparency = SHADOW_T })
	end

	-- ── boot splash ────────────────────────────────────────────────────────────
	-- `Splash = true` (or a table of overrides) plays components/Splash.lua first
	-- and mounts the window when it's on its way out. The window is built either
	-- way — the caller's tabs populate it while the splash is up — it's just kept
	-- hidden, so nothing about the rest of the API changes. Off by default: a
	-- boot screen on every re-run of a loader that doesn't want one is a tax.
	local splashOpts = opts.Splash
	if splashOpts ~= nil and splashOpts ~= false then
		local so: any = type(splashOpts) == "table" and splashOpts or {}
		-- The splash shows the window's mark unless it's given one of its own;
		-- its own art brings its own zoom (a different source, a different crop).
		local splashLogo, splashZoom = logoSource, logoZoom
		if so.Logo ~= nil then
			splashLogo, splashZoom = so.Logo, so.LogoZoom
		elseif so.LogoZoom ~= nil then
			splashZoom = so.LogoZoom
		end
		main.Visible = false
		splash = Splash(ctx, screenGui, {
			Title = so.Title or brandName,
			Subtitle = so.Subtitle or opts.Subtitle,
			Logo = splashLogo,
			LogoZoom = splashZoom,
			LogoRadius = so.LogoRadius,
			Duration = so.Duration,
			Dim = so.Dim,
			Steps = so.Steps,
		})
		splash:Play(function()
			splash = nil -- it fades itself out from here; the window takes over
			mountWindow()
		end)
	else
		task.defer(mountWindow)
	end

	-- Mount LAST, and exactly once. This used to go straight to PlayerGui, which
	-- any LocalScript in the place can walk; `Gui.mount` runs protect_gui where
	-- the executor has it and then picks the most hidden container available —
	-- opts.Parent → gethui() → CoreGui → PlayerGui. Parenting somewhere first and
	-- moving it after would leave a frame where the place can see us, so there's
	-- one write, at the resolved target.
	local guiParent, guiParentLabel = Gui.mount(screenGui, opts.Parent)
	if guiParent then
		Log.infof("mounted into %s", guiParentLabel)
	else
		Log.warn("CreateWindow", "no GUI container available (no gethui, CoreGui or PlayerGui) — the window is built but not on screen")
	end

	-- Claim the global slot LAST, once this window is actually on screen — the
	-- next run of the loadstring finds this record and unloads us before it
	-- builds. `Unload` tears down without the fade: the replacement window is
	-- already being built and shouldn't overlap the outgoing one.
	--
	-- ...but not if we were torn down on the way here. `Destroy` can land during
	-- construction — a host's `OnFlag` watcher, a tab `Callback`, another chunk
	-- running `Uranium:Unload()` while this one is still building — and it calls
	-- `Singleton.release(record)` with `record` still nil, so it can't unclaim a
	-- slot that hadn't been claimed yet. Claiming anyway parked a record pointing
	-- at a destroyed window in the shared env, after which `IsLoaded()` reported a
	-- window that isn't there and the next loader run "unloaded" a corpse instead
	-- of finding nothing.
	if singleton and not destroyed then
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
