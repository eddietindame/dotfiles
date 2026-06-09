#!/usr/bin/env zsh
# Generate repos.txt in each worktree's tmp/ directory.
# Usage: generate-repos-txt.sh <fe_branch> [be_branch] [pkg_branch]
# If only one branch is given, it's used for all three.

fe_branch="$1"
be_branch="${2:-$fe_branch}"
pkg_branch="${3:-$fe_branch}"

fe_root=~/Documents/bertie/bertie-desktop/${fe_branch//\//-}
be_root=~/Documents/bertie/bertie-backend/${be_branch//\//-}
pkg_root=~/Documents/bertie/bertie-packages/${pkg_branch//\//-}

for dir in "$be_root" "$fe_root" "$pkg_root"; do
  mkdir -p "$dir/tmp"
  printf 'frontend=%s\nbackend=%s\npackages=%s\n' "$fe_root" "$be_root" "$pkg_root" > "$dir/tmp/repos.txt"
done
