# Dev layout: left nvim, right top claude, right bottom lazygit
split-window -h -c "#{pane_current_path}"
split-window -v -c "#{pane_current_path}"
send-keys 'lazygit' C-m
select-pane -U
send-keys 'claude' C-m
select-pane -L
send-keys 'nvim' C-m

