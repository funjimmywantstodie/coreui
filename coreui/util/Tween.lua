--!strict
-- util/Tween.lua — shared tween presets. All UI motion is ease-out ~0.12–0.18s.
--
-- **Motion is optional here, not load-bearing.** `TweenService:Create` is not
-- guaranteed to exist: a client reported `attempt to call a nil value` on
-- exactly that line (Delta, Android, in a place that had also left
-- `Player:GetAttribute` nil — the game had been over the Instance metatable).
-- Every one of the ~67 `Tween.play` call sites is a bare call, so one nil method
-- threw out of all of them and took whole components down with it — a menu that
-- doesn't animate is a nuisance, a menu that errors is broken.
--
-- So `Tween.play` decides **once, on first use**, whether tweening actually
-- works, and where it doesn't it writes the goal properties straight onto the
-- instance and hands back a stub. Two rules behind that:
--
--  * **Probe by use, never by `type(x) == "function"`.** The failure mode is a
--    metatable that answers every index with something callable; a type check
--    passes and the call still returns nothing usable. The probe builds a
--    throwaway instance the library owns, runs a real `Create`/`Play`/`Cancel`
--    on it, and requires a `.Completed` to come back.
--  * **One funnel, no guards at the call sites** — same reason
--    `util/Services.lua` is one funnel. 67 `if` statements is 67 chances to
--    forget one.
--
-- The stub satisfies every caller's contract: `:Play()`, `:Cancel()`, and a
-- `.Completed` answering `:Once(state)` / `:Connect(state)` / `:Wait()`. The
-- properties are already at their goal by the time it's returned, so Completed
-- fires (and Wait returns) immediately with `Enum.PlaybackState.Completed`. That
-- part is not cosmetic: a `Once` that never fires leaves Collapse's `activeTween`
-- set forever and the panel stuck half-open, and does the same to Window's page
-- slide and Fade's driver.

local Services = require(script.Parent.Services)
local Log = require(script.Parent.Log)

local TweenService = Services.TweenService

local Tween = {}

local OUT = Enum.EasingStyle.Quad
local DIR = Enum.EasingDirection.Out

Tween.Fast   = TweenInfo.new(0.12, OUT, DIR) -- hovers, borders
Tween.Normal = TweenInfo.new(0.18, OUT, DIR) -- toggle, chevron
Tween.Spin   = TweenInfo.new(0.26, Enum.EasingStyle.Back, DIR) -- collapse chevrons (slight overshoot)
Tween.Spring = TweenInfo.new(0.28, Enum.EasingStyle.Back, DIR) -- knobs / pops that should overshoot
Tween.Press  = TweenInfo.new(0.09, Enum.EasingStyle.Quad, DIR) -- button tap squash
Tween.Pop    = TweenInfo.new(0.16, Enum.EasingStyle.Back, DIR) -- popovers / window in
Tween.Slide  = TweenInfo.new(0.22, Enum.EasingStyle.Quint, DIR) -- panel collapse/expand, search reveal (smooth, no overshoot)
Tween.MenuOut = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In) -- window leaving (accelerate + fade away)
Tween.Toast  = TweenInfo.new(0.22, Enum.EasingStyle.Quint, DIR)
Tween.ToastOut = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- ── the fallback ────────────────────────────────────────────────────────────
-- Read once, defensively: handlers compare the state they're handed against
-- this exact value, so the stub has to report the same thing a real tween does.
local COMPLETED: any = nil
pcall(function()
	COMPLETED = Enum.PlaybackState.Completed
end)

-- Already-disconnected, because the event it would have carried has happened.
local DEAD_CONNECTION = {
	Connected = false,
	Disconnect = function() end,
}

-- The goals are on the instance before the caller ever sees this, so subscribing
-- to Completed is subscribing to something already over: fire on connect.
-- `task.spawn` resumes immediately (so it lands this frame, like the properties
-- did) while keeping a handler that errors out of the caller's stack.
local completedSignal = {}
completedSignal.__index = completedSignal

function completedSignal:Connect(fn: any): any
	if type(fn) == "function" then
		task.spawn(fn, COMPLETED)
	end
	return DEAD_CONNECTION
end

completedSignal.Once = completedSignal.Connect

function completedSignal:Wait(): any
	return COMPLETED
end

-- One shared stub: every method on it is a no-op, so there is no per-call state
-- worth allocating.
local STUB: any = {
	PlaybackState = COMPLETED,
	Completed = setmetatable({}, completedSignal),
	Play = function() end,
	Pause = function() end,
	Cancel = function() end,
	Destroy = function() end,
}

-- pcall PER PROPERTY: without motion, a goal the engine won't accept under this
-- name is one dropped property, not a dropped animation.
local function applyDirect(instance: Instance, goals: { [string]: any })
	for prop, value in goals do
		pcall(function()
			(instance :: any)[prop] = value
		end)
	end
end

local supported: boolean? = nil

local function probe(): boolean
	local ok = pcall(function()
		local dummy = Instance.new("NumberValue")
		local t = TweenService:Create(dummy, Tween.Fast, { Value = 1 })
		t:Play()
		t:Cancel()
		if t.Completed == nil then
			error("no Completed")
		end
		dummy:Destroy()
	end)
	return ok
end

function Tween.play(instance: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	if supported == nil then
		supported = probe()
		if not supported then
			-- Once, on the first tween of the session — not per call, or a hover
			-- fills the console.
			Log.warn(
				"Tween",
				"TweenService is unavailable in this game — applying values instantly instead of animating"
			)
		end
	end

	if supported then
		local tween = TweenService:Create(instance, info, goals)
		tween:Play()
		return tween
	end

	applyDirect(instance, goals)
	return STUB
end

return Tween
