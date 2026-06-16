--!strict
-- util/Tween.lua — shared tween presets. All UI motion is ease-out ~0.12–0.18s.

local TweenService = game:GetService("TweenService")

local Tween = {}

local OUT = Enum.EasingStyle.Quad
local DIR = Enum.EasingDirection.Out

Tween.Fast   = TweenInfo.new(0.12, OUT, DIR) -- hovers, borders
Tween.Normal = TweenInfo.new(0.18, OUT, DIR) -- toggle, chevron
Tween.Spin   = TweenInfo.new(0.26, Enum.EasingStyle.Back, DIR) -- collapse chevrons (slight overshoot)
Tween.Spring = TweenInfo.new(0.28, Enum.EasingStyle.Back, DIR) -- knobs / pops that should overshoot
Tween.Press  = TweenInfo.new(0.09, Enum.EasingStyle.Quad, DIR) -- button tap squash
Tween.Pop    = TweenInfo.new(0.16, Enum.EasingStyle.Back, DIR) -- popovers / window in
Tween.Toast  = TweenInfo.new(0.22, Enum.EasingStyle.Quint, DIR)
Tween.ToastOut = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

function Tween.play(instance: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goals)
	tween:Play()
	return tween
end

return Tween
