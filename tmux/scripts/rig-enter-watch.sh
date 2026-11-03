#!/usr/bin/env bash
# rig-enter-watch.sh — press Enter on OpenRig messages left in an agent's input box.
#
#   rig-enter-watch.sh --start        from tmux.conf: start the watcher once per tmux server
#   rig-enter-watch.sh --box <pane>   print the text in <pane>'s Claude input box
#
# OpenRig delivers a message by pasting it into the seat's Claude prompt and
# pressing Enter 200ms later. Under load Claude sometimes loses that Enter, and
# the message sits in the box until someone notices. Every few seconds this
# looks at each rig seat's input box (between Claude's last two ─── rules: a
# queued message sits above them and isn't touched). When the box holds only an
# OpenRig message ("From: <seat>@<rig>" or "[OpenRig ...") and it hasn't
# changed since the last look, it presses Enter. Anything you've typed after it
# changes the box, so a message you're adding to isn't sent until you stop
# typing for a full interval; one that doesn't start like OpenRig's is never sent.

INTERVAL=4
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/rig-enter-watch.log"
PIDFILE="${XDG_CACHE_HOME:-$HOME/.cache}/rig-enter-watch.pid"

box() { # <pane>: the input box's text, lines joined with "\n"
  tmux capture-pane -p -t "$1" 2>/dev/null | awk '
    /^─────────/ { a = b; b = NR }
    { l[NR] = $0 }
    END { if (a) for (i = a + 1; i < b; i++) print l[i] }'
}

case "${1:-}" in
  --box) box "$2"; exit 0 ;;
  --start)
    mkdir -p "${PIDFILE%/*}"
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then exit 0; fi
    nohup "$0" --run >/dev/null 2>&1 &
    echo $! >"$PIDFILE"
    exit 0 ;;
  --run) ;;
  *) echo "usage: $(basename "$0") --start | --box <pane>" >&2; exit 1 ;;
esac

# What each pane's box held at the last look: one file per pane id.
SEEN=$(mktemp -d "${TMPDIR:-/tmp}/rig-enter-watch.XXXXXX")
trap 'rm -rf "$SEEN"' EXIT
while tmux list-sessions >/dev/null 2>&1; do
  while read -r session pane; do
    text=$(box "$pane") last="$SEEN/${pane#%}"
    first=${text%%$'\n'*}
    case "$first" in
      "❯ From: "*@*|"❯ [OpenRig "*) ;;
      *) rm -f "$last"; continue ;;
    esac
    if [ -f "$last" ] && [ "$(cat "$last")" = "$text" ]; then
      tmux send-keys -t "$pane" Enter
      printf '%s %s pressed Enter: %s\n' "$(date '+%m-%d %H:%M:%S')" "$session" "${first:2:80}" >>"$LOG"
      rm -f "$last"
    else
      printf '%s' "$text" >"$last"
    fi
  done < <(tmux list-panes -a -F '#{session_name} #{pane_id}' 2>/dev/null | grep '^[^ ]*@')
  [ ! -f "$LOG" ] || [ "$(wc -l <"$LOG")" -lt 2000 ] || { tail -n 1000 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"; }
  sleep "$INTERVAL"
done
rm -f "$PIDFILE"
