# Dev layout: left half editor, right top shell, right bottom lazygit
split-window -h -c "#{pane_current_path}"
split-window -v -c "#{pane_current_path}"
send-keys 'lazygit' C-m
select-pane -t 0
