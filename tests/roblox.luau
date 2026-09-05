--!nocheck
-- tests/roblox.luau — just enough Roblox to LOAD the bundle outside Roblox.
--
-- Scope, stated up front so nobody mistakes this for more than it is: this
-- harness proves the module graph **evaluates**. Every one of the 46 modules
-- runs its body, every `require` resolves in an order that works, every
-- load-time constant (Theme's `Color3.fromHex`, Tween's `Enum.EasingStyle`,
-- Bind's mouse tables) is built, and the library table comes back with the API
-- on it. That is the class of breakage you otherwise find by pasting a
-- loadstring into an executor and watching nothing happen.
--
-- It does NOT render anything, and it is not trying to. `Instance.new` returns a
-- permissive table that accepts any property and hands back a stub signal for
-- any event, so nothing here can tell you a frame is the wrong size or a tween
-- looks wrong. Don't grow this into a fake renderer — the moment the stub has
-- opinions about layout it starts failing for reasons that aren't the library's.
--
-- NOT a module: it is concatenated ahead of the bundle by bundle.py into a
-- single chunk, because the luau CLI gives every `require`d module its own
-- environment — globals written in one are invisible to the next, so a stub that
-- was `require`d set Color3/Enum/game for nobody. One chunk, one environment.

local function class(name)
	-- One permissive shape for every datatype: remembers what it was built with,
	-- accepts arithmetic where the real one would, and answers to any method with
	-- another one of itself. Enough for constant folding at module scope.
	local meta
	meta = {
		__index = function(self, key)
			if key == "Name" then
				return rawget(self, "_name") or name
			end
			if key == "Value" then
				return rawget(self, "_value") or 0
			end
			-- Any method call: return something of the same shape.
			return function()
				return setmetatable({ _name = name }, meta)
			end
		end,
		__add = function(a) return a end,
		__sub = function(a) return a end,
		__mul = function(a) return a end,
		__eq = function(a, b) return rawequal(a, b) end,
		__tostring = function() return name end,
	}
	return function(...)
		local args = table.pack(...)
		return setmetatable({ _name = name, _args = args, X = 0, Y = 0 }, meta)
	end
end

local newColor = class("Color3")
Color3 = {
	new = newColor,
	fromHex = newColor,
	fromRGB = newColor,
	fromHSV = newColor,
}
UDim = { new = class("UDim") }
UDim2 = { new = class("UDim2"), fromOffset = class("UDim2"), fromScale = class("UDim2") }
Vector2 = { new = class("Vector2") }
Vector3 = { new = class("Vector3") }
TweenInfo = { new = class("TweenInfo") }
Font = { new = class("Font") }
Random = { new = class("Random") }

-- Enums resolve lazily and memoize, so `Enum.KeyCode.RightShift` is a stable
-- identity — several modules use enum items as TABLE KEYS, which only works if
-- the same name gives back the same value every time.
local enumItem = {}
enumItem.__index = enumItem
enumItem.__tostring = function(self)
	return ("Enum.%s.%s"):format(self.EnumType, self.Name)
end

local function newEnumType(typeName)
	local items = {}
	return setmetatable({ EnumTypeName = typeName }, {
		__index = function(_, name)
			if name == "GetEnumItems" then
				return function()
					local out = {}
					for _, item in items do
						table.insert(out, item)
					end
					return out
				end
			end
			if not items[name] then
				items[name] = setmetatable(
					{ Name = name, Value = 0, EnumType = typeName },
					enumItem
				)
			end
			return items[name]
		end,
	})
end

local enumTypes = {}
Enum = setmetatable({}, {
	__index = function(_, typeName)
		if not enumTypes[typeName] then
			enumTypes[typeName] = newEnumType(typeName)
		end
		return enumTypes[typeName]
	end,
})

-- A stub signal: Connect hands back something with Disconnect, and nothing ever
-- fires. Load-time code only ever *connects*.
local signal = {}
signal.__index = signal
function signal:Connect()
	return { Disconnect = function() end, Connected = false }
end
signal.Once = signal.Connect
function signal:Wait() end

local EVENTS = {
	Changed = true, ChildAdded = true, ChildRemoved = true, Activated = true,
	MouseEnter = true, MouseLeave = true, MouseButton1Down = true,
	InputBegan = true, InputChanged = true, InputEnded = true, Heartbeat = true,
	RenderStepped = true, Stepped = true, Event = true, FocusLost = true,
	Focused = true, PlayerAdded = true, PlayerRemoving = true, Ended = true,
	TextBoxFocused = true, TextBoxFocusReleased = true,
}

local instance = {}
instance.__index = function(self, key)
	local stored = rawget(self, "_props")[key]
	if stored ~= nil then
		return stored
	end
	if EVENTS[key] then
		return setmetatable({}, signal)
	end
	-- Methods: GetChildren/GetDescendants return empty, GetPropertyChangedSignal
	-- returns a signal, everything else is a no-op returning nil.
	return function(_, ...)
		if key == "GetChildren" or key == "GetDescendants" then
			return {}
		end
		if key == "GetPropertyChangedSignal" then
			return setmetatable({}, signal)
		end
		return nil
	end
end
instance.__newindex = function(self, key, value)
	rawget(self, "_props")[key] = value
end

Instance = {
	new = function(className)
		return setmetatable({
			_props = { ClassName = className, Name = className, Parent = nil },
		}, instance)
	end,
}

local services = {}
game = setmetatable({}, {
	__index = function(_, key)
		if key == "GetService" then
			return function(_, name)
				if not services[name] then
					services[name] = Instance.new(name)
				end
				return services[name]
			end
		end
		if EVENTS[key] then
			return setmetatable({}, signal)
		end
		return Instance.new(tostring(key))
	end,
})
workspace = Instance.new("Workspace")

-- `typeof` is Roblox's, not Luau's: it names datatypes ("Color3", "EnumItem")
-- where `type` would say "table". Every option check in util/Log.lua goes
-- through it, so the stub has to answer the same way or validation misfires.
local baseType = type
typeof = function(value)
    if baseType(value) ~= "table" then
        return baseType(value)
    end
    if getmetatable(value) == enumItem then
        return "EnumItem"
    end
    if rawget(value, "_props") ~= nil then
        return "Instance"
    end
    local name = rawget(value, "_name")
    if name ~= nil then
        return name
    end
    return "table"
end

task = task or {
	spawn = function(fn, ...) return fn(...) end,
	defer = function() end,
	delay = function() end,
	wait = function() end,
}

