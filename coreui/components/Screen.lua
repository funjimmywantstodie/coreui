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
--
-- Plus the engine globals (Enum, UDim2, Color3, Vector2, task, typeof, …).
-- Nothing else. No `require`, no library table, no executor globals except the
-- clipboard lookup below, which is guarded.
-- ─────────────────────────────────────────────────────────────────────────────

local ORDER = 1000000 -- above the window's ScreenGui, which leaves DisplayOrder at 0
local DIM = 0.28      -- backdrop transparency at rest (lower = darker)
local CARD_W = 420    -- max card width; below that it tracks the viewport
local PAD = 18
local GAP = 12
local RADIUS = 14

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

	-- Scale width + a max-size cap: 420px on anything desktop-shaped, and a
	-- proportion of the viewport once the screen is narrower than that.
	local card = new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.card,
		Parent = backdrop,
	}, {
		corner(RADIUS),
		stroke(C.border),
		pad(PAD),
		list({ Padding = UDim.new(0, GAP) }),
		new("UISizeConstraint", { MaxSize = Vector2.new(CARD_W, math.huge) }),
	})
	local scale = new("UIScale", { Parent = card })

	-- ── header: tone chip + close ────────────────────────────────────────────
	local head = new("Frame", {
		Name = "Head",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 1,
		Parent = card,
	})
	local chip = new("Frame", {
		Name = "Chip",
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = C.card:Lerp(tone, 0.16),
		Parent = head,
	}, {
		corner(12),
	})
	local iconName = str(o.Icon) or "triangle-alert"
	local iconInst = putIcon(chip, iconName, 20, tone)

	local closeBtn = new("TextButton", {
		Name = "Close",
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
		Visible = dismissable,
		Parent = head,
	})
	local closeIcon = putIcon(closeBtn, "x", 16, C.text_dim)
	closeBtn.MouseEnter:Connect(function()
		tintIcon(closeIcon, C.text)
	end)
	closeBtn.MouseLeave:Connect(function()
		tintIcon(closeIcon, C.text_dim)
	end)

	-- ── title + code ─────────────────────────────────────────────────────────
	-- Their own block on a tighter 4px rhythm: the code line is a subtitle of the
	-- title, not a sibling of the body copy.
	local titleBlock = new("Frame", {
		Name = "TitleBlock",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = card,
	}, {
		list({ Padding = UDim.new(0, 4) }),
	})
	local title = new("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		TextColor3 = C.text,
		TextSize = 18,
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
		Parent = card,
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
		Parent = card,
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
		LayoutOrder = 5,
		Parent = card,
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
		LayoutOrder = 6,
		Parent = card,
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
		LayoutOrder = 7,
		Parent = card,
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
		LayoutOrder = 8,
		Parent = card,
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
		LayoutOrder = 9,
		Parent = card,
	})

	local footerRule = new("Frame", {
		Name = "FooterRule",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.border_soft,
		BorderSizePixel = 0,
		Visible = false,
		LayoutOrder = 10,
		Parent = card,
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
		LayoutOrder = 11,
		Parent = card,
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
	local function newButton(label: string, icon: string?, primary: boolean, onClick: () -> ()): any
		local base = primary and C.accent_fill or C.control
		local over = primary and C.accent or C.control_hi
		local btn = new("TextButton", {
			Name = "Action",
			AutoButtonColor = false,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 34),
			BackgroundColor3 = base,
			Text = label,
			TextColor3 = primary and C.knockout or C.text,
			TextSize = 13,
			FontFace = F.Medium,
			Parent = actions,
		}, {
			corner(8),
			-- Extra left padding when there's an icon: the glyph is positioned
			-- into that gutter, so the label still centres in what's left.
			pad(0, 14, 0, icon and 32 or 14),
			new("UISizeConstraint", { MinSize = Vector2.new(76, 34) }),
		})
		if icon then
			local bi: any = newIcon(icon, 14, primary and C.knockout or C.text_muted)
			bi.AnchorPoint = Vector2.new(0, 0.5)
			bi.Position = UDim2.new(0, 11, 0.5, 0)
			bi.Parent = btn
		end
		btn.MouseEnter:Connect(function()
			tw(btn, TW.Fast, { BackgroundColor3 = over })
		end)
		btn.MouseLeave:Connect(function()
			tw(btn, TW.Fast, { BackgroundColor3 = base })
		end)
		btn.Activated:Connect(onClick)
		return btn
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
		chip.BackgroundColor3 = C.card:Lerp(tone, 0.16)
		rule.BackgroundColor3 = tone

		-- `newIcon` hands back an ImageLabel for a name it knows and a glyph
		-- TextLabel for one it doesn't, so a *changed* name is a rebuild rather
		-- than a property write that would be wrong half the time.
		local nextIcon = str(o.Icon) or "triangle-alert"
		if nextIcon ~= iconName then
			iconName = nextIcon
			iconInst:Destroy()
			iconInst = putIcon(chip, iconName, 20, tone)
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
