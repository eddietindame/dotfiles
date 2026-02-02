-- Theme selector: "mocha" or "legacy"
local THEME = "mocha"

local with_alpha = function(color, alpha)
  if alpha > 1.0 or alpha < 0.0 then return color end
  return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)
end

-- Catppuccin Mocha base colors
local m = {
  rosewater = 0xfff5e0dc,
  flamingo = 0xfff2cdcd,
  pink = 0xfff5c2e7,
  mauve = 0xffcba6f7,
  red = 0xfff38ba8,
  maroon = 0xffeba0ac,
  peach = 0xfffab387,
  yellow = 0xfff9e2af,
  green = 0xffa6e3a1,
  teal = 0xff94e2d5,
  sky = 0xff89dceb,
  sapphire = 0xff74c7ec,
  blue = 0xff89b4fa,
  lavender = 0xffb4befe,
  text = 0xffcdd6f4,
  subtext1 = 0xffbac2de,
  subtext0 = 0xffa6adc8,
  overlay2 = 0xff9399b2,
  overlay1 = 0xff7f849c,
  overlay0 = 0xff6c7086,
  surface2 = 0xff585b70,
  surface1 = 0xff45475a,
  surface0 = 0xff313244,
  base = 0xff1e1e2e,
  mantle = 0xff181825,
  crust = 0xff11111b,
}

local mocha = {
  -- Base colors
  rosewater = m.rosewater,
  flamingo = m.flamingo,
  pink = m.pink,
  mauve = m.mauve,
  red = m.red,
  maroon = m.maroon,
  peach = m.peach,
  yellow = m.yellow,
  green = m.green,
  teal = m.teal,
  sky = m.sky,
  sapphire = m.sapphire,
  blue = m.blue,
  lavender = m.lavender,
  text = m.text,
  subtext1 = m.subtext1,
  subtext0 = m.subtext0,
  overlay2 = m.overlay2,
  overlay1 = m.overlay1,
  overlay0 = m.overlay0,
  surface2 = m.surface2,
  surface1 = m.surface1,
  surface0 = m.surface0,
  base = m.base,
  mantle = m.mantle,
  crust = m.crust,

  -- Aliases
  black = m.crust,
  white = m.text,
  orange = m.peach,
  magenta = m.pink,
  purple = m.mauve,
  cyan = m.teal,
  grey = m.overlay1,
  dirty_white = with_alpha(m.subtext1, 0.78),
  dark_grey = m.surface1,
  transparent = 0x00000000,
  bar = {
    bg = with_alpha(m.base, 0.95),
    -- border = m.surface0,
    border = with_alpha(m.lavender, 0.1),
  },
  popup = {
    bg = with_alpha(m.mantle, 0.95),
    border = m.surface0,
  },
  slider = {
    bg = with_alpha(m.mantle, 0.95),
    border = m.surface0,
  },
  bg1 = with_alpha(m.mantle, 0.83),
  bg2 = m.surface0,

  with_alpha = with_alpha,
}

local legacy = {
  black = 0xff181819,
  white = 0xfff8f8f2,
  red = 0xf1FD6592,
  green = 0xff007692,
  blue = 0xff5199ba,
  yellow = 0xffffff81,
  orange = 0xfff4c07b,
  magenta = 0xd3fc7ebd,
  purple = 0xff796fa9,
  other_purple = 0xff302c45,
  cyan = 0xff7bf2de,
  grey = 0xff7f8490,
  dirty_white = 0xc8cad3f5,
  dark_grey = 0xff2b2736,
  transparent = 0x00000000,
  bar = {
    bg = 0xf11e1e2e,
    border = 0xff2c2e34,
  },
  popup = {
    bg = 0xf1151320,
    border = 0xff2c2e34,
  },
  slider = {
    bg = 0xf1151320,
    border = 0xff2c2e34,
  },
  bg1 = 0xd322212c,
  bg2 = 0xff302c45,

  with_alpha = with_alpha,
}

local themes = {
  mocha = mocha,
  legacy = legacy,
}

return themes[THEME]
