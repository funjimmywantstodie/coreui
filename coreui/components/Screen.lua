--!strict
-- components/Screen.lua — the full-screen status page: what Uranium says when
-- there is no window to say it in.
--
-- A hub has exactly two ways to talk to a user — a toast, or `warn()` — and
-- everything fatal falls into the second one: the hub's own scripts failing on
-- the way up, and, before the hub exists at all, the delivery server refusing a
-- client (banned, stale loader, kill switch, nothing to serve). All of those are
-- invisible. The line lands behind whatever else is in the executor console, the
-- UI never appears, and what comes back is "it doesn't work". So the library
-- owns the failure state the same way it owns the window, and it has to read as
-- *Uranium saying something*, not as an executor error.
--
--   local page = Uranium:Screen({
--       Title = "You've been banned",
--       Text  = "Reason: reselling builds.",
--       Code  = "BANNED",
--       Icon  = "ban",
--       Tone  = "error",
--       Discord = "discord.gg/uranium",
--       Dismissable = false,
--   })
--
-- Four things shape the whole file:
--
--   * **No window, no Context, no singleton.** The main case is a page shown
--     when `CreateWindow` has never been called and never will be, so nothing
--     here may touch per-window state. The theme is read statically; the accent
--     is the palette's, not a live one.
--   * **Never throws.** This is the code that runs when everything else already
--     failed, so every option is optional and a junk value degrades to the
--     generic page. `str()` is the funnel — anything that isn't a usable string
--     becomes nil and that row hides itself. What it deliberately does *not* do
--     is swallow its own internal errors: the callers wrap the call in `pcall`
--     and fall back to a console warning, and quietly rendering nothing would
--     rob them of that.
--   * **Identity is the ScreenGui attribute**, set by `mountGui` — so the
--     singleton sweep in util/Singleton.lua removes a live page exactly like it
--     removes a stale window, which is what stops a ban page from surviving the
--     re-run of a fixed loader. It never *claims* the singleton record, so
--     `Uranium:IsLoaded()` keeps meaning "a window exists".
--   * **It can take a value back, not just hand one out.** The optional `Input`
--     block is a key gate: the hub refusing to load until the user types a key,
--     with this page as the only UI on screen. It's built LAZILY and
--     `handle.Input` is absent without it — callers probe that absence to decide
--     whether to fall back to a clipboard button, so it has to mean something.
--   * **One source, two builds.** Everything below the `--@body` marker is
--     shared verbatim with the standalone `ui/screen.lua` (bundle.py glues it to
--     `standalone/screen.prelude.lua` instead of the requires below). The body
--     may therefore use ONLY the small surface the prelude defines — see the
--     contract at the marker — and never `require`, `Services`, `Theme`, `Log`
--     or anything else by name. Blocks between `--@lib` and `--@endlib` are
--     dropped from the standalone build, which is where `Detail` lives: the
--     refusal path never passes one and every byte there is inlined into every
--     refusal reply.

local Services = require(script.Parent.Parent.util.Services)
local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Fade = require(script.Parent.Parent.util.Fade)
local Icons = require(script.Parent.Parent.Icons)
local Asset = require(script.Parent.Parent.util.Asset)
local Gui = require(script.Parent.Parent.util.Gui)

local UIS = Services.UserInputService
local C = Theme.Colors
local F = Theme.Font
local new = Create
local corner, stroke, pad, list = Create.corner, Create.stroke, Create.padding, Create.listLayout
local tw = Tween.play
local TW = Tween
local newIcon = Icons.new
local tintIcon = Icons.tint
local newFade = Fade.new
local gname = Gui.rname
local BRAND = Theme.Brand.name

-- Paint the brand mark into `image` and report whether it rendered — the body
-- draws the accent square + initial underneath and hides that on `true`, so the
-- titlebar is never a hole (same contract Window.lua's logo follows).
--
-- The zoom lives here, not in the shared body: it's a property of the shipped
-- art (see Theme.Brand.zoom), and the standalone build has no art at all — it
-- runs on a client our own API has just refused, so there is no network to fetch
-- a PNG over. Its prelude answers `false` at once and the fallback mark IS the
-- logo there.
local function loadLogo(image: ImageLabel, done: (boolean) -> ())
	local zoom = tonumber(Theme.Brand.zoom) or 1
	image.Size = UDim2.fromScale(zoom, zoom)
	Asset.load(image, Theme.Brand.logo, done)
end

-- Parent the page and stamp the identity attribute. `Gui.mount` already does
-- both (opts.Parent → gethui → CoreGui → PlayerGui, protect_gui first), and the
-- standalone prelude reimplements exactly this much of it.
local function mountGui(gui: ScreenGui, preferred: Instance?)
	Gui.mount(gui, preferred)
end

--@body
-- ─────────────────────────────────────────────────────────────────────────────
-- SHARED SOURCE. Everything from here down is copied verbatim into the
-- standalone build, so it may use only these names, all supplied by whichever
-- prelude is glued on top:
--
--   UIS                              UserInputService
--   C, F                             Theme.Colors, Theme.Font
--   new(class, props, children?)     the instance factory (Parent applied last)
--   corner(r) stroke(c, t?) pad(t, r?, b?, l?) list(props?)
--   tw(inst, info, goals)            Tween.play
--   TW.Fast / .Normal / .Pop / .MenuOut
--   newIcon(name, size, color)       → ImageLabel, or a glyph TextLabel
--   tintIcon(inst, color)            colours either shape
--   newFade(root)                    → :Set(a) :To(info, a, done?) :Destroy()
--   mountGui(gui, preferred?)        parent it + stamp the identity attribute
--   gname()                          a neutral, per-load ScreenGui name
--   BRAND                            the brand name, for the wordmark
--   loadLogo(image, done)            paint the brand mark; done(loaded).
--                                    LIBRARY ONLY — its one call site is inside
--                                    a --@lib region, since the standalone has
--                                    no art to load.
--
-- Plus the engine globals (Enum, UDim2, Color3, Vector2, task, typeof, …).
-- Nothing else. No `require`, no library table, no executor globals except the
-- clipboard lookup below, which is guarded.
-- ─────────────────────────────────────────────────────────────────────────────

local ORDER = 1000000 -- above the window's ScreenGui, which leaves DisplayOrder at 0
local DIM = 0.28      -- backdrop transparency at rest (lower = darker)
local CARD_W = 420    -- max card width; below that it tracks the viewport
local PAD = 16
local GAP = 12
-- The card is a miniature of the window, the same way the bind HUD is: window
-- radius, a chrome titlebar with the mark in it over a `bg` body, one border,
-- and a soft shadow under the whole thing. It used to be a lone `card`-coloured
-- box with an icon chip at the top — correct palette, but nothing about it said
-- Uranium, which is a strange thing for the one screen that exists to be the
-- product speaking.
local RADIUS = 12  -- Theme.Metrics.windowRadius
local BAR = 42     -- titlebar height (the window's own is 50; this is a dialog)
local LOGO = 24    -- brand mark, square
local CHIP = 36    -- tone icon chip
local SHADOW_PAD = 48 -- how far the shadow's soft tail bleeds past the card
local SHADOW_T = 0.72 -- resting transparency (high = faint)

-- The one input funnel. Anything that isn't usable text becomes nil, and every
-- caller treats nil as "hide that row" — which is how a junk options table
-- degrades to the generic page instead of erroring.
local function str(v: any): string?
	if type(v) == "string" then
		return v ~= "" and v or nil
	end
	if type(v) == "number" then
		return tostring(v)
	end
	return nil
end

-- Tone TINTS, it doesn't repaint: only the icon chip and the hairline under the
-- header take this colour, and the card stays the library's own dark surface.
-- `info` deliberately maps to the accent rather than Notify's neutral grey — a
-- grey chip on a grey card is no mark at all at this size, and a page is the one
-- place the product should be visibly speaking.
local function toneOf(v: any): Color3
	local name = type(v) == "string" and string.lower(v) or ""
	if name == "warning" or name == "warn" then
		return C.warning
	elseif name == "info" then
		return C.accent
	end
	return C.danger
end

-- Best-effort clipboard. Guarded twice over: the global may not exist (Studio),
-- and reading it may itself throw in a locked-down sandbox.
local function copyText(text: string): boolean
	local fn: any = nil
	pcall(function()
		if type(setclipboard) == "function" then
			fn = setclipboard
		elseif type(toclipboard) == "function" then
			fn = toclipboard
		end
	end)
	if not fn then
		return false
	end
	return (pcall(fn, text))
end

-- The read half, for the paste affordance on an `Input` block. Resolved once per
-- page and handed back as a function or nil — where the executor exposes none,
-- the affordance is never drawn rather than drawn dead. `toclipboard` is last:
-- on some builds it's the *write* half under another name, so it's the fallback
-- rather than something we'd rather call.
local function clipboardFn(): any
	local fn: any = nil
	pcall(function()
		if type(getclipboard) == "function" then
			fn = getclipboard
		elseif type(getclipboardtext) == "function" then
			fn = getclipboardtext
		elseif type(toclipboard) == "function" then
			fn = toclipboard
		end
	end)
	return fn
end

-- Uppercase, with a literal space between every glyph: Roblox has no
-- letter-spacing property, so a wordmark is spelled out that way. Same helper
-- the titlebar and the splash use, and it's resolved once at load rather than
-- per page.
local WORDMARK = (function(): string
	local out = {}
	for _, c in utf8.codes(string.upper(BRAND)) do
		table.insert(out, utf8.char(c))
	end
	return table.concat(out, " ")
end)()

local function putIcon(parent: Instance, name: string, size: number, color: Color3): any
	local i: any = newIcon(name, size, color)
	i.AnchorPoint = Vector2.new(0.5, 0.5)
	i.Position = UDim2.fromScale(0.5, 0.5)
	i.Parent = parent
	return i
end

-- The page currently up, if any. A second call replaces the first — two stacked
-- failure pages is never the right answer, and the newer one is the truer one.
-- Cleared from `Destroying` as well as from `Close`, because the singleton sweep
-- destroys the ScreenGui out from under us without going through the handle.
local active: any = nil

return function(opts: any): any
	-- The caller's table is copied, never held: `Set` patches this copy, so a
	-- loader that reuses one options table across two pages doesn't find our
	-- edits in it afterwards (same rule components/Settings.lua follows).
	local o: any = {}
	if type(opts) == "table" then
		for key, value in opts :: any do
			o[key] = value
		end
	end

	if active then
		local previous = active
		active = nil
		previous:Close(true)
	end

	local dismissable = o.Dismissable ~= false
	local tone = toneOf(o.Tone)

	local screenGui = new("ScreenGui", {
		Name = gname(),
		DisplayOrder = ORDER,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	-- A TextButton, not a Frame: it sinks every click, so a page over a live
	-- window (or over the game) is modal rather than decorative. `Modal = true`
	-- also unlocks the mouse in a game that captured it — without it a shift-lock
	-- title leaves the user looking at buttons they can't reach.
	local backdrop = new("TextButton", {
		Name = "Backdrop",
		AutoButtonColor = false,
		Modal = true,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.chrome,
		BackgroundTransparency = DIM,
		BorderSizePixel = 0,
		Parent = screenGui,
	})

	-- The elevation under the card, same radial image and the same job as the
	-- window's: it's what stops a flat rectangle from reading as part of the
	-- backdrop. Sized off the card rather than a constant, because the card grows
	-- with its content (and shrinks with the entrance UIScale, which the shadow
	-- should follow rather than sit still through).
	local shadow = new("ImageLabel", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.fromOffset(CARD_W + SHADOW_PAD, SHADOW_PAD),
		BackgroundTransparency = 1,
		Image = "rbxassetid://1316045217", -- soft radial blur
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = SHADOW_T,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 0,
		Parent = backdrop,
	})

	-- Scale width + a max-size cap: 420px on anything desktop-shaped, and a
	-- proportion of the viewport once the screen is narrower than that.
	local card = new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.bg,
		ZIndex = 1,
		Parent = backdrop,
	}, {
		corner(RADIUS),
		stroke(C.border),
		list(),
		new("UISizeConstraint", { MaxSize = Vector2.new(CARD_W, math.huge) }),
	})
	local scale = new("UIScale", { Parent = card })
	card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local size = card.AbsoluteSize
		shadow.Size = UDim2.fromOffset(size.X + SHADOW_PAD, size.Y + SHADOW_PAD)
	end)

	-- ── titlebar: the mark, the wordmark, the close ──────────────────────────
	-- Chrome over the `bg` body, one hairline between them, top corners rounded
	-- to the card — the window's titlebar at dialog scale.
	local bar = new("Frame", {
		Name = "Titlebar",
		Size = UDim2.new(1, 0, 0, BAR),
		BackgroundColor3 = C.chrome,
		LayoutOrder = 1,
		Parent = card,
	}, {
		-- Only the TOP corners should round. A UICorner rounds all four, and the
		-- card clips to a rectangle rather than to its own rounded shape, so the
		-- square strip would otherwise poke past the card's corners. Window.lua
		-- squares the bottom off the same way.
		corner(RADIUS),
		new("Frame", {
			Name = "SquareFill",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, RADIUS),
			BackgroundColor3 = C.chrome,
			BorderSizePixel = 0,
		}),
		new("Frame", {
			Name = "Border",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = C.border_soft,
			BorderSizePixel = 0,
		}),
	})

	-- The mark. Accent square + the brand initial is the backdrop and the art is
	-- drawn over it, never instead of it: `loadLogo` only ever *hides* the
	-- fallback, so a client with no art (every standalone one — no network) gets
	-- the square, and none of them gets a hole. The holder clips, which is what
	-- lets the library build crop the dead margin out of the shipped tile — and
	-- that tile's baked-in background is exactly `chrome`, which is the other
	-- reason the mark belongs on the titlebar rather than on the card: the crop
	-- edge disappears into the bar the same way it does in the window.
	local logo = new("Frame", {
		Name = "Logo",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(LOGO, LOGO),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = bar,
	}, {
		corner(7),
	})
	local logoSquare = new("Frame", {
		Name = "Square",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
		Parent = logo,
	}, {
		corner(7),
	})
	local logoInitial = new("TextLabel", {
		Name = "Initial",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = string.upper(string.sub(BRAND, 1, 1)),
		TextColor3 = C.knockout,
		TextSize = 14,
		FontFace = F.Bold,
		Parent = logo,
	})
	--@lib
	-- The art layer is library-only, and that's not a byte-saving: the standalone
	-- build has no network and no asset id for the mark, so an ImageLabel there
	-- could only ever be an empty one over the square that's already drawn. The
	-- square + initial is the mark on that build, by design.
	local logoImage = new("ImageLabel", {
		Name = "Mark",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Image = "",
		-- Fit, not Crop: a brand mark must never lose an edge or change
		-- proportion. The zoom the prelude applies is what fills the holder.
		ScaleType = Enum.ScaleType.Fit,
		Parent = logo,
	})
	-- `Visible`, not transparency: this lands whenever the asset does, which can
	-- be mid-fade, and writing a transparency util/Fade.lua is driving strands
	-- the mark half-painted.
	loadLogo(logoImage, function(loaded)
		logoSquare.Visible = not loaded
		logoInitial.Visible = not loaded
	end)
	--@endlib

	local BRAND_X = 14 + LOGO + 10
	new("TextLabel", {
		Name = "Brand",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, BRAND_X, 0.5, 0),
		Size = UDim2.new(1, -(BRAND_X + 44), 1, 0),
		Text = WORDMARK,
		TextColor3 = C.text,
		TextSize = 13,
		FontFace = F.Bold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = bar,
	})

	local closeBtn = new("TextButton", {
		Name = "Close",
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -13, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
		Visible = dismissable,
		Parent = bar,
	})
	local closeIcon = putIcon(closeBtn, "x", 16, C.text_dim)
	closeBtn.MouseEnter:Connect(function()
		tintIcon(closeIcon, C.text)
	end)
	closeBtn.MouseLeave:Connect(function()
		tintIcon(closeIcon, C.text_dim)
	end)

	-- ── body ─────────────────────────────────────────────────────────────────
	-- Everything the page actually says lives here, padded off the card edge;
	-- the titlebar above it is full-bleed chrome.
	local content = new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = card,
	}, {
		pad(PAD),
		list({ Padding = UDim.new(0, GAP) }),
	})

	-- ── header: tone chip beside the title ───────────────────────────────────
	-- The chip used to sit alone on a row above the title, which read as a
	-- generic alert box. Beside it, the two are one statement, and the block is
	-- `AutomaticSize.Y` off the taller of them so a wrapping title just grows it.
	local head = new("Frame", {
		Name = "Head",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = content,
	}, {
		-- Centred against each other, so a one-line title sits on the chip's
		-- centreline; the row grows off whichever is taller once the title wraps
		-- or a code line appears under it.
		list({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 12),
		}),
	})
	local chip = new("Frame", {
		Name = "Chip",
		Size = UDim2.fromOffset(CHIP, CHIP),
		BackgroundColor3 = C.bg:Lerp(tone, 0.18),
		LayoutOrder = 1,
		Parent = head,
	}, {
		corner(10),
	})
	local iconName = str(o.Icon) or "triangle-alert"
	local iconInst = putIcon(chip, iconName, 18, tone)

	-- ── title + code ─────────────────────────────────────────────────────────
	-- Their own block on a tighter 3px rhythm: the code line is a subtitle of the
	-- title, not a sibling of the body copy.
	local titleBlock = new("Frame", {
		Name = "TitleBlock",
		BackgroundTransparency = 1,
		-- Exactly the width the chip and the row's padding leave behind, so the
		-- horizontal layout above lands it flush with the card's right edge.
		Size = UDim2.new(1, -(CHIP + 12), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = head,
	}, {
		list({ Padding = UDim.new(0, 3) }),
	})
	local title = new("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		TextColor3 = C.text,
		TextSize = 17,
		FontFace = F.Bold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = 1,
		Parent = titleBlock,
	})
	local codeLabel = new("TextLabel", {
		Name = "Code",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		TextColor3 = C.text_dim,
		TextSize = 11,
		FontFace = F.Mono,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Visible = false,
		LayoutOrder = 2,
		Parent = titleBlock,
	})

	local rule = new("Frame", {
		Name = "Rule",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = tone,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		LayoutOrder = 3,
		Parent = content,
	})

	local body = new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		TextColor3 = C.text_muted,
		TextSize = 13,
		FontFace = F.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		LineHeight = 1.25,
		Visible = false,
		LayoutOrder = 4,
		Parent = content,
	})

	-- ── the invite, as text you can select ───────────────────────────────────
	-- The Copy button below is the happy path, but an executor with no
	-- `setclipboard` still has to be able to hand the user the invite — so it's
	-- on the page as a read-only TextBox (selectable, not editable) rather than
	-- living only inside the button's callback.
	local inviteRow = new("Frame", {
		Name = "Discord",
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = C.control,
		Visible = false,
		LayoutOrder = 6,
		Parent = content,
	}, {
		corner(8),
		stroke(C.border),
	})
	local inviteIcon: any = newIcon("message-circle", 14, C.text_dim)
	inviteIcon.AnchorPoint = Vector2.new(0, 0.5)
	inviteIcon.Position = UDim2.new(0, 11, 0.5, 0)
	inviteIcon.Parent = inviteRow
	local inviteBox = new("TextBox", {
		Name = "Invite",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(33, 0),
		Size = UDim2.new(1, -44, 1, 0),
		Text = "",
		TextColor3 = C.text,
		TextSize = 12,
		FontFace = F.Mono,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		TextEditable = false,
		Parent = inviteRow,
	})

	--@lib
	-- ── details (library build only) ─────────────────────────────────────────
	-- A traceback folded away behind a toggle. The refusal path never passes one,
	-- so the standalone build drops this whole block rather than inlining it into
	-- every refusal reply.
	local detailOpen = false
	local detailToggle = new("TextButton", {
		Name = "DetailToggle",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Text = "Details",
		TextColor3 = C.text_dim,
		TextSize = 12,
		FontFace = F.Medium,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		LayoutOrder = 7,
		Parent = content,
	}, {
		pad(0, 0, 0, 17),
	})
	-- Positioned by hand, not laid out: a UIListLayout owns its children's
	-- transform and suppresses Rotation, and this one spins when the box opens.
	local detailChev: any = newIcon("chevron-down", 12, C.text_dim)
	detailChev.AnchorPoint = Vector2.new(0, 0.5)
	detailChev.Position = UDim2.new(0, -17, 0.5, 0)
	detailChev.Rotation = -90
	detailChev.Parent = detailToggle

	local detailBox = new("Frame", {
		Name = "Detail",
		Size = UDim2.new(1, 0, 0, 118),
		BackgroundColor3 = C.control,
		Visible = false,
		LayoutOrder = 8,
		Parent = content,
	}, {
		corner(8),
		stroke(C.border),
	})
	local detailScroll = new("ScrollingFrame", {
		Name = "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.text_dim,
		ScrollBarImageTransparency = 0.35,
		Parent = detailBox,
	}, {
		pad(9, 10),
	})
	local detailText = new("TextLabel", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -30, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		TextColor3 = C.text_muted,
		TextSize = 11,
		FontFace = F.Mono,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Parent = detailScroll,
	})
	local detailCopy = new("TextButton", {
		Name = "Copy",
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -7, 0, 7),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = C.control_hi,
		ZIndex = 2,
		Parent = detailBox,
	}, {
		corner(6),
	})
	putIcon(detailCopy, "copy", 13, C.text_muted)
	--@endlib

	local actions = new("Frame", {
		Name = "Actions",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		Visible = false,
		LayoutOrder = 9,
		Parent = content,
	}, {
		list({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
	})

	-- Transient confirmation under the buttons ("Copied …"). Hidden until it has
	-- something to say, so a page that never flashes doesn't reserve a strip of
	-- dead space — the list layout skips invisible children, and the card is
	-- centre-anchored, so the one growth spurt on first use reads as the line
	-- appearing rather than the card lurching.
	local flash = new("TextLabel", {
		Name = "Flash",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 14),
		Text = "",
		TextColor3 = C.accent,
		TextSize = 11,
		FontFace = F.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 1,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false,
		LayoutOrder = 10,
		Parent = content,
	})

	local footerRule = new("Frame", {
		Name = "FooterRule",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.border_soft,
		BorderSizePixel = 0,
		Visible = false,
		LayoutOrder = 11,
		Parent = content,
	})
	local footer = new("TextLabel", {
		Name = "Footer",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		TextColor3 = C.text_dim,
		TextSize = 11,
		FontFace = F.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Visible = false,
		LayoutOrder = 12,
		Parent = content,
	})

	-- ── handle ───────────────────────────────────────────────────────────────
	local handle: any = {}
	handle.ScreenGui = screenGui
	handle.Card = card

	local fade = newFade(backdrop)
	local closing = false
	local conns: { RBXScriptConnection } = {}
	local flashToken = 0

	function handle:Close(immediate: boolean?)
		if closing then
			return
		end
		closing = true
		if active == handle then
			active = nil
		end
		if immediate then
			screenGui:Destroy()
			return
		end
		tw(scale, TW.MenuOut, { Scale = 0.96 })
		fade:To(TW.MenuOut, 1, function()
			screenGui:Destroy()
		end)
	end

	-- The Esc listener lives on UserInputService, so it outlives the tree — and
	-- the singleton sweep destroys the ScreenGui without going through `Close`.
	-- `Destroying` is the one signal that covers every way this page can go.
	screenGui.Destroying:Connect(function()
		closing = true
		if active == handle then
			active = nil
		end
		for _, conn in conns do
			conn:Disconnect()
		end
		table.clear(conns)
		fade:Destroy()
	end)

	function handle:Flash(text: any)
		local s = str(text)
		flash.Text = s or ""
		flash.Visible = s ~= nil
		if not s then
			flash.TextTransparency = 1
			return
		end
		flashToken += 1
		local token = flashToken
		tw(flash, TW.Fast, { TextTransparency = 0 })
		task.delay(3, function()
			if closing or token ~= flashToken then
				return
			end
			tw(flash, TW.Normal, { TextTransparency = 1 })
		end)
	end

	-- ── buttons ──────────────────────────────────────────────────────────────
	-- `parent` defaults to the action row; the submit button of an `Input` block
	-- borrows the same button rather than growing a second one.
	local function newButton(label: string, icon: string?, primary: boolean, onClick: () -> (), parent: any?): any
		local base = primary and C.accent_fill or C.control
		local over = primary and C.accent or C.control_hi
		local btn = new("TextButton", {
			Name = "Action",
			AutoButtonColor = false,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 34),
			BackgroundColor3 = base,
			Text = "",
			Parent = parent or actions,
		}, {
			corner(8),
			pad(0, 14, 0, 14),
			-- Icon + label are laid out as a row rather than the icon being
			-- absolutely positioned into a wider left padding: a UIPadding shifts
			-- the button's CHILDREN too, so that gutter moved the glyph *and* the
			-- text by the same amount and the two drew on top of each other.
			list({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
			}),
			new("UISizeConstraint", { MinSize = Vector2.new(76, 34) }),
		})
		if icon then
			local bi: any = newIcon(icon, 14, primary and C.knockout or C.text_muted)
			bi.LayoutOrder = 1
			bi.Parent = btn
		end
		new("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 34),
			Text = label,
			TextColor3 = primary and C.knockout or C.text,
			TextSize = 13,
			FontFace = F.Medium,
			LayoutOrder = 2,
			Parent = btn,
		})
		-- The `busy` attribute is how a disabled button keeps its disabled fill:
		-- these closures own `base`/`over`, so nothing outside could otherwise stop
		-- a hover from painting a dead button as a live one.
		btn.MouseEnter:Connect(function()
			if btn:GetAttribute("busy") then
				return
			end
			tw(btn, TW.Fast, { BackgroundColor3 = over })
		end)
		btn.MouseLeave:Connect(function()
			if btn:GetAttribute("busy") then
				return
			end
			tw(btn, TW.Fast, { BackgroundColor3 = base })
		end)
		btn.Activated:Connect(onClick)
		return btn
	end

	-- ── the entry block ──────────────────────────────────────────────────────
	-- Built only when an `Input` option was passed, and never torn down again: a
	-- page without one has to be exactly the page it was before this existed, and
	-- `handle.Input` is the capability probe a caller uses to decide whether to
	-- fall back to a clipboard button, so its absence has to be load-bearing
	-- rather than incidental.
	--
	-- Everything the block needs lives in this closure. The only things reaching
	-- out of it are `inputBlock` (so `apply` can tell built from not) and
	-- `applyInput` (so `apply` can re-read the options over a live block).
	local INPUT_H = 34  -- the action buttons' height: the row has to read as one
	local MIN_BOX = 200 -- below this the box can't show a full key, so the button wraps
	local inputBlock: any = nil
	local applyInput: any = nil

	local function ensureInput()
		if inputBlock then
			return
		end
		local reader = clipboardFn()
		local submitFn: any, filterFn: any, maxLen: any, seenCfg: any = nil, nil, nil, nil
		local busy, guard, pasteOn, isError = false, false, false, false
		local estW = 76

		inputBlock = new("Frame", {
			Name = "Input",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 5,
			Parent = content,
		}, {
			list({ Padding = UDim.new(0, 6) }),
		})
		local capLabel = new("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 12),
			Text = "",
			TextColor3 = C.text_dim,
			TextSize = 10,
			FontFace = F.Medium,
			TextXAlignment = Enum.TextXAlignment.Left,
			Visible = false,
			LayoutOrder = 1,
			Parent = inputBlock,
		})

		-- The row lays itself out by hand (see relayout) rather than with a
		-- UIListLayout, because the wrap has to be decided on measured width.
		local row = new("Frame", {
			Name = "Row",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, INPUT_H),
			LayoutOrder = 2,
			Parent = inputBlock,
		})
		local field = new("Frame", {
			Name = "Field",
			Size = UDim2.new(1, 0, 0, INPUT_H),
			BackgroundColor3 = C.control,
			Parent = row,
		}, {
			corner(8),
			stroke(C.border),
		})
		local fieldStroke: any = field:FindFirstChildOfClass("UIStroke")
		-- Mono, like the invite: what goes in here is a key, and a key is read
		-- character by character.
		local box = new("TextBox", {
			Name = "Box",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -24, 1, 0),
			Text = "",
			PlaceholderText = "",
			PlaceholderColor3 = C.text_dim,
			TextColor3 = C.text,
			TextSize = 13,
			FontFace = F.Mono,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			Parent = field,
		})
		local paste = new("TextButton", {
			Name = "Paste",
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = C.control_hi,
			Visible = false,
			Parent = field,
		}, {
			corner(6),
		})
		local pasteIcon = putIcon(paste, "clipboard", 13, C.text_dim)

		local status = new("TextLabel", {
			Name = "Status",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = "",
			TextColor3 = C.danger,
			TextSize = 11,
			FontFace = F.Regular,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Visible = false,
			LayoutOrder = 3,
			Parent = inputBlock,
		})

		-- `Filter` is the caller's code running on every keystroke, so it's pcalled
		-- and ignored unless it hands back a string. MaxLength clamps AFTER it, or a
		-- filter that expands its input (grouping dashes into a key) could push the
		-- value past the limit it was clamped to.
		local function clean(text: string): string
			local out = text
			if filterFn then
				local ok, filtered = pcall(filterFn, out)
				if ok and type(filtered) == "string" then
					out = filtered
				end
			end
			if maxLen and #out > maxLen then
				out = string.sub(out, 1, maxLen)
			end
			return out
		end

		-- Error and Success share one line — the second replaces the first — and an
		-- error clears itself as soon as the user edits, because a red line under a
		-- box they're already fixing is noise.
		local function setStatus(text: string?, bad: boolean)
			isError = text ~= nil and bad
			status.Text = text or ""
			status.TextColor3 = bad and C.danger or C.accent
			status.Visible = text ~= nil
		end

		-- Busy repaints with COLOURS, never transparency: transparency in this tree
		-- belongs to util/Fade.lua, and writing one it's driving is how a control
		-- ends up stuck half-visible after the next fade.
		local btn: any = nil
		local function paintBusy()
			box.TextEditable = not busy
			box.TextColor3 = busy and C.text_muted or C.text
			paste.Visible = pasteOn and not busy
			if btn then
				btn:SetAttribute("busy", busy)
				btn.BackgroundColor3 = busy and C.accent_dim or C.accent_fill
			end
		end

		local ui: any = {}

		-- An empty submit does nothing at all — no callback, and no error flash for
		-- something the user hasn't done yet.
		local function submit()
			if busy or closing or not submitFn then
				return
			end
			local value = box.Text
			if value == "" then
				return
			end
			-- Same contract as an Action's callback: it gets an object it can talk
			-- back through, and one that errors or yields can't take the page down.
			local fn = submitFn
			task.spawn(function()
				pcall(fn, value, ui)
			end)
		end

		btn = newButton("Continue", nil, true, submit, row)
		local btnLabel: any = btn:FindFirstChild("Label")

		-- The wrap is done by hand: `UIListLayout.Wraps` is a recent property and
		-- this is the file that has to run on whatever engine the client is on.
		-- The DECISION uses the button's estimated width, never its measured one —
		-- a stacked button is as wide as the row, so measuring would latch the
		-- layout into the stacked branch and never come back out of it.
		local function relayout()
			local w = row.AbsoluteSize.X
			if w > 0 and (w - estW - 8) < MIN_BOX then
				btn.AutomaticSize = Enum.AutomaticSize.None
				btn.AnchorPoint = Vector2.new(0, 0)
				btn.Position = UDim2.fromOffset(0, INPUT_H + 8)
				btn.Size = UDim2.new(1, 0, 0, INPUT_H)
				field.Size = UDim2.new(1, 0, 0, INPUT_H)
				row.Size = UDim2.new(1, 0, 0, INPUT_H * 2 + 8)
			else
				-- Measured only while it's auto-sizing, so the field never gets sized
				-- off a width the button is about to stop having.
				local bw = estW
				if btn.AutomaticSize == Enum.AutomaticSize.X and btn.AbsoluteSize.X > 0 then
					bw = btn.AbsoluteSize.X
				end
				btn.AutomaticSize = Enum.AutomaticSize.X
				btn.AnchorPoint = Vector2.new(1, 0)
				btn.Position = UDim2.new(1, 0, 0, 0)
				btn.Size = UDim2.fromOffset(0, INPUT_H)
				field.Size = UDim2.new(1, -(bw + 8), 0, INPUT_H)
				row.Size = UDim2.new(1, 0, 0, INPUT_H)
			end
		end

		function ui:Get(): string
			return box.Text
		end
		function ui:Set(value: any)
			-- Cleaned here and written under the guard, so the Text signal below
			-- doesn't filter it a second time. Coerced first: TextBox.Text refuses
			-- anything that isn't a string.
			local text = value == nil and "" or tostring(value)
			guard = true
			box.Text = clean(text)
			guard = false
		end
		function ui:Clear()
			ui:Set("")
		end
		function ui:Focus()
			if busy then
				return
			end
			pcall(function()
				box:CaptureFocus()
			end)
		end
		function ui:Busy(on: any)
			busy = on and true or false
			paintBusy()
			if busy then
				pcall(function()
					box:ReleaseFocus()
				end)
			end
		end
		-- An error never clears the box: someone who typed nineteen characters and
		-- got one wrong should be editing, not retyping. So it puts the caret back
		-- where they left it instead.
		function ui:Error(text: any)
			setStatus(str(text) or "That didn't work.", true)
			ui:Focus()
		end
		function ui:Success(text: any)
			setStatus(str(text), false)
		end

		box:GetPropertyChangedSignal("Text"):Connect(function()
			if guard then
				return
			end
			local filtered = clean(box.Text)
			if filtered ~= box.Text then
				-- Rewriting Text re-fires this signal synchronously; the guard skips
				-- that pass so the filter can't chase its own tail.
				guard = true
				box.Text = filtered
				guard = false
			end
			if isError then
				setStatus(nil, true)
			end
		end)
		box.Focused:Connect(function()
			tw(fieldStroke, TW.Fast, { Color = C.accent })
		end)
		box.FocusLost:Connect(function(enterPressed)
			tw(fieldStroke, TW.Fast, { Color = C.border })
			if enterPressed then
				submit()
			end
		end)

		paste.Activated:Connect(function()
			if busy or not reader then
				return
			end
			local ok, text = pcall(reader)
			if ok and type(text) == "string" and text ~= "" then
				ui:Set(text)
				submit()
			else
				handle:Flash("Nothing on the clipboard.")
			end
		end)
		paste.MouseEnter:Connect(function()
			tw(paste, TW.Fast, { BackgroundColor3 = C.pop })
			tintIcon(pasteIcon, C.text)
		end)
		paste.MouseLeave:Connect(function()
			tw(paste, TW.Fast, { BackgroundColor3 = C.control_hi })
			tintIcon(pasteIcon, C.text_dim)
		end)

		row:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
		btn:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)

		applyInput = function(cfg: any)
			submitFn = type(cfg.Submit) == "function" and cfg.Submit or nil
			filterFn = type(cfg.Filter) == "function" and cfg.Filter or nil
			maxLen = nil
			if type(cfg.MaxLength) == "number" and cfg.MaxLength >= 1 then
				maxLen = math.floor(cfg.MaxLength)
			end

			local cap = str(cfg.Label)
			capLabel.Text = cap and string.upper(cap) or ""
			capLabel.Visible = cap ~= nil

			box.PlaceholderText = str(cfg.Placeholder) or ""

			local text = str(cfg.Button) or "Continue"
			btnLabel.Text = text
			estW = math.clamp(#text * 8 + 28, 76, 220)

			-- Where there's no clipboard function at all the affordance isn't drawn,
			-- rather than drawn and dead.
			pasteOn = cfg.Paste == true and reader ~= nil
			box.Size = UDim2.new(1, pasteOn and -48 or -24, 1, 0)
			paintBusy()

			-- `Value` lands only when the Input TABLE itself changed. `apply` re-reads
			-- every option on every patch, so a `Set{ Text = … }` — the gate
			-- rewording itself mid-attempt — would otherwise re-apply the original
			-- `Value = ""` over whatever the user has typed.
			if cfg ~= seenCfg then
				seenCfg = cfg
				local v = cfg.Value
				if type(v) == "string" or type(v) == "number" then
					ui:Set(v)
				end
			end
			relayout()
		end

		handle.Input = ui
	end

	-- Rebuilt rather than patched, so `Set{ Actions = … }` is the same code path
	-- as the initial build and can't drift from it.
	local function buildActions()
		for _, child in actions:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local n = 0
		if type(o.Actions) == "table" then
			for _, def in o.Actions :: any do
				if type(def) == "table" then
					local closeAfter = def.Close ~= false
					local callback = type(def.Callback) == "function" and def.Callback or nil
					local btn = newButton(str(def.Label) or "OK", str(def.Icon), def.Primary == true, function()
						-- The handle is the argument, and a callback that errors
						-- (or yields) must not take the close with it.
						if callback then
							task.spawn(function()
								pcall(callback, handle)
							end)
						end
						if closeAfter then
							handle:Close()
						end
					end)
					n += 1
					btn.LayoutOrder = n
				end
			end
		end

		-- Discord is a first-class option, not something the caller assembles out
		-- of `Actions` — every caller wants the same button, after their own, and
		-- wants the confirmation wired to it.
		local invite = str(o.Discord)
		if invite then
			local only = n == 0
			n += 1
			local btn = newButton("Copy Discord", "message-circle", only, function()
				if copyText(invite) then
					handle:Flash("Copied " .. invite)
				else
					handle:Flash("No clipboard here — select the invite above.")
				end
			end)
			btn.LayoutOrder = n
		end
		actions.Visible = n > 0
	end

	-- ── options → screen ─────────────────────────────────────────────────────
	-- One function for the initial build and for `Set`, so a patched page and a
	-- freshly built one can never disagree about what an option means.
	local function apply(patch: any?)
		if patch ~= nil then
			if type(patch) ~= "table" then
				return
			end
			for key, value in patch :: any do
				o[key] = value
			end
		end

		dismissable = o.Dismissable ~= false
		closeBtn.Visible = dismissable

		tone = toneOf(o.Tone)
		chip.BackgroundColor3 = C.bg:Lerp(tone, 0.18)
		rule.BackgroundColor3 = tone

		-- `newIcon` hands back an ImageLabel for a name it knows and a glyph
		-- TextLabel for one it doesn't, so a *changed* name is a rebuild rather
		-- than a property write that would be wrong half the time.
		local nextIcon = str(o.Icon) or "triangle-alert"
		if nextIcon ~= iconName then
			iconName = nextIcon
			iconInst:Destroy()
			iconInst = putIcon(chip, iconName, 18, tone)
		else
			tintIcon(iconInst, tone)
		end

		title.Text = str(o.Title) or "Something went wrong"

		local code = str(o.Code)
		codeLabel.Text = code or ""
		codeLabel.Visible = code ~= nil

		local text = str(o.Text)
		body.Text = text or ""
		body.Visible = text ~= nil

		-- Built on the first apply that sees an `Input`, patched on every one
		-- after. Dropping the option later only hides the block — `handle.Input`
		-- stays valid, because a caller holding it shouldn't have it turn into a
		-- nil index underneath them.
		if type(o.Input) == "table" then
			ensureInput()
			applyInput(o.Input)
		elseif inputBlock then
			inputBlock.Visible = false
		end

		local invite = str(o.Discord)
		inviteBox.Text = invite or ""
		inviteRow.Visible = invite ~= nil

		local foot = str(o.Footer)
		footer.Text = foot or ""
		footer.Visible = foot ~= nil
		footerRule.Visible = foot ~= nil

		--@lib
		local detail = str(o.Detail)
		detailText.Text = detail or ""
		detailToggle.Visible = detail ~= nil
		if detail == nil then
			detailOpen = false
			detailBox.Visible = false
		end
		--@endlib

		buildActions()
	end

	function handle:Set(patch: any)
		if closing then
			return
		end
		apply(patch or {})
	end

	--@lib
	detailToggle.Activated:Connect(function()
		detailOpen = not detailOpen
		detailBox.Visible = detailOpen
		tw(detailChev, TW.Normal, { Rotation = detailOpen and 0 or -90 })
	end)
	detailCopy.Activated:Connect(function()
		if copyText(detailText.Text) then
			handle:Flash("Details copied")
		else
			handle:Flash("No clipboard here — select the text instead.")
		end
	end)
	detailCopy.MouseEnter:Connect(function()
		tw(detailCopy, TW.Fast, { BackgroundColor3 = C.pop })
	end)
	detailCopy.MouseLeave:Connect(function()
		tw(detailCopy, TW.Fast, { BackgroundColor3 = C.control_hi })
	end)
	--@endlib

	closeBtn.Activated:Connect(function()
		if dismissable then
			handle:Close()
		end
	end)

	-- `Dismissable = false` means the only way out is re-running the loader.
	-- That's the point for a ban: read it, then get a new loadstring.
	--
	-- Guarded on UIS existing at all: the standalone build resolves its own
	-- services and hands back nil rather than throwing if one won't resolve, and
	-- losing the Esc shortcut is a far better outcome than losing the page.
	--
	-- With an `Input` block focused, the first Escape is the engine's — it
	-- releases text capture and arrives here `gameProcessed`, so the page closes
	-- on the second press. That's deliberate: taking Escape off the guard would
	-- mean a game that consumes it closes the page out from under itself.
	if UIS then
		table.insert(conns, UIS.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or not dismissable or closing then
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape then
				handle:Close()
			end
		end))
	end

	-- Fill it in BEFORE the fade snapshots the tree, or a row hidden by `apply`
	-- would be caught in the snapshot at its built transparency and revealed by
	-- the entrance (see util/Fade.lua — hidden subtrees are pruned).
	apply(nil)
	mountGui(screenGui, typeof(o.Parent) == "Instance" and o.Parent or nil)

	fade:Set(1)
	scale.Scale = 0.94
	tw(scale, TW.Pop, { Scale = 1 })
	fade:To(TW.Normal, 0)

	active = handle
	return handle
end
