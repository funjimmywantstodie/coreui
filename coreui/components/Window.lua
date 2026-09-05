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
	{ "MinimizeHintStyle", "string" },
	{ "Touch", "boolean" },
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
	-- Has anyone — the user, a restored record, a host — chosen the geometry? Until
	-- they have, a phone opens maximized (set once the Context exists, below): the
	-- inset around a windowed frame is wasted on a screen that small. A saved
	-- `uranium_window` record still wins, since it arrives through the same setters.
	local geometryChosen = false
	-- The size the window wants to be, which is the theme's until someone says
	-- otherwise (`Window:SetSize`, or a restored `uranium_window` record). It's the
	-- *unclamped* wish: fitWindow below is what actually reconciles it with the
	-- viewport, so a size saved on a big monitor survives a session on a laptop
	-- instead of being permanently shrunk to fit it.
	local baseWidth, baseHeight = M.windowWidth, M.windowHeight
	-- Below this the sidebar and the two columns stop being a layout.
	local MIN_W, MIN_H = 420, 320
	-- Air left around the window at full size. A phone viewport is ~360 logical px
	-- tall, so the desktop's 24 on each side is a tenth of the screen spent on
	-- nothing; touch keeps a hairline of it.
	local VIEWPORT_INSET, VIEWPORT_INSET_TOUCH = 24, 8
	-- The device answer, per call (Context:IsTouch — touch AND no keyboard). The
	-- Context is built further down, so this reads it lazily; before it exists the
	-- answer is the engine's own.
	local ctx: any = nil
	local function isTouch(): boolean
		if ctx then
			return ctx:IsTouch()
		end
		return UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled ~= true
	end
	local function viewportInset(): number
		return if isTouch() then VIEWPORT_INSET_TOUCH else VIEWPORT_INSET
	end
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
		local inset = viewportInset()
		local availW = math.max(MIN_W, vp.X - inset)
		local availH = math.max(MIN_H, vp.Y - inset)
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

	-- The brand mark — square art over an accent tile, rounded off and clipped by
	-- its holder. `Logo` accepts anything util/Asset.lua resolves (id, url, file
	-- path); the accent tile with a Lucide glyph is the fallback while it loads or
	-- if it never resolves (Studio without executor globals, bad id, …).
	--
	-- It's a factory because there are TWO of them: the titlebar's and the one on
	-- the minimized hint card. Both have to follow `SetLogo` and `SetAccent`, so
	-- the composition is written once and every instance registers itself in
	-- `marks`; anything that repaints a mark walks that list rather than naming an
	-- instance, or the second one silently stops tracking the first.
	local marks: { { apply: (any, number?) -> (), square: Frame, glyph: any, resize: (number) -> () } } = {}
	local function newMark(parent: Instance, size: number, glyphSize: number, extra: { [string]: any }?): (Frame, any)
		local radius = opts.LogoRadius or Theme.Brand.radius
		local first = #marks == 0
		local props: { [string]: any } = {
			Name = "Logo",
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Parent = parent,
		}
		for key, value in extra or {} do
			props[key] = value
		end
		-- Both corners are held rather than created inline: the minimized hint
		-- card resizes its mark at runtime (see `resize` below), and a radius that
		-- doesn't scale with the tile reads as a different shape rather than the
		-- same mark at another size.
		local holderCorner = Create.corner(radius)
		local squareCorner = Create.corner(radius)
		local holder = Create("Frame", props, {
			holderCorner,
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
		local square = Create("Frame", {
			Name = "Square",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = colors.accent_soft,
			BorderSizePixel = 0,
			Parent = holder,
		}, {
			squareCorner,
		})
		local fallback = Icons.new("atom", glyphSize, colors.accent) :: any
		fallback.Name = "Glyph"
		fallback.AnchorPoint = Vector2.new(0.5, 0.5)
		fallback.Position = UDim2.fromScale(0.5, 0.5)
		fallback.Parent = holder
		-- Fit, not Crop: a brand mark must never lose an edge or change proportion.
		-- Fit letterboxes non-square art inside the square holder; the zoom below is
		-- what fills the holder, and it's a scale on both axes so it can't stretch.
		local image = Create("ImageLabel", {
			Name = "Mark",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Image = "",
			ScaleType = Enum.ScaleType.Fit,
			Visible = false,
			Parent = holder,
		}) :: ImageLabel
		-- `zoom` > 1 draws the art oversized inside the clipping holder, trimming a
		-- margin baked into the source (see Theme.Brand.zoom). nil = draw it 1:1.
		local function apply(source: any, zoom: number?)
			local z = tonumber(zoom) or 1
			if z <= 0 then
				z = 1
			end
			image.Size = UDim2.fromScale(z, z)
			-- The mark is ALWAYS visible — it has to be, or the engine never fetches
			-- the texture — and it's drawn over the accent square, which stays put as
			-- a backdrop. So the art covers the square when it loads, and if it never
			-- loads you're left with the accent square + glyph. Never a hole,
			-- whatever the load check believes.
			image.Visible = true
			fallback.Visible = true
			square.Visible = true
			Asset.load(image, source, function(loaded)
				-- Only the fallback reacts; the image is left alone.
				fallback.Visible = not loaded
				square.Visible = not loaded
				-- One warning per failed source, not one per mark drawing it.
				if first and not loaded and source ~= nil then
					Log.warn("CreateWindow", ("Logo %s hasn't loaded — the fallback mark is showing. "
						.. "Check the id is an image/decal, that it passed moderation, and that "
						.. "it isn't Restricted in Creator Dashboard."):format(tostring(source)))
				end
			end)
		end
		-- Everything the mark's geometry is made of, scaled together — holder,
		-- both radii and the fallback glyph. Additive to the entry: only the
		-- minimized hint card calls it (30px as a card, 46px as a bare tile), and
		-- nothing else reads it.
		local function resize(newSize: number)
			local k = newSize / size
			holder.Size = UDim2.fromOffset(newSize, newSize)
			holderCorner.CornerRadius = UDim.new(0, radius * k)
			squareCorner.CornerRadius = UDim.new(0, radius * k)
			local glyph = glyphSize * k
			fallback.Size = UDim2.fromOffset(glyph, glyph)
			if fallback:IsA("TextLabel") then
				fallback.TextSize = glyph
			end
		end
		local entry = { apply = apply, square = square, glyph = fallback, resize = resize }
		table.insert(marks, entry)
		return holder, entry
	end

	local logo = newMark(titlebar, M.logo, 20, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, M.sidebar / 2, 0.5, 0),
	})
	local brandName = opts.Title or Theme.Brand.name

	-- `Logo = false` means "no art at all" — keep the accent square + glyph.
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
	-- Paints every mark registered so far, and is re-run by `SetLogo`; a mark
	-- built later (the hint's) applies the current source itself at construction.
	local function setLogo(source: any, zoom: number?)
		logoSource, logoZoom = source, zoom
		for _, mark in marks do
			mark.apply(source, zoom)
		end
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

	local titleLabel = Create("TextLabel", {
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

	local winButtonLayout = Create.listLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 15),
	})
	local winButtons = Create("Frame", {
		Name = "WinButtons",
		Size = UDim2.fromOffset(0, M.titlebar),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = rightCluster,
	}, {
		winButtonLayout,
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

	-- With the status bar hidden (touch — see `applyChrome`) the sidebar is what
	-- meets the window's rounded bottom-left corner, and `main` clips to a
	-- RECTANGLE, not to its UICorner. So the sidebar carries a corner of its own
	-- plus two chrome fills that square off every edge but that one — the same
	-- trick as the titlebar's SquareFill. Both fills are hidden while the status
	-- bar is up, and the corner is harmless then (the fills cover it).
	local sidebarTopFill = Create("Frame", {
		Name = "SquareTop",
		Visible = false,
		Size = UDim2.new(1, 0, 0, M.windowRadius),
		BackgroundColor3 = colors.chrome,
		BorderSizePixel = 0,
	})
	local sidebarRightFill = Create("Frame", {
		Name = "SquareRight",
		Visible = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, M.windowRadius, 1, 0),
		BackgroundColor3 = colors.chrome,
		BorderSizePixel = 0,
	})
	-- The corner is only PARENTED on touch (applyChrome): with the status bar up
	-- the sidebar is a plain rectangle and a rounded one would show `bg` at its
	-- top corners.
	local sidebarCorner = Create.corner(M.windowRadius)
	local sidebar = Create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, M.sidebar, 1, 0),
		BackgroundColor3 = colors.chrome,
		Parent = body,
	}, {
		sidebarTopFill,
		sidebarRightFill,
		Create("Frame", {
			Name = "Border",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = colors.border_soft,
			BorderSizePixel = 0,
			ZIndex = 2,
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
	--
	-- ...which was true until the phone numbers came in. On a 360px viewport the
	-- body is ~250px, and a menu with four tabs on top and two on the bottom needs
	-- ~320 — the clusters overlapped and the icons drew over each other, and since
	-- a plain Frame doesn't sink input, a tap in the overlap went to whichever
	-- button was on top rather than the one whose icon was visible. `fitNav` below
	-- measures the two against each other and never lets them meet: it tightens
	-- the padding and gap first, then the tiles, and if that still isn't enough the
	-- TOP cluster scrolls (it's a ScrollingFrame, always, with scrolling switched
	-- on only when it has to be) and ends above the bottom one, which stays put.
	local NAV_LEVELS = {
		{ pad = 16, gap = 10, size = M.navButton, icon = M.navIcon }, -- the design
		{ pad = 6, gap = 4, size = M.navButton, icon = M.navIcon },   -- tighter air
		{ pad = 6, gap = 4, size = 32, icon = 16 },                   -- smaller tiles
	}
	local NAV_SEPARATOR_H = 9 -- components/Tab.lua's NavSeparator
	local navTopPad = Create.padding(16, 0, 0, 0)
	local navTopLayout = Create.listLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 10),
	})
	local navTop = Create("ScrollingFrame", {
		Name = "NavTop",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollingEnabled = false,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		Parent = sidebar,
	}, {
		navTopPad,
		navTopLayout,
	})
	local navBottomPad = Create.padding(0, 0, 16, 0)
	local navBottomLayout = Create.listLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 10),
	})
	local navBottom = Create("Frame", {
		Name = "NavBottom",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = sidebar,
	}, {
		navBottomPad,
		navBottomLayout,
	})
	local function navFor(pin: string?): GuiObject
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
	local toastLayout = Create.listLayout({
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 9),
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
		toastLayout,
	})

	ctx = Context.new(Theme, overlay, opts.Accent or colors.accent)
	-- `Touch = true/false` pins the device answer (nil = per call, from
	-- UserInputService). Testing the phone layout in Studio needs this: its
	-- emulator reports a touch screen AND a keyboard, which is a touchscreen laptop
	-- as far as the library can tell.
	if opts.Touch ~= nil then
		ctx.Touch = opts.Touch == true
	end
	-- For Context:LockScroll — a slider dragged under a thumb holds the page still.
	ctx.Scroller = content
	-- A phone opens maximized (see `geometryChosen`). Set directly rather than
	-- through setMaximized: nothing is on screen yet and there's no record to
	-- announce. The deferred fitWindow draws it at that size.
	if isTouch() then
		maximized = true
	end
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
		for _, mark in marks do
			mark.square.BackgroundColor3 = ctx.AccentSoft
			Icons.tint(mark.glyph, accent)
		end
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

	-- ── on-screen keyboard ────────────────────────────────────────────────────
	-- Focusing a TextBox on a phone raises a keyboard over the bottom half of the
	-- screen — over the config name box, a `Group:Input`, the titlebar search. The
	-- window slides up just far enough to keep the focused box above it and slides
	-- back when focus is released. `keyboardShift` is how far it's currently
	-- pushed, so the restore subtracts exactly that and a drag in between survives.
	--
	-- The box's bottom is read off AbsolutePosition PLUS the GUI inset: this
	-- ScreenGui ignores the inset, and on some clients AbsolutePosition reports as
	-- though it hadn't (see the minimized hint's drag for the same trap). Adding it
	-- where it wasn't needed over-shifts by a topbar's height, which is harmless;
	-- omitting it where it was leaves the box under the keyboard, which isn't.
	local keyboardShift = 0
	local KEYBOARD_GAP = 12
	local function guiInsetY(): number
		local ok, inset = pcall(function()
			return Services.GuiService:GetGuiInset().Y
		end)
		return (ok and tonumber(inset)) or 0
	end
	local function shiftForKeyboard()
		local okBox, box = pcall(function()
			return UserInputService:GetFocusedTextBox()
		end)
		local focused: any = okBox and box or nil
		local keyboardTop = 0
		pcall(function()
			if UserInputService.OnScreenKeyboardVisible == true then
				keyboardTop = UserInputService.OnScreenKeyboardPosition.Y
			end
		end)
		local wanted = 0
		if focused and keyboardTop > 0 and main.Visible and focused:IsDescendantOf(screenGui) then
			local bottom = focused.AbsolutePosition.Y + focused.AbsoluteSize.Y + guiInsetY() + KEYBOARD_GAP
			-- Never push the titlebar off the top: the window's resting top-left is
			-- the shifted one plus what's already applied.
			local restingTop = topLeft().Y + keyboardShift
			wanted = math.clamp(keyboardShift + (bottom - keyboardTop), 0, math.max(0, restingTop - 8))
		end
		wanted = math.round(wanted)
		if wanted == keyboardShift then
			return
		end
		local delta = wanted - keyboardShift
		keyboardShift = wanted
		local pos = main.Position
		Tween.play(main, Tween.Slide, {
			Position = UDim2.new(pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset - delta),
		})
	end
	-- Deferred: focus lands before the keyboard exists, and a focus release may be
	-- focus moving to another box — by the next resumption both have settled.
	local function keyboardSoon()
		task.defer(shiftForKeyboard)
	end
	-- Every hook is guarded: not every client exposes the on-screen keyboard
	-- properties, and losing the shift is better than losing the window.
	pcall(function()
		table.insert(connections, UserInputService.TextBoxFocused:Connect(keyboardSoon))
		table.insert(connections, UserInputService.TextBoxFocusReleased:Connect(keyboardSoon))
	end)
	for _, prop in { "OnScreenKeyboardVisible", "OnScreenKeyboardPosition" } do
		pcall(function()
			table.insert(connections, UserInputService:GetPropertyChangedSignal(prop):Connect(keyboardSoon))
		end)
	end

	-- ── public API ───────────────────────────────────────────────────────────
	local tabs = {}
	local activeIndex = 1
	local window = {}

	-- ── chrome + sidebar fit ──────────────────────────────────────────────────
	-- Two layouts of the same frame, picked per call from the device answer
	-- (`isTouch`): the desktop one is byte-for-byte what it always was, and the
	-- phone one spends less of a ~360px-tall viewport on chrome. A phone's body is
	-- 250–280px after the titlebar and status bar; every pixel of chrome comes
	-- straight out of the sidebar and the content.
	--
	--   titlebar   50 → 40
	--   statusbar  34 → hidden (a clock and a version string are not worth 34px
	--              of a 280px body; the sidebar squares itself off underneath)
	--   window buttons  16px glyphs → 36px targets, same footprint
	--   toasts     bottom-right (where a phone's jump button is) → top-right
	local TITLEBAR_TOUCH = 40
	local function chromeHeight(): number
		if isTouch() then
			return TITLEBAR_TOUCH
		end
		return M.titlebar + M.statusbar
	end
	local function applyChrome()
		local touch = isTouch()
		local bar = touch and TITLEBAR_TOUCH or M.titlebar
		titlebar.Size = UDim2.new(1, 0, 0, bar)
		rightCluster.Size = UDim2.fromOffset(0, bar)
		winButtons.Size = UDim2.fromOffset(0, bar)
		titleLabel.TextSize = touch and 14 or 16
		local hit = touch and 36 or 16
		winButtonLayout.Padding = UDim.new(0, touch and 2 or 15)
		for _, btn in winBtns do
			btn.Size = UDim2.fromOffset(hit, hit)
		end
		status.Visible = not touch
		sidebarCorner.Parent = if touch then sidebar else nil
		sidebarTopFill.Visible = touch
		sidebarRightFill.Visible = touch
		body.Position = UDim2.fromOffset(0, bar)
		body.Size = UDim2.new(1, 0, 1, -chromeHeight())
		if touch then
			toasts.AnchorPoint = Vector2.new(1, 0)
			toasts.Position = UDim2.new(1, -12, 0, bar + 10)
			toastLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		else
			toasts.AnchorPoint = Vector2.new(1, 1)
			toasts.Position = UDim2.new(1, -16, 1, -46)
			toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		end
	end
	applyChrome()

	-- Keep the two nav clusters from ever meeting. Everything is computed off the
	-- LAYOUT size (`main.Size.Y.Offset`, like `layoutSize`) rather than measured
	-- AbsoluteSizes, so it's deterministic on the frame it runs and doesn't have to
	-- wait a frame for AutomaticSize to settle.
	local function fitNav()
		local sample = tabs[1]
		if not sample then
			return
		end
		local bodyH = main.Size.Y.Offset - chromeHeight()
		if bodyH <= 0 then
			return
		end
		local touch = isTouch()
		local function need(pin: string, level: any, spec: any): number
			local n, seps = 0, 0
			for _, tab in tabs do
				if tab.pin == pin and tab:IsVisible() then
					n += 1
					if tab.separator then
						seps += 1
					end
				end
			end
			if n == 0 then
				return 0
			end
			return level.pad + n * sample:_tileHeight(spec) + seps * NAV_SEPARATOR_H
				+ (n + seps - 1) * level.gap
		end
		-- The first level both clusters fit at; the last one if none does.
		local chosen: any = NAV_LEVELS[#NAV_LEVELS]
		local spec: any = nil
		for _, level in NAV_LEVELS do
			-- On touch the label always draws: it wins over the gap, never the icon.
			local candidate = { size = level.size, icon = level.icon, label = touch }
			if need("top", level, candidate) + need("bottom", level, candidate) <= bodyH then
				chosen, spec = level, candidate
				break
			end
		end
		spec = spec or { size = chosen.size, icon = chosen.icon, label = touch }
		navTopPad.PaddingTop = UDim.new(0, chosen.pad)
		navBottomPad.PaddingBottom = UDim.new(0, chosen.pad)
		navTopLayout.Padding = UDim.new(0, chosen.gap)
		navBottomLayout.Padding = UDim.new(0, chosen.gap)
		for _, tab in tabs do
			tab:_layout(spec)
		end
		-- Still short: the top cluster ends above the bottom one and scrolls
		-- (no scrollbar, drag/wheel). The bottom cluster always stays put.
		local room = bodyH - need("bottom", chosen, spec)
		if need("top", chosen, spec) > room then
			navTop.AutomaticSize = Enum.AutomaticSize.None
			navTop.Size = UDim2.new(1, 0, 0, math.max(0, room))
			navTop.ScrollingEnabled = true
		else
			navTop.ScrollingEnabled = false
			navTop.CanvasPosition = Vector2.zero
			navTop.Size = UDim2.new(1, 0, 0, 0)
			navTop.AutomaticSize = Enum.AutomaticSize.Y
		end
	end
	-- Every time the window's size moves: fitWindow, maximize, a restore.
	main:GetPropertyChangedSignal("Size"):Connect(fitNav)

	-- Below this much content width the two columns stack (components/Tab.lua
	-- `_setStacked`). A phone at 420 wide has ~150px per column after the sidebar
	-- and the page insets, and every control in it is crushed. The desktop default
	-- (780 wide → 672 of content) never crosses it.
	local STACK_BELOW = 600
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
	-- The card that stands in for the window while it's minimized — and it is a
	-- BUTTON, not a label. The only documented way back used to be the toggle key,
	-- which is a *keyboard* key: on a phone this card was the entire UI, forever,
	-- telling the user to press something their device doesn't have. Clicking or
	-- tapping it restores the window, which is also the shortest route back with a
	-- mouse. It carries the brand mark for the same reason components/Screen.lua
	-- does: with the window gone, this card is the only thing on screen that is us.
	local HINT_PAD, HINT_MARK, HINT_GAP = 14, 30, 10
	local HINT_W = 246
	-- Logo style: the tile IS the card, at 46px — the mark plus the same ring of
	-- air the card gives it, and nothing else.
	local HINT_TILE_PAD = 4
	local HINT_LOGO = 46
	local HINT_LOGO_MARK = HINT_LOGO - HINT_TILE_PAD * 2
	local HINT_MARGIN = 16
	local HINT_RADIUS = opts.LogoRadius or Theme.Brand.radius
	-- The text column is a fixed offset, not a scale: it sits in a horizontal
	-- UIListLayout, where a scale width would measure against the card's FULL
	-- width and push the wrap out past the padding.
	local HINT_TEXT_W = HINT_W - HINT_PAD * 2 - (HINT_MARK + HINT_TILE_PAD * 2) - HINT_GAP
	-- Both held: the two styles below drive them. The card had no UICorner at all
	-- — a sharp rectangle among a UI of rounded ones — and its radius is the
	-- WINDOW's, not a card's: this thing stands in for the window, so its outline
	-- is the one the window just left behind.
	local hintPadding = Create.padding(11, HINT_PAD)
	local hintCorner = Create.corner(M.windowRadius)
	local restoreHint = Create("TextButton", {
		Name = "MinimizedHint",
		Visible = false,
		Text = "",
		AutoButtonColor = false, -- the hover pair below owns the fill
		-- Anchored top-left and positioned in raw pixel offsets because the card is
		-- DRAGGED: a drag writes a top-left and the clamp reads one, and any other
		-- anchor puts half a card of slack between the two.
		AnchorPoint = Vector2.zero,
		Position = UDim2.fromOffset(0, HINT_MARGIN),
		Size = UDim2.fromOffset(HINT_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = colors.pop,
		Parent = screenGui,
	}, {
		hintPadding,
		hintCorner,
		-- Horizontal, centered: with AutomaticSize.Y the card is as tall as its
		-- tallest child, so the mark and the text block centre against each other
		-- whether the line wraps or not. (Centring the mark by hand would need a
		-- scale Position, which is exactly what AutomaticSize can't measure.)
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, HINT_GAP),
		}),
	})
	local hintScale = Create("UIScale", { Parent = restoreHint }) :: UIScale
	local hintStroke = Create.stroke(colors.border)
	hintStroke.Parent = restoreHint
	-- Hover lifts the fill and lights the border. Roblox has no `cursor: pointer`,
	-- so the border is the whole of what says this card can be pressed — and it's
	-- driven off the card's own MouseEnter (Create.hover only animates the instance
	-- under the pointer, and a UIStroke has no mouse events of its own).
	Create.hover(restoreHint, "BackgroundColor3", colors.pop, colors.hover)
	local hintHovered = false
	local function paintHintStroke()
		Tween.play(hintStroke, Tween.Fast, { Color = if hintHovered then ctx.Accent else colors.border })
	end
	restoreHint.MouseEnter:Connect(function()
		hintHovered = true
		paintHintStroke()
	end)
	restoreHint.MouseLeave:Connect(function()
		hintHovered = false
		paintHintStroke()
	end)
	ctx:RegisterAccent(paintHintStroke)

	-- The mark sits on a chrome tile of its own, and that tile is what carries the
	-- rounded edge. The art is a full-bleed square whose margin is exactly
	-- `chrome`, and the holder that crops the zoom `ClipsDescendants` — which
	-- clips to a RECTANGLE, not to its UICorner (same engine limit as the titlebar
	-- above). So the art's square corners overhang the rounded shape by a couple
	-- of pixels: invisible on the titlebar, where the surface under them IS
	-- chrome, and four dark nubs out here, where a rounded stroke then traced a
	-- shape the art plainly wasn't. Backing it with chrome and insetting it by
	-- HINT_TILE_PAD puts the overhang back on its own colour, and the only edge
	-- left to see is a UICorner's.
	local hintTileCorner = Create.corner(HINT_RADIUS + HINT_TILE_PAD)
	local hintTile = Create("Frame", {
		Name = "Tile",
		Size = UDim2.fromOffset(HINT_MARK + HINT_TILE_PAD * 2, HINT_MARK + HINT_TILE_PAD * 2),
		BackgroundColor3 = colors.chrome,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = restoreHint,
	}, {
		hintTileCorner,
	})
	-- The mark registers in `marks` like the titlebar's, so it follows SetLogo and
	-- SetAccent from here on — but it's built after both have already run, so it
	-- paints itself into the window's current state rather than the theme's.
	local _, hintMark = newMark(hintTile, HINT_MARK, 17, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	})
	hintMark.square.BackgroundColor3 = ctx.AccentSoft
	Icons.tint(hintMark.glyph, ctx.Accent)
	hintMark.apply(logoSource, logoZoom)
	-- Mark and tile resize together, radius included, so the two styles are one
	-- shape at two sizes. Returns the tile's outer size — the logo style's whole
	-- card is that square.
	local function sizeHintTile(mark: number): number
		hintMark.resize(mark)
		local tile = mark + HINT_TILE_PAD * 2
		hintTile.Size = UDim2.fromOffset(tile, tile)
		hintTileCorner.CornerRadius = UDim.new(0, HINT_RADIUS * (mark / HINT_MARK) + HINT_TILE_PAD)
		return tile
	end

	local hintCopy = Create("Frame", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(HINT_TEXT_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = restoreHint,
	}, {
		Create.listLayout({ Padding = UDim.new(0, 2) }),
	})
	Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = brandName .. " Minimized",
		TextColor3 = colors.text,
		TextSize = 13,
		FontFace = Theme.Font.Medium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
		Parent = hintCopy,
	})
	-- What the card says. `CreateWindow{ ToggleKey = Enum.KeyCode.Unknown }` is a
	-- legal way to say "no toggle key", and building the label inline printed the
	-- literal "Press None to show it again." for it. It no longer has to send the
	-- keyless case away empty-handed either — the card itself is the way back now,
	-- so that branch just drops the key clause instead of naming a dead end.
	local function hintText(): string
		if toggleKey == nil or toggleKey == Enum.KeyCode.Unknown then
			return "Click here to reopen it."
		end
		return ("Click here or press %s to reopen it."):format(Bind.name(toggleKey))
	end
	local restoreHintText = Create("TextLabel", {
		Name = "Body",
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
		Parent = hintCopy,
	})
	-- ── hint style: a card with a keyboard, a logo without one ────────────────
	-- "card" is the full thing: mark, "<Brand> Minimized" and the click/press
	-- line. "logo" is the mark on its own — on a phone the sentence is about a key
	-- the device doesn't have, and the tile alone is the same affordance in a
	-- quarter of the screen. "auto" picks per device.
	local HINT_STYLES: { [string]: boolean } = { auto = true, card = true, logo = true }
	local minimizeHintStyle = "auto"
	-- Resolved on every apply rather than cached at build: an executor can run
	-- before the input devices have reported themselves, and a cached answer would
	-- pin the wrong style for the whole session. Touch AND no keyboard, not touch
	-- alone — a touchscreen laptop has both, and the card's text is a sentence
	-- about the keyboard.
	local function hintStyleInForce(): string
		if minimizeHintStyle ~= "auto" then
			return minimizeHintStyle
		end
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			return "logo"
		end
		return "card"
	end

	-- ── where the card rests, and the drag that moves it ──────────────────────
	-- Two resting places, one per style, because they're two different objects.
	-- The card is wide and wordy and belongs where a desktop UI puts a dismissed
	-- thing: BOTTOM RIGHT, out of the way of both the game's HUD and ours. The
	-- logo tile is small and is the phone's only route back to the menu, so it
	-- sits TOP CENTRE — the one strip of screen a game's own touch controls
	-- almost never occupy, and the thumb's reach doesn't matter for something you
	-- have to look for. `hintPos` stays nil for "wherever the default is", so the
	-- card keeps re-placing itself through a style change or a viewport resize and
	-- stops the moment the user has an opinion about where it goes.
	local hintPos: Vector2? = nil
	-- The position last WRITTEN, post-clamp. A drag seeds its grab from this and
	-- never from AbsolutePosition: this ScreenGui sets IgnoreGuiInset and
	-- AbsolutePosition reports as though it hadn't, so a grab seeded from it starts
	-- a topbar's height above the cursor and stays there for the whole gesture.
	local hintDrawn = Vector2.zero
	local function placeHint(p: Vector2?)
		local vp = screenGui.AbsoluteSize
		-- Width off the LAYOUT, not AbsoluteSize: the rendered size runs through
		-- `hintScale`, which sits at 0.92 through the pop, and dividing that back
		-- out lands a frame behind the tween — the card would slide while it popped.
		-- Only the height is measured, and only the bottom clamp reads it.
		local w = restoreHint.Size.X.Offset
		local h = restoreHint.AbsoluteSize.Y
		local target = p
		if target == nil then
			if hintStyleInForce() == "logo" then
				target = Vector2.new((vp.X - w) / 2, HINT_MARGIN)
			else
				target = Vector2.new(vp.X - w - HINT_MARGIN, vp.Y - h - HINT_MARGIN)
			end
		end
		-- The WHOLE card stays on screen, not just an edge: with no keyboard to
		-- press the toggle key on, this card is the only way back to the UI.
		if vp.X > 0 then
			target = Vector2.new(
				math.clamp(target.X, HINT_MARGIN, math.max(HINT_MARGIN, vp.X - w - HINT_MARGIN)),
				math.clamp(target.Y, HINT_MARGIN, math.max(HINT_MARGIN, vp.Y - h - HINT_MARGIN))
			)
		end
		hintDrawn = Vector2.new(math.round(target.X), math.round(target.Y))
		restoreHint.Position = UDim2.fromOffset(hintDrawn.X, hintDrawn.Y)
	end
	placeHint(hintPos)
	table.insert(connections, screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		placeHint(hintPos)
	end))
	-- AutomaticSize settles a frame late, so the first place above measured a card
	-- of no height at all — and a style switch changes both dimensions.
	restoreHint:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		placeHint(hintPos)
	end)

	local function applyHintStyle()
		if hintStyleInForce() == "logo" then
			-- Hidden, NOT sized to zero: a UIListLayout skips invisible children, so
			-- a zero-width column still spends the layout's padding and leaves the
			-- mark off-centre in a card the width of its own padding.
			hintCopy.Visible = false
			hintPadding.PaddingTop = UDim.new()
			hintPadding.PaddingBottom = UDim.new()
			hintPadding.PaddingLeft = UDim.new()
			hintPadding.PaddingRight = UDim.new()
			restoreHint.AutomaticSize = Enum.AutomaticSize.None
			local tile = sizeHintTile(HINT_LOGO_MARK)
			restoreHint.Size = UDim2.fromOffset(tile, tile)
			-- No fill of its own: the tile under it is the whole card, so the
			-- button's job here is the hit target and the stroke. Matching its
			-- corner to the tile's is what makes the outline hug the shape instead
			-- of tracing a rounder one around it — and it's why the hover fill is
			-- left alone in this style (the tile has to stay `chrome`, which is the
			-- colour the art's own margin is drawn in). The stroke's accent lift is
			-- the feedback.
			restoreHint.BackgroundTransparency = 1
			hintCorner.CornerRadius = hintTileCorner.CornerRadius
		else
			hintCopy.Visible = true
			hintPadding.PaddingTop = UDim.new(0, 11)
			hintPadding.PaddingBottom = UDim.new(0, 11)
			hintPadding.PaddingLeft = UDim.new(0, HINT_PAD)
			hintPadding.PaddingRight = UDim.new(0, HINT_PAD)
			restoreHint.AutomaticSize = Enum.AutomaticSize.Y
			restoreHint.Size = UDim2.fromOffset(HINT_W, 0)
			restoreHint.BackgroundTransparency = 0
			hintCorner.CornerRadius = UDim.new(0, M.windowRadius)
			sizeHintTile(HINT_MARK)
		end
		placeHint(hintPos)
	end
	-- Validated like Context:SetDescriptions — lowercased, and an unrecognized
	-- value warns and changes nothing rather than falling back to the default,
	-- since a typo in a host's settings dropdown that silently means "auto" reads
	-- as "the control does nothing in one position".
	local function setHintStyle(style: any, where: string): string
		local wanted = if type(style) == "string" then style:lower() else nil
		if wanted == nil or not HINT_STYLES[wanted] then
			local got = if type(style) == "string" then ('"%s"'):format(style) else typeof(style)
			Log.warn(where, ('expects "auto", "card" or "logo", got %s — staying on "%s".')
				:format(got, minimizeHintStyle))
			return minimizeHintStyle
		end
		if wanted ~= minimizeHintStyle then
			minimizeHintStyle = wanted
			applyHintStyle()
		end
		return minimizeHintStyle
	end
	if opts.MinimizeHintStyle ~= nil then
		setHintStyle(opts.MinimizeHintStyle, "CreateWindow")
	end
	applyHintStyle()

	-- The card drags, with the same gesture as the bind HUD (components/Hud.lua).
	-- It ASKS `ctx:DragClaimed` so a press where the HUD overlaps drags the HUD
	-- alone, but deliberately registers no probe of its own: it's a TextButton and
	-- already sinks its own press, so a probe would only make it claim that press
	-- from itself and never start a drag.
	local hintDragging = false
	local hintDragStart = Vector2.zero
	local hintDragOrigin = Vector2.zero
	local hintDragMoved = false
	-- Press feedback and a long-press. The tile is the only route back to the
	-- menu on a phone, so the press squashes it a touch (a tap that lands has to
	-- look like it landed), and holding it toggles the bind HUD — the hotbar comes
	-- up without opening the window. A long-press is not a tap: Activated fires on
	-- the same release and is told to stand down.
	local HINT_LONG_PRESS = 0.55
	local hintPressToken = 0
	local hintLongPressed = false
	restoreHint.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			local point = Vector2.new(input.Position.X, input.Position.Y)
			if ctx:DragClaimed(point) then
				return
			end
			hintDragging = true
			hintDragMoved = false
			hintDragStart = point
			hintDragOrigin = hintDrawn
			Tween.play(hintScale, Tween.Press, { Scale = 0.9 })
			hintPressToken += 1
			local token = hintPressToken
			hintLongPressed = false
			task.delay(HINT_LONG_PRESS, function()
				if token ~= hintPressToken or not hintDragging or hintDragMoved then
					return
				end
				hintLongPressed = true
				Tween.play(hintScale, Tween.Spring, { Scale = 1 })
				local hud = window:GetHud()
				ctx:User(function()
					window:SetHudVisible(not (hud ~= nil and hud:IsVisible()))
				end)
			end)
		end
	end)
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if not hintDragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local delta = Vector2.new(input.Position.X, input.Position.Y) - hintDragStart
			if math.abs(delta.X) + math.abs(delta.Y) > 4 then
				hintDragMoved = true
			end
			-- Only a real drag gives the card a position of its own; until then
			-- `hintPos` stays nil and the card keeps re-centring itself.
			if hintDragMoved then
				hintPos = hintDragOrigin + delta
				placeHint(hintPos)
			end
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			if hintDragging then
				hintPressToken += 1 -- a lift before the long-press lands cancels it
				Tween.play(hintScale, Tween.Spring, { Scale = 1 })
			end
			hintDragging = false
			-- The card is a TextButton, so a drag ends in a release that fires
			-- `Activated` and would reopen the window under the cursor. Deferred
			-- because that Activated fires on this same release and has to still see
			-- the flag. Same for the long-press flag.
			task.defer(function()
				hintDragMoved = false
				hintLongPressed = false
			end)
		end
	end))

	-- Shown with a small pop, hidden outright. Deliberately NOT a util/Fade.lua
	-- fade: on a device with no keyboard this card is the only way back to the UI,
	-- and a fade stranded mid-play would leave it invisible-but-there — the exact
	-- state the card exists to prevent. A wrong scale is still a card you can see
	-- and press.
	local function showHint(show: boolean)
		restoreHint.Visible = show
		if show then
			hintScale.Scale = 0.92
			Tween.play(hintScale, Tween.Pop, { Scale = 1 })
		end
	end

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
			showHint(minimizeHint)
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
			showHint(false)
		end
	end
	winBtns.min.Activated:Connect(function()
		setMinimized(true)
	end)
	-- Tapping the card is the restore. `Activated` covers mouse and touch alike,
	-- which is the whole point of it — it fires for a finger, and a finger has no
	-- toggle key. Guarded on `minimized` because the card can only be up while the
	-- window is down, and a stray Activated on the way out shouldn't re-show it.
	restoreHint.Activated:Connect(function()
		-- A press that moved the card was a drag, not a click on it (see the drag
		-- block above) — without this, every drag would end by reopening the window.
		-- A long-press already did its job (toggled the HUD) and isn't a tap either.
		if hintDragMoved or hintLongPressed then
			return
		end
		if minimized then
			setMinimized(false)
		end
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
		geometryChosen = true
		ctx:User(function()
			setMaximized(not maximized)
		end)
	end)

	-- ── the device answer moving under us ─────────────────────────────────────
	-- An executor can run before the input devices have reported themselves, so
	-- every touch decision above reads `isTouch()` per call — and this is what
	-- re-runs them when the engine's answer changes after the window was built.
	-- Also the path `Window:SetTouch` takes.
	local function touchChanged()
		ctx:TouchChanged() -- the components' own re-layouts (chips, HUD, groups…)
		applyChrome()
		fitWindow()
		fitNav()
		applyHintStyle()
		placeHint(hintPos)
		-- A phone opens maximized — unless someone already chose the geometry.
		if isTouch() and not maximized and not geometryChosen then
			setMaximized(true, false)
		end
	end
	for _, prop in { "TouchEnabled", "KeyboardEnabled" } do
		pcall(function()
			table.insert(connections, UserInputService:GetPropertyChangedSignal(prop):Connect(touchChanged))
		end)
	end

	-- ── close ────────────────────────────────────────────────────────────────
	-- Close is a real unload, not a hide: same shrink+fade as minimize, but the
	-- listeners come off, the ScreenGui is destroyed and the singleton slot is
	-- freed. Use the minimize button (or the toggle key) to stash it temporarily.
	--
	-- ...on a DEFERRED thread, not this one. `Activated` runs us on the engine's
	-- input thread, and a teardown that has to write to a protected container
	-- (the executor's hidden GUI parent) can be refused there — the same reason
	-- the hub's row loop does its writes on a thread it spawned. `task.defer`
	-- hops off it before any of the teardown runs, and costs one frame nobody
	-- can see behind the close fade. The `immediate` path deliberately does NOT
	-- get this: a re-run unloads the old window and immediately claims the slot
	-- for the new one, and a deferred `Singleton.release` would land AFTER that
	-- claim and free the new window's slot.
	winBtns.close.Activated:Connect(function()
		task.defer(function()
			window:Destroy()
		end)
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
			local width = math.max(0, avail - CONTENT_PAD_X * 2)
			tab.page.Size = UDim2.new(0, width, 0, 0)
			-- Single column on a narrow page — a layout decision made here, once,
			-- rather than per group (see STACK_BELOW).
			tab:_setStacked(avail > 0 and width < STACK_BELOW)
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
			fitNav() -- a tab moving between clusters changes what each needs
		end
		mountNav(tab.pin)
		tab._onPin = mountNav

		table.insert(tabs, tab)
		fitNav() -- ...as does a new tab (it's in `tabs` now, so the fit sees it)
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
			fitNav() -- a hidden tab takes no sidebar room
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
		showHint(minimizeHint and minimized)
	end

	function window:GetMinimizeHint(): boolean
		return minimizeHint
	end

	-- The minimized card's shape: "auto" (a bare logo on touch, the full card
	-- wherever there's a keyboard) · "card" · "logo". Applied live, and returns
	-- the style in force afterwards — an unrecognized one warns and changes
	-- nothing, so a caller can echo the result back into its own control rather
	-- than assume the write landed.
	function window:SetMinimizeHintStyle(style: any): string
		return setHintStyle(style, "SetMinimizeHintStyle")
	end

	-- What was SET, not what "auto" resolved to on this device.
	function window:GetMinimizeHintStyle(): string
		return minimizeHintStyle
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
		geometryChosen = true
		fitWindow()
		ctx:WindowStateChanged()
	end

	function window:IsMaximized(): boolean
		return maximized
	end

	function window:SetMaximized(value: boolean, animate: boolean?)
		geometryChosen = true
		setMaximized(value ~= false, animate)
	end

	-- ── settings: the device ──────────────────────────────────────────────────
	-- "Is this a phone?" as the library decides it: a touch screen AND no keyboard,
	-- read per call. Everything that lays itself out differently on a phone (the
	-- chrome, the sidebar, the bind HUD's rows, the chips, the Settings tab) reads
	-- this, so a host building its own panel can make the same call.
	function window:IsTouch(): boolean
		return ctx:IsTouch()
	end

	-- Pin the answer (`true` / `false`), or `nil` to go back to asking the engine.
	-- Applied live: the whole window re-lays out. The `Touch` option at build time
	-- is this, set before anything is drawn.
	function window:SetTouch(value: boolean?)
		if value ~= nil and type(value) ~= "boolean" then
			Log.warn("SetTouch", ("expects true, false or nil, got %s — ignoring."):format(typeof(value)))
			return
		end
		ctx.Touch = value
		touchChanged()
	end

	-- `fn(isTouch)` whenever the answer changes. No initial call; read IsTouch.
	function window:OnTouch(fn: (boolean) -> ()): () -> ()
		return ctx:OnTouch(fn)
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
		-- A restored record is a choice too: a phone that saved itself windowed
		-- must not be re-maximized the moment the input devices report in.
		setMaximized = function(value: boolean, animate: boolean?)
			geometryChosen = true
			setMaximized(value, animate)
		end,
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
	--
	-- EVERY step is its own pcall, and that is the whole shape of this function.
	-- The steps are independent — a flyout that refuses to hide has nothing to do
	-- with whether the ScreenGui goes away — but written as a straight sequence
	-- they aren't: one error unwinds the rest, and the two that MUST happen
	-- (`screenGui:Destroy()` and `Singleton.release`) are the ones at the bottom.
	-- The result was a window still on screen with the singleton slot still
	-- claimed, i.e. an unload that did nothing but set `destroyed = true` — and
	-- the re-run that followed found a record pointing at a corpse. Failures are
	-- warned about, never rethrown: by the time we are here the caller has already
	-- decided this window is going.
	local destroyed = false
	local function step(what: string, fn: () -> ())
		local ok, err = pcall(fn)
		if not ok then
			Log.warn("Destroy", ("%s failed (%s) — continuing teardown."):format(what, tostring(err)))
		end
		return ok
	end
	function window:Destroy(immediate: boolean?)
		if destroyed then
			return
		end
		destroyed = true
		step("disconnecting listeners", function()
			for _, conn in connections do
				pcall(function()
					conn:Disconnect()
				end)
			end
		end)
		table.clear(connections)
		step("binds:Destroy", function()
			binds:Destroy() -- drops every registered binding with the listeners
		end)
		step("ClosePopover", function()
			ctx:ClosePopover()
		end)
		step("hiding flyouts", hideFlyouts)
		step("Singleton.release", function()
			Singleton.release(record)
		end)
		if splash then
			local s = splash
			splash = nil -- cleared first: a splash that won't die isn't retried
			step("splash:Destroy", function()
				s:Destroy() -- torn down mid-boot: don't leave the splash on screen
			end)
		end
		-- The HUD's own input listeners outlive the ScreenGui, same as ours.
		step("hud teardown", hudApi.Destroy)

		local function finish()
			step("screenGui:Destroy", function()
				screenGui:Destroy()
			end)
		end
		if immediate then
			finish()
			return
		end
		-- The fade is the one step allowed to be skipped rather than survived: if
		-- starting it throws, the callback that destroys the GUI never runs, so the
		-- fallback is to destroy it now and let the window vanish without the
		-- animation. A missing 0.16s fade is not a failure; a surviving window is.
		local ok = step("close animation", function()
			Tween.play(mainScale, Tween.MenuOut, { Scale = 0.9 })
			Tween.play(shadow, Tween.MenuOut, { ImageTransparency = 1 })
			mainFade:To(Tween.MenuOut, 1, finish)
		end)
		if not ok then
			finish()
		end
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
