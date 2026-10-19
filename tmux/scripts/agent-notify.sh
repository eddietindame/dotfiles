#!/usr/bin/env bash
# agent-notify.sh <done|input> — ring the terminal when an agent changes state,
# the tmux stand-in for herdr's sounds. Called from Claude Code and Codex hooks
# and Pi's extension (pi/extensions/agent-notify.ts).
#
# Rings every attached tmux client directly instead of sending a bell to the
# agent's own pane: tmux only forwards a pane's bell to clients attached to that
# session, and OpenRig seats live in sessions nobody is attached to. A BEL is
# also the only signal that survives mosh to the laptop (it drops OSC 9/777
# notifications), so Ghostty on the laptop turns it into the sound.
#
#   done   one bell   — the agent finished its turn
#   input  two bells  — the agent is waiting on you (permission, question)
#
# Clients already looking at the agent's pane get neither: you can see it.

state="${1:-done}"
cat >/dev/null 2>&1 || true   # hook payload on stdin; not needed

command -v tmux >/dev/null || exit 0
# OpenRig starts Pi seats with a bare environment: no TMUX_PANE, but the seat's
# session name, which is also its tmux session.
if [ -z "${TMUX_PANE:-}" ] && [ -n "${OPENRIG_SESSION_NAME:-}" ]; then
  TMUX_PANE=$(tmux display-message -p -t "=$OPENRIG_SESSION_NAME:" '#{pane_id}' 2>/dev/null)
fi
[ -n "${TMUX_PANE:-}" ] || exit 0   # not in tmux (herdr has its own sounds)

label=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_name}' 2>/dev/null) || exit 0
# For prefix+a (rig-switch.sh --last-alert): a pane id targets session, window
# and pane at once.
tmux set -g @agent-last-alert "$TMUX_PANE"

case "$state" in
  input) bells=2 text="needs input" ;;
  *)     bells=1 text="done" ;;
esac

tmux list-clients -F '#{client_name}	#{client_tty}	#{pane_id}' 2>/dev/null |
  while IFS=$'\t' read -r client tty pane; do
    [ "$pane" = "$TMUX_PANE" ] && continue
    tmux display-message -c "$client" -d 5000 "🔔 $label — $text" 2>/dev/null
    (
      i=0
      while [ "$i" -lt "$bells" ]; do
        printf '\a' >"$tty" 2>/dev/null
        i=$((i + 1))
        # mosh sends one bell per screen update however many arrived, so space
        # them out or two bells reach the laptop as one.
        [ "$i" -lt "$bells" ] && sleep 0.5
      done
    ) &
  done
wait
exit 0
