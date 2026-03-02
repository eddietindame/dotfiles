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
    # Branch exists, create worktree for it
    git worktree add "$target_path" "$branch"
else
    # Branch doesn't exist, create new branch and worktree
    if [ -n "$base_branch" ] && \
       git show-ref --verify --quiet "refs/remotes/origin/$base_branch"; then
        git worktree add -b "$branch" "$target_path" "origin/$base_branch"
    else
        git worktree add -b "$branch" "$target_path"
    fi
fi

# Copy .env from main worktree if it exists
if [ -f "$main_worktree/.env" ]; then
    cp "$main_worktree/.env" "$target_path/.env"
fi
