-- Highlight printf format verbs (%s, %d, %v, etc.) inside Go strings
-- Uses matchadd to overlay highlighting on top of treesitter

vim.api.nvim_set_hl(0, 'GoFormatVerb', { link = 'Special' })

-- Match format verbs: %[flags][width][.precision][verb]
vim.fn.matchadd('GoFormatVerb', '%[-+# 0]*[*]\\?\\d*\\(\\.\\d*\\)\\?[vTtbcdoOqxXUeEfFgGspw%]')
