-- standalone/screen.prelude.lua — the dependency-free half of `ui/screen.lua`.
--
-- `bundle.py` builds the standalone status page by gluing this file on top of
-- the SHARED BODY of coreui/components/Screen.lua (everything after that file's
-- `--@body` marker, minus its `--@lib` regions). So there is one implementation
-- of the page and two preludes: the library's requires the rest of the library,
-- this one inlines the little it needs.
--
-- If you change a name the body uses, change it in BOTH preludes — the contract
-- is written out at the `--@body` marker and is the only thing holding the two
-- builds together.
--
-- Constraints this file exists to satisfy (see the task in DOCS.md → Screen):
--   * It is inlined into a Lua reply and evaluated as `(function(...) … end)()`,
--     so everything here must be legal INSIDE A FUNCTION BODY. `...` is read
--     once, at the top, and must be optional — the caller passes nothing.
--   * Nothing may call our own API — the client running this has just been
--     refused by it. Icons are Roblox-hosted `rbxassetid` spritesheet slices,
--     never an https image. The ONE exception is the brand mark: a single
--     `HttpGet` of a static file on the art host, off-thread, after the page is
--     already up, guarded end to end — see `loadLogo` below for why that one
--     earns its place and why nothing else should follow it.
--   * No library, no globals from the hub, no singleton, no `require`.
--
-- Lines tagged `--@inject NAME` are REPLACED WHOLE by bundle.py with values
-- pulled out of the library source, so the palette, the icon slices, the brand
-- name and the ScreenGui identity attribute can't drift from Theme.lua /
-- LucideData.lua / util/Gui.lua. They're written as valid Lua here so the file
-- still parses.

local passed = ...

-- A host service cache if one was handed in (`loadstring(src)(Services)`),
-- otherwise our own, cloned with `cloneref` where the executor has it — the
-- same deal util/Services.lua offers. Every lookup is guarded: this is the
-- code that runs when things are already going wrong.
local CACHE: any = type(passed) == "table" and passed or nil

local function service(name: string): any
	if CACHE then
		local okCache, cached = pcall(function()
			return CACHE[name]
		end)
		if okCache and cached then
			return cached
		end
	end
	local ok, svc = pcall(function()
		local s = game:GetService(name)
		return (type(cloneref) == "function") and cloneref(s) or s
	end)
	return ok and svc or nil
end

local UIS = service("UserInputService")
local TS = service("TweenService")

-- ── theme ───────────────────────────────────────────────────────────────────
local C = {} --@inject COLORS

local GOTHAM = "rbxasset://fonts/families/GothamSSm.json"
local F = {
	Bold = Font.new(GOTHAM, Enum.FontWeight.Bold),
	Medium = Font.new(GOTHAM, Enum.FontWeight.Medium),
	Regular = Font.new(GOTHAM, Enum.FontWeight.Regular),
	Mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular),
}

-- ── instances (util/Create.lua, inlined) ────────────────────────────────────
local function new(className: string, props: any?, children: any?): any
	local inst = Instance.new(className)
	local parent
	if props then
		for key, value in pairs(props) do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	inst.Parent = parent
	return inst
end

local function corner(radius: number): any
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(color: any, thickness: number?): any
	return new("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

local function pad(top: number, right: number?, bottom: number?, left: number?): any
	right = right or top
	bottom = bottom or top
	left = left or right
	return new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom),
		PaddingLeft = UDim.new(0, left),
	})
end

local function list(props: any?): any
	local layout = new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Vertical,
	})
	if props then
		for key, value in pairs(props) do
			(layout :: any)[key] = value
		end
	end
	return layout
end

-- ── tweens (util/Tween.lua, the four presets the page uses) ─────────────────
local OUT = Enum.EasingDirection.Out
local QUAD = Enum.EasingStyle.Quad
local TW = {
	Fast = TweenInfo.new(0.12, QUAD, OUT),
	Normal = TweenInfo.new(0.18, QUAD, OUT),
	Pop = TweenInfo.new(0.16, Enum.EasingStyle.Back, OUT),
	MenuOut = TweenInfo.new(0.2, QUAD, Enum.EasingDirection.In),
}

-- Falls back to setting the goals outright if TweenService didn't resolve, so a
-- page still appears (unanimated) rather than erroring on its way up.
local function tw(inst: any, info: any, goals: any): any
	if not TS then
		for key, value in pairs(goals) do
			inst[key] = value
		end
		return nil
	end
	local tween = TS:Create(inst, info, goals)
	tween:Play()
	return tween
end

-- ── icons (Lucide 48px slices, lifted from LucideData.lua) ──────────────────
-- Spritesheet ids are Roblox assets: the engine fetches them itself, and an
-- unknown name degrades to a glyph exactly like Icons.lua does.
local ICONS = {} --@inject ICONS

local function newIcon(name: string, size: number, color: any): any
	local entry = ICONS[name]
	if entry then
		return new("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size, size),
			Image = "rbxassetid://" .. entry[1],
			ImageRectSize = Vector2.new(entry[2][1], entry[2][2]),
			ImageRectOffset = Vector2.new(entry[3][1], entry[3][2]),
			ImageColor3 = color,
			ScaleType = Enum.ScaleType.Stretch,
		})
	end
	return new("TextLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Text = "•",
		TextColor3 = color,
		TextSize = size,
		FontFace = F.Medium,
	})
end

local function tintIcon(icon: any, color: any)
	if icon:IsA("ImageLabel") then
		icon.ImageColor3 = color
	elseif icon:IsA("TextLabel") then
		icon.TextColor3 = color
	end
end

-- ── the brand mark ──────────────────────────────────────────────────────────
-- `BRAND` is injected from Theme.lua so this build's wordmark can't drift from
-- the library's.
--
-- The art is the harder half, and this file does the whole of what
-- util/Asset.lua does for it: disk cache → `getcustomasset`, and on a miss,
-- `HttpGet` → magic-byte check → `writefile` → `getcustomasset`. `MARK` (the
-- cache path), `ZOOM` and `LOGO_URL` are injected from Theme.lua / Asset.lua so
-- this build downloads the same file to the same place the library does — a
-- second copy under a second name would be a silent waste of a request.
--
-- **This is the one network call on this page, and it was a deliberate
-- exception to the "fetches nothing" rule**, made after the cache-only version
-- shipped and turned out to be useless in practice: the audience for a refusal
-- page is people the API just said no to, so the library never ran, so it never
-- wrote the cache — the one user guaranteed *not* to have the file is the user
-- looking at this page. The exception is narrow and safe to keep that way:
--
--   * It is a **static file on the art host**, never our API. The reason this
--     page must not call home is that home is what just failed; GitHub raw
--     isn't home, and it's where the library gets the same bytes.
--   * It runs **off-thread and after the page is already up**. `done(false)`
--     fires first, so the fallback mark is drawn and the page is interactive
--     before any of this starts. A hung request costs nothing but the logo.
--   * Every leg is guarded, and any failure just leaves the accent square that
--     is already on screen. The PNG check is the same one Asset.lua makes, for
--     the same reason: a 404 body written to `<name>.png` would poison the
--     cache for the library too.
--
-- If the mark ever gets an uploaded `rbxassetid://`, delete all of this — an id
-- the engine fetches itself needs no network of ours, no file access, and no
-- exception.
local BRAND = "Uranium" --@inject BRAND
local MARK, ZOOM, LOGO_URL = "", 1, "" --@inject MARK

local PNG = "\137PNG\r\n\26\n"

-- Never reports `true`: the square + initial stays underneath, so a path that
-- resolves to something the engine won't render leaves the fallback mark rather
-- than a hole. The art is a full-bleed opaque tile, so when it does render it
-- covers the square anyway.
local function loadLogo(image: any, done: any)
	done(false)
	if MARK == "" then
		return
	end
	task.spawn(function()
		local content: any = nil
		pcall(function()
			local get = getcustomasset or getsynasset or get_custom_asset
			if type(get) ~= "function" then
				return
			end
			if type(isfile) == "function" and isfile(MARK) then
				content = get(MARK)
				return
			end
			if type(writefile) ~= "function" or LOGO_URL == "" then
				return
			end
			local body = game:HttpGet(LOGO_URL)
			if type(body) ~= "string" or string.sub(body, 1, 8) ~= PNG then
				return
			end
			-- makefolder doesn't create parents, so walk the path a segment at a
			-- time exactly like util/Asset.lua's ensureFolder.
			if type(makefolder) == "function" and type(isfolder) == "function" then
				local built = ""
				for segment in string.gmatch(MARK, "[^/]+") do
					if string.find(segment, "%.") then
						break -- the filename, not a folder
					end
					built = built == "" and segment or (built .. "/" .. segment)
					if not isfolder(built) then
						makefolder(built)
					end
				end
			end
			writefile(MARK, body)
			content = get(MARK)
		end)
		-- The page can have closed while that was in flight.
		if type(content) == "string" and content ~= "" and image.Parent then
			image.Size = UDim2.fromScale(ZOOM, ZOOM)
			image.Image = content
		end
	end)
end

-- ── fade (util/Fade.lua, compact) ───────────────────────────────────────────
-- Same contract and the same reason it isn't a CanvasGroup: a group rasterizes
-- its subtree into a buffer and the text comes out soft. Snapshot every
-- transparency in the tree once, then drive them all off one NumberValue.
-- Alpha 0 = as built (each instance at its OWN resting value), 1 = invisible.
local function newFade(root: any): any
	local self: any = {}
	local targets: any = nil
	local driver: any, conn: any = nil, nil
	local alpha = 0

	local function collect(inst: any, out: any)
		if inst:IsA("GuiObject") then
			table.insert(out, { inst, "BackgroundTransparency", inst.BackgroundTransparency })
			if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
				table.insert(out, { inst, "TextTransparency", inst.TextTransparency })
			end
			if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
				table.insert(out, { inst, "ImageTransparency", inst.ImageTransparency })
			end
			if inst:IsA("ScrollingFrame") then
				table.insert(out, { inst, "ScrollBarImageTransparency", inst.ScrollBarImageTransparency })
			end
		elseif inst:IsA("UIStroke") then
			table.insert(out, { inst, "Transparency", inst.Transparency })
		end
		for _, child in ipairs(inst:GetChildren()) do
			if not (child:IsA("GuiObject") and not child.Visible) then
				collect(child, out)
			end
		end
	end

	local function snapshot()
		if targets then
			return
		end
		targets = {}
		collect(root, targets)
	end

	local function put(a: number)
		alpha = a
		if not targets then
			return
		end
		for _, t in ipairs(targets) do
			t[1][t[2]] = t[3] + (1 - t[3]) * a
		end
	end

	local function stop()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if driver then
			driver:Destroy()
			driver = nil
		end
	end

	local function land(a: number, done: any)
		stop()
		put(a)
		if a <= 0 then
			targets = nil
		end
		if done then
			done()
		end
	end

	function self:Set(a: number)
		stop()
		snapshot()
		put(a)
		if a <= 0 then
			targets = nil
		end
	end

	function self:To(info: any, a: number, done: any)
		stop()
		snapshot()
		local value = Instance.new("NumberValue")
		value.Value = alpha
		driver = value
		conn = value.Changed:Connect(put)
		local tween = tw(value, info, { Value = a })
		if not tween then
			land(a, done)
			return
		end
		tween.Completed:Once(function()
			if driver ~= value then
				return
			end
			land(a, done)
		end)
	end

	function self:Destroy()
		stop()
		targets = nil
	end

	return self
end

-- ── where the ScreenGui goes (util/Gui.lua, the parts with no library) ──────
local ATTR = "__urn" --@inject ATTR

local ALPHA = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

local function gname(): string
	local out = {}
	for i = 1, 12 do
		local n = math.random(1, #ALPHA)
		out[i] = string.sub(ALPHA, n, n)
	end
	return table.concat(out)
end

-- protect_gui first (some executors reparent it themselves), then the most
-- hidden container that will actually accept the write. Every step guarded:
-- CoreGui resolves and still refuses the assignment on an unprivileged client.
local function mountGui(gui: any, preferred: any)
	pcall(function()
		gui:SetAttribute(ATTR, true)
	end)
	pcall(function()
		if type(protect_gui) == "function" then
			protect_gui(gui)
		elseif type(syn) == "table" and type(syn.protect_gui) == "function" then
			syn.protect_gui(gui)
		end
	end)

	local targets = {}
	if typeof(preferred) == "Instance" then
		table.insert(targets, preferred)
	end
	pcall(function()
		if type(gethui) == "function" then
			local hidden = gethui()
			if typeof(hidden) == "Instance" then
				table.insert(targets, hidden)
			end
		end
	end)
	local core = service("CoreGui")
	if core then
		table.insert(targets, core)
	end
	pcall(function()
		local players = service("Players")
		local player = players and players.LocalPlayer
		if player then
			local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
			if pg then
				table.insert(targets, pg)
			end
		end
	end)

	for _, target in ipairs(targets) do
		local ok = pcall(function()
			gui.Parent = target
		end)
		if ok and gui.Parent == target then
			return
		end
	end
end
