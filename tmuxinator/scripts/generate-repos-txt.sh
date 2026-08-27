#!/usr/bin/env zsh
# Generate repos.txt in each worktree's tmp/ directory.
# Usage: generate-repos-txt.sh <fe_branch> [be_branch] [pkg_branch] [web_branch]
# If only one branch is given, it's used for frontend/backend/packages. Web is omitted unless web_branch is passed.

fe_branch="$1"
be_branch="${2:-$fe_branch}"
pkg_branch="${3:-$fe_branch}"
web_branch="$4"

fe_root=~/Documents/bertie/bertie-desktop/${fe_branch//\//-}
be_root=~/Documents/bertie/bertie-backend/${be_branch//\//-}
pkg_root=~/Documents/bertie/bertie-packages/${pkg_branch//\//-}
web_root=""
[[ -n "$web_branch" ]] && web_root=~/Documents/bertie/bertie-web/${web_branch//\//-}

dirs=("$be_root" "$fe_root" "$pkg_root")
[[ -n "$web_root" ]] && dirs+=("$web_root")

for dir in $dirs; do
  mkdir -p "$dir/tmp"
  {
    printf 'frontend=%s\nbackend=%s\npackages=%s\n' "$fe_root" "$be_root" "$pkg_root"
    [[ -n "$web_root" ]] && printf 'web=%s\n' "$web_root"
  } > "$dir/tmp/repos.txt"
done
