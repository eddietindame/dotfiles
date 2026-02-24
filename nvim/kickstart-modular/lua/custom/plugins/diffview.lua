return {
  'sindrets/diffview.nvim',
  cmd = { 'DiffviewOpen', 'DiffviewFileHistory' },
  keys = {
    { '<leader>gd', '<cmd>DiffviewOpen<CR>', desc = '[G]it [D]iff view' },
    { '<leader>gf', '<cmd>DiffviewFileHistory %<CR>', desc = '[G]it [F]ile history' },
    { '<leader>gF', '<cmd>DiffviewFileHistory<CR>', desc = '[G]it [F]ile history (all)' },
    { '<leader>gq', '<cmd>DiffviewClose<CR>', desc = '[G]it diff [Q]uit' },
  },
  opts = {
    view = {
      merge_tool = {
        layout = 'diff1_plain',
      },
    },
  },
}
