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
local DataGrid = require(script.Parent.DataGrid)
local MediaPlayer = require(script.Parent.MediaPlayer)

local Controls = {}

function Controls.new(ctx: any, frame: Frame)
	local items: { { inst: Instance, sep: Frame?, bordered: boolean } } = {}
	local count = 0

	local function refresh()
		local n = #items
		for i, entry in items do
			if entry.sep then
				entry.sep.Visible = entry.bordered and i < n
			end
		end
	end

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
				LayoutOrder = count * 2 + 1,
				Parent = frame,
			})
		end
		table.insert(items, { inst = inst, sep = sep, bordered = bordered })
		refresh()
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
			local where = Log.where(control, opts.Name)
			Log.field(where, "Callback", opts.Callback, "function")
			Log.field(where, "Flag", opts.Flag, "string")
			Log.field(where, "Name", opts.Name, "string")
		end

		local inst, handle, bordered = builder(ctx, opts)
		place(inst, bordered)
		if opts and opts.Flag and kind then
			ctx:RegisterFlag(opts.Flag, handle, kind)
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
		local section, body = Section(ctx, o)
		place(section, true)
		return Controls.new(ctx, body)
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

	function api:DataGrid(o)
		return mount(DataGrid, o, nil, "DataGrid")
	end

	function api:MediaPlayer(o)
		return mount(MediaPlayer, o, nil, "MediaPlayer")
	end

	return api
end

return Controls
