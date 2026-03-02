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
