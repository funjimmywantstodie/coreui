--!strict
-- components/Settings.lua — the built-in settings panel, as three INDEPENDENT
-- group builders rather than one sealed tab.
--
-- `Window:CreateSettingsTab` composes all three (that's still the one-line
-- drop-in), but the panel used to be all-or-nothing: a host with its own config
-- UI got the library's Configuration group whether it wanted it or not, couldn't
-- switch it off, and couldn't even fake it off — the group tested util/Config.lua's
-- own `supported` flag rather than the public `window.ConfigSupported`. So:
--
--   * `CreateSettingsTab{ Sections = { Config = false } }` drops a section, and
--   * every builder here is public (`Uranium.Settings.ConfigGroup(window, tab)`),
--     so a host can compose its own settings tab out of the parts it likes and
--     put its own controls in between.
--
-- Everything below goes through the PUBLIC window API — nothing reaches into the
-- Context, the flag registry or util/Config.lua directly. That's deliberate: it's
-- the proof that a host can build the same panel, and it means the auto-load
-- pointer (the one config path that used to bypass `window:`) is interceptable
-- like every other.

local Theme = require(script.Parent.Parent.Theme)
local Log = require(script.Parent.Parent.util.Log)
local Signal = require(script.Parent.Parent.util.Signal)

local Settings = {}

-- Toasts, unless the caller said not to. A host that wraps the window's config
-- methods to add its own rules (per-place scoping, say) already tells the user
-- why a load was refused; the panel piling a generic "Couldn't load X" on top of
-- that is noise it had no way to suppress.
local function notifier(window: any, opts: any): (string) -> ()
	local enabled = not (opts and opts.Notify == false)
	return function(text: string)
		if enabled then
			window:Notify({ Title = "Config", Text = text })
		end
	end
end

-- "Couldn't load "x" — corrupt JSON." out of the `(ok, reason)` pair.
local function because(text: string, reason: string?): string
	if type(reason) == "string" and reason ~= "" then
		return ("%s — %s."):format(text, reason)
	end
	return text .. "."
end

local function group(tab: any, opts: any, title: string, column: number): any
	if opts.Group then
		return opts.Group
	end
	return tab:CreateGroup({ Title = opts.Title or title, Column = opts.Column or column })
end

-- Where control descriptions are drawn, as the user picks it. Capitalized for the
-- dropdown and handed to `SetDescriptions` unchanged — it lowercases — so the
-- persisted value is the label the user saw rather than a second vocabulary.
local DESCRIPTION_OPTIONS = { "Hover", "Inline", "Both" }
local DESCRIPTION_LABELS: { [string]: string } = {
	hover = "Hover",
	inline = "Inline",
	both = "Both",
}

-- The minimized card's shape, as the user picks it. Same deal as the
-- descriptions labels above: capitalized for the dropdown, handed to
-- `SetMinimizeHintStyle` unchanged.
local HINT_STYLE_OPTIONS = { "Auto", "Card", "Logo" }
local HINT_STYLE_LABELS: { [string]: string } = {
	auto = "Auto",
	card = "Card",
	logo = "Logo",
}

-- ── Interface ────────────────────────────────────────────────────────────────
-- Accent colour, the toggle keybind, descriptions, the minimize hint,
-- notifications, the bind HUD switch. Returns
-- `{ Group, Accent, ToggleKey, Descriptions, MinimizeHint, MinimizeHintStyle,
-- Notifications, Hud }`.
function Settings.InterfaceGroup(window: any, tab: any, opts: any?): any
	local o: any = opts or {}
	local g = group(tab, o, "Interface", 1)
	local controls: any = { Group = g }

	controls.Accent = g:Colorpicker({
		Name = "Accent Color",
		Desc = "Re-themes the whole UI.",
		Flag = o.AccentFlag or "uranium_accent",
		Default = window:GetAccent(),
		Callback = function(c)
			window:SetAccent(c)
		end,
	})
	controls.ToggleKey = g:Keybind({
		Name = "Toggle UI",
		Desc = "Show or hide the window.",
		Flag = o.ToggleKeyFlag or "uranium_togglekey",
		Default = window:GetToggleKey(),
		Callback = function(k)
			window:SetToggleKey(k)
		end,
	})
	-- Not on a phone: the row describes a key the device can't press, and the
	-- minimize hint already resolves to the logo tile there. The flag still
	-- registers (a config round-trips either way); only the row stands down.
	-- Re-applied when the device answer moves, like everything else that reads it.
	local function fitToggleKey(touch: boolean)
		controls.ToggleKey:SetVisible(not touch)
	end
	fitToggleKey(window:IsTouch())
	controls.TouchWatch = window:OnTouch(fitToggleKey)
	-- The library moved descriptions off the row and behind a hover glyph by
	-- default, which is a change to how the whole menu reads — so the user gets the
	-- old look back from here rather than needing the hub author to pass an option.
	-- Unlike the HUD switch below this IS the flag: the mode isn't persisted
	-- anywhere else, so there's nothing for a second one to fight with on load.
	controls.Descriptions = g:Dropdown({
		Name = "Descriptions",
		Desc = "Hover for a popover, inline for a line under each name.",
		-- ...and this row is the one place `Desc` must never be hover-only: a user
		-- who has just set the mode to "Inline" and wants to change it back can't be
		-- asked to hover the control that explains hovering.
		Info = false,
		Flag = o.DescriptionsFlag or "uranium_descriptions",
		Options = DESCRIPTION_OPTIONS,
		Default = DESCRIPTION_LABELS[window:GetDescriptions()],
		Width = 110,
		Callback = function(mode)
			window:SetDescriptions(mode)
		end,
	})

	-- `Hud = false` on the switches below: they're preferences about the UI, not
	-- features running in the game, and the bind HUD lists what's running. Left to
	-- the default rule they'd all qualify — a keyless toggle that's ON is listed —
	-- so every user would open the panel to find "Notifications" and, absurdly,
	-- "Keybind HUD" at the top of it.

	-- The minimized card. It's the only on-screen answer to "where did the menu
	-- go?" — and, since it's clickable, the only way back at all on a device with
	-- no keyboard to press the toggle key on — so it stays on by default — but it's also the one piece of the UI
	-- that's deliberately visible when everything else is hidden, which is exactly
	-- what someone recording or screenshotting with the menu closed wants rid of.
	controls.MinimizeHint = g:Toggle({
		Name = "Minimize Hint",
		Desc = "Show the corner card that reopens the UI when the UI is hidden.",
		Flag = o.MinimizeHintFlag or "uranium_minimizehint",
		Default = window:GetMinimizeHint(),
		Hud = false,
		Callback = function(on)
			window:SetMinimizeHint(on)
		end,
	})
	-- Its OWN flag rather than a third state folded into the switch above: on/off
	-- and card/logo are two settings, and a config written before this existed
	-- still loads its boolean into the switch with nothing to disagree with.
	-- Capitalized labels handed to the setter unchanged (it lowercases), like the
	-- Descriptions dropdown above.
	controls.MinimizeHintStyle = g:Dropdown({
		Name = "Hint Style",
		Desc = "How the minimized card is drawn.",
		Info = {
			Fields = {
				{ "Auto", "Logo on touch, card with a keyboard" },
				{ "Card", "Mark, title and the reopen line" },
				{ "Logo", "The mark on its own" },
			},
		},
		Flag = o.MinimizeHintStyleFlag or "uranium_minimizehintstyle",
		Options = HINT_STYLE_OPTIONS,
		Default = HINT_STYLE_LABELS[window:GetMinimizeHintStyle()],
		Width = 110,
		Callback = function(style)
			window:SetMinimizeHintStyle(style)
		end,
	})

	controls.Notifications = g:Toggle({
		Name = "Notifications",
		Desc = "Show toast notifications.",
		Flag = o.NotificationsFlag or "uranium_notifications",
		Default = window:GetNotificationsEnabled(),
		Hud = false,
		Callback = function(on)
			window:SetNotificationsEnabled(on)
		end,
	})

	-- The bind HUD switch. Deliberately NOT flagged itself: the HUD is the source
	-- of truth (it also persists its position and collapsed state), and two flags
	-- for one thing would fight each other on load. Instead the flag below proxies
	-- to the HUD — built on demand, so a config that has it off never creates one —
	-- and the switch mirrors whatever the HUD ends up at. Both directions no-op
	-- when already in step, so the sync can't loop.
	local hud = window:GetHud()
	local hudSwitch = g:Toggle({
		Name = "Keybind HUD",
		Desc = "Floating panel: active binds, FPS and ping.",
		Default = hud ~= nil and hud:IsVisible(),
		Hud = false,
		Callback = function(on)
			local live = window:GetHud()
			if live and live:IsVisible() == on then
				return
			end
			window:SetHudVisible(on)
		end,
	})
	controls.Hud = hudSwitch
	-- Fires once immediately with the HUD's current state, so the switch is in
	-- step even if the HUD moved between being built and this tab existing.
	controls.HudMirror = window:OnHudVisible(function(value: boolean)
		if hudSwitch:Get() ~= value then
			hudSwitch:Set(value)
		end
	end)
	local hudFlag = o.HudFlag or "uranium_hud"
	window:RegisterFlag(hudFlag, {
		GetFlag = function(): any
			local live = window:GetHud()
			return live and live:GetFlag() or { Visible = false }
		end,
		SetFlag = function(_, value: any)
			if type(value) ~= "table" then
				return
			end
			if value.Visible == true then
				window:CreateHud():SetFlag(value)
			else
				local live = window:GetHud()
				if live then
					live:SetFlag(value)
				end
			end
		end,
	}, "hud")
	-- The HUD's state moves with the mouse, so nothing in the flag system hears
	-- about it on its own — a host persisting on change (`Window:OnFlagChanged`)
	-- would miss a dragged or folded HUD entirely. This is the one flag whose
	-- change notification has to be wired by whoever registered it.
	controls.HudChanges = window:OnHudChanged(function()
		window:NotifyFlag(hudFlag)
	end)

	return controls
end

-- ── Configuration ────────────────────────────────────────────────────────────
-- Save / load / delete + the auto-load pointer. Returns
-- `{ Group, Name, List, AutoLoad, Refresh, Save, Load, Delete }` — the handles
-- used to be locals in a closure, so a host couldn't refresh the list after its
-- own write, read what was selected, or hang its own button off the selection.
--
-- `Notify = false` silences the panel's own toasts. A host wrapping
-- `window:LoadConfig` can also return `false, "handled"` from its wrapper to
-- suppress the failure toast for one call while keeping the rest.
function Settings.ConfigGroup(window: any, tab: any, opts: any?): any
	local o: any = opts or {}
	local g = group(tab, o, "Configuration", 2)
	local controls: any = { Group = g }
	local say = notifier(window, o)

	-- The PUBLIC flag, not util/Config.lua's own — a host that wants the library's
	-- config UI to stand down (because it owns persistence itself) can set
	-- `window.ConfigSupported = false` and get the same honest "unavailable" panel
	-- an executor without file access gets.
	if not window.ConfigSupported then
		controls.Unavailable = g:Paragraph({
			Title = "Unavailable",
			Body = o.UnavailableText
				or "Your executor doesn't expose file functions, so configs can't "
					.. "be saved. Everything else here still works.",
		})
		-- There's no dropdown on this panel, so nothing can ever be picked — but a
		-- host subscribing unconditionally shouldn't index nil for it.
		controls.OnSelect = function(_fn: (string?) -> ()): () -> ()
			return function() end
		end
		return controls
	end

	local nameBox = g:Input({ Name = "Config Name", Placeholder = "my config" })
	local list: any
	local autoSwitch: any

	-- Picking a saved config fills the name box with it, so the obvious gesture —
	-- pick "main", press Save — overwrites the config you just picked instead of
	-- silently writing a second one under whatever stale text the box still held.
	-- `filled` is the name WE last put there: anything else in the box is the
	-- user's own typing and is never clobbered. Clearing the selection clears
	-- nothing, for the same reason.
	local filled: string? = nil
	local function prefill(name: string?)
		if name == nil or name == "" then
			return
		end
		local cur = nameBox:Get()
		-- `cur == name` adopts a name the user typed and then saved (`save` re-selects
		-- it), so the pick after that one is fillable again.
		if cur == nil or cur == "" or cur == filled or cur == name then
			filled = name
			nameBox:Set(name)
		end
	end

	-- The selection as a signal. A host whose list isn't a flat set of local file
	-- names — Uranium itself lists other games' configs as "main - Some Game" —
	-- has to substitute the real name after a pick, and could only do that by
	-- polling `List:Get()`: `controls` handed back the box and the dropdown but no
	-- event. A watcher that writes the box wins over the prefill above, and what it
	-- wrote becomes the new `filled`, so the next pick isn't mistaken for typing.
	local watchers = Signal.new() :: any
	local lastPick: string? = nil
	local function fireSelect(name: string?)
		if watchers:Count() == 0 then
			return
		end
		local before = nameBox:Get()
		-- Guarded: a host's bookkeeping blowing up doesn't take the pick down with
		-- it, same contract as OnFlagChanged's watchers.
		watchers:FireGuarded(function(err)
			Log.warn("Settings.OnSelect", tostring(err))
		end, name)
		local after = nameBox:Get()
		if after ~= before then
			filled = after
		end
	end

	-- Auto Load points at whatever is selected NOW. It used to be written only
	-- from the switch's own callback, so picking a different config afterwards
	-- left the pointer on the old one — and flipping the switch on with nothing
	-- selected wrote nil, silently clearing it while the switch read "on".
	local function syncAutoload()
		if not autoSwitch then
			return
		end
		local on = autoSwitch:Get()
		local name = list:Get()
		if on and (name == nil or name == "") then
			window:SetAutoload(nil)
			autoSwitch:Set(false) -- re-enters here with `on` false; terminates
			say("Pick a config to auto-load first.")
			return
		end
		window:SetAutoload(on and name or nil)
	end

	-- The dropdown's one callback: fill the name box, point auto-load at the new
	-- selection, then tell the host. Deduped against the last name we announced, so
	-- the `list:Set` in `save` (and in the auto-load pass) is silent when it lands
	-- on what's already picked.
	local function picked(name: string?)
		prefill(name)
		syncAutoload()
		if name == lastPick then
			return
		end
		lastPick = name
		fireSelect(name)
	end

	list = g:Dropdown({
		Name = "Saved Configs",
		Placeholder = "None saved",
		Stack = true,
		Options = window:ListConfigs(),
		Callback = picked,
	})
	local function refresh()
		list:SetOptions(window:ListConfigs())
	end
	-- Re-scoping persistence (window:SetConfigFolder — per-place folders, profiles)
	-- makes this list a different folder's; it fires once immediately, which is a
	-- harmless second read of the list we just built.
	controls.FolderWatch = window:OnConfigFolder(function()
		refresh()
	end)

	local function save()
		local n = nameBox:Get()
		if n == nil or n == "" then
			say("Enter a name first.")
			return
		end
		local ok, reason = window:SaveConfig(n)
		if ok then
			refresh()
			list:Set(n)
			say(('Saved "%s".'):format(n))
		elseif reason ~= "handled" then
			say(because(('Couldn\'t save "%s"'):format(n), reason))
		end
	end

	local function load()
		local n = list:Get()
		if not n then
			say("Pick a config to load.")
			return
		end
		local ok, reason = window:LoadConfig(n)
		if ok then
			say(('Loaded "%s".'):format(n))
		elseif reason ~= "handled" then
			-- Saying nothing on failure made a missing or corrupt file look like a
			-- dead button; saying only "Couldn't load" made it look like a bug. The
			-- reason comes straight off the (ok, reason) pair.
			say(because(('Couldn\'t load "%s"'):format(n), reason))
		end
	end

	local function remove()
		local n = list:Get()
		if not n then
			say("Pick a config to delete.")
			return
		end
		local deleted, reason = window:DeleteConfig(n)
		refresh()
		if deleted then
			say(('Deleted "%s".'):format(n))
		elseif reason ~= "handled" then
			say(because(('Couldn\'t delete "%s"'):format(n), reason))
		end
	end

	g:ButtonRow({
		{ Label = "Save", Callback = save },
		{ Label = "Load", Callback = load },
	})
	g:ButtonRow({
		{ Label = "Delete", Callback = remove },
		{ Label = "Refresh", Callback = refresh },
	})
	autoSwitch = g:Toggle({
		Name = "Auto Load",
		Desc = "Apply the selected config on launch.",
		Default = window:GetAutoload() ~= nil,
		Hud = false, -- a config preference, not a feature (see InterfaceGroup)
		Callback = syncAutoload,
	})

	controls.Name = nameBox
	controls.List = list
	controls.AutoLoad = autoSwitch
	-- `fn(name)` on every selection change, `nil` when the selection is dropped.
	-- No initial call — there's nothing selected when this returns. Returns an
	-- unsubscribe, like the window's own watchers.
	controls.OnSelect = function(fn: (string?) -> ()): () -> ()
		return watchers:Connect(fn)
	end
	controls.Refresh = refresh
	controls.Save = save
	controls.Load = load
	controls.Delete = remove

	-- Apply the auto-load config once the rest of the UI has finished building
	-- (this tab is meant to be created last, so all flags exist). `AutoLoad = false`
	-- opts out for a host that decides itself what to apply on boot.
	if o.AutoLoad ~= false then
		task.defer(function()
			local auto = window:GetAutoload()
			if auto then
				list:Set(auto)
				window:LoadConfig(auto)
			end
		end)
	end

	return controls
end

-- ── Danger Zone ──────────────────────────────────────────────────────────────
-- Pass `Group` (the Configuration group) to append into it behind a divider,
-- which is where it has always lived; without one it gets its own card, so a tab
-- built with `Sections = { Config = false }` still has an unload button.
function Settings.DangerGroup(window: any, tab: any, opts: any?): any
	local o: any = opts or {}
	local inline = o.Group ~= nil
	local g = group(tab, o, "Danger Zone", 2)
	local controls: any = { Group = g }
	if inline then
		g:Divider()
	end
	controls.Unload = g:Button({
		Name = inline and "Danger Zone" or nil,
		Label = o.Label or ("Unload " .. Theme.Brand.name),
		-- Deferred for the same reason the titlebar â is (see Window.lua's close
		-- button): this runs on the engine's Activated thread, where a write into
		-- a protected GUI container can be refused, and the teardown has to be able
		-- to make those writes. Never deferred on the `immediate` path.
		Callback = function()
			task.defer(function()
				window:Destroy()
			end)
		end,
	})
	return controls
end

-- ── the whole panel ──────────────────────────────────────────────────────────
-- What `Window:CreateSettingsTab` calls. `opts.Sections` switches sections off
-- individually (`{ Config = false }`); everything else is forwarded to the
-- builders. Returns the flat control table the tab hands back alongside itself.
function Settings.build(window: any, tab: any, opts: any?): any
	local o: any = opts or {}
	local sections: any = o.Sections or {}
	if type(sections) ~= "table" then
		Log.warn("CreateSettingsTab", ("Sections must be a table like { Config = false }, got %s"
			.. " — building all of them."):format(typeof(sections)))
		sections = {}
	end
	local controls: any = {}

	-- Copied, never edited in place: `o.Config` / `o.Danger` are the caller's own
	-- tables, and a loader that reuses one options table across two windows
	-- shouldn't find our defaults baked into it afterwards.
	local function sub(key: string): any
		local out: any = {}
		if type(o[key]) == "table" then
			for k, v in o[key] :: any do
				out[k] = v
			end
		end
		return out
	end

	if sections.Interface ~= false then
		local iface = Settings.InterfaceGroup(window, tab, sub("Interface"))
		controls.Interface = iface.Group
		controls.Accent = iface.Accent
		controls.ToggleKey = iface.ToggleKey
		controls.Notifications = iface.Notifications
		controls.Hud = iface.Hud
		-- Carried through for the same reason as the config group's below: a host
		-- that tears its own settings UI down needs the unsubscribers, and there is
		-- no second way to reach them once this returns.
		controls.HudMirror = iface.HudMirror
		controls.HudChanges = iface.HudChanges
		controls.TouchWatch = iface.TouchWatch
	end

	local cfgGroup: any = nil
	if sections.Config ~= false then
		local cfgOpts: any = sub("Config")
		if cfgOpts.Notify == nil then
			cfgOpts.Notify = o.Notify -- `CreateSettingsTab{ Notify = false }` covers the panel
		end
		local cfg = Settings.ConfigGroup(window, tab, cfgOpts)
		cfgGroup = cfg.Group
		controls.Configuration = cfg.Group
		controls.Name = cfg.Name
		controls.List = cfg.List
		controls.AutoLoad = cfg.AutoLoad
		controls.Refresh = cfg.Refresh
		controls.Save = cfg.Save
		controls.Load = cfg.Load
		controls.Delete = cfg.Delete
		-- The selection event, and the unsubscriber for the folder watch. These
		-- were built by ConfigGroup and then dropped on the floor here, which made
		-- `OnSelect` — a documented part of what CreateSettingsTab hands back, and
		-- the only way to correct the name box for a list whose entries aren't file
		-- names — a nil index for everyone who reached it the documented way. The
		-- ConfigSupported = false branch returns a no-op OnSelect for the same
		-- reason, so this is never nil.
		controls.OnSelect = cfg.OnSelect
		controls.FolderWatch = cfg.FolderWatch
	end

	if sections.Danger ~= false then
		local dangerOpts: any = sub("Danger")
		if dangerOpts.Group == nil then
			dangerOpts.Group = cfgGroup -- nil when Config is off → its own card
		end
		local danger = Settings.DangerGroup(window, tab, dangerOpts)
		controls.Danger = danger.Group
		controls.Unload = danger.Unload
	end

	return controls
end

return Settings
