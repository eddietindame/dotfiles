-- Extract lualine theme colors for tmux sync
-- Usage: LUALINE_THEME=<name> nvim -l extract-colors.lua

local theme_name = os.getenv('LUALINE_THEME') or ''
local home = os.getenv('HOME')

-- Find lazy.nvim plugin root
local lazy_roots = {
  home .. '/.local/share/nvim/kickstart-modular/lazy',
  home .. '/.local/share/nvim/lazy',
}
local lazy_root
for _, root in ipairs(lazy_roots) do
  if vim.fn.isdirectory(root) == 1 then
    lazy_root = root
    break
  end
end

-- Add user config + all lazy plugins to Lua path
local config_lua = home .. '/.config/nvim/kickstart-modular/lua'
package.path = config_lua .. '/?.lua;' .. config_lua .. '/?/init.lua;' .. package.path
if lazy_root then
  for _, dir in ipairs(vim.fn.glob(lazy_root .. '/*/lua', false, true)) do
    package.path = dir .. '/?.lua;' .. dir .. '/?/init.lua;' .. package.path
  end
end

-- Resolve the lualine theme table
local t

-- 1) Load the user's custom lualine spec
local ok, spec = pcall(require, 'custom.lualine.' .. theme_name)
if ok and type(spec) == 'table' then
  local lt = spec.opts and spec.opts.options and spec.opts.options.theme
  if type(lt) == 'table' then
    t = lt
  elseif type(lt) == 'string' then
    ok, t = pcall(require, 'lualine.themes.' .. lt)
    if not ok then t = nil end
  end
end

-- 2) Try as a built-in lualine theme name
if not t and theme_name ~= '' then
  ok, t = pcall(require, 'lualine.themes.' .. theme_name)
  if not ok then t = nil end
end

-- Extract colors: bg  bg1  bg3  fg  accent  grey  prefix_accent  session_accent
if t and t.normal then
  local a = t.normal.a or {}
  local b = t.normal.b or {}
  local c = t.normal.c or {}
  local inactive_fg = t.inactive and t.inactive.c and t.inactive.c.fg or ''
  local prefix_bg = t.visual and t.visual.a and t.visual.a.bg
    or t.command and t.command.a and t.command.a.bg
    or ''
  local session_bg = t.command and t.command.a and t.command.a.bg
    or t.insert and t.insert.a and t.insert.a.bg
    or ''

  io.write(string.format('%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s',
    a.fg or '', c.bg or '', b.bg or '', c.fg or '', a.bg or '', inactive_fg, prefix_bg, session_bg))
end
