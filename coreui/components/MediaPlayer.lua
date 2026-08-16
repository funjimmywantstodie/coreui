--!strict
-- components/MediaPlayer.lua — cover art + title/artist, a draggable scrub
-- timeline, transport (shuffle/prev/play·pause/next/repeat) and a volume bar.
--
-- Three ways to drive it, mixable per track:
--   1. `SoundId` (single) or `Queue = { { SoundId = ... }, ... }` (playlist) —
--      the component owns a real Instance.new("Sound") per track (parented to
--      SoundService), actually plays it, and drives the timeline from
--      Sound.TimePosition. Track-end advances the queue (respecting Loop /
--      Shuffle) automatically.
--   2. `Sound = <Instance>` (or a Queue entry's `Sound`) — a Sound you already
--      own; the component calls :Play()/:Pause()/sets .TimePosition/.Volume on
--      it but never destroys it, so you keep the instance's lifetime.
--   3. Neither — a pure remote-control surface. Play/Pause/Next/Previous/Seek/
--      Volume all just fire `Callback(action, payload)` + the matching event;
--      drive your own audio and push state back with :SetProgress/:SetPlaying/
--      :SetDuration.
--
-- Group:MediaPlayer({
--     Title = "Song Name", Artist = "Artist", Cover = "rbxassetid://...",
--     Queue = { { Title = "...", Artist = "...", SoundId = "rbxassetid://..." } },
--     Volume = 0.5, Shuffle = false, Loop = "off", -- "off" | "one" | "all"
--     ShowVolume = true, ShowShuffle = true, ShowLoop = true, ShowFavorite = false,
--     Callback = function(action, payload) end, -- "play"|"pause"|"next"|"previous"|"seek"|"volume"|"shuffle"|"loop"|"favorite"|"track"
-- })
-- handle:Play() :Pause() :TogglePlay() :IsPlaying() :Next() :Previous()
-- handle:Seek(t) :GetProgress() :SetProgress(t) :GetDuration() :SetDuration(t)
-- handle:GetVolume() :SetVolume(v) :GetShuffle() :SetShuffle(b)
-- handle:GetLoop() :SetLoop(mode) :SetTrack(data) :SetQueue(list, startIndex?)
-- handle:GetTrack()
-- handle.Played/.Paused/.NextTrack/.PreviousTrack/.Seeked/.VolumeChanged/
--        .ShuffleChanged/.LoopChanged/.TrackChanged/.Ended/.FavoriteChanged (all `.Event`)

local Services = require(script.Parent.Parent.util.Services)

local UserInputService = Services.UserInputService
local RunService = Services.RunService
local SoundService = Services.SoundService

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Icons = require(script.Parent.Parent.Icons)
local Log = require(script.Parent.Parent.util.Log)
local Asset = require(script.Parent.Parent.util.Asset)
local Field = require(script.Parent.Field)

local function clamp(v: number, a: number, b: number): number
	return math.max(a, math.min(b, v))
end

local function fmtTime(t: number): string
	if t ~= t or t == math.huge or t == -math.huge then -- guard NaN/inf
		t = 0
	end
	t = math.max(0, math.floor(t))
	return ("%d:%02d"):format(math.floor(t / 60), t % 60)
end

-- A draggable pill bar: `width` is the hit area's X UDim (fill = UDim.new(1,0),
-- fixed = UDim.new(0, px)). Returns the clickable hit frame + the fill/knob to
-- animate + the knob's UIScale (grown while dragging, like Slider.lua).
local function newBar(ctx: any, parent: Instance, width: UDim, hitHeight: number, barHeight: number, knobSize: number, order: number?)
	local colors = Theme.Colors
	local hit = Create("TextButton", {
		Name = "Hit",
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(width.Scale, width.Offset, 0, hitHeight),
		LayoutOrder = order,
		Parent = parent,
	}) :: TextButton
	local track = Create("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, barHeight),
		BackgroundColor3 = colors.toggle_off,
		Parent = hit,
	}, { Create.corner(999) })
	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = ctx.Accent,
		Parent = track,
	}, { Create.corner(999) })
	local knob = Create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(knobSize, knobSize),
		BackgroundColor3 = colors.text, -- see Slider.lua: knob leaves the accent fill at 0
		ZIndex = 2,
		Parent = track,
	}, { Create.corner(999), Create("UIScale", {}) })
	return hit, fill, knob, knob:FindFirstChildOfClass("UIScale") :: UIScale
end

-- Shared drag wiring (mirrors Slider.lua): global listeners only live for the
-- duration of one drag, so N idle bars never leak a permanent InputChanged
-- connection.
local function attachDrag(hit: GuiButton, knobScale: UIScale, setFromX: (number) -> (), onStart: (() -> ())?, onEnd: (() -> ())?)
	local conns: { RBXScriptConnection } = {}
	local function stop()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		Tween.play(knobScale, Tween.Spring, { Scale = 1 })
		if onEnd then
			onEnd()
		end
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if #conns > 0 then
				return
			end
			if onStart then
				onStart()
			end
			Tween.play(knobScale, Tween.Spring, { Scale = 1.3 })
			setFromX(input.Position.X)
			table.insert(conns, UserInputService.InputChanged:Connect(function(move)
				if move.UserInputType == Enum.UserInputType.MouseMovement or move.UserInputType == Enum.UserInputType.Touch then
					setFromX(move.Position.X)
				end
			end))
			table.insert(conns, UserInputService.InputEnded:Connect(function(up)
				if up.UserInputType == Enum.UserInputType.MouseButton1 or up.UserInputType == Enum.UserInputType.Touch then
					stop()
				end
			end))
		end
	end)
end

-- Small hover-tint circular icon button, used for prev/next/shuffle/loop/favorite.
local function iconButton(parent: Instance, size: number, iconSize: number, iconName: string, order: number): (TextButton, GuiObject)
	local colors = Theme.Colors
	local btn = Create("TextButton", {
		Name = iconName,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = colors.control,
		LayoutOrder = order,
		Parent = parent,
	}, { Create.corner(999) }) :: TextButton
	local icon = Icons.new(iconName, iconSize, colors.text)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	;(icon :: any).Parent = btn
	Create.hover(btn, "BackgroundColor3", colors.control, colors.control_hi)
	return btn, icon
end

local SCHEMA: Log.Schema = {
	{ "Callback", "function" },
	{ "Queue", "table" },
	-- Cover is handed to Asset.resolve, which takes a bare decal id, an
	-- rbxassetid/url string, a file path or a fallback-chain array — so the only
	-- thing worth rejecting is something Asset can't read at all.
	{ "Cover", { "string", "number", "table" } },
}

return function(ctx: any, opts: any): (Instance, any, boolean)
	local colors = Theme.Colors
	opts = opts or {}
	local where = Log.where("MediaPlayer", opts.Name)
	Log.check(where, opts, SCHEMA)

	local showVolume = opts.ShowVolume ~= false
	local showShuffle = opts.ShowShuffle ~= false
	local showLoop = opts.ShowLoop ~= false
	local showFavorite = opts.ShowFavorite == true

	-- ── state ────────────────────────────────────────────────────────────────
	local rng = Random.new()
	local queue: { any } = (type(opts.Queue) == "table" and opts.Queue) or {}
	local useQueue = #queue > 0
	local index = useQueue and math.clamp(math.floor(opts.Index or 1), 1, #queue) or 1

	local current = { Title = "", Artist = "", Cover = nil :: string? }
	local elapsed, duration = 0, 0
	local playing = false
	local draggingProgress = false
	local loved = false

	local volume = clamp(opts.Volume ~= nil and opts.Volume or 0.5, 0, 1)
	local shuffle = opts.Shuffle == true
	local loopMode = opts.Loop or "off"
	if loopMode ~= "off" and loopMode ~= "one" and loopMode ~= "all" then
		Log.warn(where, ("Loop must be \"off\", \"one\" or \"all\", got \"%s\" — using \"off\"."):format(tostring(loopMode)))
		loopMode = "off"
	end

	local activeSound: Sound? = nil
	local ownsSound = false
	local soundConns: { RBXScriptConnection } = {}
	local tickConn: RBXScriptConnection? = nil

	local bindables = {
		Played = Instance.new("BindableEvent"),
		Paused = Instance.new("BindableEvent"),
		NextTrack = Instance.new("BindableEvent"),
		PreviousTrack = Instance.new("BindableEvent"),
		Seeked = Instance.new("BindableEvent"),
		VolumeChanged = Instance.new("BindableEvent"),
		ShuffleChanged = Instance.new("BindableEvent"),
		LoopChanged = Instance.new("BindableEvent"),
		TrackChanged = Instance.new("BindableEvent"),
		Ended = Instance.new("BindableEvent"),
		FavoriteChanged = Instance.new("BindableEvent"),
	}

	local function currentPayload()
		return {
			Title = current.Title,
			Artist = current.Artist,
			Cover = current.Cover,
			Duration = duration,
			Progress = elapsed,
			Index = useQueue and index or nil,
			Playing = playing,
		}
	end

	-- forward decls (mutually referential: track load ↔ sound end ↔ queue nav)
	local fireEvent: (string, any?) -> ()
	local renderMeta: () -> ()
	local renderProgress: () -> ()
	local renderVolume: () -> ()
	local paintPlayPause: () -> ()
	local paintShuffle: () -> ()
	local paintLoop: () -> ()
	local paintFavorite: () -> ()
	local startTicking: () -> ()
	local stopTicking: () -> ()
	local seekTo: (number, boolean) -> ()
	local attachTrackAudio: (any) -> ()
	local loadTrackData: (any, boolean) -> ()
	local gotoIndex: (number, boolean) -> ()
	local pickIndex: (number) -> number?
	local handleEnded: () -> ()
	local doPlay: () -> ()
	local doPause: () -> ()
	local applyVolume: (number, boolean) -> ()
	local applyShuffle: (boolean, boolean) -> ()
	local applyLoop: (string, boolean) -> ()
	local doNext: () -> ()
	local doPrevious: () -> ()

	-- ── layout ───────────────────────────────────────────────────────────────
	local f = Field.new(ctx, opts, true)

	local panel = Create("Frame", {
		Name = "MediaPlayer",
		BackgroundColor3 = colors.control,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = f.field,
	}, {
		Create.corner(Theme.Metrics.controlRadius),
		Create.stroke(colors.border),
		Create.padding(14),
		Create.listLayout({ Padding = UDim.new(0, 14) }),
	})

	-- meta row: cover · title/artist · (favorite) ──────────────────────────────
	local favW = showFavorite and 38 or 0
	local meta = Create("Frame", {
		Name = "Meta",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 48),
		LayoutOrder = 1,
		Parent = panel,
	})

	local cover = Create("Frame", {
		Name = "Cover",
		Size = UDim2.fromOffset(48, 48),
		BackgroundColor3 = colors.control_hi,
		ClipsDescendants = true,
		Parent = meta,
	}, { Create.corner(10), Create.stroke(colors.border) })
	-- Flat surface placeholder (no gradient) until real cover art is set.
	local coverIcon = Icons.new("music", 20, colors.text_dim)
	coverIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	coverIcon.Position = UDim2.fromScale(0.5, 0.5)
	;(coverIcon :: any).Parent = cover
	-- Stays visible with an empty Image when there's no art: the engine only
	-- fetches what it renders, so a hidden ImageLabel would never load and
	-- Asset.load's "did it arrive?" answer would always be no. The icon behind
	-- it is what toggles.
	local coverImage = Create("ImageLabel", {
		Name = "Art",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = "",
		ScaleType = Enum.ScaleType.Crop,
		Parent = cover,
	}) :: ImageLabel

	local info = Create("Frame", {
		Name = "Info",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 60, 0.5, 0),
		Size = UDim2.new(1, -60 - favW, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = meta,
	}, { Create.listLayout({ Padding = UDim.new(0, 3) }) })

	local titleLabel = Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Text = "No Track",
		TextColor3 = colors.text,
		TextSize = 14,
		FontFace = Theme.Font.Medium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
		Parent = info,
	})
	local artistLabel = Create("TextLabel", {
		Name = "Artist",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Text = "",
		TextColor3 = colors.text_muted,
		TextSize = 12,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		Parent = info,
	})

	local favoriteBtn, favoriteIcon
	if showFavorite then
		favoriteBtn, favoriteIcon = iconButton(meta, 28, 14, "heart", 1)
		favoriteBtn.AnchorPoint = Vector2.new(1, 0.5)
		favoriteBtn.Position = UDim2.new(1, 0, 0.5, 0)
	end

	-- progress row: scrub bar + time labels ─────────────────────────────────────
	local progress = Create("Frame", {
		Name = "Progress",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 2,
		Parent = panel,
	})
	local progressHit, progressFill, progressKnob, progressKnobScale =
		newBar(ctx, progress, UDim.new(1, 0), 16, 5, 13, 1)

	local timeCur = Create("TextLabel", {
		Name = "Current",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.fromOffset(40, 14),
		Text = "0:00",
		TextColor3 = colors.text_muted,
		TextSize = 11,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = progress,
	})
	local timeDur = Create("TextLabel", {
		Name = "Duration",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 20),
		Size = UDim2.fromOffset(40, 14),
		Text = "0:00",
		TextColor3 = colors.text_muted,
		TextSize = 11,
		FontFace = Theme.Font.Regular,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = progress,
	})

	-- transport row: shuffle · prev · play/pause · next · loop  +  volume ───────
	local transport = Create("Frame", {
		Name = "Transport",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 3,
		Parent = panel,
	})
	local center = Create("Frame", {
		Name = "Center",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 0, 0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = transport,
	}, {
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
	})

	local shuffleBtn, shuffleIcon
	if showShuffle then
		shuffleBtn, shuffleIcon = iconButton(center, 30, 15, "shuffle", 1)
	end
	local prevBtn, _prevIcon = iconButton(center, 34, 16, "skip-back", 2)
	local playBtn = Create("TextButton", {
		Name = "PlayPause",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = ctx.Accent,
		LayoutOrder = 3,
		Parent = center,
	}, { Create.corner(999), Create("UIScale", {}) }) :: TextButton
	local playScale = playBtn:FindFirstChildOfClass("UIScale") :: UIScale
	local playIcon = Icons.new("play", 18, colors.knockout)
	playIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	playIcon.Position = UDim2.fromScale(0.5, 0.5)
	;(playIcon :: any).Parent = playBtn
	local nextBtn, _nextIcon = iconButton(center, 34, 16, "skip-forward", 4)
	local loopBtn, loopIcon
	if showLoop then
		loopBtn, loopIcon = iconButton(center, 30, 15, "repeat", 5)
	end

	local volumeGroup, volumeBtn, volumeIcon, volumeHit, volumeFill, volumeKnob, volumeKnobScale
	if showVolume then
		volumeGroup = Create("Frame", {
			Name = "Volume",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.new(0, 0, 0, 22),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = transport,
		}, {
			Create.listLayout({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
			}),
		})
		volumeBtn, volumeIcon = iconButton(volumeGroup, 22, 14, "volume-2", 1)
		volumeBtn.BackgroundTransparency = 1
		volumeHit, volumeFill, volumeKnob, volumeKnobScale = newBar(ctx, volumeGroup, UDim.new(0, 64), 16, 4, 10, 2)
	end

	-- ── playback plumbing ────────────────────────────────────────────────────
	fireEvent = function(name, payload)
		local b = (bindables :: any)[name]
		if b then
			b:Fire(payload)
		end
	end

	-- Bumped on every renderMeta so a cover that resolves late can tell whether
	-- the track it was fetched for is still the one on screen.
	local coverGen = 0

	renderMeta = function()
		titleLabel.Text = (current.Title ~= "" and current.Title) or "No Track"
		artistLabel.Text = current.Artist or ""
		artistLabel.Visible = current.Artist ~= nil and current.Artist ~= ""

		coverGen += 1
		local gen = coverGen
		local art = current.Cover -- captured: `current` is replaced wholesale per track
		coverIcon.Visible = true
		if art == nil then
			coverImage.Image = ""
			return
		end
		-- Through Asset so a track's Cover can be a bare id / url / file path, and
		-- off-thread because resolving an https cover downloads + caches it —
		-- inline, that stalled the menu build and every Next click.
		task.spawn(function()
			Asset.load(coverImage, art, function(loaded)
				if gen ~= coverGen then
					return -- the track moved on while this was in flight
				end
				coverIcon.Visible = not loaded
			end)
		end)
	end

	-- Whole seconds currently ON the two labels, so the strings are only rebuilt
	-- when they'd actually read differently. `renderProgress` runs every Heartbeat
	-- while a track plays: the fill and the knob genuinely move every frame, but
	-- the clocks change once a second, and reformatting both plus writing both
	-- `Text` properties 60 times a second was ~59 wasted string allocations and
	-- two wasted layout invalidations per second, forever, on the render path.
	-- `-1` can't collide with a real value (both are floored to ≥ 0), so the first
	-- call always paints.
	local shownElapsed, shownDuration = -1, -1

	renderProgress = function()
		local pct = duration > 0 and clamp(elapsed / duration, 0, 1) or 0
		progressFill.Size = UDim2.fromScale(pct, 1)
		progressKnob.Position = UDim2.fromScale(pct, 0.5)
		local secs = math.floor(math.max(0, elapsed))
		if secs ~= shownElapsed then
			shownElapsed = secs
			timeCur.Text = fmtTime(elapsed)
		end
		local total = math.floor(math.max(0, duration))
		if total ~= shownDuration then
			shownDuration = total
			timeDur.Text = duration > 0 and fmtTime(duration) or "0:00"
		end
	end

	renderVolume = function()
		if not showVolume then
			return
		end
		volumeFill.Size = UDim2.fromScale(volume, 1)
		volumeKnob.Position = UDim2.fromScale(volume, 0.5)
		if volume <= 0 then
			Icons.apply(volumeIcon :: any, "volume-x")
		elseif volume < 0.5 then
			Icons.apply(volumeIcon :: any, "volume-1")
		else
			Icons.apply(volumeIcon :: any, "volume-2")
		end
	end

	paintPlayPause = function()
		if playing then
			Icons.apply(playIcon :: any, "pause")
		else
			Icons.apply(playIcon :: any, "play")
		end
	end

	paintShuffle = function()
		if not showShuffle then
			return
		end
		Icons.tint(shuffleIcon, shuffle and ctx.Accent or colors.text_dim)
		shuffleBtn.BackgroundColor3 = shuffle and colors.control_hi or colors.control
	end

	paintLoop = function()
		if not showLoop then
			return
		end
		if loopMode == "one" then
			Icons.apply(loopIcon :: any, "repeat-1")
		else
			Icons.apply(loopIcon :: any, "repeat")
		end
		local active = loopMode ~= "off"
		Icons.tint(loopIcon, active and ctx.Accent or colors.text_dim)
		loopBtn.BackgroundColor3 = active and colors.control_hi or colors.control
	end

	paintFavorite = function()
		if not showFavorite then
			return
		end
		Icons.tint(favoriteIcon, loved and ctx.Accent or colors.text_dim)
	end

	stopTicking = function()
		if tickConn then
			tickConn:Disconnect()
			tickConn = nil
		end
	end

	startTicking = function()
		if tickConn or not activeSound then
			return
		end
		tickConn = RunService.Heartbeat:Connect(function()
			local snd = activeSound
			if draggingProgress or not snd then
				return
			end
			elapsed = snd.TimePosition
			if duration <= 0 and snd.TimeLength > 0 then
				duration = snd.TimeLength
			end
			renderProgress()
		end)
	end

	seekTo = function(t, fireCB)
		t = clamp(t, 0, math.max(duration, 0))
		elapsed = t
		renderProgress()
		local snd = activeSound
		if snd then
			pcall(function()
				snd.TimePosition = t
			end)
		end
		if fireCB then
			fireEvent("Seeked", t)
			if opts.Callback then
				task.spawn(opts.Callback, "seek", t)
			end
		end
	end

	attachTrackAudio = function(data)
		for _, c in soundConns do
			c:Disconnect()
		end
		table.clear(soundConns)
		local prev = activeSound
		if prev then
			if ownsSound then
				prev:Stop()
				prev:Destroy()
			else
				-- A caller's Sound is theirs to destroy, but we still have to let go
				-- of it *quiet*: leaving it playing strands audio with nothing left
				-- driving it (no transport, no timeline, no volume).
				prev:Pause()
			end
		end
		activeSound = nil
		ownsSound = false

		if data.Sound then
			activeSound = data.Sound
			ownsSound = false
		elseif data.SoundId then
			local snd = Instance.new("Sound")
			snd.Name = "Uranium_MediaPlayerSound"
			snd.SoundId = data.SoundId
			snd.Parent = SoundService
			activeSound = snd
			ownsSound = true
		end

		local snd = activeSound
		if snd then
			snd.Volume = volume
			table.insert(soundConns, snd.Ended:Connect(function()
				handleEnded()
			end))
			table.insert(soundConns, snd:GetPropertyChangedSignal("TimeLength"):Connect(function()
				if not data.Duration or data.Duration <= 0 then
					duration = snd.TimeLength
					renderProgress()
				end
			end))
			if snd.TimeLength > 0 and (not data.Duration or data.Duration <= 0) then
				duration = snd.TimeLength
			end
		end
	end

	loadTrackData = function(data, autoplayThis)
		data = data or {}
		current = { Title = data.Title or "", Artist = data.Artist, Cover = data.Cover }
		elapsed = 0
		duration = data.Duration or 0
		draggingProgress = false
		attachTrackAudio(data)
		renderMeta()
		renderProgress()

		if autoplayThis then
			playing = true
			if activeSound then
				activeSound:Play()
			end
			startTicking()
		else
			playing = false
			if activeSound then
				activeSound:Pause()
			end
			stopTicking()
		end
		paintPlayPause()

		fireEvent("TrackChanged", currentPayload())
		if opts.Callback then
			task.spawn(opts.Callback, "track", currentPayload())
		end
	end

	pickIndex = function(direction)
		if not useQueue or #queue <= 1 then
			return nil
		end
		if shuffle then
			local n
			repeat
				n = rng:NextInteger(1, #queue)
			until n ~= index
			return n
		end
		local n = index + direction
		if n < 1 then
			return loopMode == "all" and #queue or nil
		elseif n > #queue then
			return loopMode == "all" and 1 or nil
		end
		return n
	end

	gotoIndex = function(n, autoplayThis)
		index = n
		loadTrackData(queue[n], autoplayThis)
	end

	handleEnded = function()
		if loopMode == "one" then
			seekTo(0, false)
			if activeSound then
				activeSound:Play()
			end
			return
		end
		if useQueue then
			local n = pickIndex(1)
			if n then
				gotoIndex(n, true)
				fireEvent("Ended")
				return
			end
		end
		playing = false
		elapsed = duration
		renderProgress()
		paintPlayPause()
		stopTicking()
		fireEvent("Ended")
	end

	doPlay = function()
		if playing then
			return
		end
		playing = true
		if activeSound then
			activeSound:Play()
		end
		paintPlayPause()
		startTicking()
		fireEvent("Played")
		if opts.Callback then
			task.spawn(opts.Callback, "play", currentPayload())
		end
	end

	doPause = function()
		if not playing then
			return
		end
		playing = false
		if activeSound then
			activeSound:Pause()
		end
		paintPlayPause()
		stopTicking()
		fireEvent("Paused")
		if opts.Callback then
			task.spawn(opts.Callback, "pause", currentPayload())
		end
	end

	applyVolume = function(v, fireCB)
		volume = clamp(v, 0, 1)
		if activeSound then
			activeSound.Volume = volume
		end
		renderVolume()
		if fireCB then
			fireEvent("VolumeChanged", volume)
			if opts.Callback then
				task.spawn(opts.Callback, "volume", volume)
			end
		end
	end

	applyShuffle = function(v, fireCB)
		shuffle = v == true
		paintShuffle()
		if fireCB then
			fireEvent("ShuffleChanged", shuffle)
			if opts.Callback then
				task.spawn(opts.Callback, "shuffle", shuffle)
			end
		end
	end

	applyLoop = function(mode, fireCB)
		if mode ~= "off" and mode ~= "one" and mode ~= "all" then
			Log.warn(where, ("Loop must be \"off\", \"one\" or \"all\", got \"%s\" — using \"off\"."):format(tostring(mode)))
			mode = "off"
		end
		loopMode = mode
		paintLoop()
		if fireCB then
			fireEvent("LoopChanged", loopMode)
			if opts.Callback then
				task.spawn(opts.Callback, "loop", loopMode)
			end
		end
	end

	doNext = function()
		if useQueue then
			local n = pickIndex(1)
			if n then
				gotoIndex(n, playing)
			end
		end
		fireEvent("NextTrack")
		if opts.Callback then
			task.spawn(opts.Callback, "next", currentPayload())
		end
	end

	doPrevious = function()
		if elapsed > 3 then
			seekTo(0, true)
		elseif useQueue then
			local n = pickIndex(-1)
			if n then
				gotoIndex(n, playing)
			else
				seekTo(0, true)
			end
		else
			seekTo(0, true)
		end
		fireEvent("PreviousTrack")
		if opts.Callback then
			task.spawn(opts.Callback, "previous", currentPayload())
		end
	end

	-- ── wire the chrome ──────────────────────────────────────────────────────
	attachDrag(progressHit, progressKnobScale, function(x)
		local w = progressHit.AbsoluteSize.X
		local pos = progressHit.AbsolutePosition.X
		local pct = w > 0 and clamp((x - pos) / w, 0, 1) or 0
		seekTo(pct * math.max(duration, 0), true)
	end, function()
		draggingProgress = true
	end, function()
		draggingProgress = false
	end)

	if showVolume then
		attachDrag(volumeHit, volumeKnobScale, function(x)
			local w = volumeHit.AbsoluteSize.X
			local pos = volumeHit.AbsolutePosition.X
			local pct = w > 0 and clamp((x - pos) / w, 0, 1) or 0
			applyVolume(pct, true)
		end)
		local lastVolume = volume > 0 and volume or 0.5
		volumeBtn.Activated:Connect(function()
			if volume > 0 then
				lastVolume = volume
				applyVolume(0, true)
			else
				applyVolume(lastVolume > 0 and lastVolume or 0.5, true)
			end
		end)
	end

	-- The setter is kept: SetAccent moves both ends of this hover, and it can land
	-- while the pointer is already on the button (see Create.hover).
	local _, setPlayHover = Create.hover(playBtn, "BackgroundColor3", ctx.Accent, ctx.AccentHover)
	playBtn.Activated:Connect(function()
		playScale.Scale = 0.92
		Tween.play(playScale, Tween.Spring, { Scale = 1 })
		if playing then
			doPause()
		else
			doPlay()
		end
	end)

	prevBtn.Activated:Connect(function()
		doPrevious()
	end)

	nextBtn.Activated:Connect(function()
		doNext()
	end)

	if showShuffle then
		shuffleBtn.Activated:Connect(function()
			applyShuffle(not shuffle, true)
		end)
	end
	if showLoop then
		local order = { "off", "all", "one" }
		loopBtn.Activated:Connect(function()
			local nextMode = "off"
			for i, m in order do
				if m == loopMode then
					nextMode = order[(i % 3) + 1]
					break
				end
			end
			applyLoop(nextMode, true)
		end)
	end
	if showFavorite then
		favoriteBtn.Activated:Connect(function()
			loved = not loved
			paintFavorite()
			fireEvent("FavoriteChanged", loved)
			if opts.Callback then
				task.spawn(opts.Callback, "favorite", loved)
			end
		end)
	end

	ctx:RegisterAccent(function(accent)
		progressFill.BackgroundColor3 = accent
		-- Repaints playBtn itself, to whichever end applies right now — so a
		-- re-theme under a hovered button doesn't snap it back to the resting fill.
		setPlayHover(ctx.Accent, ctx.AccentHover)
		if showVolume then
			volumeFill.BackgroundColor3 = accent
		end
		paintShuffle()
		paintLoop()
		paintFavorite()
	end)

	-- ── public handle ────────────────────────────────────────────────────────
	local handle = {}
	handle.Played = bindables.Played.Event
	handle.Paused = bindables.Paused.Event
	handle.NextTrack = bindables.NextTrack.Event
	handle.PreviousTrack = bindables.PreviousTrack.Event
	handle.Seeked = bindables.Seeked.Event
	handle.VolumeChanged = bindables.VolumeChanged.Event
	handle.ShuffleChanged = bindables.ShuffleChanged.Event
	handle.LoopChanged = bindables.LoopChanged.Event
	handle.TrackChanged = bindables.TrackChanged.Event
	handle.Ended = bindables.Ended.Event
	handle.FavoriteChanged = bindables.FavoriteChanged.Event

	function handle:Play()
		doPlay()
	end
	function handle:Pause()
		doPause()
	end
	function handle:TogglePlay()
		if playing then
			doPause()
		else
			doPlay()
		end
	end
	function handle:IsPlaying(): boolean
		return playing
	end
	function handle:Next()
		doNext()
	end
	function handle:Previous()
		doPrevious()
	end
	function handle:Seek(t: number)
		seekTo(t, true)
	end
	function handle:GetProgress(): number
		return elapsed
	end
	function handle:SetProgress(t: number)
		elapsed = clamp(t, 0, math.max(duration, 0))
		renderProgress()
	end
	function handle:GetDuration(): number
		return duration
	end
	function handle:SetDuration(t: number)
		duration = math.max(0, t)
		renderProgress()
	end
	function handle:SetPlaying(v: boolean)
		if v then
			doPlay()
		else
			doPause()
		end
	end
	function handle:GetVolume(): number
		return volume
	end
	function handle:SetVolume(v: number)
		applyVolume(v, true)
	end
	function handle:GetShuffle(): boolean
		return shuffle
	end
	function handle:SetShuffle(v: boolean)
		applyShuffle(v, true)
	end
	function handle:GetLoop(): string
		return loopMode
	end
	function handle:SetLoop(mode: string)
		applyLoop(mode, true)
	end
	function handle:GetTrack()
		return currentPayload()
	end
	function handle:SetTrack(data: any)
		useQueue = false
		loadTrackData(data, playing)
	end
	function handle:SetQueue(list: { any }, startIndex: number?)
		queue = list or {}
		useQueue = #queue > 0
		index = useQueue and math.clamp(math.floor(startIndex or 1), 1, #queue) or 1
		if useQueue then
			loadTrackData(queue[index], false)
		end
	end

	-- ── cleanup ──────────────────────────────────────────────────────────────
	-- Heartbeat + the owned Sound live outside the GUI tree, so they need
	-- explicit teardown — Destroying is the one signal that fires regardless of
	-- who tears down the ancestor (Group/Tab/Window:Destroy).
	f.field.Destroying:Connect(function()
		stopTicking()
		for _, c in soundConns do
			c:Disconnect()
		end
		table.clear(soundConns)
		local snd = activeSound
		if snd then
			if ownsSound then
				snd:Stop()
				snd:Destroy()
			else
				snd:Pause() -- same rule as attachTrackAudio: don't destroy it, don't leave it playing
			end
		end
		activeSound = nil
	end)

	-- ── initial load ─────────────────────────────────────────────────────────
	local initial
	if useQueue then
		initial = queue[index]
	else
		initial = {
			Title = opts.Title,
			Artist = opts.Artist,
			Cover = opts.Cover,
			Duration = opts.Duration,
			SoundId = opts.SoundId,
			Sound = opts.Sound,
		}
	end
	renderVolume()
	loadTrackData(initial, opts.Autoplay == true)

	return f.field, handle, true
end
