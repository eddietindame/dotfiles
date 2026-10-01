#!/bin/bash
# Usage: ensure-worktree.sh <main-worktree> <target-path> <branch> [base-branch] [--rebase]
# Ensures a git worktree exists at target-path for the given branch
# If base-branch is provided, new branches are created off it instead of HEAD
# If --rebase is passed, existing worktrees are rebased onto the base branch

set -e

main_worktree="$1"
target_path="$2"
branch="$3"
base_branch=""
rebase=false

shift 3
for arg in "$@"; do
    case "$arg" in
        --rebase) rebase=true ;;
        *) base_branch="$arg" ;;
    esac
done

# Expand ~ to $HOME
main_worktree="${main_worktree/#\~/$HOME}"
target_path="${target_path/#\~/$HOME}"

# If a stray directory exists at the target but it's not a worktree, remove it
if [ -d "$target_path" ] && [ ! -e "$target_path/.git" ]; then
    echo "ensure-worktree.sh: $target_path exists but is not a git worktree, removing"
    rm -rf "$target_path"
fi

# Fail loudly if the repo was never cloned. Without this the script falls through
# to `cd "$main_worktree"` and dies with a bare "no such file or directory",
# while tmuxinator carries on building windows over a half-made environment.
if [ ! -d "$main_worktree" ]; then
    echo "ensure-worktree: main worktree not found: $main_worktree" >&2
    echo "  clone the repo there first, then re-run." >&2
    exit 1
fi

if ! git -C "$main_worktree" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ensure-worktree: not a git repository: $main_worktree" >&2
    exit 1
fi

# If worktree already exists
if [ -d "$target_path" ]; then
    if [ -f "$main_worktree/.env" ] && [ ! -f "$target_path/.env" ]; then
        cp "$main_worktree/.env" "$target_path/.env"
    fi
    # Rebase onto base branch if requested
    if $rebase && [ -n "$base_branch" ]; then
        cd "$target_path"
        git fetch --quiet
        # Stash any dirty state (tracked + untracked)
        stashed=false
        if ! git diff --quiet || ! git diff --cached --quiet; then
            git stash --include-untracked --quiet
            stashed=true
        fi
        # Remove untracked files that would conflict with the target
        git clean -fd --quiet
        git rebase "origin/$base_branch"
        if $stashed; then
            git stash pop --quiet || echo "Warning: stash pop had conflicts, check manually"
        fi
    fi
    exit 0
fi

cd "$main_worktree"

# Fetch to ensure we have latest remote refs
git fetch --quiet

# Check if branch exists (local or remote)
if git show-ref --verify --quiet "refs/heads/$branch" || \
   git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    # Branch exists, create worktree for it. If it exists locally and is behind
    # its upstream, say so — git checks out the local ref as-is, and silently
    # resuming on stale code is the thing this script is meant to prevent.
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        behind=$(git rev-list --count "$branch..$branch@{upstream}" 2>/dev/null || echo 0)
        if [ "$behind" -gt 0 ]; then
            echo "ensure-worktree: $branch is $behind commit(s) behind its upstream" >&2
            echo "  worktree uses the local ref as-is; pass --rebase to move it." >&2
        fi
    fi
    git worktree add "$target_path" "$branch"
else
    # New branch: always cut it from a freshly fetched REMOTE ref, never from
    # this checkout's HEAD. `git fetch` advances refs/remotes/* but leaves the
    # base clone's local branch where it was, and these base clones sit far
    # behind — staging was 1202 commits stale when this was written.
    if [ -n "$base_branch" ]; then
        if ! git show-ref --verify --quiet "refs/remotes/origin/$base_branch"; then
            echo "ensure-worktree: no origin/$base_branch in $main_worktree" >&2
            echo "  refusing to fall back to a stale local HEAD — check the name." >&2
            exit 1
        fi
        base_ref="origin/$base_branch"
    else
        # Default to the remote counterpart of whatever the base clone tracks
        # (staging, main, ...), then origin's default branch.
        base_ref=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || base_ref=""
        if [ -z "$base_ref" ]; then
            base_ref=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || base_ref=""
        fi
        if [ -z "$base_ref" ]; then
            echo "ensure-worktree: cannot resolve a remote base branch in $main_worktree" >&2
            echo "  set one with 'git remote set-head origin -a', or pass -b/-bfe/-bbe." >&2
            exit 1
        fi
    fi
    echo "ensure-worktree: $branch off $base_ref ($(git rev-parse --short "$base_ref"))"
    git worktree add -b "$branch" "$target_path" "$base_ref"
fi

# Copy .env from main worktree if it exists
if [ -f "$main_worktree/.env" ]; then
    cp "$main_worktree/.env" "$target_path/.env"
fi
