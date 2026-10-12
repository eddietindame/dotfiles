#!/usr/bin/env bash
# cleanup-rig.sh — undo start-rig.sh: stop the rig, remove its worktrees, its
# builder branches and its generated spec.
#
#   cleanup-rig.sh <branch> [-r REPO] [--branches]
#   cleanup-rig.sh --name RIG [--branches]
#
#   <branch>      every rig start-rig made for this branch, in any repo, the
#                 same way cleanup-worktrees takes every repo's worktree
#   -r, --repo    only the rig in this repo (name or bd/bw/bb/bp)
#   --name RIG    one rig by name, for rigs started with --name
#   --branches    also delete the feature branch. Without it the feature branch
#                 is kept, with whatever the lead merged, so a pushed or
#                 unpushed result is never lost by accident.
#
# Builder branches (<branch>-bN) are always deleted: anything worth keeping on
# them has been merged into the feature branch by the lead.
# The base clone is left in place for the next rig.

set -euo pipefail
. "$(dirname "$0")/lib.sh"

branch="" repo="" name="" drop_feature=false

while [ $# -gt 0 ]; do
  case "$1" in
    -r|--repo)  repo=$(resolve_repo "$2") || die "cleanup-rig: unknown repo '$2'"; shift 2 ;;
    --name)     name="$2"; shift 2 ;;
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
    [ -z "$repo" ] || [ "$(rig_env_get "$f" REPO)" = "$repo" ] || continue
  fi
  envs+=("$f")
done < <(all_rig_envs)

[ ${#envs[@]} -gt 0 ] || die "cleanup-rig: no rig from start-rig matches${name:+ --name $name}${branch:+ $branch}${repo:+ in $repo} (see $SPECS_ROOT)"

for f in "${envs[@]}"; do
  rig=$(rig_env_get "$f" RIG)
  feature=$(rig_env_get "$f" BRANCH)
  builders=$(rig_env_get "$f" BUILDERS)
  base_clone=$(rig_env_get "$f" BASE_CLONE)
  lead_wt=$(rig_env_get "$f" LEAD_WT)

  # Agents first, for the same reason cleanup-worktrees closes herdr first:
  # their sessions sit in the directories about to be deleted. --delete because
  # the rig can't come back without its worktrees anyway.
  if rig ps --json 2>/dev/null | jq -e --arg n "$rig" 'any(.[]; .name == $n)' >/dev/null; then
    say "Stopping rig '$rig'"
    rig down "$rig" --delete || warn "cleanup-rig: rig down $rig failed; carrying on with the worktrees"
  fi

  # Worktrees in parallel, like cleanup-worktrees: rm of node_modules is the
  # cost. They share one .git, but `worktree remove` of different worktrees
  # only touches each one's own admin dir.
  wts=("$lead_wt")
  i=1
  while [ "$i" -le "$builders" ]; do wts+=("$lead_wt-b$i"); i=$((i + 1)); done
  pids=()
  for wt in "${wts[@]}"; do
    [ -d "$wt" ] || continue
    say "Removing worktree $wt"
    git -C "$base_clone" worktree remove --force "$wt" &
    pids+=($!)
  done
  [ ${#pids[@]} -gt 0 ] && for p in "${pids[@]}"; do wait "$p" || warn "cleanup-rig: a worktree removal failed"; done
  git -C "$base_clone" worktree prune

  i=1
  while [ "$i" -le "$builders" ]; do
    git -C "$base_clone" show-ref --verify --quiet "refs/heads/$feature-b$i" &&
      git -C "$base_clone" branch -D --quiet "$feature-b$i" && say "Deleted branch $feature-b$i"
    i=$((i + 1))
  done
  if $drop_feature && git -C "$base_clone" show-ref --verify --quiet "refs/heads/$feature"; then
    git -C "$base_clone" branch -D --quiet "$feature" && say "Deleted branch $feature"
  elif git -C "$base_clone" show-ref --verify --quiet "refs/heads/$feature"; then
    say "Kept branch $feature in $base_clone (--branches deletes it)"
  fi

  rm -rf "$(dirname "$f")"
  say "Removed spec $(dirname "$f")"
done
