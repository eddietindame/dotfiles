#!/usr/bin/env bash
# add-repo.sh <repo>... [--seat SEATS] — add repos to the rig this folder
# belongs to. For the lead, which runs it from its own folder; the human can run
# it too.
#
#   add-repo.sh bt                 the lead's folder gets bertie-terraform
#   add-repo.sh bt --seat b1       and b1 gets one too (b1,b2 or all)
#
# Without --seat only the lead gets the repo; it gives builders one when it
# assigns them a slice that needs it. Each new worktree is on the rig's branch
# for that seat, with dependencies installed (several minutes) and, where a seat
# has both desktop and packages, the ui link. The culture and guidance are
# rendered again. Prints what changed, for the lead to pass on.
# Repos: bd, bp, bw, bb, ba, bt or their full names. Worktrees already there are skipped.

set -euo pipefail
. "$(dirname "$0")/lib.sh"

case "${1:-}" in -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
usage="usage: add-repo.sh <repo>... [--seat b1,b2|all] (repos: bd, bp, bw, bb, ba, bt)"
list="" seat_opt=()
while [ $# -gt 0 ]; do
  case "$1" in
    -s|--seat) need_value "$@"; seat_opt+=(--seat "$2"); shift 2 ;;
    -*)        die "add-repo: unknown option $1. $usage" ;;
    *)         list="$list${list:+,}$1"; shift ;;
  esac
done
[ -n "$list" ] || die "$usage"

dir=$PWD
while [ "$dir" != / ] && [ ! -f "$dir/.rig/rig.env" ]; do dir=$(dirname "$dir"); done
env="$dir/.rig/rig.env"
[ -f "$env" ] || die "add-repo: $PWD is not inside a rig folder from start-rig"
[ "$(rig_env_get "$env" LAYOUT)" = 2 ] || die "add-repo: $dir is an old-layout rig, which can't be extended"

exec "$(dirname "$0")/start-rig.sh" "$(rig_env_get "$env" BRANCH)" \
  --name "$(rig_env_get "$env" RIG)" -r "$list" ${seat_opt[@]+"${seat_opt[@]}"} --from-lead
