#!/usr/bin/env bash
# rig-switch.sh — get around OpenRig seats from tmux.
#
#   rig-switch.sh --open <client>        prefix+A: fzf popup of rig leads / seats
#   rig-switch.sh --last-lead <client>   prefix+g: back to the last lead you were in
#   rig-switch.sh --next-input <client>  prefix+N: cycle the seats waiting on you
#   rig-switch.sh --last-alert <client>  prefix+a: jump to the last agent that rang
#
# Seats are the tmux sessions OpenRig names <pod>-<seat>@<rig>. Their state comes
# from `rig ps`; with the daemon down the picker still lists them, stateless.
# rig ps takes seconds, so the picker opens on the last result it saved and
# swaps in a fresh one when that arrives.
# The last alert is recorded by agent-notify.sh in @agent-last-alert.

self="$0"
mode="${1:-}"
client="${2:-}"

msg() { tmux display-message ${client:+-c "$client"} "$1"; }

# seat sessions that actually exist; rig ps also lists stale records
live_seats() { tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '@'; }

# rig ps's seat records. Every fetch is saved; with RIG_CACHED=1 the saved one
# is used when there is one. Only the states can be out of date that way: the
# seats themselves always come from tmux.
NODES_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/rig-switch/nodes.json"
rig_nodes() {
  local nodes
  if [ "${RIG_CACHED:-}" = 1 ] && [ -s "$NODES_CACHE" ]; then cat "$NODES_CACHE"; return; fi
  # </dev/null: rig is Node, which saves the tty mode at startup and restores
  # it on exit. Run alongside fzf, it put the popup back into cooked mode
  # after fzf had made it raw, and fzf stopped seeing keys.
  # --full for the activity reason: see the stale-hook note below.
  if nodes=$(rig ps --nodes -A --full --json </dev/null 2>/dev/null); then
    mkdir -p "${NODES_CACHE%/*}" &&
      printf '%s\n' "$nodes" >"$NODES_CACHE.$$" && mv "$NODES_CACHE.$$" "$NODES_CACHE"
    printf '%s\n' "$nodes"
  else
    # daemon down or not answering: the saved states beat none
    cat "$NODES_CACHE" 2>/dev/null || echo '[]'
  fi
}

# "rank<TAB>session<TAB>rig<TAB>seat<TAB>runtime<TAB>state<TAB>work<TAB>last",
# one per live seat, most urgent first; last is when you were last in it.
# Optional <rig> limits it to that rig.
seat_rows() {
  local only="${1:-}" sessions nodes
  sessions=$(tmux list-sessions -F '#{session_name}	#{session_last_attached}' 2>/dev/null |
    grep '@') || return 0
  nodes=$(rig_nodes)
  jq -r --arg sessions "$sessions" --arg only "$only" '
    (map({key: .canonicalSessionName, value: .}) | from_entries) as $by
    | $sessions | split("\n")[] | select(length > 0)
    | split("\t") as [$s, $last]
    | ($s | split("@")) as $p
    | select($only == "" or $p[1] == $only)
    | ($by[$s] // {}) as $n
    # OpenRig drops a seat to "unknown" once its last Claude hook is over 5
    # minutes old and its pane heuristic has no verdict, which is most quiet
    # seats. A busy seat still shows as running (OpenRig sees the pane move),
    # so a stale hook still says what the seat is doing: read it instead.
    | ($n.agentActivity // {}) as $a
    | (if ($a.state // "unknown") == "unknown" and $a.stale == true
       then ({idle_prompt: "idle", permission_prompt: "needs_input",
              elicitation_dialog: "needs_input"}[$a.evidence // ""] // "unknown")
       else ($a.state // "unknown") end) as $st
    | [ ({needs_input: 0, running: 1, idle: 2}[$st] // 3),
        $s, $p[1], ($p[0] | sub("^[^-]*-"; "")),
        ($n.runtime // "?" | sub("-code$"; "")), $st,
        (($n.assignedWorkCount // 0) + ($n.pendingWorkCount // 0)),
        ($last // "0" | if . == "" then "0" else . end) ]
    | @tsv' <<<"$nodes" | sort -t $'\t' -k1,1n -k3,3 -k4,4
}

# fzf lines are "session<TAB>rig<TAB>display"; fzf shows only the display part.
# Shared by both views: icon and coloured state word for a seat state.
AWK_STATE='
  function icon(st) {
    if (st == "needs_input") return "\033[33m▲\033[0m"
    if (st == "running")     return "\033[32m●\033[0m"
    if (st == "idle")        return "\033[90m○\033[0m"
    return "\033[90m?\033[0m"
  }
  function word(st) {
    if (st == "needs_input") return "\033[33minput  \033[0m"
    if (st == "running")     return "\033[32mworking\033[0m"
    if (st == "idle")        return "\033[90midle   \033[0m"
    return "\033[90m?      \033[0m"
  }'

# Every seat, most urgent first. Optional <rig> limits it to that rig.
seat_lines() {
  seat_rows "${1:-}" | awk -F '\t' "$AWK_STATE"'
    { row[NR] = $0; if (length($3) > w) w = length($3) }
    END {
      for (i = 1; i <= NR; i++) {
        split(row[i], f, "\t")
        work = f[7] > 0 ? "  " f[7] " queued" : ""
        printf "%s\t%s\t%s %-" w "s  %-6s %-7s %s%s\n", f[2], f[3], icon(f[6]), f[3], f[4], f[5], word(f[6]), work
      }
    }'
}

# One line per rig, for its lead, with the other seats' states after it. The
# lead you were in last comes first, so enter usually takes you back to it; the
# rig you are in now goes last. <here> is the rig you are in, if any.
# left/right pick another seat in a row instead of the lead: the picks live in
# $RIG_SEL ("<rig> <n>" lines; 0 is the lead) and the row's session field
# becomes that seat, so the preview and enter follow it.
lead_lines() {
  seat_rows | sort -t $'\t' -k3,3 -k4,4 | awk -F '\t' -v here="${1:-}" -v selfile="${RIG_SEL:-}" "$AWK_STATE"'
    BEGIN { if (selfile != "") while ((getline l < selfile) > 0) { split(l, a, " "); sel[a[1]] = a[2] } }
    {
      rig = $3
      if (!(rig in seen)) { seen[rig] = 1; order[++n] = rig; if (length(rig) > w) w = length(rig) }
      work[rig] += $7
      if ($4 == "lead") { lead[rig] = $2; st[rig] = $6; last[rig] = $8 }
      else { c = ++ncrew[rig]; cs[rig, c] = $2; cname[rig, c] = $4; cst[rig, c] = $6 }
    }
    END {
      for (i = 1; i <= n; i++) {
        rig = order[i]
        m = ncrew[rig] + 1
        k = ((sel[rig] + 0) % m + m) % m
        s = (rig in lead) ? lead[rig] : cs[rig, 1]
        crew = ""
        for (c = 1; c <= ncrew[rig]; c++) {
          label = (c == k) ? "\033[1;7m " cname[rig, c] " \033[0m" : cname[rig, c]
          crew = crew "  " icon(cst[rig, c]) " " label
          if (c == k) s = cs[rig, c]
        }
        key = (rig == here) ? -1 : last[rig] + 0
        q = work[rig] > 0 ? "  \033[90m" work[rig] " queued\033[0m" : ""
        printf "%d\t%s\t%s\t%s %-" w "s  %s%s%s\n", key, s, rig, icon(st[rig]), rig, word(st[rig]), crew, q
      }
    }' | sort -t $'\t' -k1,1nr | cut -f2-
}

LEADS_PROMPT=' leads › '
SEATS_PROMPT=' seats › '

case "$mode" in
  --open)
    if ! live_seats >/dev/null; then msg "No rig sessions running"; exit 0; fi
    # An explicit bg, not default: tmux 3.8's popup-style is a grey, and
    # "default" inside a popup inherits it. #232a2e is everforest's bg_dim.
    tmux display-popup -c "$client" -E -B -s bg=#232a2e,fg=terminal -w 85% -h 75% \
      "'$self' --pick '$client'"
    ;;

  --pick)   # runs inside the popup
    here=$(tmux display-message -c "$client" -p '#{session_name}' 2>/dev/null)
    case "$here" in *@*) here_rig="${here#*@}" ;; *) here_rig="" ;; esac
    export RIG_HERE="$here_rig"   # for --lines and --view, run by fzf
    RIG_SEL=$(mktemp "${TMPDIR:-/tmp}/rig-switch.XXXXXX") && export RIG_SEL
    trap 'rm -f "$RIG_SEL"' EXIT
    # Views and seat moves redraw from the saved states, so they're instant;
    # only refresh (ctrl-r, and once on open) waits for rig ps, and it keeps
    # the list up meanwhile. Before anything is saved, the first open waits.
    export RIG_CACHED=1
    hydrate=()
    [ -s "$NODES_CACHE" ] && hydrate=(--bind "load:unbind(load)+transform('$self' --view refresh)")
    choice=$(lead_lines "$here_rig" | fzf "${hydrate[@]}" --ansi --delimiter '\t' --with-nth 3 \
      --no-sort --layout reverse --border rounded --border-label ' Rigs ' \
      --prompt "$LEADS_PROMPT" --info inline-right \
      --header '←/→ seat · enter switch · tab leads/all seats · alt-c rig'"'"'s seats · ctrl-r refresh' \
      --preview "tmux capture-pane -ep -t {1} | awk 'NF{last=NR} {l[NR]=\$0} END{for(i=1;i<=last;i++)print l[i]}' | tail -n \$FZF_PREVIEW_LINES" \
      --preview-window 'right,50%,border-left' \
      --bind 'focus:transform-preview-label:echo " {1} "' \
      --bind "tab:transform('$self' --view toggle)" \
      --bind "right:transform('$self' --view next {2})" \
      --bind "left:transform('$self' --view prev {2})" \
      --bind "alt-c:reload('$self' --lines seats {2})+transform-prompt(echo ' '{2}' › ')" \
      --bind "ctrl-r:transform('$self' --view refresh)") || exit 0
    tmux switch-client -c "$client" -t "=$(cut -f1 <<<"$choice")"
    ;;

  --view)   # fzf transform: which reload to do, from the view the prompt shows
    if [ "$2" = next ] || [ "$2" = prev ]; then
      # Only the leads view has seats to move between; elsewhere the arrows
      # keep moving the cursor in the query.
      if [ "$FZF_PROMPT" != "$LEADS_PROMPT" ]; then
        [ "$2" = next ] && echo forward-char || echo backward-char; exit 0
      fi
      step=1; [ "$2" = prev ] && step=-1
      awk -v rig="$3" -v step="$step" '
        $1 == rig { $2 += step; found = 1 } { print }
        END { if (!found) print rig, step }' "$RIG_SEL" >"$RIG_SEL.new" && mv "$RIG_SEL.new" "$RIG_SEL"
      # reload-sync then pos: the rows keep their order, so the cursor stays put
      echo "reload-sync('$self' --lines leads)+pos(${FZF_POS:-1})"
      exit 0
    fi
    if [ "$2" = refresh ]; then
      # reload-sync: the current list stays until the fresh one is ready.
      # +pos: the rows keep their order unless a state changed, so the cursor
      # usually stays on the same seat.
      case "$FZF_PROMPT" in
        "$LEADS_PROMPT") echo "reload-sync(RIG_CACHED= '$self' --lines leads)+pos(${FZF_POS:-1})" ;;
        "$SEATS_PROMPT") echo "reload-sync(RIG_CACHED= '$self' --lines seats)+pos(${FZF_POS:-1})" ;;
        *)               echo "reload-sync(RIG_CACHED= '$self' --lines seats {2})+pos(${FZF_POS:-1})" ;;
      esac
      exit 0
    fi
    if [ "$FZF_PROMPT" = "$LEADS_PROMPT" ]; then now=leads; else now=seats; fi
    if [ "$2" = toggle ]; then [ "$now" = leads ] && now=seats || now=leads; fi
    case "$now" in
      leads) echo "reload('$self' --lines leads)+change-prompt($LEADS_PROMPT)" ;;
      *)     echo "reload('$self' --lines seats)+change-prompt($SEATS_PROMPT)" ;;
    esac
    ;;

  --lines)  # reload source for the picker: leads | seats [<rig>]
    if [ "${2:-}" = leads ]; then lead_lines "${RIG_HERE:-}"; else seat_lines "${3:-}"; fi
    ;;

  --last-lead)
    here=$(tmux display-message -c "$client" -p '#{session_name}')
    # From tmux alone, no rig ps: this has to be instant. Leads are the
    # <pod>-lead@<rig> sessions; the most recently used one not in this rig.
    lead=$(tmux list-sessions -F '#{session_last_attached}	#{session_name}' |
      awk -F '\t' -v here_rig="${here#*@}" -v here="$here" '
        $2 ~ /^[^@]*-lead@/ { split($2, p, "@"); if (here ~ /@/ && p[2] == here_rig) next; print }' |
      sort -t $'\t' -k1,1nr | head -1 | cut -f2)
    [ -n "$lead" ] || { msg "No other rig lead to go to"; exit 0; }
    tmux switch-client -c "$client" -t "=$lead"
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
    echo "usage: $(basename "$0") --open|--last-lead|--next-input|--last-alert <client>" >&2
    exit 1
    ;;
esac
