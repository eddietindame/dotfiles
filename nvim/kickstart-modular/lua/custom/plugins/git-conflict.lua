return {
  'akinsho/git-conflict.nvim',
  version = '*',
  event = 'BufReadPre',
  opts = {
    default_mappings = true,
    -- Default keybindings:
    --   co — choose ours
    --   ct — choose theirs
    --   cb — choose both
    --   c0 — choose none
    --   ]x — next conflict
    --   [x — previous conflict
  },
}
