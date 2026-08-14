--!strict
-- components/Splash.lua — the boot screen. A dimmed backdrop with the brand mark,
-- the wordmark, a status line and a progress bar, played once before the window
-- itself appears (`CreateWindow{ Splash = true }`).
--
-- It's deliberately small: no gradients, no glow, no spinner — the palette rules
-- apply here too. The whole effect is a 4-beat stagger in, a bar that fills for
-- the rest of the budget, then a fade out. `onDone` fires as the fade *starts*,
-- not after it, so the window pops in behind the dim and the two cross-fade
-- instead of the screen blinking empty between them.
--
-- Nothing here is on a UIListLayout on purpose: a layout owns its children's
-- Position, which would suppress the slide-up each element enters with. The
-- stack is a fixed-size frame with the four pieces placed by hand.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Asset = require(script.Parent.Parent.util.Asset)
local Log = require(script.Parent.Parent.util.Log)

-- Timeline. `Duration` is the *whole* on-screen time; the bar's fill soaks up
-- whatever is left after the entrance stagger and the exit fade, so a longer
-- duration reads as a slower bar rather than a longer wait on a full one.
local IN_STAGGER = 0.07 -- beat between each element entering
local BAR_DELAY = IN_STAGGER * 3 -- the bar is the 4th element in
local OUT_TIME = 0.2 -- matches Tween.MenuOut, the window's own leaving fade
local MIN_FILL = 0.35

local LOGO = 76
local STACK_W = 280
local BAR_W = 168

-- Layout, top-down inside the stack (offsets, like every other metric here).
local Y_LOGO = 0
local Y_TITLE = Y_LOGO + LOGO + 20
local Y_SUB = Y_TITLE + 26
local Y_BAR = Y_SUB + 16 + 22
local STACK_H = Y_BAR + 3

-- Same trick as the titlebar: Roblox has no letter-spacing, so a wordmark is
-- literal spaces between the glyphs.
local function wordmark(s: string): string
	local out = {}
	for _, c in utf8.codes(s:upper()) do
		table.insert(out, utf8.char(c))
	end
	return table.concat(out, " ")
end

return function(ctx: any, parent: Instance, opts: any): any
	opts = opts or {}
	local colors = Theme.Colors

	Log.field("Splash", "Title", opts.Title, "string")
	Log.field("Splash", "Subtitle", opts.Subtitle, "string")
	Log.field("Splash", "Duration", opts.Duration, "number")
	Log.field("Splash", "Dim", opts.Dim, "number")
	Log.field("Splash", "Steps", opts.Steps, "table")

	local duration = math.clamp(tonumber(opts.Duration) or 2, 1, 8)
	-- `Dim` is opacity (1 = solid chrome over the game), not transparency.
	local dim = math.clamp(tonumber(opts.Dim) or 0.88, 0, 1)
	local title = opts.Title or Theme.Brand.name
	local steps: { string }? = nil
	if type(opts.Steps) == "table" and #opts.Steps > 0 then
		steps = opts.Steps
	end
	local fillTime = math.max(MIN_FILL, duration - BAR_DELAY - OUT_TIME)

	-- A CanvasGroup so the exit is ONE tween: backdrop, mark and text all fade
	-- together as a single unit (fading each child separately drifts apart).
	local root = Create("CanvasGroup", {
		Name = "Splash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors.chrome,
		BackgroundTransparency = 1, -- faded up to `dim` on Play
		BorderSizePixel = 0,
		ZIndex = 1000, -- above the window frame and its overlay
		Parent = parent,
	})

	local stack = Create("Frame", {
		Name = "Stack",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(STACK_W, STACK_H),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		Create("UIScale", {}),
	})
	local stackScale = stack:FindFirstChildOfClass("UIScale") :: UIScale

	-- Each element parks 8px low + invisible and is released a beat after the one
	-- above it. Built here, *played* by :Play so nothing moves until asked.
	local reveals: { () -> () } = {}
	local function reveal(inst: GuiObject, y: number, order: number, goals: { [string]: any })
		inst.AnchorPoint = Vector2.new(0.5, 0)
		inst.Position = UDim2.new(0.5, 0, 0, y + 8)
		local target = table.clone(goals)
		target.Position = UDim2.new(0.5, 0, 0, y)
		table.insert(reveals, function()
			task.delay(order * IN_STAGGER, function()
				if inst.Parent then
					Tween.play(inst, Tween.Slide, target)
				end
			end)
		end)
	end

	-- ── brand mark ───────────────────────────────────────────────────────────
	-- Same contract as the titlebar logo: the accent square + initial is the
	-- backdrop, the art is drawn over it and NEVER hidden by the load check
	-- (see util/Asset.lua) — worst case you get the square, never a hole.
	local holder = Create("CanvasGroup", {
		Name = "Logo",
		Size = UDim2.fromOffset(LOGO, LOGO),
		BackgroundColor3 = ctx.Accent,
		GroupTransparency = 1,
		ClipsDescendants = true,
		Parent = stack,
	}, {
		Create.corner(opts.LogoRadius or (Theme.Brand.radius * 2)),
		Create("UIScale", { Scale = 0.86 }),
	})
	local holderScale = holder:FindFirstChildOfClass("UIScale") :: UIScale
	local initial = Create("TextLabel", {
		Name = "Initial",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = title:sub(1, 1):upper(),
		TextColor3 = colors.knockout,
		TextSize = 40,
		FontFace = Theme.Font.Bold,
		Parent = holder,
	})
	if opts.Logo ~= nil and opts.Logo ~= false then
		local zoom = tonumber(opts.LogoZoom) or 1
		if zoom <= 0 then
			zoom = 1
		end
		local mark = Create("ImageLabel", {
			Name = "Mark",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(zoom, zoom),
			Image = "",
			ScaleType = Enum.ScaleType.Fit,
			Parent = holder,
		}) :: ImageLabel
		Asset.load(mark, opts.Logo, function(loaded)
			-- Only the fallback reacts — the art is left alone either way.
			initial.Visible = not loaded
			holder.BackgroundTransparency = loaded and 1 or 0
		end)
	end
	reveal(holder, Y_LOGO, 0, { GroupTransparency = 0 })
	table.insert(reveals, function()
		-- The mark gets the extra pop the text doesn't: it's the thing you're
		-- meant to look at.
		Tween.play(holderScale, Tween.Pop, { Scale = 1 })
	end)

	-- ── wordmark + status line ───────────────────────────────────────────────
	local titleLabel = Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		Text = wordmark(title),
		TextColor3 = colors.text,
		TextSize = 22,
		TextTransparency = 1,
		FontFace = Theme.Font.Bold,
		Parent = stack,
	})
	reveal(titleLabel, Y_TITLE, 1, { TextTransparency = 0 })

	local subtitle = Create("TextLabel", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Text = steps and steps[1] or (opts.Subtitle or ""),
		TextColor3 = colors.text_dim,
		TextSize = 12,
		TextTransparency = 1,
		FontFace = Theme.Font.Regular,
		Parent = stack,
	})
	reveal(subtitle, Y_SUB, 2, { TextTransparency = 0 })

	-- ── progress bar ─────────────────────────────────────────────────────────
	local track = Create("Frame", {
		Name = "Track",
		Size = UDim2.fromOffset(BAR_W, 3),
		BackgroundColor3 = colors.toggle_off,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = stack,
	}, {
		Create.corner(2),
	})
	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = ctx.Accent,
		BorderSizePixel = 0,
		Parent = track,
	}, {
		Create.corner(2),
	})
	reveal(track, Y_BAR, 3, { BackgroundTransparency = 0 })

	-- ── play ─────────────────────────────────────────────────────────────────
	local splash = {}
	local finished = false

	-- Swap the status line through `Steps` across the fill, so the bar and the
	-- text tell the same story. One step = no cycling, it's just a caption.
	local function cycleSteps()
		local list = steps
		if not list or #list <= 1 then
			return
		end
		task.spawn(function()
			local slot = fillTime / #list
			for i = 2, #list do
				task.wait(slot)
				if not subtitle.Parent or finished then
					return
				end
				Tween.play(subtitle, Tween.Fast, { TextTransparency = 1 }).Completed:Wait()
				subtitle.Text = list[i]
				Tween.play(subtitle, Tween.Fast, { TextTransparency = 0 })
			end
		end)
	end

	-- `onDone` fires when the fade BEGINS — the window mounts behind the dim and
	-- the two cross-fade. Waiting for the fade to finish would show a blank
	-- screen for a fifth of a second in between.
	function splash:Play(onDone: (() -> ())?)
		task.spawn(function()
			Tween.play(root, Tween.Slide, { BackgroundTransparency = 1 - dim })
			for _, run in reveals do
				run()
			end

			task.wait(BAR_DELAY)
			Tween.play(
				fill,
				TweenInfo.new(fillTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
				{ Size = UDim2.fromScale(1, 1) }
			)
			cycleSteps()

			task.wait(fillTime + 0.06) -- a beat on a full bar before it leaves
			finished = true
			if onDone then
				onDone()
			end
			Tween.play(stackScale, Tween.MenuOut, { Scale = 1.05 })
			Tween.play(root, Tween.MenuOut, { GroupTransparency = 1 }).Completed:Wait()
			root:Destroy()
		end)
	end

	function splash:Destroy()
		finished = true
		root:Destroy()
	end

	return splash
end
