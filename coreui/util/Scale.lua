--!strict
-- util/Scale.lua — the global UI scale, and the coordinate space that comes
-- with it.
--
-- ~97% of Uranium's sessions are phones, and a phone hands Roblox a viewport of
-- roughly 1200×560. So the window is never *cramped* there — it's the opposite:
-- the content clears every width threshold the library has and a phone gets the
-- full desktop layout, at desktop metrics, on a six-inch screen. 11px body text
-- at that physical size is unreadable and a 40px touch target is a quarter of an
-- inch. The touch layout (bigger rows, labelled nav tiles, ≥40px targets) fixes
-- the *shapes*; none of it makes anything bigger than it was designed to be.
--
-- One `UIScale` over everything the library draws does. The awkward half is that
-- Roblox gives it to you in mixed units: `screenGui.AbsoluteSize` stays the raw
-- viewport, every scaled child's `AbsoluteSize`/`AbsolutePosition` comes back
-- multiplied, and every offset you *write* is multiplied on the way out. Every
-- clamp in the library compares one to the other. So this module owns both
-- halves — the scale itself, and the single answer to "how big is the screen, in
-- the units I write positions in" (`:Viewport()`), which is what the window, the
-- bind HUD, the popovers and the flyouts all measure against.
--
--   layout px   what you write: Size/Position offsets, Theme.Metrics, MIN_W…
--   physical px what you read: AbsoluteSize, AbsolutePosition, InputObject.Position
--   physical = layout × scale
--
-- Divide a measured number by `:Get()` before you write it back as an offset, or
-- the write lands `scale`× off. `Context:LayoutSize` / `Context:Viewport` are the
-- shorthands components use for exactly that.

local Services = require(script.Parent.Services)

local Create = require(script.Parent.Create)
local Gui = require(script.Parent.Gui)
local Log = require(script.Parent.Log)
local Signal = require(script.Parent.Signal)

local Scale = {}
Scale.__index = Scale

-- The range a scale may be pinned to. Below 0.75 the 10px type in the chrome
-- stops being legible at all; above 2.0 a phone has no room left for content.
local MIN, MAX = 0.75, 2
-- Auto resolves in 5% steps, so a viewport a few pixels different from another
-- phone's doesn't produce a scale nobody can name.
local STEP = 0.05

-- The auto rule, and it is deliberately a small one:
--
--   * A desktop is left at 1.0, always. The library was designed at these
--     metrics on a monitor, and nothing about a 1080p screen needs fixing.
--   * A touch device is scaled so its SHORT side is worth about `AUTO_REF`
--     layout pixels. A phone's ~560 becomes 1.5; a tablet's ~1000 is already
--     roomy and lands back at 1.0. `AUTO_REF` is the one number here worth
--     arguing about, so here is the arithmetic behind it: a ~1200px-wide
--     viewport on a ~5.7in-wide screen is ~210 physical pixels per inch, which
--     puts a 44px touch target at 0.21in — well under the ~0.3in every phone
--     platform asks for — and 13px body text at 1.6mm of cap height. At 1.5
--     those become 0.31in and 2.4mm, which is the point of the exercise.
--
-- `AUTO_MAX` is well under `MAX`: the touch layout already spends bumps on the
-- target-size half of the problem (44px HUD rows, a 32px slider track, 12px
-- field text), and auto only has to cover legibility on top of them. Anything
-- more than this is the user's call, from the Settings panel.
local AUTO_REF = 840
local AUTO_MAX = 1.6

export type Deps = {
	-- The device answer, per call — Context:IsTouch, or the engine's own before a
	-- Context exists. Never cached: an executor can run before the input devices
	-- have reported themselves.
	isTouch: () -> boolean,
	-- The smallest window the layout survives (components/Window.lua's
	-- MIN_W/MIN_H), in layout px. Auto never picks a scale that stops that
	-- fitting on screen — the floor and the space available have to be in the
	-- same space or the window clamps itself bigger than the phone it's on.
	minSize: Vector2,
}

local function clamp(n: number): number
	return math.clamp(n, MIN, MAX)
end

-- ── the stage ────────────────────────────────────────────────────────────────
-- A full-screen frame under the ScreenGui with ONE UIScale in it. Everything the
-- library draws is parented here rather than into the ScreenGui directly — the
-- window, its shadow, the minimized hint, the bind HUD, the splash — because
-- several of those are siblings of the window frame rather than children of it,
-- and a UIScale under `main` alone would scale the window and leave the HUD at
-- 1.0 beside it.
--
-- Its size is `fromScale(1/s, 1/s)`, which is the whole trick: the engine
-- resolves that against the raw viewport and the UIScale multiplies it straight
-- back, so the stage covers the screen exactly (physical = vp) while measuring
-- `vp / s` in its own units. No viewport read, nothing to keep in sync, and it's
-- correct on the frame it's built — before AbsoluteSize has ever been reported.
function Scale.new(screenGui: ScreenGui, deps: Deps): any
	local uiScale = Create("UIScale", { Scale = 1 })
	local stage = Create("Frame", {
		-- Neutral name for the same reason every other direct child of the
		-- ScreenGui has one (util/Gui.lua): it's as visible to a walk of the tree
		-- as the window itself.
		Name = Gui.rname(),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		-- A plain transparent Frame doesn't sink input, so nothing about putting
		-- the whole UI inside one changes what receives a press.
		Parent = screenGui,
	}, {
		uiScale,
	})

	return setmetatable({
		Stage = stage,
		UIScale = uiScale,
		-- The number in force. `_pinned` is what the USER asked for — nil means
		-- "auto", which is the default and the case that matters: nobody should
		-- have to find a setting to get a usable window on the device 97% of them
		-- are on.
		Value = 1,
		_pinned = nil :: number?,
		_isTouch = deps.isTouch,
		_minSize = deps.minSize,
		_watchers = Signal.new(),
	}, Scale)
end

-- The viewport in LAYOUT pixels — the units every offset in the library is
-- written in. This is the number a clamp wants, never `screenGui.AbsoluteSize`.
function Scale:Viewport(): Vector2
	local size = self.Stage.AbsoluteSize
	local value = self.Value
	if value <= 0 then
		return size
	end
	return Vector2.new(size.X / value, size.Y / value)
end

-- A measured (physical) number in layout px. The one conversion every component
-- doing arithmetic on an AbsoluteSize needs.
function Scale:ToLayout(n: number): number
	local value = self.Value
	return if value > 0 then n / value else n
end

function Scale:Get(): number
	return self.Value
end

-- Is the scale being resolved from the device, or did someone pin it?
function Scale:IsAuto(): boolean
	return self._pinned == nil
end

-- The screen, in physical pixels. The stage answers this once it's on screen —
-- but the window resolves its scale while it's still building, before the
-- ScreenGui has been parented, and an unparented GUI reports nothing. So the
-- camera is asked first: getting this right on the first resolve is the
-- difference between the window opening at its size and the window opening at
-- 1.0 and jumping. Guarded, and a failure just means auto stays at 1 until the
-- first AbsoluteSize report re-runs it.
local function screenSize(stage: GuiObject): Vector2
	local size = Vector2.zero
	pcall(function()
		size = Services.Workspace.CurrentCamera.ViewportSize
	end)
	if size.X <= 0 then
		size = stage.AbsoluteSize
	end
	return size
end

-- What auto would pick right now. Returns 1 before the viewport can be measured
-- at all — the first AbsoluteSize report re-runs it (Window connects `Refresh`
-- to the same signal the touch layout re-resolves on).
function Scale:Auto(): number
	local vp = screenSize(self.Stage)
	if vp.X <= 0 or vp.Y <= 0 then
		return 1
	end
	if not self._isTouch() then
		return 1
	end
	local short = math.min(vp.X, vp.Y)
	local wanted = math.floor((AUTO_REF / short) / STEP + 0.5) * STEP
	wanted = math.clamp(wanted, 1, AUTO_MAX)
	-- ...but never so large that the window's own minimum stops fitting. At 1.6
	-- a 420×320 floor is 672×512 physical, which is most of a phone and all of a
	-- short one, and a window clamped bigger than the screen is the exact bug
	-- components/Window.lua's `targetSize` comment already warns about.
	local fit = self._minSize
	if fit.X > 0 and fit.Y > 0 then
		wanted = math.min(wanted, vp.X / fit.X, vp.Y / fit.Y)
	end
	return clamp(wanted)
end

-- Write a resolved number in. Everything mode-dependent in the library re-lays
-- out off the watcher list, so this is the single point a scale change passes
-- through however it was caused (a pin, a device change, a rotation).
function Scale:_apply(value: number)
	value = clamp(value)
	if math.abs(value - self.Value) < 0.001 then
		return
	end
	self.Value = value
	self.UIScale.Scale = value
	-- The stage keeps covering the viewport exactly: bigger scale, fewer layout
	-- pixels to draw in.
	self.Stage.Size = UDim2.fromScale(1 / value, 1 / value)
	-- Guarded: a host's own OnScale watcher blowing up must not stop the window
	-- and the HUD from re-placing themselves.
	self._watchers:FireGuarded(function(err)
		Log.warn("OnScale", tostring(err))
	end, value)
end

-- Pin the scale, or hand it back to auto with nil. Returns the number in force
-- afterwards, so a caller can echo the result into its own control rather than
-- assume the write landed (`SetDescriptions` has the same shape).
function Scale:Set(value: number?): number
	if value == nil then
		self._pinned = nil
		self:_apply(self:Auto())
		return self.Value
	end
	self._pinned = clamp(value)
	self:_apply(self._pinned :: number)
	return self.Value
end

-- Re-resolve auto. A no-op when the scale is pinned — a viewport change doesn't
-- get to overrule the user.
function Scale:Refresh()
	if self._pinned ~= nil then
		return
	end
	self:_apply(self:Auto())
end

-- `fn(scale)` whenever it changes. No initial call: read `:Get()`.
function Scale:OnChange(fn: (number) -> ()): () -> ()
	return self._watchers:Connect(fn)
end

Scale.Min = MIN
Scale.Max = MAX

return Scale
