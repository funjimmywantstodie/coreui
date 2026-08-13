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
		BackgroundColor3 = accent and ctx.Accent or colors.control,
		Text = label or "Button",
		TextColor3 = accent and colors.white or colors.text,
		TextSize = 13,
		FontFace = Theme.Font.Medium,
	}, {
		Create.corner(Theme.Metrics.controlRadius),
		Create.stroke(accent and colors.accent or colors.border, 1),
		Create("UIScale", {}),
	})
	local stroke = btn:FindFirstChildOfClass("UIStroke") :: UIStroke
	if accent then
		stroke.Transparency = 1
	end
	local scale = btn:FindFirstChildOfClass("UIScale") :: UIScale

	local hovering = false
	local function base(): Color3
		return accent and ctx.Accent or colors.control
	end
	local function over(): Color3
		return accent and ctx.AccentHover or colors.control_hi
	end
	btn.MouseEnter:Connect(function()
		hovering = true
		Tween.play(btn, Tween.Fast, { BackgroundColor3 = over() })
	end)
	btn.MouseLeave:Connect(function()
		hovering = false
		Tween.play(btn, Tween.Fast, { BackgroundColor3 = base() })
	end)
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
			btn.BackgroundColor3 = hovering and over() or base()
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
