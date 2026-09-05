--!strict
-- components/Button.lua — single button (bare or titled) + side-by-side ButtonRow.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Tween = require(script.Parent.Parent.util.Tween)
local Field = require(script.Parent.Field)

local function newButton(ctx: any, label: string, accent: boolean, callback: (() -> ())?): TextButton
	local colors = Theme.Colors
	local btn = Create("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 36),
		-- An accent button is a TINTED tile — `AccentSoft` fill, accent edge,
		-- accent text — the same "this is live" language the active nav tile, a
		-- lit bind chip and the HUD's rows speak. It used to be a solid
		-- `accent_fill` slab, which even deepened was the loudest thing on the
		-- page: a card with two of them read as two green bars with a menu around
		-- them. The tile keeps the button unmistakably the primary action (nothing
		-- else at rest carries an accent edge) without painting a slab.
		BackgroundColor3 = accent and ctx.AccentSoft or colors.control,
		Text = label or "Button",
		TextColor3 = accent and ctx.Accent or colors.text,
		TextSize = 13,
		FontFace = Theme.Font.Medium,
	}, {
		Create.corner(Theme.Metrics.controlRadius),
		-- A secondary button rests on the soft edge and firms it under the pointer
		-- (Theme.lua, the two line weights); the accent one wears the accent edge
		-- at rest — that edge is what makes it the primary action.
		Create.stroke(accent and ctx.Accent or colors.border_soft, 1),
		Create("UIScale", {}),
	})
	local stroke = btn:FindFirstChildOfClass("UIStroke") :: UIStroke
	local scale = btn:FindFirstChildOfClass("UIScale") :: UIScale

	local function base(): Color3
		return accent and ctx.AccentSoft or colors.control
	end
	-- Hover: the secondary fill lifts `control` → `control_hi` like every other
	-- control. The tinted tile has no lighter token to lift to, so its fill stays
	-- put and the edge + text light to `AccentHover` instead (below).
	local function over(): Color3
		return accent and ctx.AccentSoft or colors.control_hi
	end
	-- The `hovering` boolean this used to keep is Create.hover's now: its setter
	-- repaints to whichever end applies, so a SetAccent landing while the pointer
	-- is on the button doesn't snap it back to the resting fill.
	local _, setHover = Create.hover(btn, "BackgroundColor3", base(), over())
	local setEdge
	if accent then
		-- Hover brightens edge + text to the accent's hover shade, so the tile
		-- "lights up" the way the old slab did, without ever becoming one.
		setEdge = Create.edge(btn, stroke, ctx.Accent, ctx.AccentHover)
		btn.MouseEnter:Connect(function()
			Tween.play(btn, Tween.Fast, { TextColor3 = ctx.AccentHover })
		end)
		btn.MouseLeave:Connect(function()
			Tween.play(btn, Tween.Fast, { TextColor3 = ctx.Accent })
		end)
	else
		setEdge = Create.edge(btn, stroke, colors.border_soft, colors.border)
	end
	btn.Activated:Connect(function()
		-- quick squash-and-release so the tap feels physical
		scale.Scale = 0.96
		Tween.play(scale, Tween.Spring, { Scale = 1 })
		if callback then
			task.spawn(callback)
		end
	end)

	if accent then
		ctx:RegisterAccent(function()
			setHover(base(), over())
			setEdge(ctx.Accent, ctx.AccentHover)
			btn.TextColor3 = ctx.Accent
		end)
	end
	return btn
end

local Button = {}

function Button.single(ctx: any, opts: any)
	-- titled → stacked field; bare → standalone padded row
	if opts.Name or opts.Desc then
		local f = Field.new(ctx, opts, true)
		local btn = newButton(ctx, opts.Label, opts.Accent == true, opts.Callback)
		btn.LayoutOrder = 2
		btn.Parent = f.field
		return f.field, { element = btn }, true
	end

	local wrap = Create("Frame", {
		Name = "ButtonRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Create.padding(8, 2),
	})
	local btn = newButton(ctx, opts.Label, opts.Accent == true, opts.Callback)
	btn.Parent = wrap
	return wrap, { element = btn }, true
end

function Button.row(ctx: any, list: { any })
	local wrap = Create("Frame", {
		Name = "ButtonRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Create.padding(8, 2),
		Create.listLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
		}),
	})
	local GAP = 10
	local n = #list
	if n == 0 then
		return wrap, {}, true -- empty row: nothing to size (1/n would be a div by zero)
	end
	for i, item in list do
		local btn = newButton(ctx, item.Label, item.Accent == true, item.Callback)
		btn.LayoutOrder = i
		-- Even split without flexbox: each button takes 1/n of the row, minus
		-- its share of the inter-button gaps.
		btn.Size = UDim2.new(1 / n, -(GAP * (n - 1)) / n, 0, 36)
		btn.Parent = wrap
	end
	return wrap, {}, true
end

return Button
