#!/usr/bin/env bash
# Sync tmux theme with nvim lualine theme (boxy style)
# Reads `local theme = '...'` from the lualine config, then uses nvim to
# resolve the actual lualine color palette dynamically.

LUALINE_CONFIG="$HOME/.config/nvim/kickstart-modular/lua/custom/plugins/lualine.lua"
EXTRACT_SCRIPT="$HOME/.config/tmux/scripts/extract-colors.lua"

theme=$(grep "^local theme" "$LUALINE_CONFIG" | sed "s/.*['\"]\\(.*\\)['\"].*/\\1/")

# Use nvim -l to resolve colors from the lualine theme (fast, no editor UI)
colors=$(LUALINE_THEME="$theme" nvim -l "$EXTRACT_SCRIPT" 2>/dev/null)

if [ -n "$colors" ]; then
  IFS=$'\t' read -r bg bg1 bg3 fg accent grey prefix_accent session_accent <<< "$colors"
fi

# Fallback to terminal defaults (matches lualine default/auto)
: "${bg:=black}"
: "${bg1:=colour236}"
: "${bg3:=colour239}"
: "${fg:=white}"
: "${accent:=green}"
: "${grey:=colour245}"
: "${prefix_accent:=yellow}"
: "${session_accent:=blue}"

# Session item uses command-mode color, swaps to visual-mode on prefix
tmux set -g status-style "bg=default"
tmux set -g status-left "#{?client_prefix,#[fg=$bg]#[bg=$prefix_accent]#[bold] #S #[bg=default] ,#[fg=$bg]#[bg=$session_accent]#[bold] #S #[bg=default] }"
tmux set -g status-right "#[fg=$fg,bg=$bg1] #{b:pane_current_path} "
tmux set -g window-status-format "#[fg=$grey,bg=$bg1] #I #W #[bg=default]"
tmux set -g window-status-current-format "#[fg=$bg,bg=$accent,bold] #I #W#{?window_zoomed_flag, 󰁌,} #[bg=default]"
tmux set -g window-status-separator " "
tmux set -g pane-active-border-style "fg=$accent,bg=default"
tmux set -g pane-border-style "fg=$bg3,bg=default"
tmux set -g message-style "fg=$fg,bg=$bg1"
tmux set -g message-command-style "fg=$fg,bg=$bg1"
tmux set -g mode-style "fg=$bg,bg=$accent"
