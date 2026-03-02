-- Disabled in favour of multiple-cursors.nvim
-- return {
--   'jake-stewart/multicursor.nvim',
--   branch = '1.0',
--   config = function()
--     ...
--   end,
-- }

return {
  'brenton-leighton/multiple-cursors.nvim',
  version = '*',
  opts = {
    pre_hook = function()
      vim.b.completion = false
      local ok, autopairs = pcall(require, 'nvim-autopairs')
      if ok then
        autopairs.disable()
      end
    end,
    post_hook = function()
      vim.b.completion = true
      local ok, autopairs = pcall(require, 'nvim-autopairs')
      if ok then
        autopairs.enable()
      end
    end,
  },
  keys = {
    { '<leader><Up>', '<cmd>MultipleCursorsAddUp<CR>', mode = { 'n', 'i', 'x' }, desc = 'Add cursor above' },
    { '<leader><Down>', '<cmd>MultipleCursorsAddDown<CR>', mode = { 'n', 'i', 'x' }, desc = 'Add cursor below' },
    { '<C-LeftMouse>', '<cmd>MultipleCursorsMouseAddDelete<CR>', mode = { 'n', 'i' }, desc = 'Add/remove cursor (click)' },
    { '<leader>n', '<cmd>MultipleCursorsAddJumpNextMatch<CR>', mode = { 'n' }, desc = 'Add cursor at [n]ext match' },
    { '<leader>n', '<cmd>MultipleCursorsAddMatches<CR>', mode = { 'x' }, desc = 'Add cursors at [A]ll matches (visual)' },
    { '<leader>A', '<cmd>MultipleCursorsAddMatches<CR>', mode = { 'n', 'x' }, desc = 'Add cursors at [A]ll matches' },
    { '<leader>k', '<cmd>MultipleCursorsJumpNextMatch<CR>', mode = { 'n' }, desc = 'S[k]ip to next match' },
  },
}
