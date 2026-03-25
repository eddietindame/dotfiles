return {
  'sindrets/diffview.nvim',
  cmd = { 'DiffviewOpen', 'DiffviewFileHistory' },
  keys = {
    { '<leader>gd', '<cmd>DiffviewOpen<CR>', desc = '[G]it [D]iff view' },
    { '<leader>gf', '<cmd>DiffviewFileHistory %<CR>', desc = '[G]it [F]ile history' },
    { '<leader>gF', '<cmd>DiffviewFileHistory<CR>', desc = '[G]it [F]ile history (all)' },
    { '<leader>gq', '<cmd>DiffviewClose<CR>', desc = '[G]it diff [Q]uit' },
  },
  config = function()
    require('diffview').setup {
      file_panel = {
        listing_style = 'list',
      },
      keymaps = {
        view = { { 'n', 'q', '<cmd>DiffviewClose<CR>', { desc = 'Close diffview' } } },
        file_panel = { { 'n', 'q', '<cmd>DiffviewClose<CR>', { desc = 'Close diffview' } } },
        file_history_panel = { { 'n', 'q', '<cmd>DiffviewClose<CR>', { desc = 'Close diffview' } } },
      },
      view = {
        default = {
          layout = 'diff2_vertical',
        },
        file_history = {
          layout = 'diff2_vertical',
        },
        merge_tool = {
          layout = 'diff1_plain',
        },
      },
    }
  end,
}
