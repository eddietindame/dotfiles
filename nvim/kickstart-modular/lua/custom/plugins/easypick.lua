return {
  'axkirillov/easypick.nvim',
  dependencies = { 'nvim-telescope/telescope.nvim' },
  keys = {
    { '<leader>se', '<cmd>Easypick git_changed_files<CR>', desc = '[S]earch [E]dited files' },
  },
  config = function()
    local easypick = require 'easypick'
    local previewers = require 'telescope.previewers'

    local function make_delta_previewer()
      return previewers.new_termopen_previewer {
        get_command = function(entry)
          return { 'bash', '-c', 'git diff -- ' .. vim.fn.shellescape(entry.value) .. ' | delta' }
        end,
      }
    end

    local function make_diff_so_fancy_previewer()
      return previewers.new_termopen_previewer {
        get_command = function(entry)
          return { 'bash', '-c', 'git diff -- ' .. vim.fn.shellescape(entry.value) .. ' | diff-so-fancy' }
        end,
      }
    end

    -- Available previewers: 'default', 'delta', 'diff-so-fancy'
    vim.g.easypick_diff_previewer = vim.g.easypick_diff_previewer or 'delta'

    local function get_previewer()
      local choice = vim.g.easypick_diff_previewer
      if choice == 'delta' then
        return make_delta_previewer()
      elseif choice == 'diff-so-fancy' then
        return make_diff_so_fancy_previewer()
      else
        return easypick.previewers.file_diff()
      end
    end

    -- Command to switch previewer: :EasypickPreviewer <name>
    vim.api.nvim_create_user_command('EasypickPreviewer', function(opts)
      local choices = { default = true, delta = true, ['diff-so-fancy'] = true }
      local choice = opts.args
      if choices[choice] then
        vim.g.easypick_diff_previewer = choice
        vim.notify('Diff previewer: ' .. choice, vim.log.levels.INFO)
      else
        vim.notify('Choose: default, delta, diff-so-fancy', vim.log.levels.ERROR)
      end
    end, {
      nargs = 1,
      complete = function()
        return { 'default', 'delta', 'diff-so-fancy' }
      end,
    })

    easypick.setup {
      pickers = {
        {
          name = 'git_changed_files',
          command = 'git diff --name-only --relative',
          previewer = get_previewer(),
          opts = {
            prompt_title = 'Git Changed Files',
          },
        },
      },
    }
  end,
}
