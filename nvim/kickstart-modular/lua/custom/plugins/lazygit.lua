-- Use default lazygit config merged with nvim-specific overrides
vim.g.lazygit_use_custom_config_file_path = 1
vim.g.lazygit_config_file_path = vim.fn.stdpath 'config' .. '/lazygit.yml'

return {
  'kdheepak/lazygit.nvim',
  lazy = true,
  cmd = {
    'LazyGit',
    'LazyGitConfig',
    'LazyGitCurrentFile',
    'LazyGitFilter',
    'LazyGitFilterCurrentFile',
  },
  -- optional for floating window border decoration
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  -- setting the keybinding for LazyGit with 'keys' is recommended in
  -- order to load the plugin when the command is run for the first time
  keys = {
    { '<leader>lg', '<cmd>LazyGit<cr>', desc = 'LazyGit' },
  },
  config = function()
    -- Darkened background for the lazygit floating window
    local darken = require('custom.utils').darken
    local DARKEN_AMOUNT = 5

    local bg = vim.api.nvim_get_hl(0, { name = 'Normal' }).bg
    if bg then
      local dark = darken(string.format('#%06x', bg), DARKEN_AMOUNT)
      vim.api.nvim_set_hl(0, 'LazyGitBg', { bg = dark })
      -- local hex = string.format('#%06x', bg)
      local darker = darken(string.format('#%06x', bg), DARKEN_AMOUNT + 10)
      vim.api.nvim_set_hl(0, 'LazyGitBorder', { bg = darker, fg = '#ffffff' })
    end

    vim.api.nvim_create_autocmd('TermOpen', {
      pattern = '*lazygit*',
      callback = function()
        vim.wo.winhighlight = 'Normal:LazyGitBg,FloatBorder:LazyGitBorder,NormalFloat:LazyGitBg'
        -- Shrink the float to leave room at the bottom
        local win = vim.api.nvim_get_current_win()
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= '' then
          config.height = config.height - 4
          vim.api.nvim_win_set_config(win, config)
        end
      end,
    })
  end,
}
