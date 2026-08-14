--!strict
-- util/Gui.lua — where the ScreenGui goes, what it's called, and how we find it
-- again. Everything in here exists because a LocalScript in the place can walk
-- `PlayerGui` and read `Name`.
--
-- **Parenting order** (`Gui.mount`), most hidden first:
--   1. `opts.Parent` — the host already resolved a container; trust it.
--   2. `gethui()`     — the executor's hidden container. Invisible to the place.
--   3. `CoreGui`      — not enumerable by a normal LocalScript.
--   4. `PlayerGui`    — last resort (Studio, and executors with neither global).
--
-- `protect_gui` / `syn.protect_gui` runs FIRST where the global exists, because
-- some executors want to do the reparent themselves. We then set `Parent` ONCE,
-- at the resolved target: the old code parented to PlayerGui and nothing else,
-- and even a "parent here, move it after" would leave a frame where the place
-- can see the instance.
--
-- **Identity is an attribute, not the name.** The ScreenGui used to be called
-- `Theme.Brand.name` ("Uranium") — a fixed, brand-shaped string is the single
-- cheapest thing to detect, and `util/Singleton.lua`'s leftover sweep matched on
-- it, so the name couldn't just be dropped. Instead each load gets a fresh
-- neutral name (`Gui.rname`) and carries `Gui.Attribute` as an attribute;
-- attributes don't show up in an Explorer-style name walk, and the sweep matches
-- on that instead. `Window{ GuiName = "..." }` pins the name if a host wants one.

local Services = require(script.Parent.Services)

local Players = Services.Players

local Gui = {}

-- The identity marker. Set on every ScreenGui we create; the singleton sweep
-- looks for it across all three possible roots.
Gui.Attribute = "__urn"

-- ── neutral names ───────────────────────────────────────────────────────────
-- Fresh every load, so a place can't learn the name from a previous session
-- either. Letters first (instance names starting with a digit are legal but
-- unusual enough to stand out), then letters + digits.
local HEAD = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local TAIL = HEAD .. "0123456789"
local rng = Random.new()

function Gui.rname(minLen: number?, maxLen: number?): string
	local lo = minLen or 10
	local hi = maxLen or 16
	local n = rng:NextInteger(lo, math.max(lo, hi))
	local out = table.create(n)
	local h = rng:NextInteger(1, #HEAD)
	out[1] = HEAD:sub(h, h)
	for i = 2, n do
		local t = rng:NextInteger(1, #TAIL)
		out[i] = TAIL:sub(t, t)
	end
	return table.concat(out)
end

-- ── executor globals ────────────────────────────────────────────────────────
-- Resolved the same way util/Config.lua resolves the file API: the shared env
-- (getgenv) first, then the ambient global. Both reads are pcall-guarded —
-- some sandboxes throw merely on touching getgenv, and this module is required
-- at load time.
local genv: any = nil
pcall(function()
	if type(getgenv) == "function" then
		genv = getgenv()
	end
end)

local function g(name: string): any
	if type(genv) == "table" then
		local ok, v = pcall(function()
			return genv[name]
		end)
		if ok and v ~= nil then
			return v
		end
	end
	local ok2, v2 = pcall(function()
		return (_G :: any)[name]
	end)
	if ok2 and v2 ~= nil then
		return v2
	end
	return nil
end

-- ── containers ──────────────────────────────────────────────────────────────
-- Each returns the container or nil; all of them are pcall-guarded, because
-- `gethui` is executor-only and `CoreGui` throws for an unprivileged script.

function Gui.hidden(): Instance?
	local ok, h = pcall(function()
		local fn = g("gethui")
		-- ...and the ambient global, for executors that inject it into the chunk
		-- env rather than onto getgenv/_G.
		if type(fn) ~= "function" and type(gethui) == "function" then
			fn = gethui
		end
		if type(fn) == "function" then
			return fn()
		end
		return nil
	end)
	if ok and typeof(h) == "Instance" then
		return h
	end
	return nil
end

function Gui.coreGui(): Instance?
	local ok, c = pcall(function()
		return Services.CoreGui
	end)
	if ok and typeof(c) == "Instance" then
		return c
	end
	return nil
end

-- `timeout` is opt-in and only the mount uses it: the sweep runs before the
-- window is built and must not stall the load waiting on a container it's merely
-- checking for leftovers.
function Gui.playerGui(timeout: number?): Instance?
	local ok, pg = pcall(function()
		local lp = Players.LocalPlayer
		if not lp then
			return nil
		end
		local found = lp:FindFirstChildOfClass("PlayerGui")
		if found then
			return found
		end
		if timeout then
			-- Only ever waits when the library loads before PlayerGui replicates,
			-- which is the one case the old `WaitForChild("PlayerGui")` covered.
			return lp:WaitForChild("PlayerGui", timeout)
		end
		return nil
	end)
	if ok and typeof(pg) == "Instance" then
		return pg
	end
	return nil
end

-- Every root a leftover window of ours could be sitting in — the hidden
-- container included, or a window parented there leaks on reload (its record is
-- gone with the old chunk, the sweep never looks in gethui, and the user ends up
-- with two windows stacked).
function Gui.roots(): { Instance }
	local roots: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	for _, get in { Gui.hidden, Gui.coreGui, Gui.playerGui } do
		local root = get()
		if root and not seen[root] then
			seen[root] = true
			table.insert(roots, root)
		end
	end
	return roots
end

-- ── protection + mounting ───────────────────────────────────────────────────

-- `protect_gui(gui)` / `syn.protect_gui(gui)` where they exist. Some executors
-- implement it as "I'll hide and reparent this for you", which is why it runs
-- before we set Parent, not after.
function Gui.protect(inst: Instance): boolean
	local done = false
	pcall(function()
		local fn = g("protect_gui")
		if type(fn) ~= "function" and type(protect_gui) == "function" then
			fn = protect_gui
		end
		if type(fn) == "function" then
			fn(inst)
			done = true
		end
	end)
	if not done then
		pcall(function()
			local s: any = g("syn")
			if type(s) ~= "table" then
				s = syn
			end
			if type(s) == "table" and type(s.protect_gui) == "function" then
				s.protect_gui(inst)
				done = true
			end
		end)
	end
	return done
end

-- Tag + parent, once. Returns `(target, label)` — the label names which branch
-- won, for the verbose log line.
function Gui.mount(inst: Instance, preferred: Instance?): (Instance?, string)
	pcall(function()
		inst:SetAttribute(Gui.Attribute, true)
	end)

	Gui.protect(inst)

	local target: Instance? = nil
	local label = "nowhere"

	if typeof(preferred) == "Instance" then
		target, label = preferred, "opts.Parent"
	end
	if not target then
		target = Gui.hidden()
		if target then
			label = "gethui()"
		end
	end
	if not target then
		target = Gui.coreGui()
		if target then
			label = "CoreGui"
		end
	end
	if not target then
		target = Gui.playerGui(5)
		if target then
			label = "PlayerGui"
		end
	end

	if target then
		local ok = pcall(function()
			inst.Parent = target
		end)
		-- CoreGui can resolve and still refuse the write on a client with no
		-- elevated identity; PlayerGui always accepts it.
		if not ok then
			local fallback = Gui.playerGui(5)
			if fallback and fallback ~= target then
				pcall(function()
					inst.Parent = fallback
				end)
				target, label = fallback, "PlayerGui (fallback)"
			else
				target, label = nil, "nowhere"
			end
		end
	end

	return target, label
end

-- True for a ScreenGui this library created (any run of it, including one whose
-- record was lost). Attribute first; a build older than the neutral-name change
-- is matched by name via the caller's legacy list.
function Gui.isOurs(inst: Instance): boolean
	local ok, v = pcall(function()
		return inst:GetAttribute(Gui.Attribute)
	end)
	return ok and v == true
end

return Gui
