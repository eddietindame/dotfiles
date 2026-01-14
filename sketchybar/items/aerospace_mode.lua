local constants = require("constants")
local settings = require("config.settings")

local mode_icons = {
  main = "󰘧",
  service = "󰒓",
  resize = "󰩨",
  join = "󰘖",
}

local mode_item = sbar.add("item", constants.items.AEROSPACE_MODE, {
  position = "left",
  icon = {
    string = mode_icons.main,
    color = settings.colors.white,
    font = settings.fonts.text .. ":Bold:16.0",
  },
  label = {
    string = "MAIN",
    color = settings.colors.white,
    font = settings.fonts.text .. ":Bold:12.0",
  },
  background = {
    color = settings.colors.bg1,
    border_color = settings.colors.white,
    border_width = 0,
  },
  padding_left = 0,
  padding_right = settings.dimens.padding.item,
})

mode_item:subscribe(constants.events.AEROSPACE_MODE_CHANGED, function(env)
  local mode = env.MODE or "main"
  local icon = mode_icons[mode] or mode_icons.main

  mode_item:set({
    icon = {
      string = icon,
      color = mode == "main" and settings.colors.white or settings.colors.orange,
    },
    label = {
      string = mode:upper(),
      color = mode == "main" and settings.colors.white or settings.colors.orange,
    },
    background = {
      border_width = mode == "main" and 0 or 2,
    },
  })
end)
