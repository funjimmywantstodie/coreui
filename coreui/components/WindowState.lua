--!strict
-- components/WindowState.lua — the `uranium_window` flag.
--
-- Split out of components/Window.lua. Position, size, maximize, the selected tab
-- and the folded state of every group, persisted as one flag on the same terms
-- as the bind HUD's: every host wants the menu to come back where it was left,
-- and asking each of them to reimplement the clamping and the "that tab doesn't
-- exist any more" fallbacks is how those get written four different ways and
-- wrong three of them.
--
-- This is the one extraction that genuinely reaches back into the window — a
-- restore moves the geometry, picks a tab and folds groups — so it takes those
-- as an explicit `deps` table rather than pretending it doesn't. That the list
-- is short, and that all of it is behaviour rather than state, is what makes the
-- split hold: nothing here can reach a field it wasn't handed.

export type Deps = {
	-- Geometry, in the window's own terms.
	--
	-- `wantedSize` is the size the window ASKED for, which is not the size it is
	-- drawn at: the viewport clamps it, and maximize overrides it entirely. The
	-- wish is what's persisted, so a size chosen on a big monitor survives a
	-- session on a laptop instead of being permanently shrunk to fit it. `setSize`
	-- is its inverse — it sets the wish and lets the window reconcile.
	--
	-- `topLeft` / `moveTo` are the window's top-left in screen pixels, which is
	-- the only coordinate worth persisting (the live Position is a scale/offset
	-- pair whose numbers mean nothing on a viewport of another size). `moveTo`
	-- clamps exactly as a drag does.
	topLeft: () -> Vector2,
	wantedSize: () -> Vector2,
	setSize: (number, number) -> (),
	moveTo: (number, number) -> (),
	setMaximized: (boolean, boolean?) -> (),
	isMaximized: () -> boolean,
	-- Viewport width, or 0 before it has been measured: a snapshot taken on the
	-- frame the window is built must not write down a position resolved against a
	-- zero viewport as if the user had chosen it.
	viewportWidth: () -> number,
	-- Tabs: the list, which one is open, and how to open one WITHOUT announcing it
	-- as a window-state change (restoring a record is not a run of edits).
	tabs: () -> { any },
	selected: () -> number,
	select: (number) -> (),
}

-- No `window` argument, unlike the other two installers: this registers a flag
-- on the Context and installs no public method, so it never needs the handle.
return function(ctx: any, opts: any, deps: Deps)
	-- ── the window-state flag ─────────────────────────────────────────────────
	-- Registered by the library itself, on the same terms as the bind HUD's flag:
	-- every host wants the menu to come back where it was left, and asking each of
	-- them to reimplement the clamping and the "that tab doesn't exist any more"
	-- fallbacks is how those get written four different ways and wrong three of
	-- them. `CreateWindow{ PersistWindow = false }` opts out; `WindowFlag` renames
	-- it, exactly like `HudFlag`.
	local windowFlagName = opts.WindowFlag or "uranium_window"
	local persistWindow = opts.PersistWindow ~= false
	local applyingWindowState = false

	local function windowState(): any
		local groups: { [string]: boolean } = {}
		for _, entry in ctx.Groups do
			groups[entry.key] = entry.handle:IsCollapsed() == true
		end
		-- The size the window WANTS, not the size it's drawn at. Those differ
		-- whenever the viewport clamped it (or it's maximized), and persisting the
		-- drawn one would permanently shrink a size set on a big monitor the first
		-- time the menu opened on a laptop.
		local wanted = deps.wantedSize()
		local record: any = {
			Width = wanted.X,
			Height = wanted.Y,
			Maximized = deps.isMaximized(),
			Tab = deps.selected(),
			Groups = groups,
		}
		-- Position only once the viewport has actually been measured. A snapshot
		-- taken on the frame the window is built (a host that saves immediately)
		-- would otherwise resolve the scale half of the Position against a zero
		-- viewport and record the window as sitting off the top-left corner — a
		-- coordinate that means nothing, written down as if the user had chosen it.
		-- Omitted, the restore just leaves the window where it opens.
		if deps.viewportWidth() > 0 then
			local origin = deps.topLeft()
			record.X = origin.X
			record.Y = origin.Y
		end
		return record
	end

	-- Every field is optional and every one of them is allowed to be wrong: a
	-- record is written by one session and applied by another, with a different
	-- viewport, a different set of tabs (a game script that isn't loaded this
	-- time) and possibly a different build of the menu. Nothing in here errors on
	-- a mismatch — it restores what still makes sense and drops the rest.
	--
	-- Split out from `applyWindowState` below so the suppression flag that call
	-- runs under can be cleared even if something in here does throw.
	local function restoreWindowState(value: any)
		-- Size first (the position clamp is computed against it), then maximize
		-- (which overrides the size), then the position it's clamped into.
		if value.Width and value.Height then
			-- setSize floors and clamps to the window's own minimum, which is where
			-- that rule belongs; this only has to hand it two numbers.
			deps.setSize(value.Width, value.Height)
		end
		if value.Maximized ~= nil then
			deps.setMaximized(value.Maximized == true, false)
		end
		if value.X and value.Y then
			deps.moveTo(value.X, value.Y)
		end

		if value.Tab then
			local index = math.floor(value.Tab)
			local tabs = deps.tabs()
			local target = tabs[index]
			if target and target:IsVisible() then
				deps.select(index)
			else
				-- The saved tab is gone (or hidden) — a config written with a
				-- game-specific tab loaded, restored without it. Fall through to the
				-- first tab that's actually there rather than erroring or leaving the
				-- window on a page nobody can navigate back to.
				for i, other in tabs do
					if other:IsVisible() then
						deps.select(i)
						break
					end
				end
			end
		end

		-- Only groups that still exist under the same key. Anything built after
		-- this runs isn't in the registry yet and keeps its own `Collapsed` option,
		-- which is the same ordering rule as every other flag: state is restored
		-- for the controls that exist when the config is applied.
		if type(value.Groups) == "table" then
			for _, entry in ctx.Groups do
				local collapsed = value.Groups[entry.key]
				if collapsed ~= nil then
					entry.handle:SetCollapsed(collapsed == true, false)
				end
			end
		end
	end

	-- `restoreWindowState` under the notification-suppression flag, which has to
	-- come back down whatever happens in there.
	--
	-- It used to be a bare `flag = true … flag = false` around the body, and the
	-- body is called from inside Context:LoadConfig's pcall — so anything that
	-- threw mid-restore was swallowed upstream and left the flag stuck ON for the
	-- rest of the session. From then on every drag, maximize, tab click and folded
	-- group stopped notifying `uranium_window`: the window silently stopped
	-- persisting, with no error and nothing on screen to say so.
	local function applyWindowState(value: any)
		if type(value) ~= "table" then
			return
		end
		applyingWindowState = true
		local ok, err = pcall(restoreWindowState, value)
		applyingWindowState = false
		if not ok then
			error(err, 0) -- re-raised untouched; LoadConfig names the flag that failed
		end
	end

	if persistWindow then
		ctx:RegisterFlag(windowFlagName, {
			GetFlag = function(): any
				return windowState()
			end,
			SetFlag = function(_, value: any)
				applyWindowState(value)
			end,
		}, "window")
		-- One funnel for everything that moves the record — a drag landing, a
		-- maximize, a tab click, a group folded three components away. Suppressed
		-- while a restore is in flight: applying one record would otherwise report
		-- a change per field, each with a half-applied value, and Context:LoadConfig
		-- announces the finished result once anyway.
		ctx:OnWindowState(function()
			if not applyingWindowState then
				ctx:NotifyFlag(windowFlagName)
			end
		end)
	end

end
