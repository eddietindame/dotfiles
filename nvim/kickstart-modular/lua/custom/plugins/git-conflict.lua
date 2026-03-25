return {
  'akinsho/git-conflict.nvim',
  version = '*',
  event = 'BufReadPre',
  config = function()
    require('git-conflict').setup {
      default_mappings = true,
      -- Default keybindings:
      --   co — choose ours
      --   ct — choose theirs
      --   cb — choose both
      --   c0 — choose none
      --   ]x — next conflict
      --   [x — previous conflict
    }

    -- Clear git-conflict state from diffview buffers to prevent
    -- "Invalid 'line': out of range" errors in its decoration provider.
    -- Diffview buffers have modified line counts that desync from cached positions.
    local gc_augroup = vim.api.nvim_create_augroup('git-conflict-diffview-fix', { clear = true })
    vim.api.nvim_create_autocmd('BufEnter', {
      group = gc_augroup,
      callback = function(args)
        local name = vim.api.nvim_buf_get_name(args.buf)
        if name:match '^diffview://' then
          -- Clear any cached conflict data so git-conflict skips this buffer
          require('git-conflict').clear(args.buf)
        end
      end,
    })
  end,
}
