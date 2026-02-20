local darken = require('custom.utils').darken
local FLOAT_DARKEN_AMOUNT = 40

-- Apply custom background per direction:
--   float: slightly darkened version of the current colorscheme bg
--   horizontal: solid black
local function apply_term_bg(bufnr, direction)
  if direction == 'float' then
    local bg = vim.api.nvim_get_hl(0, { name = 'Normal' }).bg
    if bg then
      local hex = string.format('#%06x', bg)
      vim.api.nvim_set_hl(0, 'ToggleTermFloat', { bg = darken(hex, FLOAT_DARKEN_AMOUNT) })
      vim.api.nvim_buf_set_option(bufnr, 'winhighlight', 'Normal:ToggleTermFloat')
    end
  else
    vim.api.nvim_set_hl(0, 'ToggleTermBlack', { bg = '#000000' })
    vim.api.nvim_buf_set_option(bufnr, 'winhighlight', 'Normal:ToggleTermBlack')
  end
end

-- Open or switch the single shared terminal instance to a given size/direction
local function open_term(size, direction)
  local term = require('toggleterm.terminal').get(1)
  if term then
    term:close()
    term.direction = direction
    term:open(size, direction)
  else
    require('toggleterm').toggle(1, size, nil, direction)
  end
  local t = require('toggleterm.terminal').get(1)
  if t and t.bufnr then
    apply_term_bg(t.bufnr, direction)
  end
end

return {
  'akinsho/toggleterm.nvim',
  lazy = false,
  opts = {
    open_mapping = [[<C-\>]],
    direction = 'horizontal',
    size = 15,
    shade_terminals = false,
    float_opts = {
      border = 'curved',
    },
    -- Also apply bg when opened via the default <C-\> mapping
    on_open = function(term)
      apply_term_bg(term.bufnr, term.direction)
    end,
  },
  keys = {
    {
      '<leader>ts',
      function()
        open_term(20, 'horizontal')
      end,
      desc = 'Terminal (small)',
    },
    {
      '<leader>tm',
      function()
        open_term(50, 'horizontal')
      end,
      desc = 'Terminal (medium)',
    },
    {
      '<leader>tl',
      function()
        open_term(vim.o.lines, 'horizontal')
      end,
      desc = 'Terminal (large)',
    },
    {
      '<leader>tf',
      function()
        open_term(nil, 'float')
      end,
      desc = 'Terminal (float)',
    },
  },
}
