--!strict
-- components/Image.lua — drop a picture into a card.
--
-- The `Image` field takes anything util/Asset.lua can resolve: a bare decal id,
-- an `rbxassetid://` url, a local file written by the executor, or an https url
-- (downloaded + cached on first use). Everything else is chrome: rounded frame,
-- 1px border, an optional caption, and a placeholder icon while there's nothing
-- to show yet.
--
--   Group:Image({ Image = 91296376944710, Height = 160 })
--   Group:Image({ Name = "Banner", Image = "https://…/banner.png", Fit = "cover" })
--
-- The handle exposes :Set(source) / :Get(), so a live view (a thumbnail that
-- tracks a selection, say) just calls :Set with the new source.

local Create = require(script.Parent.Parent.util.Create)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)
local Asset = require(script.Parent.Parent.util.Asset)
local Field = require(script.Parent.Field)

-- How the picture fills its frame. "cover" crops to fill (the sane default for
-- banners/art), "contain" fits the whole image inside, "stretch" distorts.
local FIT: { [string]: Enum.ScaleType } = {
	cover = Enum.ScaleType.Crop,
	contain = Enum.ScaleType.Fit,
	fit = Enum.ScaleType.Fit,
	stretch = Enum.ScaleType.Stretch,
	tile = Enum.ScaleType.Tile,
}

return function(ctx: any, opts: any)
	local colors = Theme.Colors
	opts = opts or {}

	local height = tonumber(opts.Height) or 140
	local radius = tonumber(opts.Corner) or Theme.Metrics.controlRadius
	local scaleType = FIT[tostring(opts.Fit or "cover"):lower()] or Enum.ScaleType.Crop

	-- Titled → the standard stacked field (name/desc above, image below).
	-- Bare → a plain padded row, like a bare Button.
	local container: Frame
	local field: Frame
	if opts.Name or opts.Desc then
		local f = Field.new(ctx, opts, true)
		field = f.field
		container = f.field
	else
		container = Create("Frame", {
			Name = "Image",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, {
			Create.padding(10, 2),
			Create.listLayout({ Padding = UDim.new(0, 6) }),
		})
		field = container
	end

	-- The frame clips so the UICorner actually rounds the picture (a UICorner on
	-- the ImageLabel alone doesn't clip a Crop-scaled image).
	local frame = Create("Frame", {
		Name = "Frame",
		Size = opts.Width and UDim2.new(0, tonumber(opts.Width) or 0, 0, height)
			or UDim2.new(1, 0, 0, height),
		BackgroundColor3 = colors.control,
		ClipsDescendants = true,
		LayoutOrder = 2,
		Parent = container,
	}, {
		Create.corner(radius),
		Create.stroke(colors.border),
	})

	local picture = Create("ImageLabel", {
		Name = "Picture",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = "",
		ScaleType = scaleType,
		Parent = frame,
	}) :: ImageLabel

	-- Shown whenever there's no resolvable source (or it's still downloading).
	local placeholder = Icons.new("image", 22, colors.text_dim)
	placeholder.AnchorPoint = Vector2.new(0.5, 0.5)
	placeholder.Position = UDim2.fromScale(0.5, 0.5)
	;(placeholder :: any).Parent = frame

	local caption: TextLabel? = nil
	if opts.Caption then
		caption = Create("TextLabel", {
			Name = "Caption",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = opts.Caption,
			TextColor3 = colors.text_muted,
			TextSize = 12,
			FontFace = Theme.Font.Regular,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			LayoutOrder = 3,
			Parent = container,
		})
	end

	local source: any = nil

	local function apply(value: any)
		source = value
		-- Asset.load runs off-thread (an https source downloads on first use, and
		-- it waits on the load to report back), so building a menu never blocks.
		-- The placeholder holds the frame until the picture is genuinely up — an
		-- id that never resolves leaves the icon showing, not an empty box.
		placeholder.Visible = true
		Asset.load(picture, value, function(loaded)
			placeholder.Visible = not loaded
		end)
	end

	-- Clickable variant: a transparent button over the picture. Only added when a
	-- Callback is given, so a plain image stays inert (and doesn't eat scrolls).
	if opts.Callback then
		local hit = Create("TextButton", {
			Name = "Hit",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Text = "",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = frame,
		})
		hit.Activated:Connect(function()
			task.spawn(opts.Callback, source)
		end)
	end

	local handle = {}
	function handle:Get(): any
		return source
	end
	function handle:Set(value: any)
		apply(value)
	end
	function handle:SetCaption(text: string)
		if caption then
			caption.Text = text
		end
	end
	handle.element = picture

	apply(opts.Image or opts.Source)

	return field, handle, true
end
