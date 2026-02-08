local function open_term(size, direction)
  local term = require('toggleterm.terminal').get(1)
  if term then
    term:close()
    term.direction = direction
    term:open(size, direction)
  else
    require('toggleterm').toggle(1, size, nil, direction)
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
  },
}
