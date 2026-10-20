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
# Which alerts reach you, as tmux options (prefix+M toggles them in a menu):
#   @agent-alert-leads        on   rig leads, done and input
#   @agent-alert-seat-input   on   builders and reviewers waiting on you
#   @agent-alert-seat-done    off  builders and reviewers finishing a turn
#   @agent-alert-outside      on   agents outside rigs (your own claude, start-dev)
#   @agent-alert-current      off  only agents in the session or rig you're in
# Clients already looking at the agent's pane get nothing: you can see it.

state="${1:-done}"
cat >/dev/null 2>&1 || true   # hook payload on stdin; not needed

LAPTOP=eddietindame@100.86.187.87   # as in copy-on-laptop.sh

# @agent-alert-<name>, or its default when unset
DEFAULTS="leads=on seat-input=on seat-done=off outside=on current=off"
opt() {
  local v; v=$(tmux show -gv "@agent-alert-$1" 2>/dev/null)
  if [ -z "$v" ]; then v="${DEFAULTS#*"$1"=}"; v="${v%% *}"; fi
  printf '%s' "$v"
}

case "$state" in
  --menu)   # prefix+M: <client>. Checkboxes; picking one toggles it and reopens.
    client="${2:-}"
    items=()
    item() { # <option> <key> <text>
      # Nerd Font toggle switches (nf-md-toggle_switch / _off_outline)
      local box="#[fg=#7a8478]󰨙#[default]"
      [ "$(opt "$1")" = on ] && box="#[fg=#a7c080]󰔡#[default]"
      box=$(printf "$box")
      items+=("$box $3" "$2" "run-shell -b \"'$0' --toggle $1 '$client'\"")
    }
    item leads      l "Rig leads"
    item seat-input i "Builders and reviewers needing input"
    item seat-done  d "Builders and reviewers finishing"
    item outside    o "Agents outside rigs"
    items+=("")
    item current    c "Only the rig or session I'm in"
    tmux display-menu ${client:+-c "$client"} -T " Agent alerts " -x C -y C "${items[@]}"
    exit 0 ;;
  --toggle) # <option> <client>, from the menu
    [ "$(opt "$2")" = on ] && v=off || v=on
    tmux set -g "@agent-alert-$2" "$v"
    exec "$0" --menu "${3:-}" ;;
esac

command -v tmux >/dev/null || exit 0
# OpenRig starts Pi seats with a bare environment: no TMUX_PANE, but the seat's
# session name, which is also its tmux session.
if [ -z "${TMUX_PANE:-}" ] && [ -n "${OPENRIG_SESSION_NAME:-}" ]; then
  TMUX_PANE=$(tmux display-message -p -t "=$OPENRIG_SESSION_NAME:" '#{pane_id}' 2>/dev/null)
fi
[ -n "${TMUX_PANE:-}" ] || exit 0   # not in tmux (herdr has its own sounds)

session=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null) || exit 0
label=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_name}')

# Rig seats are <pod>-<seat>@<rig>; leads are <pod>-lead@<rig>.
case "$session" in *@*) rig="${session#*@}" ;; *) rig="" ;; esac
if [ -z "$rig" ]; then
  wanted=$(opt outside)
else
  case "${session%@*}" in
    *-lead) wanted=$(opt leads) ;;
    *)      [ "$state" = input ] && wanted=$(opt seat-input) || wanted=$(opt seat-done) ;;
  esac
fi
[ "$wanted" = on ] || exit 0
current=$(opt current)

# The clients to alert, as "<client>\t<tty>" lines.
targets=$(tmux list-clients -F '#{client_name}	#{client_tty}	#{pane_id}	#{session_name}' 2>/dev/null |
  while IFS=$'\t' read -r client tty pane csession; do
    [ "$pane" = "$TMUX_PANE" ] && continue
    if [ "$current" = on ] && [ "$csession" != "$session" ]; then
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
