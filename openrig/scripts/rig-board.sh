#!/usr/bin/env bash
# rig-board.sh — a written status board for every rig, so the human can see
# where each one is without reading panes or PROGRESS.md.
#
#   rig-board.sh --start    start the updater loop once (tmux.base.conf runs this)
#   rig-board.sh --once     update the board now
#   rig-board.sh --view     show the board (prefix+b opens this in a popup)
#
# For each running rig in $RIGS it collects the lead's PROGRESS.md, the
# brief's opening, the lead's screen, open queue items, recent commits on the
# feature branch and its PRs, and has a small model write a short summary.
# A rig is summarised again only when its PROGRESS.md, queue, commits or PRs
# change, or after $STALE seconds if only the lead's screen moved. Rigs are
# done one at a time to keep memory down on the mini.
#
# Output: ~/.cache/rig-board/board.md.

RIGS="$HOME/Documents/bertie-rigs"
DIR="$HOME/.cache/rig-board"
BOARD="$DIR/board.md"
INTERVAL="${BOARD_INTERVAL:-300}"   # how often to look
STALE="${BOARD_STALE:-1200}"        # re-summarise on screen changes alone after this
MODEL="${BOARD_MODEL:-haiku}"
ORG=bertie-technology
export PATH="$HOME/.local/bin:$HOME/.volta/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

mkdir -p "$DIR"
log() { echo "$(date '+%F %T') $*" >>"$DIR/log"; }

read -r -d '' PROMPT <<'EOF'
You write one entry of a status board for a busy human who runs several teams
of coding agents at once. Each team ("rig") has a lead, builders (b1, b2, ...,
and x1, ... on the laptop) and a reviewer (r1). The human glances at this board
to know where every rig is without reading anything else, so be concrete and
current, and say what is actually happening, not who is idle.

Below is the raw state of one rig: the lead's progress log (most recent at the
bottom), the start of the brief, open queue items, recent commits, PRs, and the
last lines of the lead's screen. The human wants the least text that tells
them where the rig is. Write exactly this markdown and nothing else:

<headline, at most 8 words, on its own line, no # and no rig name>
<At most two short sentences, 40 words in all: what is happening now and what comes next, or what it is stuck on.>
**You:** <only if the human must decide or do something: the ask in at most 20 words, several asks separated by " · ". Leave this line out entirely otherwise.>
**PRs:** <open PRs from the PRs section on ONE line, exactly like "desktop #1431 ✗ · packages #371 ○ · web #183 draft ✗" (✓ checks passing, ✗ failing, ○ pending). Never titles, never URLs, never bullets. With more than five open, summarise instead, e.g. "17 drafts in 4 repos, most failing". Leave this line out if none are open.>

Plain language. No queue ids, hashes, file paths or seat names unless essential.
Prefer the newest information: the lead's screen and the end of the progress
log beat older entries. If something is stuck or failing, say so plainly.
EOF

# rig_state <rig dir>: everything the summariser sees, on stdout. Puts the parts
# that should trigger a re-summary in $DIR/<rig>.key.
rig_state() {
  local d="$1" rig BRANCH lead repo
  # shellcheck disable=SC1091
  . "$d/.rig/rig.env"; rig="$RIG"; lead="$d/lead"
  {
    echo "## PROGRESS.md"; tail -c 12000 "$lead/PROGRESS.md" 2>/dev/null
    echo; echo "## Open queue items"
    rig queue list --json --full --state pending,in-progress,blocked --limit 200 2>/dev/null |
      python3 -c '
import json, sys
rig = sys.argv[1]
for i in json.load(sys.stdin):
    if not str(i.get("destinationSession", "")).endswith("@" + rig) and not str(i.get("sourceSession", "")).split("@host-")[0].endswith("@" + rig):
        continue
    body = " ".join(str(i.get("summary") or i.get("body") or "").split())[:300]
    print("-", i.get("sourceSession"), "->", i.get("destinationSession"), "[" + str(i.get("state")) + "]", body)
' "$rig"
    echo; echo "## Commits on $BRANCH in the last 24h"
    for repo in "$lead"/*/; do
      repo="${repo%/}"; [ -e "$repo/.git" ] || continue
      # Only the branch's own commits, not the upstream it was rebased onto.
      local base=() b
      for b in staging main master; do
        git -C "$repo" rev-parse -q --verify "origin/$b" >/dev/null && base+=("^origin/$b")
      done
      git -C "$repo" log --since=24.hours --format="- ${repo##*/}: %s (%cr)" "$BRANCH" "${base[@]}" 2>/dev/null | head -10
    done
    # A PR is this rig's if its branch is the feature branch, or the lead's
    # log or screen mentions its branch, number or URL. ($DIR/prs comes from
    # fetch_prs; PR branches don't follow one naming pattern.)
    echo; echo "## PRs"
    { cat "$lead/PROGRESS.md" 2>/dev/null
      tmux capture-pane -p -J -t "orch-lead@$rig" -S -400 2>/dev/null
    } >"$DIR/$rig.text"
    python3 - "$DIR/prs" "$DIR/$rig.text" "$BRANCH" <<'PY'
import json, os, re, sys, time
from datetime import datetime
prdir, textfile, branch = sys.argv[1:4]
text = open(textfile, errors="replace").read()
for f in sorted(os.listdir(prdir)) if os.path.isdir(prdir) else []:
    repo = f[:-5]
    try: prs = json.load(open(os.path.join(prdir, f)))
    except Exception: continue
    for p in prs:
        n, head = p["number"], p["headRefName"]
        if p["state"] != "OPEN":
            done = p.get("mergedAt") or p.get("closedAt") or ""
            if not done or time.time() - datetime.fromisoformat(done.replace("Z", "+00:00")).timestamp() > 2 * 86400:
                continue
        mine = (head == branch or head.startswith(branch + "-") or head in text
                or p["url"] in text
                # "desktop #12" / "bertie-desktop#12"; a bare "#12" only from 100 up,
                # since low numbers turn up in lists of findings and slices.
                or re.search(r"%s ?#%d(?!\d)" % (re.escape(repo.replace("bertie-", "")), n), text)
                or (n >= 100 and re.search(r"(?<![\w/])#%d(?!\d)" % n, text)))
        if not mine: continue
        runs = p.get("statusCheckRollup") or []
        res = [(r.get("conclusion") or r.get("state") or r.get("status") or "").upper() for r in runs]
        bad = sum(x in ("FAILURE", "ERROR", "CANCELLED", "TIMED_OUT") for x in res)
        pend = sum(x in ("", "PENDING", "IN_PROGRESS", "QUEUED", "EXPECTED") for x in res)
        checks = "no checks" if not res else "%d failing" % bad if bad else "%d pending" % pend if pend else "passing"
        state = "draft" if p.get("isDraft") and p["state"] == "OPEN" else p["state"].lower()
        review = (p.get("reviewDecision") or "none").lower()
        print("- %s #%s %s: %s, checks %s, review %s, %s" % (repo, n, p["title"], state, checks, review, p["url"]))
PY
    if compgen -G "$d/.rig/offload/*.rig" >/dev/null; then
      echo; echo "## Laptop builders"
      for f in "$d"/.rig/offload/*.rig; do f="${f##*/}"; echo "- dev-${f%.rig}@$rig-${f%.rig}"; done
    fi
  } >"$DIR/$rig.key"
  echo "# Rig: $rig (branch $BRANCH)"
  echo; echo "## Brief (start)"; head -c 2500 "$lead/BRIEF.md" 2>/dev/null
  echo; cat "$DIR/$rig.key"
  echo; echo "## Lead's screen (last lines)"
  tmux capture-pane -p -J -t "orch-lead@$rig" -S -60 2>/dev/null | grep -v '^[[:space:]]*$' | tail -50
}

# fetch_prs: the human's recent PRs in every repo a rig has, into $DIR/prs.
fetch_prs() {
  local repo
  mkdir -p "$DIR/prs"
  for repo in $(/bin/ls -d "$RIGS"/*/lead/*/.git 2>/dev/null | sed 's|/.git$||; s|.*/||' | sort -u); do
    gh pr list -R "$ORG/$repo" --author @me --state all --limit 40 \
      --json number,title,state,isDraft,reviewDecision,statusCheckRollup,url,headRefName,mergedAt,closedAt \
      >"$DIR/prs/$repo.json.tmp" 2>/dev/null && mv "$DIR/prs/$repo.json.tmp" "$DIR/prs/$repo.json"
  done
}

update() {
  local d rig now running out sections="" needs=""
  now=$(date +%s)
  : >"$DIR/links.tmp"
  fetch_prs
  running=$(rig ps --json 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
for r in (d if isinstance(d, list) else d.get("rigs", [])):
    if (r.get("runningCount") or r.get("running") or 0) or str(r.get("status", "")).lower() in ("running", "partial"):
        print(r.get("name") or r.get("rigName"))
' 2>/dev/null)
  for d in "$RIGS"/*/; do
    d="${d%/}"; [ -f "$d/.rig/rig.env" ] && [ -d "$d/lead" ] || continue
    rig="${d##*/}"
    if [ -n "$running" ] && ! grep -qx "$rig" <<<"$running"; then
      sections+="### $rig: stopped"$'\n\n'; continue
    fi
    rig_state "$d" >"$DIR/$rig.in"
    local key old age
    key=$(md5 -q "$DIR/$rig.key"); old=$(cat "$DIR/$rig.hash" 2>/dev/null)
    age=$(( now - $(stat -f %m "$DIR/$rig.md" 2>/dev/null || echo 0) ))
    if [ ! -s "$DIR/$rig.md" ] || [ "$key" != "$old" ] || [ "$age" -ge "$STALE" ]; then
      if out=$(cd "$DIR" && claude -p --model "$MODEL" --tools "" --no-session-persistence \
          --setting-sources "" --strict-mcp-config --system-prompt "$PROMPT" \
          <"$DIR/$rig.in" 2>>"$DIR/log") && [ -n "$out" ]; then
        printf '%s\n' "$out" >"$DIR/$rig.md"; echo "$key" >"$DIR/$rig.hash"
        log "summarised $rig"
      else
        log "summary failed for $rig"
      fi
    fi
    [ -s "$DIR/$rig.md" ] || continue
    sections+="### $rig · $(grep -m1 -v '^[[:space:]]*$' "$DIR/$rig.md" | sed 's/^#* *//')"$'\n'
    sections+="$(grep -v '^[[:space:]]*$' "$DIR/$rig.md" | sed 1d | grep -v '^\*\*You:\*\*')"$'\n\n'
    # PR links for the board's picker: rig, repo, number, title, state, checks, url
    sed -n '/^## PRs$/,/^## /p' "$DIR/$rig.key" | grep '^- ' |
      sed -E "s|^- bertie-|- |; s|^- ([^ ]+) #([0-9]+) (.*): ([a-z]+), checks ([^,]+), review [^,]+, (https://[^ ]+)$|$rig\t\1\t\2\t\3\t\4\t\5\t\6|" |
      grep $'\t' >>"$DIR/links.tmp"
    local n
    n=$(grep -m1 '^\*\*You:\*\*' "$DIR/$rig.md" | sed 's/^\*\*You:\*\* *//')
    [ -z "$n" ] || needs+="- **${rig}**: $n"$'\n'
  done
  {
    echo "# Rigs · updated $(date '+%H:%M')"
    echo
    if [ -n "$needs" ]; then echo "## Needs you"; echo; printf '%s\n' "$needs"; else echo "_Nothing needs you._"; echo; fi
    echo "---"; echo
    printf '%s' "$sections"
  } >"$BOARD.tmp" && mv "$BOARD.tmp" "$BOARD"
  mv "$DIR/links.tmp" "$DIR/links.tsv"
}

case "${1:-}" in
  --start)
    pid=$(cat "$DIR/pid" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && exit 0
    nohup "$0" --run >/dev/null 2>&1 &
    echo $! >"$DIR/pid" ;;
  --run)   # one update at a time, whether from this loop or --once
    while :; do lockf -t 600 "$DIR/lock" "$0" --update; sleep "$INTERVAL"; done ;;
  --once) lockf -t 600 "$DIR/lock" "$0" --update ;;
  --update) update ;;
  --state) fetch_prs; rig_state "$2" ;;   # debugging: what the summariser sees for one rig
  --view)   # the board above, its PR links below: type to filter, enter opens
    [ -s "$BOARD" ] || { echo "No board yet: it's being written (takes a minute or two)."; read -r -n1; exit; }
    tmux_scripts="$HOME/.config/tmux/scripts"
    python3 - "$DIR/links.tsv" <<'PY' |
import sys
path = sys.argv[1]   # long titles: fzf cuts them at the panel's edge
try: rows = [l.rstrip("\n").split("\t") for l in open(path)]
except OSError: rows = []
import re
rows = [[re.sub(r"^[a-z]+-\d+-", "", r[0])] + r[1:] for r in rows if len(r) == 7]   # ber-827-x → x
if not rows:
    print("  no PR links\t"); sys.exit()
dim, red, green, yellow, magenta, bold, off = "\033[2m", "\033[31m", "\033[32m", "\033[33m", "\033[35m", "\033[1m", "\033[0m"
order = {"open": 0, "draft": 1, "merged": 2, "closed": 3}
rows.sort(key=lambda r: (r[0], order.get(r[4], 9), r[1], -int(r[2])))
rigw = min(max(len(r[0]) for r in rows), 26)
refw = max(len("%s #%s" % (r[1], r[2])) for r in rows)
for rig, repo, num, title, state, checks, url in rows:
    mark = (green + "✓" if checks == "passing" else red + "✗" if "failing" in checks
            else yellow + "○" if "pending" in checks else dim + "·") + off
    tag = {"draft": dim + "draft ", "merged": magenta + "merged", "closed": dim + "closed"}.get(state, "      ") + off
    ref = "%s #%s" % (repo, num)
    print("%s%-*s%s  %s %s  %s%-*s%s  %s\t%s" % (dim, rigw, rig[:rigw], off, mark, tag, bold, refw, ref, off, title, url))
PY
      fzf --ansi --delimiter=$'\t' --with-nth=1 --layout=reverse --no-sort --tiebreak=index \
        --preview "CLICOLOR_FORCE=1 glow -s dark -w \$((FZF_PREVIEW_COLUMNS - 2)) '$BOARD'" \
        --preview-window 'up,75%,border-bottom' \
        --prompt '  link › ' --info=hidden \
        --header 'enter open on laptop · ctrl-y copy · ↑↓ pick · mouse/shift-↑↓ scroll board · esc close' \
        --bind "enter:execute-silent('$tmux_scripts/open-on-laptop.sh' {2})" \
        --bind "ctrl-y:execute-silent(printf %s {2} | '$tmux_scripts/copy-on-laptop.sh')" \
        --bind 'shift-up:preview-up,shift-down:preview-down,pgup:preview-page-up,pgdn:preview-page-down' >/dev/null
    ;;
  *) echo "usage: $(basename "$0") --start | --once | --view" >&2; exit 2 ;;
esac
