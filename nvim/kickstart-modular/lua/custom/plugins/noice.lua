-- lazy.nvim
return {
  'folke/noice.nvim',
  event = 'VeryLazy',
  opts = {
    cmdline = {
      view = 'cmdline',
    },
    messages = {
      enabled = false, -- use default vim messages (shows "recording @q", etc)
    },
    notify = {
      enabled = true, -- keep toast notifications for vim.notify()
    },
  },
  dependencies = {
    -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
    'MunifTanjim/nui.nvim',
    -- OPTIONAL:
    --   `nvim-notify` is only needed, if you want to use the notification view.
    --   If not available, we use `mini` as the fallback
    'rcarriga/nvim-notify',
  },
}
--
-- -- lazy.nvim
-- return {
--   'folke/noice.nvim',
--   event = 'VeryLazy',
--   opts = {
--     cmdline = {
--       view = 'cmdline', -- classic bottom cmdline instead of popup
--     },
--   },
--   dependencies = {
--     -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
--     'MunifTanjim/nui.nvim',
--     -- OPTIONAL:
--     --   `nvim-notify` is only needed, if you want to use the notification view.
--     --   If not available, we use `mini` as the fallback
--     'rcarriga/nvim-notify',
--   },
-- }
--
