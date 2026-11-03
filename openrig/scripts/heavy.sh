#!/usr/bin/env bash
# heavy.sh <command...> — run a memory-heavy command when the machine has room.
#
# Every rig on this Mac shares its 16 GB. One TypeScript typecheck can take
# 4 GB, and a test suite with a headless browser or a Next build about as much,
# so when several builders run theirs at once the Mac runs out of memory:
# macOS kills processes, logs the desktop session out and took Tailscale (and
# with it ssh) down. The rigs' culture file says to run typechecks, test
# suites, builds and commits whose hooks run them through this.
#
# At most HEAVY_SLOTS (default 2) run at once, across every rig. The rest wait
# their turn, printing one line, then run as if called directly: same output,
# same exit status.

slots="${HEAVY_SLOTS:-2}"
dir="$HOME/.cache/heavy-slots"   # not TMPDIR: seats may start without it
[ $# -gt 0 ] || { echo "usage: $(basename "$0") <command...>" >&2; exit 2; }
mkdir -p "$dir"

waited=false
while :; do
  for i in $(seq 1 "$slots"); do
    # lockf exits 75 when the slot is taken; otherwise it ran the command.
    # (A command that itself exits 75 is run again, which none of ours do.)
    lockf -s -t 0 "$dir/$i" "$@"
    rc=$?
    [ "$rc" -eq 75 ] || exit "$rc"
  done
  $waited || { echo "heavy: $slots heavy jobs already running on this Mac; waiting for one to finish" >&2; waited=true; }
  sleep 5
done
