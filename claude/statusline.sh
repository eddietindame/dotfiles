#!/bin/bash
input=$(cat)

# Extract fields
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
session_name=$(echo "$input" | jq -r '.session_name // ""')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // "~"')
display_dir="${cwd/#$HOME/~}"
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // 0')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

# Colors
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

output=""

# Model name (cyan bold)
output="${CYAN}${BOLD}[${model}]${RESET}"

output="${output} ${DIM}│${RESET} "

# Chat name (if set via /rename)
if [ -n "$session_name" ]; then
  output="${output}${BOLD}${session_name}${RESET} ${DIM}│${RESET} "
fi

# Directory with emoji
output="${output}📁 ${display_dir}"

# Git branch
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
  if [ -n "$branch" ]; then
    output="${output} ${DIM}on${RESET} ${GREEN}${RESET} ${branch}"
  fi
fi

output="${output} ${DIM}│${RESET} "

# Context bar (green)
bar_width=10
filled=$((remaining * bar_width / 100))
empty=$((bar_width - filled))
bar="${GREEN}"
i=0; while [ $i -lt $filled ]; do bar="${bar}█"; i=$((i+1)); done
i=0; while [ $i -lt $empty ]; do bar="${bar}░"; i=$((i+1)); done
bar="${bar}${RESET} ${remaining}%"
output="${output}${bar}"

output="${output} ${DIM}│${RESET} "

# Cost (yellow)
cost_formatted=$(printf "%.4f" "$cost")
output="${output}${YELLOW}\$${cost_formatted}${RESET}"

output="${output} ${DIM}│${RESET} "

# Session time
duration_s=$((duration_ms / 1000))
hours=$((duration_s / 3600))
minutes=$(((duration_s % 3600) / 60))
seconds=$((duration_s % 60))
if [ $hours -gt 0 ]; then
  time_str=$(printf "%dh%02dm" $hours $minutes)
elif [ $minutes -gt 0 ]; then
  time_str=$(printf "%dm%02ds" $minutes $seconds)
else
  time_str="${seconds}s"
fi
output="${output}${DIM}⏱ ${time_str}${RESET}"

echo -e "$output"
