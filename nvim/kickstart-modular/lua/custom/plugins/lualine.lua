return {
  'nvim-lualine/lualine.nvim',
  dependencies = {
    'nvim-tree/nvim-web-devicons',
    { 'catppuccin/nvim', name = 'catppuccin', opts = { flavour = 'mocha' } },
  },
  opts = {
    options = {
      theme = 'catppuccin',
    },
  },
}
