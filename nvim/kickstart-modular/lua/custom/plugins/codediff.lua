return {
  'esmuellert/codediff.nvim',
  dependencies = { 'MunifTanjim/nui.nvim' },
  cmd = 'CodeDiff',
  keys = {
    { '<leader>gd', '<cmd>CodeDiff<CR>', desc = '[G]it [D]iff (CodeDiff)' },
  },
  opts = {
    explorer = {
      position = 'bottom',
    },
  },
}
