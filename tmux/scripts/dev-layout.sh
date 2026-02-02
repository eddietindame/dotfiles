#!/bin/bash
# Creates a layout with:
# - Left half: main editor pane
# - Right top quarter: empty shell
# - Right bottom quarter: lazygit

SESSION_NAME="${1:-dev}"
WORKING_DIR="${2:-$(pwd)}"

# Create session with first pane (left half - main editor)
tmux new-session -d -s "$SESSION_NAME" -c "$WORKING_DIR"

# Split right (creates right pane, 50% width)
tmux split-window -h -c "$WORKING_DIR"

# Split the right pane vertically (top and bottom quarters)
tmux split-window -v -c "$WORKING_DIR"

# Run lazygit in the bottom-right pane (pane 2)
tmux send-keys -t "$SESSION_NAME:1.2" 'lazygit' C-m

# Run claude in the top-right pane (pane 1)
tmux send-keys -t "$SESSION_NAME:1.1" 'claude' C-m

# Run nvim in the left pane (pane 0)
tmux send-keys -t "$SESSION_NAME:1.0" 'nvim' C-m

# Select the main left pane
tmux select-pane -t "$SESSION_NAME:1.0"

# Attach to session
tmux attach-session -t "$SESSION_NAME"

