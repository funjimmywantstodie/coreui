--!strict
-- components/Controls.lua — the control surface shared by Group cards and
-- Sections. Owns the container, dispatches to component builders, and manages
-- the 1px "between-field" separators (drawn after every bordered item except
-- the last, mirroring the CSS `:last-child` border rule).

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Log = require(script.Parent.Parent.util.Log)

local Toggle = require(script.Parent.Toggle)
local Slider = require(script.Parent.Slider)
local Dropdown = require(script.Parent.Dropdown)
local Input = require(script.Parent.Input)
local Code = require(script.Parent.Code)
local Keybind = require(script.Parent.Keybind)
local Colorpicker = require(script.Parent.Colorpicker)
local Button = require(script.Parent.Button)
local Paragraph = require(script.Parent.Paragraph)
local Label = require(script.Parent.Label)
local Divider = require(script.Parent.Divider)
local List = require(script.Parent.List)
local Player = require(script.Parent.Player)
local PlayerSelect = require(script.Parent.PlayerSelect)
local Section = require(script.Parent.Section)
local Custom = require(script.Parent.Custom)
local Image = require(script.Parent.Image)
local Picker = require(script.Parent.Picker)
local DataGrid = require(script.Parent.DataGrid)
local MediaPlayer = require(script.Parent.MediaPlayer)

-- The options EVERY control takes, checked here so each component only declares
-- what it adds on top (its own `SCHEMA`). `Desc` and `Default` are deliberately
-- absent: `Desc` is Field's, and `Default` is a different type per control.
--
-- `FireDefault` is here rather than in nine component SCHEMAs for the same
-- reason `Callback` is: it means the same thing, and is the same type, on every
-- stateful control. Each component still owns the *firing* — the value it hands
-- over (and, for Keybind, the whole callback signature) is its own contract, so
-- it fires from its own builder once its handle exists.
--
-- **Opt-in, and it has to stay opt-in.** A consumer that applies its own default
-- at build time (`if opts.Default then apply(true) end` — the shape every hub
-- that wraps this library ends up writing) would run it twice if this fired
-- unconditionally. Making it unconditional is possible, but only in lockstep
-- with those wrappers dropping their own line; see the note in
-- DOCS.md § Common conventions, which is where that coupling is written down.
local COMMON_SCHEMA: Log.Schema = {
	{ "Name", "string" },
	{ "Callback", "function" },
	{ "Flag", "string" },
	{ "FireDefault", "boolean" },
}

local Controls = {}

-- `inheritParent` is the bind-HUD parent (util/Bind.lua's tree) a Group or
-- Section declared for everything inside it — see the note on `mount` below.
function Controls.new(ctx: any, frame: Frame, inheritParent: any?)
	local items: { { inst: Instance, sep: Frame?, bordered: boolean } } = {}
	local count = 0
	-- `Parent = true` on the container: the first bindable control in it is the
	-- feature, and everything bindable after it is a sub-option of that one. It's
	-- the "Aimbot / Sticky Aim / Wall Check / Auto Fire" card written the way it's
	-- always written, without having to repeat the feature's name — which is the
	-- shape that made the bind HUD unreadable in the first place. Resolved to a
	-- name here rather than a handle so it behaves exactly like the explicit form.
	local autoParent: any = nil

	-- The invariant every separator is kept at: visible iff its own item is
	-- bordered AND something still follows it (the CSS `:last-child` rule the
	-- reference draws). Only TWO of them can move when an item is appended — the
	-- new one (nothing follows it yet) and the previous one (something does now) —
	-- so that's all this touches. Re-deriving the whole list on every insert made
	-- building a card quadratic in its control count, for no answer that differed.
	local function place(inst: Instance, bordered: boolean)
		count += 1
		;(inst :: any).LayoutOrder = count * 2
		inst.Parent = frame

		local sep: Frame? = nil
		if bordered then
			sep = Create("Frame", {
				Name = "Separator",
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = Theme.Colors.border_soft,
				BorderSizePixel = 0,
				Visible = false, -- last item so far; the next `place` turns it on
				LayoutOrder = count * 2 + 1,
				Parent = frame,
			})
		end
		local previous = items[#items]
		if previous and previous.sep then
			previous.sep.Visible = previous.bordered
		end
		table.insert(items, { inst = inst, sep = sep, bordered = bordered })
	end

	-- Build via a component, drop it in, register it as a flag (if it carries one
	-- and a serializable `kind`), then hand back the control's handle.
	-- `label` is the human name used in diagnostics (defaults to the kind).
	local function mount(builder: (any, any) -> (Instance, any, boolean), opts: any, kind: string?, label: string?): any
		-- Generic option shape checks shared by every control, so a bad Callback
		-- or a table where a value was expected fails with a readable message
		-- instead of erroring deep inside the component builder.
		local control = label or (kind and (kind:gsub("^%l", string.upper))) or "Control"
		if opts ~= nil and type(opts) ~= "table" then
			Log.fail(control, ("options must be a table, got %s (write %s({ Name = ... }))")
				:format(typeof(opts), control))
		end
		if opts then
			Log.check(Log.where(control, opts.Name), opts, COMMON_SCHEMA)
		end

		-- A Group / Section built with `Parent = "<feature>"` hands that down to
		-- every bindable control inside it, so a card full of sub-options declares
		-- it once at the top instead of on every line — which is the shape the bind
		-- HUD's roll-up (util/Bind.lua `Binding:IsListed`) is worth having. An
		-- explicit `Parent` on the control itself still wins, and controls that
		-- aren't bindable ignore the field.
		-- `false` means "this container resolved to no feature" (see api:Section) and
		-- is skipped like nil — otherwise it was cloned onto every control's
		-- `Parent`, where util/Bind.lua's refKey discards it anyway.
		local bindable = kind == "toggle" or kind == "bind"
		-- ...and of those, the ones that can actually GO LIVE. A `Keybind` defaults
		-- to `Mode = "None"` — a pure key picker, which never activates and is never
		-- listed in the bind HUD (util/Bind.lua `Binding:IsListed`). Only a control
		-- that can be *running* is allowed to be the feature a `Parent = true` card
		-- is named after: letting a picker claim the slot pointed every toggle in
		-- the card at a parent that can never appear, and a keyless sub-option is
		-- only listed when it has no parent — so the whole card silently dropped out
		-- of the HUD. Inheriting a parent is still fine for a picker (it's invisible
		-- either way); it's claiming one that isn't.
		local activates = kind == "toggle"
			or (kind == "bind" and opts ~= nil and type(opts.Mode) == "string"
				and opts.Mode:lower() ~= "none")
		if bindable and inheritParent ~= nil and inheritParent ~= false
			and opts ~= nil and opts.Parent == nil then
			if inheritParent ~= true then
				opts = table.clone(opts)
				opts.Parent = inheritParent
			elseif autoParent == nil then
				-- `Parent = true`: the first bindable control here IS the feature, so
				-- it claims the slot rather than filling one. `false` = it had neither
				-- a Flag nor a Name, so there's nothing later controls could point at.
				-- A picker leaves the slot open for whatever comes next instead.
				if activates then
					autoParent = opts.Flag or opts.Name or false
				end
			elseif autoParent then
				opts = table.clone(opts)
				opts.Parent = autoParent
			end
		end

		-- Change notification (Context:OnFlagChanged) hangs off the control's own
		-- callbacks rather than off each component's internals: every stateful
		-- control already fires `Callback` on every value change — a click, a drag,
		-- a `:Set`, a config landing — and updates its state before it does, so one
		-- wrapper here covers every kind instead of a hook per component.
		--
		-- `OnChanged` is wrapped for the same reason: a Keybind in an activation
		-- mode spends `Callback` on activation, and re-keying it (which is what
		-- moves the flag) only reaches `OnChanged`.
		--
		-- The wrappers go on a COPY. `opts` is the caller's table and a loader that
		-- reuses one across two controls must not find our closure baked into it —
		-- same rule components/Settings.lua follows for its section options.
		local flag = opts and opts.Flag
		local watched = flag ~= nil and kind ~= nil
		local handle: any = nil
		if watched then
			local copy = table.clone(opts)
			local onCallback, onChanged = opts.Callback, opts.OnChanged
			local function notify()
				-- `handle` is nil only if a control fires a callback from inside its
				-- own constructor, before we've been handed it — which is exactly what
				-- `FireDefault` does, and skipping it there is the right answer twice
				-- over: the flag isn't registered yet (RegisterFlag runs below), and a
				-- control taking its Default is never a flag *change*.
				if handle then
					ctx:NotifyFlag(flag)
				end
			end
			-- Notified BEFORE the caller's own callback: a callback that yields
			-- (or errors) shouldn't delay or swallow the notification, and the
			-- ambient source tag is still the one the change came in under.
			copy.Callback = function(...)
				notify()
				if onCallback then
					return onCallback(...)
				end
				return nil
			end
			copy.OnChanged = function(...)
				notify()
				if onChanged then
					return onChanged(...)
				end
				return nil
			end
			opts = copy
		end

		local inst, built, bordered = builder(ctx, opts)
		handle = built
		place(inst, bordered)
		if watched then
			ctx:RegisterFlag(flag, handle, kind)
		end
		-- Every mounted control can be hidden and shown as a ROW — the field and
		-- the hairline under it together, so a hidden control doesn't leave a
		-- stray separator behind. It exists so a panel can stand a row down on a
		-- device where it means nothing (the Settings tab's Toggle-UI key on a
		-- phone) through the public API alone. A control that already has its own
		-- SetVisible keeps it.
		if type(handle) == "table" and handle.SetVisible == nil then
			local item = items[#items]
			function handle:SetVisible(value: boolean)
				local visible = value ~= false
				;(inst :: any).Visible = visible
				if item.sep then
					item.sep.Visible = visible and item.bordered and item ~= items[#items]
				end
			end
			function handle:IsVisible(): boolean
				return (inst :: any).Visible == true
			end
		end
		return handle
	end

	local api = {}

	function api:Toggle(o) return mount(Toggle, o, "toggle") end
	function api:Slider(o) return mount(Slider, o, "slider") end
	function api:Input(o) return mount(Input, o, "input") end
	function api:Code(o) return mount(Code, o, "code") end
	-- "bind" (not "keybind") — the flag persists the key AND the mode.
	function api:Keybind(o) return mount(Keybind, o, "bind", "Keybind") end
	function api:Colorpicker(o) return mount(Colorpicker, o, "colorpicker") end
	function api:Paragraph(o) return mount(Paragraph, o, nil, "Paragraph") end
	function api:Label(o) return mount(Label, o, nil, "Label") end
	function api:Divider() return mount(Divider, {}, nil, "Divider") end
	function api:Player(o) return mount(Player, o, nil, "Player") end
	-- Source is caller-owned content (an id / path / url), not a settable value,
	-- so it gets no Flag codec — same call as Custom / DataGrid.
	function api:Image(o) return mount(Image, o, nil, "Image") end
	function api:List(o) return mount(List, o, nil, "List") end

	function api:Dropdown(o)
		return mount(function(c, opts)
			return Dropdown(c, opts, false)
		end, o, "dropdown")
	end
	function api:MultiDropdown(o)
		return mount(function(c, opts)
			return Dropdown(c, opts, true)
		end, o, "dropdown")
	end

	function api:PlayerSelect(o)
		return mount(function(c, opts)
			return PlayerSelect(c, opts, false)
		end, o, "playerselect")
	end
	function api:PlayerMultiSelect(o)
		return mount(function(c, opts)
			return PlayerSelect(c, opts, true)
		end, o, "playerselect")
	end

	function api:Button(o)
		Log.field(Log.where("Button", o and o.Name), "Callback", o and o.Callback, "function")
		local inst, handle, bordered = Button.single(ctx, o)
		place(inst, bordered)
		return handle
	end
	function api:ButtonRow(list)
		if type(list) ~= "table" then
			Log.fail("ButtonRow", ("expects an array of { Label = ..., Callback = ... } buttons, got %s")
				:format(typeof(list)))
		end
		local inst, handle, bordered = Button.row(ctx, list)
		place(inst, bordered)
		return handle
	end

	function api:Section(o)
		if o ~= nil and type(o) ~= "table" then
			Log.fail("Section", ("options must be a table like { Title = ... }, got %s"):format(typeof(o)))
		end
		Log.field(Log.where("Section", o and o.Title), "Parent", o and o.Parent, { "string", "boolean", "table" })
		local section, body = Section(ctx, o)
		place(section, true)
		-- A section is the natural place to say "everything under here belongs to
		-- that feature" — one line above eight sub-toggles. Falls through to the
		-- card's own declaration when the section doesn't make one; under a
		-- `Parent = true` card that means the feature the card already picked, so a
		-- section of sub-options doesn't start a second one of its own.
		--
		-- Spelled out rather than `(cond and autoParent) or inheritParent`: under a
		-- `Parent = true` card whose first bindable control had neither a Flag nor a
		-- Name, `autoParent` is the sentinel `false` — and the idiom fell straight
		-- through it to `inheritParent` (`true`), so the section started hunting for
		-- a feature of its own and every control in it became a sub-option of the
		-- section's first one. There is no feature to point at in that case; "no
		-- parent" is the honest answer.
		local inherit = o and o.Parent
		if inherit == nil then
			if inheritParent == true and autoParent ~= nil then
				inherit = autoParent -- the card's feature, or `false` for "there isn't one"
			else
				inherit = inheritParent
			end
		end
		return Controls.new(ctx, body, inherit)
	end

	-- Escape hatch: `builder(ctx, frame)` parents whatever it wants into `frame`.
	-- No Flag/kind — content is caller-owned, not a config-serializable value.
	function api:Custom(builder: ((any, Frame) -> ())?)
		if builder ~= nil and type(builder) ~= "function" then
			Log.fail("Custom", ("expects a builder function builder(ctx, frame), got %s"):format(typeof(builder)))
		end
		return mount(function(c, _opts)
			return Custom(c, builder)
		end, nil, nil, "Custom")
	end

	-- Stateful, unlike Image / DataGrid: the value is which item is picked, and
	-- "which skin is equipped" is exactly the kind of thing a config should hold.
	-- The `Items` themselves are caller-owned content and never persist.
	function api:Picker(o)
		return mount(Picker, o, "picker")
	end

	function api:DataGrid(o)
		return mount(DataGrid, o, nil, "DataGrid")
	end

	function api:MediaPlayer(o)
		return mount(MediaPlayer, o, nil, "MediaPlayer")
	end

	return api
end

return Controls
