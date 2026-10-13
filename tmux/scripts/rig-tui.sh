#!/usr/bin/env bash
# rig-tui.sh — the OpenRig dashboard as a floax-style popup that keeps its state.
#
#   rig-tui.sh --toggle <client>   prefix+p: show the dashboard, or hide it again
#   rig-tui.sh                     run rig tui itself (the session's process)
#
# The dashboard lives in its own session, rig-tui, and the popup only attaches
# to it, so closing the popup leaves it where it was. prefix+p inside the popup
# detaches (hides); q in the dashboard quits it, and the next prefix+p starts a
# fresh one.

SESSION=rig-tui
self="$0"

if [ "${1:-}" = "--toggle" ]; then
  client="${2:-}"
  # Inside the popup the client is the popup's own, attached to rig-tui: hide.
  if [ "$(tmux display-message -c "$client" -p '#{session_name}')" = "$SESSION" ]; then
    tmux detach-client -t "$client"
    exit 0
  fi
  if ! tmux has-session -t "=$SESSION" 2>/dev/null; then
    tmux new-session -d -s "$SESSION" -x 200 -y 50 "'$self'"
    tmux set -t "$SESSION" status off   # set rejects the = exact-match prefix
  else
    # tmux-resurrect restores the session as a bare shell: put the TUI back.
    # (Checked as "is it a shell" because the TUI itself shows up as
    # volta-shim, not as rig or node.)
    case "$(tmux display-message -p -t "=$SESSION:" '#{pane_current_command}')" in
      zsh|bash|sh|fish) tmux respawn-pane -k -t "=$SESSION:" "'$self'" ;;
    esac
  fi
  # Your config has detach-on-destroy off, so when q ends the TUI the popup's
  # client would hop to another session and stay open, and the next prefix+p
  # from inside it nested a second popup. For this session, detach instead:
  # the popup closes with the TUI.
  tmux set -t "$SESSION" detach-on-destroy on
  tmux display-popup -c "$client" -E -w 90% -h 90% -b rounded -T ' OpenRig ' \
    -s bg=terminal,fg=terminal "TMUX= tmux attach -t '=$SESSION'"
  exit 0
fi

# A session started from inside a rig seat inherits the seat's OPENRIG_*
# variables. rig tui then takes itself for that agent, prints help instead of
# the dashboard and exits 1. Run it as you, not as the seat.
for v in $(env | sed -n 's/^\(OPENRIG_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
exec "$HOME/.volta/bin/rig" tui
