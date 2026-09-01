#!/usr/bin/env bash
# Run the bertie-desktop dev server on THIS machine, creating the worktree first.
#
# Invoked over ssh by dev.yml's -l/--desktop-local, so that the Electron window
# opens on the machine you're sitting at while the rest of the stack stays on the
# host. The backend/postgres/auth ports arrive here as -R forwards, so the app's
# .env, which points at http://localhost:PORT, is correct unchanged.
#
#   desktop-dev.sh <branch> [base-branch] [--rebase]

set -euo pipefail

branch="${1:?usage: $(basename "$0") <branch> [base-branch] [--rebase]}"
shift

slug="${branch//\//-}"
root="$HOME/Documents/bertie/bertie-desktop"
here="$(cd "$(dirname "$0")" && pwd)"

# Same discovery rule as dev.yml: the base clone is the subdirectory whose .git
# is a directory; linked worktrees have .git as a file pointing back at it.
base=""
for d in "$root"/*/; do
  [ -d "${d}.git" ] && { base="$d"; break; }
done
if [ -z "$base" ]; then
  echo "desktop-dev: no base checkout in $root — clone bertie-desktop there first" >&2
  exit 1
fi

"$here/ensure-worktree.sh" "$base" "$root/$slug" "$branch" "$@"

cd "$root/$slug"

# A fresh worktree has no node_modules, and `npm run dev` rebuilds better-sqlite3
# against this platform's electron — which is the whole reason the tree can't be
# shared with the host.
[ -d node_modules ] || npm i

exec npm run dev
