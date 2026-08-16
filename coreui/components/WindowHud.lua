--!strict
-- components/WindowHud.lua — the window's bind-HUD ownership.
--
-- Split out of components/Window.lua, which was 2178 lines and eight jobs. This
-- is one of them: building the HUD on demand, merging the two places its options
-- can come from, and the two watcher lists anything mirroring it subscribes to.
-- None of it touches the window's chrome, geometry or tabs.
--
-- Installs `CreateHud` / `GetHud` / `SetHudVisible` / `OnHudVisible` /
-- `OnHudChanged` onto `window`, and returns a teardown the window calls from
-- `Destroy` — the HUD's drag/Heartbeat listeners outlive instances the same way
-- the window's own do.

local Log = require(script.Parent.Parent.util.Log)
local Signal = require(script.Parent.Parent.util.Signal)
local Hud = require(script.Parent.Hud)

return function(window: any, ctx: any, screenGui: ScreenGui, opts: any)
	-- The bind HUD, once something asks for one (components/Hud.lua). It's a
	-- sibling of `main` in the ScreenGui, not a child, so minimize leaves it up.
	local hud: any = nil
	-- Anything mirroring the HUD's visibility — the Settings tab's switch is one,
	-- but a host that builds its own settings UI needs the same signal, so it's a
	-- signal behind `window:OnHudVisible` rather than the panel's private hook it
	-- used to be.
	local hudWatchers = Signal.new() :: any
	-- ...and the same for anything else the HUD persists (its position, whether
	-- it's collapsed), which no visibility signal covers — see Window:OnHudChanged.
	local hudChangeWatchers = Signal.new() :: any

	-- ── settings: the bind HUD ────────────────────────────────────────────────
	-- A small draggable overlay listing every named bind, lit while it's live,
	-- plus FPS / ping — the answer to "what's on right now?" with the menu closed.
	-- It reads util/Bind.lua's registry, so it needs nothing declared twice; a
	-- bind appears as soon as it has a `Label` (the controls pass their `Name`).
	--
	-- Built on demand and only once: `CreateWindow{ Hud = true }`, the Settings
	-- tab's switch and a loaded config all land here.
	function window:CreateHud(hudOpts: any?): any
		if hudOpts ~= nil and type(hudOpts) ~= "table" then
			Log.fail("CreateHud", ("options must be a table like { Title = ... }, got %s")
				:format(typeof(hudOpts)))
		end
		if hud then
			-- Already built — which is the common case, since `CreateWindow{ Hud = true }`
			-- builds one before the caller has run a line of their own code, and
			-- SetHudVisible routes through here too. Returning early swallowed the
			-- options entirely; apply the ones the handle can move at runtime and say
			-- so for the rest, rather than silently ignoring the whole table.
			if type(hudOpts) == "table" then
				local o: any = hudOpts
				if type(o.Title) == "string" then
					hud:SetTitle(o.Title)
				end
				if tonumber(o.X) and tonumber(o.Y) then
					hud:SetPosition(tonumber(o.X) :: number, tonumber(o.Y) :: number)
				end
				if o.Collapsed ~= nil then
					hud:SetCollapsed(o.Collapsed == true)
				end
				if o.Visible ~= nil then
					hud:SetVisible(o.Visible ~= false)
				end
				for _, key in { "MaxRows", "Stats", "Fps", "Ping" } do
					if o[key] ~= nil then
						Log.warn("CreateHud", ("%s is only read when the HUD is first built — the existing HUD keeps its own.")
							:format(key))
					end
				end
			end
			return hud
		end
		-- CreateWindow{ Hud = {...} } is the baseline; a later CreateHud{...} (or the
		-- Settings switch, which passes nothing) overrides field by field.
		local merged: any = {}
		if type(opts.Hud) == "table" then
			for key, value in opts.Hud :: any do
				merged[key] = value
			end
		end
		if type(hudOpts) == "table" then
			for key, value in hudOpts :: any do
				merged[key] = value
			end
		end
		hud = Hud(ctx, screenGui, merged)
		-- Keep the Settings tab's switch in step with the HUD however it moved
		-- (its own :SetVisible, a loaded config, the panel being dismissed).
		hud.OnVisible = function(value: boolean)
			hudWatchers:Fire(value)
		end
		-- Everything the HUD persists — where it sits, whether it's folded, whether
		-- it's up — is moved with the mouse, not through a control, so there's no
		-- callback anywhere for a change notification to hang off. This is that
		-- callback; components/Settings.lua turns it into one for the HUD's flag.
		hud.OnChange = function()
			hudChangeWatchers:Fire()
		end
		return hud
	end

	-- Mirror the HUD's visibility however it moved (its own :SetVisible, a loaded
	-- config, the panel being dismissed). Fires immediately with the current
	-- state, like ctx:RegisterAccent, so a switch built from it starts in step;
	-- returns an unsubscribe.
	function window:OnHudVisible(fn: (boolean) -> ()): () -> ()
		local unsubscribe = hudWatchers:Connect(fn)
		fn(hud ~= nil and hud:IsVisible()) -- the initial state; Signal never replays
		return unsubscribe
	end

	-- Fires whenever anything the HUD *persists* moves — dragged to a new spot,
	-- folded, shown or hidden. Unlike `OnHudVisible` it doesn't fire immediately
	-- (there's no single value to hand you) and it takes no argument: read the
	-- HUD, or just re-save. The built-in Settings tab uses it to keep the HUD's
	-- flag in the change stream, which is the only reason a dragged HUD shows up
	-- in `OnFlagChanged` at all. Returns an unsubscribe.
	function window:OnHudChanged(fn: () -> ()): () -> ()
		return hudChangeWatchers:Connect(fn)
	end

	function window:GetHud(): any
		return hud
	end

	-- Show/hide the HUD, building it the first time it's asked for. Hiding one
	-- that was never built is a no-op rather than a pointless build.
	function window:SetHudVisible(value: boolean)
		if not hud and value == false then
			return
		end
		window:CreateHud():SetVisible(value ~= false)
	end


	return {
		-- Called from Window:Destroy. The HUD's own input listeners outlive the
		-- ScreenGui, same as the window's.
		Destroy = function()
			if hud then
				hud:Destroy()
				hud = nil
			end
		end,
	}
end
