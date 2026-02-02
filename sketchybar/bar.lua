local settings = require("config.settings")

sbar.bar({
	topmost = "window",
	height = settings.dimens.graphics.bar.height,
	color = settings.colors.bar.transparent,
	border_color = settings.colors.bar.border, 
	padding_right = settings.dimens.padding.right,
	padding = settings.dimens.padding.bar,
	padding_left = settings.dimens.padding.left,
	margin = settings.dimens.padding.bar,
	corner_radius = settings.dimens.graphics.background.corner_radius,
	y_offset = settings.dimens.graphics.bar.offset,
	notch_offset = settings.dimens.graphics.bar.notch_offset,  -- additional offset for notched MacBook display (8 + -6 = 2)
	blur_radius = settings.dimens.graphics.blur_radius,
	border_width = 1,
	notch_width = 200,
	shadow = true,
})
