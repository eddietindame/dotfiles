-- Change this to switch lualine themes: "evil", "bubbles", "catppuccin", "default"
local theme = 'everforest'
-- Set to false to disable separators, or a table like { left = '', right = '' }
local separators = false
-- Set to true to sync the MsgArea (command-line) bg with the lualine theme
local match_cmdline_bg = true
-- Set to true to reset MsgArea bg to default when entering command-line mode
local reset_cmdline_on_enter = true

local spec = require('custom.lualine.' .. theme)

spec.opts = spec.opts or {}
spec.opts.options = spec.opts.options or {}
spec.opts.options.globalstatus = true

if separators ~= nil then
  local seps = separators or { left = '', right = '' }
  spec.opts.options.section_separators = seps
  spec.opts.options.component_separators = seps
end

if match_cmdline_bg then
  spec.config = function(_, opts)
    require('lualine').setup(opts)
    local lualine_theme = opts.options and opts.options.theme
    local bg
    if type(lualine_theme) == 'table' then
      bg = lualine_theme.normal and lualine_theme.normal.c and lualine_theme.normal.c.bg
    elseif type(lualine_theme) == 'string' then
      local ok, t = pcall(require, 'lualine.themes.' .. lualine_theme)
      if ok and t.normal and t.normal.c then
        bg = t.normal.c.bg
      end
    end
    if bg then
      vim.api.nvim_set_hl(0, 'MsgArea', { bg = bg })
      if reset_cmdline_on_enter then
        local group = vim.api.nvim_create_augroup('LualineMsgArea', { clear = true })
        vim.api.nvim_create_autocmd('CmdlineEnter', {
          group = group,
          callback = function()
            vim.api.nvim_set_hl(0, 'MsgArea', {})
          end,
        })
        vim.api.nvim_create_autocmd('CmdlineLeave', {
          group = group,
          callback = function()
            vim.api.nvim_set_hl(0, 'MsgArea', { bg = bg })
          end,
        })
      end
    end
  end
end

return spec
