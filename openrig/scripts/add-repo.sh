#!/usr/bin/env bash
# add-repo.sh <repo>... — add repos to the rig this folder belongs to. For the
# lead, which runs it from its own folder; the human can run it too.
#
#   add-repo.sh bt            or   add-repo.sh bertie-web bertie-backend
#
# Every seat gets a worktree of each repo on the rig's branches, with
# dependencies installed (several minutes) and, with desktop and packages, the
# ui link. The culture and guidance are rendered again. Prints what changed,
# for the lead to pass on to the builders that need it.
# Repos: bd, bp, bw, bb, ba, bt or their full names. Already-present ones are skipped.

set -euo pipefail
. "$(dirname "$0")/lib.sh"

case "${1:-}" in -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
[ $# -gt 0 ] || die "usage: add-repo.sh <repo>... (bd, bp, bw, bb, ba, bt)"

dir=$PWD
while [ "$dir" != / ] && [ ! -f "$dir/.rig/rig.env" ]; do dir=$(dirname "$dir"); done
env="$dir/.rig/rig.env"
[ -f "$env" ] || die "add-repo: $PWD is not inside a rig folder from start-rig"
[ "$(rig_env_get "$env" LAYOUT)" = 2 ] || die "add-repo: $dir is an old-layout rig, which can't be extended"

list=""
for r in "$@"; do list="$list${list:+,}$r"; done
exec "$(dirname "$0")/start-rig.sh" "$(rig_env_get "$env" BRANCH)" \
  --name "$(rig_env_get "$env" RIG)" -r "$list" --from-lead
