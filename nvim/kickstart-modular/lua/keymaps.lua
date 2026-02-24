-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })
vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Show diagnostic [E]rror message' })

-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
-- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
-- is not what someone will guess without a bit more experience.
--
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- TIP: Disable arrow keys in normal mode
-- vim.keymap.set('n', '<left>', '<cmd>echo "Use h to move!!"<CR>')
-- vim.keymap.set('n', '<right>', '<cmd>echo "Use l to move!!"<CR>')
-- vim.keymap.set('n', '<up>', '<cmd>echo "Use k to move!!"<CR>')
-- vim.keymap.set('n', '<down>', '<cmd>echo "Use j to move!!"<CR>')

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--
--  See `:help wincmd` for a list of all window commands
vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

-- NOTE: Some terminals have colliding keymaps or are not able to send distinct keycodes
-- vim.keymap.set("n", "<C-S-h>", "<C-w>H", { desc = "Move window to the left" })
-- vim.keymap.set("n", "<C-S-l>", "<C-w>L", { desc = "Move window to the right" })
-- vim.keymap.set("n", "<C-S-j>", "<C-w>J", { desc = "Move window to the lower" })
-- vim.keymap.set("n", "<C-S-k>", "<C-w>K", { desc = "Move window to the upper" })

-- [[ Basic Autocommands ]]
--  See `:help lua-guide-autocommands`

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.hl.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- Option+Arrow word navigation (macOS terminal compatibility)
-- Map both <M-Arrow> and raw escape sequences (<Esc>b / <Esc>f)
vim.keymap.set({ 'n', 'v' }, '<M-Left>', 'b', { desc = 'Move back one word' })
vim.keymap.set({ 'n', 'v' }, '<M-Right>', 'w', { desc = 'Move forward one word' })
vim.keymap.set({ 'n', 'v' }, '<Esc>b', 'b', { desc = 'Move back one word' })
vim.keymap.set({ 'n', 'v' }, '<Esc>f', 'w', { desc = 'Move forward one word' })
vim.keymap.set('i', '<M-Left>', '<C-o>b', { desc = 'Move back one word' })
vim.keymap.set('i', '<M-Right>', '<C-o>w', { desc = 'Move forward one word' })
vim.keymap.set('i', '<Esc>b', '<C-o>b', { desc = 'Move back one word' })
vim.keymap.set('i', '<Esc>f', '<C-o>w', { desc = 'Move forward one word' })
vim.keymap.set('c', '<M-Left>', '<S-Left>', { desc = 'Move back one word' })
vim.keymap.set('c', '<M-Right>', '<S-Right>', { desc = 'Move forward one word' })
vim.keymap.set('c', '<Esc>b', '<S-Left>', { desc = 'Move back one word' })
vim.keymap.set('c', '<Esc>f', '<S-Right>', { desc = 'Move forward one word' })

-- Option+Backspace to delete word (macOS-style)
vim.keymap.set('n', '<M-BS>', 'db', { desc = 'Delete word before cursor' })
vim.keymap.set('i', '<M-BS>', '<C-w>', { desc = 'Delete word before cursor' })
vim.keymap.set('c', '<M-BS>', '<C-w>', { desc = 'Delete word before cursor' })

-- Option+Up/Down to move lines (VSCode-style)
vim.keymap.set('n', '<M-Up>', '<cmd>m .-2<CR>==', { desc = 'Move line up' })
vim.keymap.set('n', '<M-Down>', '<cmd>m .+1<CR>==', { desc = 'Move line down' })
vim.keymap.set('i', '<M-Up>', '<Esc><cmd>m .-2<CR>==gi', { desc = 'Move line up' })
vim.keymap.set('i', '<M-Down>', '<Esc><cmd>m .+1<CR>==gi', { desc = 'Move line down' })
vim.keymap.set('v', '<M-Up>', ":m '<-2<CR>gv=gv", { desc = 'Move selection up' })
vim.keymap.set('v', '<M-Down>', ":m '>+1<CR>gv=gv", { desc = 'Move selection down' })

-- -- Cmd+Arrow navigation (VSCode-style, works in GUI Neovim)
-- vim.keymap.set({ 'n', 'v' }, '<D-Up>', 'gg', { desc = 'Go to top of file' })
-- vim.keymap.set({ 'n', 'v' }, '<D-Down>', 'G', { desc = 'Go to bottom of file' })
-- vim.keymap.set({ 'n', 'v' }, '<D-Left>', '0', { desc = 'Go to start of line' })
-- vim.keymap.set({ 'n', 'v' }, '<D-Right>', '$', { desc = 'Go to end of line' })
-- vim.keymap.set('i', '<D-Up>', '<Esc>ggi', { desc = 'Go to top of file' })
-- vim.keymap.set('i', '<D-Down>', '<Esc>Gi', { desc = 'Go to bottom of file' })
-- vim.keymap.set('i', '<D-Left>', '<Home>', { desc = 'Go to start of line' })
-- vim.keymap.set('i', '<D-Right>', '<End>', { desc = 'Go to end of line' })

-- Copy path keymaps
vim.keymap.set('n', '<leader>cp', function()
  local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':.')
  vim.fn.setreg('+', path)
  vim.notify(path, vim.log.levels.INFO, { title = 'Copied relative path' })
end, { desc = '[C]opy relative [P]ath' })

vim.keymap.set('n', '<leader>cP', function()
  local path = vim.api.nvim_buf_get_name(0)
  vim.fn.setreg('+', path)
  vim.notify(path, vim.log.levels.INFO, { title = 'Copied absolute path' })
end, { desc = '[C]opy absolute [P]ath' })

vim.keymap.set('n', '<leader>c~', function()
  local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':~')
  vim.fn.setreg('+', path)
  vim.notify(path, vim.log.levels.INFO, { title = 'Copied path with ~' })
end, { desc = '[C]opy path with [~] home' })

vim.keymap.set('n', '<leader>cf', function()
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t')
  vim.fn.setreg('+', name)
  vim.notify(name, vim.log.levels.INFO, { title = 'Copied filename' })
end, { desc = '[C]opy [F]ilename' })

vim.keymap.set('n', '<leader>cl', function()
  local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':.')
  local loc = path .. ':' .. vim.fn.line '.'
  vim.fn.setreg('+', loc)
  vim.notify(loc, vim.log.levels.INFO, { title = 'Copied path with line' })
end, { desc = '[C]opy path with [L]ine number' })

-- Scratch buffers for pasting and formatting
vim.keymap.set('n', '<leader>bj', function()
  vim.cmd 'enew'
  vim.bo.buftype = 'nofile'
  vim.bo.filetype = 'json'
  vim.notify('Paste JSON, then <leader>f to format', vim.log.levels.INFO)
end, { desc = '[B]uffer scratch [J]SON' })

vim.keymap.set('n', '<leader>by', function()
  vim.cmd 'enew'
  vim.bo.buftype = 'nofile'
  vim.bo.filetype = 'yaml'
  vim.notify('Paste YAML, then <leader>f to format', vim.log.levels.INFO)
end, { desc = '[B]uffer scratch [Y]AML' })

vim.keymap.set('n', '<leader>bd', '<cmd>bdelete<CR>', { desc = '[B]uffer [D]elete' })

vim.keymap.set('n', '<leader>[', '<cmd>tabprevious<CR>', { desc = 'Previous tab' })
vim.keymap.set('n', '<leader>]', '<cmd>tabnext<CR>', { desc = 'Next tab' })

vim.keymap.set('n', '<leader><Tab>', '<C-^>', { desc = 'Switch to previous buffer' })

-- Indent with Tab in visual mode
vim.keymap.set('v', '<Tab>', '>gv', { desc = 'Indent selection' })
vim.keymap.set('v', '<S-Tab>', '<gv', { desc = 'Unindent selection' })

-- vim: ts=2 sts=2 sw=2 et

-- local map = vim.keymap.set
-- local opts = { noremap = true, silent = true }

-- VSCode-style keybindings

-- -- Save (Cmd+S)
-- vim.keymap.set({'n', 'i'}, '<M-s>', '<Cmd>w<CR>', { desc = 'Save file' })

-- -- File search (Cmd+P)
-- vim.keymap.set('n', '<M-p>', '<Cmd>Telescope find_files<CR>', { desc = 'Find files' })

-- -- Command palette (Cmd+Shift+P)
-- vim.keymap.set('n', '<M-S-p>', '<Cmd>Telescope commands<CR>', { desc = 'Command palette' })

-- -- File explorer (Cmd+B)
-- vim.keymap.set('n', '<M-b>', '<Cmd>NvimTreeToggle<CR>', { desc = 'Toggle file explorer' })

-- -- Terminal (Cmd+J)
-- vim.keymap.set({'n', 't'}, '<M-j>', '<Cmd>ToggleTerm<CR>', { desc = 'Toggle terminal' })

-- -- Find in file (Cmd+F)
-- vim.keymap.set('n', '<M-f>', '/', { desc = 'Search in file' })

-- -- Global search (Cmd+Shift+F)
-- vim.keymap.set('n', '<M-S-f>', '<Cmd>Telescope live_grep<CR>', { desc = 'Search in project' })

-- -- Close buffer (Cmd+W)
-- vim.keymap.set('n', '<M-w>', '<Cmd>bd<CR>', { desc = 'Close buffer' })

-- -- Recent files (Cmd+E)
-- vim.keymap.set('n', '<M-e>', '<Cmd>Telescope oldfiles<CR>', { desc = 'Recent files' })

-- -- Go to symbol (Cmd+Shift+O)
-- vim.keymap.set('n', '<M-S-o>', '<Cmd>Telescope lsp_document_symbols<CR>', { desc = 'Go to symbol' })

-- -- Toggle comment (Cmd+/)
-- vim.keymap.set('n', '<M-/>', 'gcc', { desc = 'Toggle comment', remap = true })
-- vim.keymap.set('v', '<M-/>', 'gc', { desc = 'Toggle comment', remap = true })

-- -- Split editor (Cmd+\)
-- vim.keymap.set('n', '<M-\\>', '<Cmd>vsplit<CR>', { desc = 'Split vertical' })

-- -- Navigate buffers (Cmd+Shift+[ and ])
-- vim.keymap.set('n', '<M-{>', '<Cmd>bprev<CR>', { desc = 'Previous buffer' })
-- vim.keymap.set('n', '<M-}>', '<Cmd>bnext<CR>', { desc = 'Next buffer' })

-- -- Go to line/search in buffer (Cmd+G)
-- vim.keymap.set('n', '<M-g>', '<Cmd>Telescope current_buffer_fuzzy_find<CR>', { desc = 'Go to line' })

-- -- Select all (Cmd+A)
-- vim.keymap.set('n', '<M-a>', 'ggVG', { desc = 'Select all' })
