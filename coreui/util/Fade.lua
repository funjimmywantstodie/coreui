--!strict
-- util/Fade.lua — fade a whole subtree in or out WITHOUT a CanvasGroup.
--
-- Why this exists, because it's the single most important rendering rule in this
-- library after "use FontFace, not Font":
--
--   **A CanvasGroup makes text blurry.** It rasterizes its entire subtree into
--   an offscreen buffer at the group's own size and then draws that buffer to
--   the screen. Text inside it is no longer drawn by the SDF renderer at the
--   display's real resolution — it's baked into a bitmap and resampled, so every
--   label comes out soft and smeared. Nothing the user can do fixes it: raising
--   graphics quality doesn't help, resizing the Roblox window doesn't help,
--   because the blur happens before the pixels ever reach the screen.
--
-- CanvasGroup is still the *obvious* way to fade a panel — one GroupTransparency
-- tween and everything inside goes with it — and that's exactly what this
-- library used to do for the window, the popovers, the toasts and the splash.
-- Which meant essentially every character of text in the UI was being rendered
-- through a buffer.
--
-- This is the replacement: snapshot every transparency property in the subtree
-- once, then drive them all from a single tweened NumberValue. Identical result
-- (same easing, everything moves together), no buffer, real text.
--
--   local fade = Fade.new(panel)
--   fade:Set(1)                        -- instantly invisible
--   fade:To(Tween.Normal, 0)           -- fade in
--   fade:To(Tween.MenuOut, 1, done)    -- fade out, then `done`
--
-- Alpha is 0 = "as built" (each instance back at its own resting transparency,
-- which is NOT necessarily 0) and 1 = fully invisible.

local Tween = require(script.Parent.Tween)

local Fade = {}
Fade.__index = Fade

type Target = { inst: Instance, prop: string, base: number }

export type Fade = typeof(setmetatable(
	{} :: {
		root: GuiObject,
		alpha: number,
		_targets: { Target }?,
		_driver: NumberValue?,
		_conn: RBXScriptConnection?,
	},
	Fade
))

-- Every transparency property that actually hides something. A GuiObject can
-- carry several at once (a TextButton has a background AND text), so this is a
-- list of checks, not a lookup.
local function collect(inst: Instance, out: { Target })
	local any: any = inst
	if inst:IsA("GuiObject") then
		table.insert(out, { inst = inst, prop = "BackgroundTransparency", base = any.BackgroundTransparency })
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		table.insert(out, { inst = inst, prop = "TextTransparency", base = any.TextTransparency })
		table.insert(out, { inst = inst, prop = "TextStrokeTransparency", base = any.TextStrokeTransparency })
	end
	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		table.insert(out, { inst = inst, prop = "ImageTransparency", base = any.ImageTransparency })
	end
	if inst:IsA("ScrollingFrame") then
		table.insert(out, { inst = inst, prop = "ScrollBarImageTransparency", base = any.ScrollBarImageTransparency })
	end
	if inst:IsA("UIStroke") then
		table.insert(out, { inst = inst, prop = "Transparency", base = any.Transparency })
	end
	-- Belt and braces: if a CanvasGroup ever shows up inside a faded subtree
	-- again, fade it as a unit rather than walking into it.
	if inst:IsA("CanvasGroup") then
		table.insert(out, { inst = inst, prop = "GroupTransparency", base = any.GroupTransparency })
	end
end

-- Hidden subtrees are skipped whole — an inactive tab page is a few hundred
-- instances that aren't on screen and don't need touching 60 times a second.
local function walk(inst: Instance, out: { Target })
	collect(inst, out)
	if inst:IsA("CanvasGroup") then
		return -- faded as a unit above
	end
	for _, child in inst:GetChildren() do
		if child:IsA("GuiObject") and not child.Visible then
			continue
		end
		walk(child, out)
	end
end

function Fade.new(root: GuiObject): Fade
	return setmetatable({
		root = root,
		alpha = 0,
		_targets = nil,
		_driver = nil,
		_conn = nil,
	}, Fade) :: any
end

-- Snapshot on demand. The cache is dropped again whenever the subtree comes
-- fully back to rest (alpha 0), so the next fade re-reads a tree that may have
-- grown controls in the meantime — and so a snapshot is never taken of a subtree
-- that's currently mid-fade, which would bake the faded values in as the bases.
function Fade:_snapshot()
	if self._targets then
		return
	end
	local targets: { Target } = {}
	walk(self.root, targets)
	self._targets = targets
end

function Fade:_apply(alpha: number)
	self.alpha = alpha
	local targets = self._targets
	if not targets then
		return
	end
	for _, t in targets do
		-- lerp each instance from its own resting value toward fully invisible
		local inst: any = t.inst
		inst[t.prop] = t.base + (1 - t.base) * alpha
	end
end

function Fade:_stop()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	if self._driver then
		self._driver:Destroy()
		self._driver = nil
	end
end

function Fade:Set(alpha: number)
	self:_stop()
	self:_snapshot()
	self:_apply(alpha)
	if alpha <= 0 then
		self._targets = nil -- back at rest
	end
end

-- One NumberValue is tweened and its Changed pushes the alpha out to the whole
-- subtree, so the easing is exactly the same TweenInfo everything else uses.
-- Returns the driver tween (`.Completed` is safe to connect to).
function Fade:To(info: TweenInfo, alpha: number, onDone: (() -> ())?): Tween
	self:_stop()
	self:_snapshot()

	local driver = Instance.new("NumberValue")
	driver.Value = self.alpha
	self._driver = driver
	self._conn = driver.Changed:Connect(function(v: number)
		self:_apply(v)
	end)

	local tween = Tween.play(driver, info, { Value = alpha })
	tween.Completed:Once(function()
		if self._driver ~= driver then
			return -- superseded by a later fade; it owns the state now
		end
		self:_stop()
		self:_apply(alpha) -- land exactly on the goal
		if alpha <= 0 then
			self._targets = nil
		end
		if onDone then
			onDone()
		end
	end)
	return tween
end

function Fade:Destroy()
	self:_stop()
	self._targets = nil
end

return Fade
