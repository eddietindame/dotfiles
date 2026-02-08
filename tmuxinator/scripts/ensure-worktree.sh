#!/bin/bash
# Usage: ensure-worktree.sh <main-worktree> <target-path> <branch>
# Ensures a git worktree exists at target-path for the given branch

main_worktree="$1"
target_path="$2"
branch="$3"

# Expand ~ to $HOME
main_worktree="${main_worktree/#\~/$HOME}"
target_path="${target_path/#\~/$HOME}"

# If worktree already exists, just ensure .env is copied
if [ -d "$target_path" ]; then
    if [ -f "$main_worktree/.env" ] && [ ! -f "$target_path/.env" ]; then
        cp "$main_worktree/.env" "$target_path/.env"
    fi
    exit 0
fi

cd "$main_worktree" || exit 1

# Fetch to ensure we have latest remote refs
git fetch --quiet

# Check if branch exists (local or remote)
if git show-ref --verify --quiet "refs/heads/$branch" || \
   git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    # Branch exists, create worktree for it
    git worktree add "$target_path" "$branch"
else
    # Branch doesn't exist, create new branch and worktree
    git worktree add -b "$branch" "$target_path"
fi

# Copy .env from main worktree if it exists
if [ -f "$main_worktree/.env" ]; then
    cp "$main_worktree/.env" "$target_path/.env"
fi
