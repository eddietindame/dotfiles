#!/usr/bin/env bash
# cleanup-rig.sh — undo start-rig.sh: stop the rig, remove its worktrees, its
# builder branches and its folder.
#
#   cleanup-rig.sh <branch> [-r REPO] [--branches]
#   cleanup-rig.sh --name RIG [--branches]
#
#   <branch>      the rig start-rig made for this branch (and, for rigs from
#                 before the per-rig folders, one per repo)
#   -r, --repo    only rigs that include this repo (name or bd/bw/bb/bp/bt)
#   --name RIG    one rig by name, for rigs started with --name
#   --branches    also delete the feature branch in each repo. Without it the
#                 feature branch is kept, with whatever the lead merged, so a
#                 pushed or unpushed result is never lost by accident.
#
# Builder branches (<branch>-bN) are always deleted: anything worth keeping on
# them has been merged into the feature branch by the lead.
# Base clones are left in place for the next rig.

set -euo pipefail
# Braced so bash reads the whole file before running any of it: a run takes
# minutes, and bash otherwise reads a script as it goes, so editing it mid-run
# breaks the run.
{
. "$(dirname "$0")/lib.sh"

branch="" repo="" name="" drop_feature=false

while [ $# -gt 0 ]; do
  case "$1" in
    -r|--repo)  need_value "$@"; repo=$(resolve_repo "$2") || die "cleanup-rig: unknown repo '$2'"; shift 2 ;;
    --name)     need_value "$@"; name="$2"; shift 2 ;;
    --branches) drop_feature=true; shift ;;
    -h|--help)  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         die "cleanup-rig: unknown option $1" ;;
    *)          [ -z "$branch" ] || die "cleanup-rig: one branch only"; branch="$1"; shift ;;
  esac
done
[ -n "$branch" ] || [ -n "$name" ] || die "usage: cleanup-rig <branch> [-r REPO] [--branches] | cleanup-rig --name RIG [--branches]"

# ~~~ which rigs ~~~
envs=()
while IFS= read -r f; do
  if [ -n "$name" ]; then
    [ "$(rig_env_get "$f" RIG)" = "$name" ] || continue
  else
    [ "$(rig_env_get "$f" BRANCH)" = "$branch" ] || continue
  fi
  if [ -n "$repo" ]; then
    case " $(rig_env_get "$f" REPOS) $(rig_env_get "$f" REPO) " in *" $repo "*) ;; *) continue ;; esac
  fi
  envs+=("$f")
done < <(all_rig_envs)

[ ${#envs[@]} -gt 0 ] || die "cleanup-rig: no rig from start-rig matches${name:+ --name $name}${branch:+ $branch}${repo:+ in $repo} (see $RIG_ROOT)"

# Agents first, for the same reason cleanup-worktrees closes herdr first: their
# sessions sit in the directories about to be deleted. --delete because the rig
# can't come back without its worktrees anyway.
stop_rig() { # <rig>
  if rig ps --json 2>/dev/null | jq -e --arg n "$1" 'any(.[]; .name == $n)' >/dev/null; then
    say "Stopping rig '$1'"
    rig down "$1" --delete || warn "cleanup-rig: rig down $1 failed; carrying on with the worktrees"
  fi
}

# Worktrees in parallel, like cleanup-worktrees: rm of node_modules is the cost.
# Worktrees of one clone share its .git, but `worktree remove` of different
# worktrees only touches each one's own admin dir.
remove_worktrees() { # "<base>\t<worktree>" lines on stdin
  local base wt pids=() bases=()
  while IFS=$'\t' read -r base wt; do
    [ -n "$wt" ] || continue
    say "Removing worktree $wt"
    git -C "$base" worktree remove --force "$wt" &
    pids+=($!) bases+=("$base")
  done
  [ ${#pids[@]} -gt 0 ] || return 0
  for p in "${pids[@]}"; do wait "$p" || warn "cleanup-rig: a worktree removal failed"; done
  printf '%s\n' "${bases[@]}" | sort -u | while IFS= read -r base; do git -C "$base" worktree prune; done
}

drop_branches() { # <base> <feature> <builders>
  local i=1
  while [ "$i" -le "$3" ]; do
    git -C "$1" show-ref --verify --quiet "refs/heads/$2-b$i" &&
      git -C "$1" branch -D --quiet "$2-b$i" && say "Deleted branch $2-b$i in $(basename "$1")"
    i=$((i + 1))
  done
  git -C "$1" show-ref --verify --quiet "refs/heads/$2" || return 0
  if $drop_feature; then
    git -C "$1" branch -D --quiet "$2" && say "Deleted branch $2 in $(basename "$1")"
  else
    say "Kept branch $2 in $1 (--branches deletes it)"
  fi
}

# ~~~ per-rig folder: <rig>/{lead,bN}/<repo> ~~~
cleanup_v2() { # <rig.env>
  local f="$1" rig feature builders rig_dir r
  rig=$(rig_env_get "$f" RIG)
  feature=$(rig_env_get "$f" BRANCH)
  builders=$(rig_env_get "$f" BUILDERS)
  rig_dir=$(rig_env_get "$f" RIG_DIR)
  # rm -rf below: only ever a folder directly under the rig root holding this rig.env.
  [ "$rig_dir/.rig/rig.env" = "$f" ] && [ "$(dirname "$rig_dir")" = "$RIG_ROOT" ] ||
    die "cleanup-rig: $f names $rig_dir, which is not its own rig folder; not touching it"

  stop_rig "$rig"
  # Every worktree under the rig folder, whichever clone it came from, so one an
  # agent added by hand goes too.
  worktrees_under "$rig_dir" | remove_worktrees
  for r in $(rig_env_get "$f" REPOS); do
    [ -d "$BASES_ROOT/$r/.git" ] && drop_branches "$BASES_ROOT/$r" "$feature" "$builders"
  done
  rm -rf "$rig_dir"
  say "Removed $rig_dir"
}

# ~~~ before per-rig folders: <repo>/<slug>[-bN], spec in _specs/<rig> ~~~
cleanup_v1() { # <rig.env>
  local f="$1" rig feature builders base_clone lead_wt i base wt answer
  rig=$(rig_env_get "$f" RIG)
  feature=$(rig_env_get "$f" BRANCH)
  builders=$(rig_env_get "$f" BUILDERS)
  base_clone=$(rig_env_get "$f" BASE_CLONE)
  lead_wt=$(rig_env_get "$f" LEAD_WT)

  stop_rig "$rig"
  {
    printf '%s\t%s\n' "$base_clone" "$lead_wt"
    i=1
    while [ "$i" -le "$builders" ]; do printf '%s\t%s\n' "$base_clone" "$lead_wt-b$i"; i=$((i + 1)); done
  } | while IFS=$'\t' read -r base wt; do [ -d "$wt" ] && printf '%s\t%s\n' "$base" "$wt"; done |
    remove_worktrees
  drop_branches "$base_clone" "$feature" "$builders"

  # Rigs in this layout had one repo, so a lead that needed another made its own
  # worktree, possibly from a dev base. Those don't belong to start-dev and nothing
  # else will clean them up, but which rig made one can't be told for sure, so ask.
  while IFS=$'\t' read -r base wt; do
    case "$base" in "$DEV_ROOT"/*) ;; *) continue ;; esac
    say ""
    say "$wt is a worktree of your dev clone $base,"
    say "on $(git -C "$wt" branch --show-current 2>/dev/null || echo '?'), probably made by a rig agent."
    [ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ] || say "It has uncommitted changes, which removing it discards."
    if [ -t 0 ] || [ -r /dev/tty ]; then
      printf 'Remove it (the branch is kept)? [y/N] '
      read -r answer </dev/tty || answer=""
    else
      answer=""
    fi
    case "$answer" in
      y|Y) printf '%s\t%s\n' "$base" "$wt" | remove_worktrees ;;
      *)   say "Kept $wt" ;;
    esac
  done < <(worktrees_under "$RIG_ROOT")

  rm -rf "$(dirname "$f")"
  say "Removed spec $(dirname "$f")"
}

for f in "${envs[@]}"; do
  if [ "$(rig_env_get "$f" LAYOUT)" = 2 ]; then cleanup_v2 "$f"; else cleanup_v1 "$f"; fi
done
exit
}
