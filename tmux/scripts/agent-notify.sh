#!/usr/bin/env bash
# agent-notify.sh <done|input> — alert you when an agent changes state, the
# tmux stand-in for herdr's sounds. Called from Claude Code and Codex hooks and
# Pi's extension (pi/extensions/agent-notify.ts).
#
#   done   a bell     — the agent finished its turn
#   input  a sound    — the agent is waiting on you (permission, question)
#
# done rings every attached tmux client directly instead of sending a bell to
# the agent's own pane: tmux only forwards a pane's bell to clients attached to
# that session, and OpenRig seats live in sessions nobody is attached to. A BEL
# is also the only signal that survives mosh to the laptop (it drops OSC 9/777
# notifications), so Ghostty on the laptop turns it into its bell sound.
# input needs a sound of its own, which a BEL can't carry, so it plays one on
# the laptop over ssh (@agent-input-sound, default Glass); if the laptop can't
# be reached it falls back to two bells.
#
# Which agents alert, @agent-alert-mode (prefix+M cycles it):
#   lead     rig leads only; builders and reviewers stay quiet (default).
#            Agents outside rigs still alert.
#   current  only agents in the session or rig the client is in
#   all      every agent
# Clients already looking at the agent's pane get nothing: you can see it.

state="${1:-done}"
cat >/dev/null 2>&1 || true   # hook payload on stdin; not needed

LAPTOP=eddietindame@100.86.187.87   # as in copy-on-laptop.sh

if [ "$state" = --cycle ]; then   # prefix+M: <client>
  case "$(tmux show -gv @agent-alert-mode 2>/dev/null)" in
    current) next=all ;;
    all)     next=lead ;;
    *)       next=current ;;
  esac
  tmux set -g @agent-alert-mode "$next"
  case "$next" in
    lead)    what="rig leads only (and agents outside rigs)" ;;
    current) what="only agents in the session or rig you're in" ;;
    all)     what="every agent" ;;
  esac
  tmux display-message ${2:+-c "$2"} "Agent alerts: $next — $what"
  exit 0
fi

command -v tmux >/dev/null || exit 0
# OpenRig starts Pi seats with a bare environment: no TMUX_PANE, but the seat's
# session name, which is also its tmux session.
if [ -z "${TMUX_PANE:-}" ] && [ -n "${OPENRIG_SESSION_NAME:-}" ]; then
  TMUX_PANE=$(tmux display-message -p -t "=$OPENRIG_SESSION_NAME:" '#{pane_id}' 2>/dev/null)
fi
[ -n "${TMUX_PANE:-}" ] || exit 0   # not in tmux (herdr has its own sounds)

session=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null) || exit 0
label=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_name}')
mode=$(tmux show -gv @agent-alert-mode 2>/dev/null); mode="${mode:-lead}"

# Rig seats are <pod>-<seat>@<rig>; leads are <pod>-lead@<rig>.
case "$session" in *@*) rig="${session#*@}" ;; *) rig="" ;; esac
if [ "$mode" = lead ] && [ -n "$rig" ]; then
  case "${session%@*}" in *-lead) ;; *) exit 0 ;; esac
fi

# The clients to alert, as "<client>\t<tty>" lines.
targets=$(tmux list-clients -F '#{client_name}	#{client_tty}	#{pane_id}	#{session_name}' 2>/dev/null |
  while IFS=$'\t' read -r client tty pane csession; do
    [ "$pane" = "$TMUX_PANE" ] && continue
    if [ "$mode" = current ] && [ "$csession" != "$session" ]; then
      [ -n "$rig" ] && [ "${csession#*@}" = "$rig" ] && [ "$csession" != "${csession#*@}" ] || continue
    fi
    printf '%s\t%s\n' "$client" "$tty"
  done)
[ -n "$targets" ] || exit 0

# For prefix+a (rig-switch.sh --last-alert): a pane id targets session, window
# and pane at once.
tmux set -g @agent-last-alert "$TMUX_PANE"

case "$state" in
  input) text="needs input" ;;
  *)     text="done" ;;
esac

bell() { # <tty> <count>
  local i=0
  while [ "$i" -lt "$2" ]; do
    printf '\a' >"$1" 2>/dev/null
    i=$((i + 1))
    # mosh sends one bell per screen update however many arrived, so space
    # them out or two bells reach the laptop as one.
    [ "$i" -lt "$2" ] && sleep 0.5
  done
}

played=false
if [ "$state" = input ]; then
  sound=$(tmux show -gv @agent-input-sound 2>/dev/null); sound="${sound:-Glass}"
  ssh -o BatchMode=yes -o ConnectTimeout=3 "$LAPTOP" \
    "nohup afplay /System/Library/Sounds/$sound.aiff >/dev/null 2>&1 &" </dev/null >/dev/null 2>&1 &&
    played=true
fi

while IFS=$'\t' read -r client tty; do
  tmux display-message -c "$client" -d 5000 "🔔 $label — $text" 2>/dev/null
  if [ "$state" = input ]; then
    $played || bell "$tty" 2 &
  else
    bell "$tty" 1 &
  fi
done <<<"$targets"
wait
exit 0
