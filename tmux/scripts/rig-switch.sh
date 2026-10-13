#!/usr/bin/env bash
# rig-switch.sh — get around OpenRig seats from tmux.
#
#   rig-switch.sh --open <client>        prefix+A: fzf popup of every rig seat
#   rig-switch.sh --next-input <client>  prefix+N: cycle the seats waiting on you
#   rig-switch.sh --last-alert <client>  prefix+a: jump to the last agent that rang
#
# Seats are the tmux sessions OpenRig names <pod>-<seat>@<rig>. Their state comes
# from `rig ps`; with the daemon down the picker still lists them, stateless.
# The last alert is recorded by agent-notify.sh in @agent-last-alert.

self="$0"
mode="${1:-}"
client="${2:-}"

msg() { tmux display-message ${client:+-c "$client"} "$1"; }

# seat sessions that actually exist; rig ps also lists stale records
live_seats() { tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '@'; }

# "rank<TAB>session<TAB>rig<TAB>seat<TAB>runtime<TAB>state<TAB>work", one per
# live seat, most urgent first. Optional <rig> limits it to that rig.
seat_rows() {
  local only="${1:-}" sessions nodes
  sessions=$(live_seats) || return 0
  # </dev/null: rig is Node, which saves the tty mode at startup and restores
  # it on exit. Run alongside fzf, it put the popup back into cooked mode
  # after fzf had made it raw, and fzf stopped seeing keys.
  nodes=$(rig ps --nodes -A --json </dev/null 2>/dev/null) || nodes='[]'
  jq -r --arg sessions "$sessions" --arg only "$only" '
    (map({key: .canonicalSessionName, value: .}) | from_entries) as $by
    | $sessions | split("\n")[] | select(length > 0)
    | . as $s
    | ($s | split("@")) as $p
    | select($only == "" or $p[1] == $only)
    | ($by[$s] // {}) as $n
    | ($n.agentActivity.state // "unknown") as $st
    | [ ({needs_input: 0, running: 1, idle: 2}[$st] // 3),
        $s, $p[1], ($p[0] | sub("^[^-]*-"; "")),
        ($n.runtime // "?" | sub("-code$"; "")), $st,
        (($n.assignedWorkCount // 0) + ($n.pendingWorkCount // 0)) ]
    | @tsv' <<<"$nodes" | sort -t $'\t' -k1,1n -k3,3 -k4,4
}

# fzf lines: "session<TAB>rig<TAB>display"; fzf shows only the display part.
picker_lines() {
  seat_rows "${1:-}" | awk -F '\t' '
    { row[NR] = $0; if (length($3) > w) w = length($3) }
    END {
      for (i = 1; i <= NR; i++) {
        split(row[i], f, "\t")
        if      (f[6] == "needs_input") { icon = "\033[33m▲\033[0m"; st = "\033[33minput\033[0m" }
        else if (f[6] == "running")     { icon = "\033[32m●\033[0m"; st = "\033[32mworking\033[0m" }
        else if (f[6] == "idle")        { icon = "\033[90m○\033[0m"; st = "\033[90midle\033[0m" }
        else                            { icon = "\033[90m?\033[0m"; st = "\033[90m?\033[0m" }
        work = f[7] > 0 ? "  " f[7] " queued" : ""
        printf "%s\t%s\t%s %-" w "s  %-6s %-7s %s%s\n", f[2], f[3], icon, f[3], f[4], f[5], st, work
      }
    }'
}

case "$mode" in
  --open)
    if ! live_seats >/dev/null; then msg "No rig sessions running"; exit 0; fi
    # An explicit bg, not default: tmux 3.8's popup-style is a grey, and
    # "default" inside a popup inherits it. #232a2e is everforest's bg_dim.
    tmux display-popup -c "$client" -E -B -s bg=#232a2e,fg=terminal -w 85% -h 75% \
      "'$self' --pick '$client'"
    ;;

  --pick)   # runs inside the popup
    # alt-c narrows to the rig you are in, or the highlighted row's rig when
    # you are not in one; alt-a goes back to every rig.
    here=$(tmux display-message -c "$client" -p '#{session_name}' 2>/dev/null)
    case "$here" in *@*) here_rig="${here#*@}" ;; *) here_rig="" ;; esac
    if [ -n "$here_rig" ]; then this_prompt="change-prompt(  $here_rig  )"
    else this_prompt="transform-prompt(echo '  '{2}'  ')"; fi
    choice=$(picker_lines | fzf --ansi --delimiter '\t' --with-nth 3 \
      --no-sort --layout reverse --border rounded --border-label ' Rig seats ' \
      --prompt '   ' --info inline-right \
      --header 'enter switch · alt-c this rig · alt-a all rigs · ctrl-r refresh' \
      --preview "tmux capture-pane -ep -t {1} | awk 'NF{last=NR} {l[NR]=\$0} END{for(i=1;i<=last;i++)print l[i]}' | tail -n \$FZF_PREVIEW_LINES" \
      --preview-window 'right,55%,border-left' \
      --bind 'focus:transform-preview-label:echo " {1} "' \
      --bind "alt-c:reload('$self' --lines '${here_rig}' {2})+$this_prompt" \
      --bind "alt-a:reload('$self' --lines)+change-prompt(   )" \
      --bind "ctrl-r:reload('$self' --lines)") || exit 0
    tmux switch-client -c "$client" -t "=$(cut -f1 <<<"$choice")"
    ;;

  --lines)  # reload source for the picker: [<current rig> [<row's rig>]]
    picker_lines "${2:-${3:-}}"
    ;;

  --next-input)
    waiting=$(seat_rows | awk -F '\t' '$1 == 0 { print $2 }')
    [ -n "$waiting" ] || { msg "No seats waiting on you"; exit 0; }
    here=$(tmux display-message -c "$client" -p '#{session_name}')
    # the one after the current seat, wrapping; the first if you're elsewhere
    next=$(awk -v here="$here" '
      { s[NR] = $0; if ($0 == here) at = NR }
      END { print s[at && at < NR ? at + 1 : 1] }' <<<"$waiting")
    tmux switch-client -c "$client" -t "=$next"
    ;;

  --last-alert)
    pane=$(tmux show -gv @agent-last-alert 2>/dev/null)
    if [ -z "$pane" ] || ! tmux display-message -p -t "$pane" '' 2>/dev/null; then
      msg "No agent alert to go to"; exit 0
    fi
    # a pane target selects its session, window and pane in one go
    tmux switch-client -c "$client" -t "$pane"
    ;;

  *)
    echo "usage: $(basename "$0") --open|--next-input|--last-alert <client>" >&2
    exit 1
    ;;
esac
