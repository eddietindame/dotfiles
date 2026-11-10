#!/usr/bin/env bash
# offload.sh — run a builder on the laptop when the mini is short of memory.
#
#   offload.sh start <rig> [repos...]   start a laptop builder for <rig> (default:
#                                       every repo in the lead's folder); prints
#                                       its seat, e.g. dev-x1@<rig>-x1 on host laptop
#   offload.sh fetch <rig> <xN>         bring its branch, <branch>-xN, into the lead's repos
#   offload.sh sync <rig> <xN>          copy the lead's BRIEF.md and PROGRESS.md to it now
#                                       (the watcher does this within a minute of a change)
#   offload.sh status [<rig>]           the laptop builders and what they're doing
#   offload.sh done <rig> <xN>          fetch, then stop and remove that laptop builder
#   offload.sh watch <rig> <xN>         (started by start) tell the lead when it needs
#                                       you, and keep its BRIEF.md / PROGRESS.md copies current
#
# The mini has 16 GB and its rigs share it; the laptop has 64 GB. A laptop
# builder is a one-seat rig on the laptop's own OpenRig daemon, in
# ~/rigs/<rig>-xN there, on branch <branch>-xN of the same repos. Its
# repos are worktrees of ~/rigs/base/<repo> on the laptop, cloned from the
# mini's base clones over ssh (nothing goes through GitHub), and its branch
# comes back the same way with `fetch`. It reports to the mini's lead with
# `rig send ... --host mini`, and a watcher on the mini messages the lead when
# the laptop seat needs attention, as a local seat's alerts would.
#
# Both machines know each other as OpenRig hosts (rig host list): `laptop` on
# the mini, `mini` on the laptop, over http to each daemon's Tailscale address
# (http, not ssh, because cross-host queue writes need it). This script's own
# setup and git traffic uses ssh with keys.

set -euo pipefail

LAPTOP=eddietindame@100.86.187.87   # as in tmux/scripts/agent-notify.sh
HOST=laptop                         # its id in the mini's ~/.openrig/hosts.yaml
laptop_url() { echo "http://${LAPTOP#*@}:7433"; }   # its daemon, as registered there
RIGS="$HOME/Documents/bertie-rigs"
POLL="${OFFLOAD_POLL:-60}"   # seconds between the watcher's looks

say()  { printf '%s\n' "$*"; }
die()  { printf 'offload: %s\n' "$*" >&2; exit 1; }
# Run a command on the laptop in a login shell, so volta, rig and tmux are on PATH.
remote() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$LAPTOP" "zsh -lc $(printf %q "$1")"; }

load_rig() { # <rig>: RIG_DIR, BRANCH and the lead's folder from the rig's .rig/rig.env
  local env="$RIGS/$1/.rig/rig.env"
  [ -f "$env" ] || die "no rig called $1 in $RIGS"
  # shellcheck disable=SC1090
  . "$env"
  rig="$1" lead_dir="$RIG_DIR/lead" state="$RIG_DIR/.rig/offload"
  mkdir -p "$state"
}

usage() { sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  start)
    [ $# -ge 1 ] || usage
    load_rig "$1"; shift
    repos=("$@")
    if [ ${#repos[@]} -eq 0 ]; then
      for d in "$lead_dir"/*/; do [ -e "$d/.git" ] && repos+=("$(basename "$d")"); done
    fi
    [ ${#repos[@]} -gt 0 ] || die "no repos in $lead_dir"
    for repo in "${repos[@]}"; do [ -e "$lead_dir/$repo/.git" ] || die "the lead has no $repo"; done

    remote 'rig daemon status >/dev/null 2>&1 || rig daemon start >/dev/null' || die "can't reach the laptop's OpenRig daemon"
    n=1; while remote "test -e ~/rigs/$rig-x$n"; do n=$((n + 1)); done
    x="x$n" name="$rig-x$n" seat="dev-x$n@$rig-x$n" branch="$BRANCH-x$n"
    dir="rigs/$name"   # under the laptop's home
    say "offload: $seat on the laptop, branch $branch, repos ${repos[*]}"

    for repo in "${repos[@]}"; do
      base="$RIGS/base/$repo"
      say "offload: $repo"
      # The laptop's base clone is made once, then only fetched.
      remote "set -e
        b=~/rigs/base/$repo
        [ -d \$b ] || git clone -q --no-checkout 'mini:${base#"$HOME/"}' \$b
        git -C \$b fetch -q origin '+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH'
        git -C \$b worktree add -q -b '$branch' ~/$dir/$x/$repo 'origin/$BRANCH'"
    done
    say "offload: installing dependencies on the laptop (logs in ~/$dir/.rig/logs there)"
    for repo in "${repos[@]}"; do
      remote "set -e; mkdir -p ~/$dir/.rig/logs; cd ~/$dir/$x/$repo
        if [ -f pnpm-lock.yaml ]; then pnpm install >~/$dir/.rig/logs/install-$repo.log 2>&1
        elif [ -f package-lock.json ]; then npm install >~/$dir/.rig/logs/install-$repo.log 2>&1; fi" ||
        say "offload: install failed in $repo; the builder is told to look at ~/$dir/.rig/logs/install-$repo.log"
    done

    # The spec, culture and guidance are written here and copied over.
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/guidance"
    agents="$(remote 'dirname "$(dirname "$(readlink -f "$(volta which rig 2>/dev/null || command -v rig)")")"')/daemon/specs/agents"
    home=$(remote 'echo $HOME')
    cat >"$tmp/rig.yaml" <<EOF
version: "0.2"
name: $name
summary: Laptop builder for $rig ($BRANCH) on the mini, offloaded because the mini is short of memory.
culture_file: CULTURE.md
permission_policy: builtin:auto
pods:
  - id: dev
    label: Development
    members:
      - id: $x
        agent_ref: "path:$agents/development/implementer"
        runtime: claude-code
        profile: default
        cwd: "$home/$dir/$x"
        startup:
          files:
            - { path: guidance/builder.md, delivery_hint: send_text, required: true }
EOF
    {
      cat <<EOF
# $name: a laptop builder for $rig

**You are on the laptop, not the mini.** Your rig, $rig, runs on the Mac mini,
which is short of memory, so its lead moved one builder here. Everything
below the line is $rig's own culture file: follow it, with these differences.

- Your seat is \`$seat\`, in \`$home/$dir/$x\`, which holds a worktree of
  each of these repos on branch \`$branch\`: ${repos[*]}.
  The culture's seat table and folders are the mini's: ignore them.
- Your lead is \`orch-lead@$rig\` **on host \`mini\`**. Send to it with
  \`rig send orch-lead@$rig --host mini "..."\`, and start every message with
  \`$seat (laptop):\` so it knows who it is from.
- Hand a finished slice to the lead, not the reviewer: commit on your branch,
  then send the lead the commit range per repo (\`$BRANCH..HEAD\`), what
  changed and the check results. The lead fetches your branch to the mini
  and hands it to the reviewer there. Fix findings on the same branch and
  tell the lead again.
- Your repos' \`origin\` is the mini, and there is no local \`$BRANCH\`.
  Wherever the guidance says \`git rebase $BRANCH\`, run
  \`git fetch origin && git rebase origin/$BRANCH\` instead: that picks up
  everything the lead has merged on the mini.
- The laptop has plenty of memory: you don't need the culture's heavy.sh.
- Never push anywhere. The mini fetches from you.
- The lead's \`BRIEF.md\` and \`PROGRESS.md\` are in \`$home/$dir\`, copied
  from the mini within a minute of every change; you're told when the brief
  changes. They are copies, so don't edit them: ask the lead.

---

EOF
      cat "$RIG_DIR/.rig/CULTURE.md"
    } >"$tmp/CULTURE.md"
    sed "s|@@RIG@@|$rig|g; s|@@BRANCH@@-bN|$branch|g; s|@@BRANCH@@|$BRANCH|g; s|@@REPOS@@|${repos[*]}|g" \
      "$HOME/.config/openrig/templates/builder.md" >"$tmp/guidance/builder.md"
    printf '\n%s\n' "Your dependencies are already installed; if an install failed its log is in $home/$dir/.rig/logs. You hand slices to the lead (see the culture file), and the lead hands them to the reviewer." >>"$tmp/guidance/builder.md"
    scp -q -o BatchMode=yes -r "$tmp/." "$LAPTOP:$dir/.rig/" || die "couldn't copy the spec to the laptop"

    "$0" sync "$rig" "$x"
    remote "rig up ~/$dir/.rig/rig.yaml" | tail -5 || die "rig up failed on the laptop; see above"

    printf '%s\n' "$name" >"$state/$x.rig"
    nohup "$0" watch "$rig" "$x" >>"$state/$x.watch.log" 2>&1 &
    echo $! >"$state/$x.pid"
    say ""
    say "offload: $seat is up on the laptop. Assign it work like any builder, with --host laptop:"
    say "  rig queue create --host $HOST --destination $seat --summary '...' --body-file <slice.md>"
    say "  rig send $seat --host $HOST '...'      rig capture $seat --host $HOST"
    say "  OPENRIG_URL=$(laptop_url) rig queue list --json   # read the laptop's queue"
    say "Your BRIEF.md and PROGRESS.md follow it to the laptop within a minute of each change."
    say "When it hands a slice back: offload.sh fetch $rig $x, then review $branch as usual."
    say "Finished with it: offload.sh done $rig $x"
    ;;

  fetch)
    [ $# -eq 2 ] || usage
    load_rig "$1"; x="$2" dir="rigs/$1-$2" branch="$BRANCH-$2"
    for repo in $(remote "ls ~/$dir/$x"); do
      [ -e "$lead_dir/$repo/.git" ] || continue
      git -C "$lead_dir/$repo" fetch -q "$LAPTOP:$dir/$x/$repo" "+$branch:$branch" &&
        say "$repo: $branch at $(git -C "$lead_dir/$repo" rev-parse --short "$branch"), $(git -C "$lead_dir/$repo" rev-list --count "$BRANCH..$branch") commit(s) ahead of $BRANCH"
    done
    ;;

  sync)
    [ $# -eq 2 ] || usage
    load_rig "$1"; dir="rigs/$1-$2"
    for f in BRIEF.md PROGRESS.md; do
      [ -f "$lead_dir/$f" ] && scp -q -o BatchMode=yes "$lead_dir/$f" "$LAPTOP:$dir/$f"
    done
    say "offload: BRIEF.md and PROGRESS.md copied to the laptop builder"
    ;;

  status)
    remote "rig ps --nodes -A" | awk -v r="${1:-}" 'NR == 1 || $1 ~ ("^" r ".*-x[0-9]+$") || $2 ~ ("@" r ".*-x[0-9]+")'
    ;;

  done)
    [ $# -eq 2 ] || usage
    load_rig "$1"; x="$2" name="$1-$2" dir="rigs/$1-$2" branch="$BRANCH-$2"
    "$0" fetch "$rig" "$x"
    [ -f "$state/$x.pid" ] && kill "$(cat "$state/$x.pid")" 2>/dev/null || true
    rm -f "$state/$x.pid" "$state/$x.rig"
    remote "rig down '$name' --delete --yes >/dev/null 2>&1 || true
      for wt in ~/$dir/$x/*(N/); do
        b=~/rigs/base/\${wt:t}
        git -C \$b worktree remove --force \$wt && git -C \$b branch -q -D '$branch'
      done
      rm -rf ~/$dir"
    say "offload: $name stopped and removed from the laptop; $branch is in the lead's repos"
    ;;

  watch)   # <rig> <xN>: message the lead when the laptop seat needs attention
    [ $# -eq 2 ] || usage
    load_rig "$1"; x="$2" name="$1-$2" seat="dev-$2@$1-$2"
    lead="orch-lead@$rig" was="" down=0
    tell() { rig send "$lead" "offload watcher: $*" >/dev/null 2>&1 || true; }
    stamp() { stat -f %m "$lead_dir/$1" 2>/dev/null || echo 0; }
    brief=$(stamp BRIEF.md) progress=$(stamp PROGRESS.md)   # start copied them
    while [ -f "$state/$x.rig" ]; do
      # Keep the laptop's copies of the lead's files current. A changed brief
      # can change the work, so the builder is told; PROGRESS.md just follows.
      if [ "$(stamp BRIEF.md)$(stamp PROGRESS.md)" != "$brief$progress" ] && "$0" sync "$rig" "$x" >/dev/null 2>&1; then
        if [ "$(stamp BRIEF.md)" != "$brief" ]; then
          rig send "$seat" --host "$HOST" "offload watcher: the lead's BRIEF.md has changed; re-read the copy in your rig folder (../BRIEF.md from your seat) before your next step." >/dev/null 2>&1 || true
        fi
        brief=$(stamp BRIEF.md) progress=$(stamp PROGRESS.md)
      fi
      if json=$(rig ps --host "$HOST" --nodes --rig "$name" --json 2>/dev/null); then
        [ "$down" -ge 5 ] && tell "the laptop is reachable again; $seat is back in view."
        down=0
        now=$(jq -r --arg s "$seat" '(if type == "array" then . else (.nodes // []) end)
          | map(select(.canonicalSessionName == $s))[0]
          | if . == null then "gone"
            elif .needsAttention then "attention \(.attentionReason // .reason // .agentActivity.state // "")"
            else "\(.lifecycleState) \(.agentActivity.state // "")" end' <<<"$json")
        if [ "$now" != "$was" ]; then
          case "$now" in
            gone) tell "$seat is no longer running on the laptop. If that wasn't offload.sh done, see: offload.sh status $rig" ;;
            attention*) tell "$seat (laptop) needs attention: ${now#attention }. Look with: rig capture $seat --host $HOST" ;;
          esac
          was=$now
        fi
      else
        down=$((down + 1))
        [ "$down" -eq 5 ] && tell "can't reach the laptop for 5 minutes, so $seat isn't being watched. Its work is safe on the laptop."
      fi
      sleep "$POLL"
    done
    ;;

  *) usage ;;
esac
