-- Splash screen: side-by-side layout
--
--   ┌──────────────────────────────────────────────────────┐
--   │                                                      │
--   │   [Neovim ASCII art]     [icon] f  Find file         │
--   │                                                      │
--   │                          [icon] g  Live grep         │
--   │                                                      │
--   │                          [icon] r  Recent files      │
--   │                                                      │
--   │                          [icon] c  Configuration     │
--   │                                                      │
--   │                          [icon] l  Lazy              │
--   │                                                      │
--   │                          [icon] q  Quit              │
--   │                                                      │
--   │                          [plugin count + startup ms] │
--   │                                                      │
--   │                          [fortune -s]                │
--   │                                                      │
--   └──────────────────────────────────────────────────────┘
--
return {
  'goolord/alpha-nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  event = 'VimEnter',
  config = function()
    local alpha = require 'alpha'

    local icon = function(codepoint)
      return vim.fn.nr2char(codepoint)
    end

    -- Pick a random art from the pool (lua/custom/alpha-art.lua)
    local art_pool = require 'custom.alpha-art'
    math.randomseed(os.time())
    local art = art_pool[math.random(#art_pool)]

    -- Menu items
    local menu = {
      { key = 'f', icon = icon(0xf15b), label = 'Find file', cmd = '<cmd>Telescope find_files<CR>' },
      { key = 'g', icon = icon(0xf002), label = 'Live grep', cmd = '<cmd>Telescope live_grep<CR>' },
      { key = 'r', icon = icon(0xf017), label = 'Recent files', cmd = '<cmd>Telescope oldfiles cwd_only=true<CR>' },
      { key = 'c', icon = icon(0xf013), label = 'Configuration', cmd = '<cmd>e $MYVIMRC<CR>' },
      { key = 'l', icon = icon(0xf04b2), label = 'Lazy', cmd = '<cmd>Lazy<CR>' },
      { key = 'q', icon = icon(0xf2f5), label = 'Quit', cmd = '<cmd>qa<CR>' },
    }

    -- Build side panel: menu + footer + fortune
    local max_width = 40
    local raw_fortune = vim.fn.systemlist 'fortune -s'
    local fortune_lines = {}
    for _, line in ipairs(raw_fortune) do
      -- Expand tabs to spaces
      line = line:gsub('\t', '    ')
      while #line > max_width do
        local cut = max_width
        -- Try to break at a space
        local space = line:sub(1, cut):match '.*() '
        if space and space > 1 then
          cut = space
        end
        table.insert(fortune_lines, line:sub(1, cut - 1))
        line = line:sub(cut + 1)
      end
      table.insert(fortune_lines, line)
    end
    -- Clamp fortune to fit within remaining art lines
    local max_fortune = #art - (#menu * 2) - 4
    if #fortune_lines > max_fortune then
      fortune_lines = vim.list_slice(fortune_lines, 1, max_fortune)
    end

    local side_lines = {}
    for _, item in ipairs(menu) do
      table.insert(side_lines, item.icon .. '  ' .. item.key .. '  ' .. item.label)
      table.insert(side_lines, '')
    end
    -- Placeholder for plugin stats (updated after LazyVimStarted)
    table.insert(side_lines, ' ')
    local footer_line_idx = #side_lines + 1
    table.insert(side_lines, ' ')
    table.insert(side_lines, ' ')
    for _, line in ipairs(fortune_lines) do
      table.insert(side_lines, line)
    end

    -- Merge art and side panel
    local art_display_width = 75
    local gap = 6
    local menu_start_row = math.floor((#art - #side_lines) / 2) + 1

    local combined = {}
    local art_byte_ends = {} -- byte length of art portion per line (for extmark positioning)
    for i, line in ipairs(art) do
      local display_w = vim.fn.strdisplaywidth(line)
      local padding = math.max(0, art_display_width - display_w) + gap
      local padded = line .. string.rep(' ', padding)
      art_byte_ends[i] = #padded
      local side_idx = i - menu_start_row + 1
      if side_idx >= 1 and side_idx <= #side_lines then
        padded = padded .. side_lines[side_idx]
      end
      table.insert(combined, padded)
    end

    -- Register keymaps for menu items
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'alpha',
      callback = function(ev)
        for _, item in ipairs(menu) do
          vim.keymap.set('n', item.key, item.cmd, { buffer = ev.buf, noremap = true, silent = true })
        end
        vim.opt_local.foldenable = false
        local nops = { 'j', 'k', '<C-d>', '<C-u>', '<C-f>', '<C-b>', 'G', 'gg', '<ScrollWheelUp>', '<ScrollWheelDown>' }
        for _, key in ipairs(nops) do
          vim.keymap.set('n', key, '<Nop>', { buffer = true })
        end
      end,
    })

    -- Track which side section each combined line belongs to
    local side_type = {} -- per combined line: 'menu', 'footer', 'fortune', or nil
    for i = 1, #art do
      local side_idx = i - menu_start_row + 1
      if side_idx >= 1 and side_idx <= #side_lines then
        if side_idx <= #menu * 2 then
          side_type[i] = 'menu'
        elseif side_idx == footer_line_idx then
          side_type[i] = 'footer'
        elseif side_idx > footer_line_idx + 1 then
          side_type[i] = 'fortune'
        end
      end
    end

    -- Define highlight groups
    -- Derive a subtle foreground from the Normal background
    local function lighten_bg(amount)
      local normal = vim.api.nvim_get_hl(0, { name = 'Normal' })
      local bg = normal.bg or 0x2d353b
      local r = math.min(255, bit.rshift(bit.band(bg, 0xff0000), 16) + amount)
      local g = math.min(255, bit.rshift(bit.band(bg, 0x00ff00), 8) + amount)
      local b = math.min(255, bit.band(bg, 0x0000ff) + amount)
      return string.format('#%02x%02x%02x', r, g, b)
    end

    vim.api.nvim_set_hl(0, 'AlphaArt', { fg = lighten_bg(30) })
    vim.api.nvim_set_hl(0, 'AlphaMenu', { link = 'Keyword' })
    vim.api.nvim_set_hl(0, 'AlphaFooter', { link = 'Comment' })
    vim.api.nvim_set_hl(0, 'AlphaFortune', { link = 'String' })

    local header = {
      type = 'text',
      val = combined,
      opts = { position = 'center', hl = 'AlphaArt' },
    }

    local win_height = vim.fn.winheight(0)
    local top_padding = math.max(0, math.floor((win_height - #combined) / 2))

    alpha.setup {
      layout = {
        { type = 'padding', val = top_padding },
        header,
      },
    }

    -- Apply per-section highlights via extmarks
    local ns = vim.api.nvim_create_namespace 'alpha_colors'
    local function apply_highlights()
      local buf = vim.api.nvim_get_current_buf()
      if vim.bo[buf].filetype ~= 'alpha' then
        return
      end
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for i, line in ipairs(lines) do
        local row = i - top_padding
        if row >= 1 and row <= #combined then
          -- Detect centering offset: alpha prepends spaces to center
          local combined_line = combined[row] or ''
          local offset = #line - #combined_line
          if offset < 0 then
            offset = 0
          end

          -- Art portion
          local art_line = art[row] or ''
          local art_end = #art_line
          if art_end > 0 then
            vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
              end_col = math.min(offset + art_end, #line),
              hl_group = 'AlphaArt',
            })
          end
          -- Side panel portion
          local side_start = (art_byte_ends[row] or 0) + offset
          if side_start > 0 and side_start < #line then
            local hl_map = { menu = 'AlphaMenu', footer = 'AlphaFooter', fortune = 'AlphaFortune' }
            local hl = hl_map[side_type[row]]
            if hl then
              vim.api.nvim_buf_set_extmark(buf, ns, i - 1, side_start, {
                end_col = #line,
                hl_group = hl,
              })
            end
          end
        end
      end
    end

    vim.api.nvim_create_autocmd('User', {
      pattern = 'AlphaReady',
      callback = function()
        vim.defer_fn(apply_highlights, 10)
      end,
    })

    vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter', 'FocusGained', 'VimResume' }, {
      callback = function()
        if vim.bo.filetype == 'alpha' then
          vim.defer_fn(apply_highlights, 10)
        end
      end,
    })

    -- Update footer line in combined text after Lazy finishes loading
    vim.api.nvim_create_autocmd('User', {
      pattern = 'LazyVimStarted',
      callback = function()
        local stats = require('lazy').stats()
        local footer_text = icon(0xf487) .. ' ' .. stats.count .. ' plugins loaded in ' .. string.format('%.1f', stats.startuptime) .. 'ms'
        local target_row = menu_start_row + footer_line_idx - 1
        if target_row >= 1 and target_row <= #combined then
          local art_line = art[target_row] or ''
          local display_w = vim.fn.strdisplaywidth(art_line)
          local padding = math.max(0, art_display_width - display_w) + gap
          combined[target_row] = art_line .. string.rep(' ', padding) .. footer_text
          art_byte_ends[target_row] = #art_line + padding
          side_type[target_row] = 'footer'
          header.val = combined
          pcall(vim.cmd.AlphaRedraw)
          vim.defer_fn(apply_highlights, 10)
        end
      end,
    })
  end,
}
