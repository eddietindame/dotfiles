local darken = require('custom.utils').darken
local FLOAT_DARKEN_AMOUNT = 40

-- Apply custom background per direction:
--   float: slightly darkened version of the current colorscheme bg
--   horizontal: solid black
local function apply_term_bg(bufnr, direction)
  if direction == 'float' then
    local bg = vim.api.nvim_get_hl(0, { name = 'Normal' }).bg
    if bg then
      local hex = string.format('#%06x', bg)
      vim.api.nvim_set_hl(0, 'ToggleTermFloat', { bg = darken(hex, FLOAT_DARKEN_AMOUNT) })
      vim.api.nvim_buf_set_option(bufnr, 'winhighlight', 'Normal:ToggleTermFloat')
    end
  else
    vim.api.nvim_set_hl(0, 'ToggleTermBlack', { bg = '#000000' })
    vim.api.nvim_buf_set_option(bufnr, 'winhighlight', 'Normal:ToggleTermBlack')
  end
end

-- Track the current terminal ID
local current_id = 1

-- Get the highest terminal ID currently in use
local function max_term_id()
  local terms = require('toggleterm.terminal').get_all()
  local max = 0
  for _, t in ipairs(terms) do
    if t.id > max then
      max = t.id
    end
  end
  return max
end

-- Open or switch a terminal instance to a given size/direction
local function open_term(size, direction, id)
  id = id or current_id
  current_id = id
  local Terminal = require('toggleterm.terminal')
  local term = Terminal.get(id)
  if term then
    term:close()
    term.direction = direction
    term:open(size, direction)
  else
    require('toggleterm').toggle(id, size, nil, direction)
  end
  local t = Terminal.get(id)
  if t and t.bufnr then
    apply_term_bg(t.bufnr, direction)
  end
end

local function next_term()
  local terms = require('toggleterm.terminal').get_all()
  if #terms == 0 then return end
  table.sort(terms, function(a, b) return a.id < b.id end)
  local next_id = terms[1].id
  for _, t in ipairs(terms) do
    if t.id > current_id then
      next_id = t.id
      break
    end
  end
  local prev = require('toggleterm.terminal').get(current_id)
  local direction = (prev and prev.direction) or 'float'
  if prev then prev:close() end
  open_term(nil, direction, next_id)
end

local function prev_term()
  local terms = require('toggleterm.terminal').get_all()
  if #terms == 0 then return end
  table.sort(terms, function(a, b) return a.id < b.id end)
  local prev_id = terms[#terms].id
  for i = #terms, 1, -1 do
    if terms[i].id < current_id then
      prev_id = terms[i].id
      break
    end
  end
  local prev = require('toggleterm.terminal').get(current_id)
  local direction = (prev and prev.direction) or 'float'
  if prev then prev:close() end
  open_term(nil, direction, prev_id)
end

return {
  'akinsho/toggleterm.nvim',
  lazy = false,
  opts = {
    open_mapping = [[<C-\>]],
    direction = 'float',
    size = 15,
    shade_terminals = false,
    float_opts = {
      border = 'curved',
    },
    -- Also apply bg when opened via the default <C-\> mapping
    on_open = function(term)
      apply_term_bg(term.bufnr, term.direction)
    end,
  },
  keys = {
    {
      '<leader>ts',
      function()
        open_term(20, 'horizontal')
      end,
      desc = 'Terminal (small)',
    },
    {
      '<leader>tm',
      function()
        open_term(50, 'horizontal')
      end,
      desc = 'Terminal (medium)',
    },
    {
      '<leader>tl',
      function()
        open_term(vim.o.lines, 'horizontal')
      end,
      desc = 'Terminal (large)',
    },
    {
      '<leader>tf',
      function()
        open_term(nil, 'float')
      end,
      desc = 'Terminal (float)',
    },
    {
      '<leader>tF',
      function()
        local term = require('toggleterm.terminal').get(1)
        if term and term.window then
          local win = term.window
          local config = vim.api.nvim_win_get_config(win)
          if config.relative ~= '' then
            -- Toggle between fullscreen and default float size
            if config.width == vim.o.columns - 2 then
              -- Restore default
              term:close()
              open_term(nil, 'float')
            else
              -- Fullscreen
              config.width = vim.o.columns - 2
              config.height = vim.o.lines - 2
              config.row = 0
              config.col = 0
              vim.api.nvim_win_set_config(win, config)
            end
          end
        else
          open_term(nil, 'float')
        end
      end,
      desc = 'Terminal (fullscreen float)',
    },
    {
      '<leader>tn',
      function()
        local id = max_term_id() + 1
        open_term(nil, 'float', id)
      end,
      desc = '[T]erminal [N]ew',
    },
    { '<leader>t]', next_term, desc = '[T]erminal next' },
    { '<leader>t[', prev_term, desc = '[T]erminal previous' },
    -- Terminal-mode bindings (work while inside the terminal)
    { '<C-S-l>', next_term, mode = 't', desc = 'Next terminal' },
    { '<C-S-h>', prev_term, mode = 't', desc = 'Previous terminal' },
    {
      '<C-n>',
      function()
        local id = max_term_id() + 1
        open_term(nil, 'float', id)
      end,
      mode = 't',
      desc = 'New terminal',
    },
  },
}
