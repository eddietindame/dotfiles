#!/usr/bin/env bash
# herdr-agent-view.sh — scope the sidebar's agent panel to the current space.
#
# Usage: herdr-agent-view.sh [toggle|space|all]
#
# herdr has no keybinding action for this, but its socket API does:
# agent.view.set with a `current_workspace_id` context filter narrows the panel
# to the focused space and keeps following it as you switch spaces;
# agent.view.clear restores the default all-spaces view.
#
# The API can't be read back (agent.view state is absent from `api snapshot`,
# and `agent list` ignores the view), so the current mode is remembered here.

set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_FILE="$STATE_DIR/herdr-agent-view"
PID_FILE="$STATE_DIR/herdr-agent-view.pid"
SOURCE_ID="herdr-agent-view"
FOLLOWER="$(cd "$(dirname "$0")" && pwd)/herdr-agent-view-follow.py"

LOG_FILE="$STATE_DIR/herdr-agent-view.log"
log() { mkdir -p "$STATE_DIR"; printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >>"$LOG_FILE"; }

# herdr runs `type = "shell"` bindings detached, and that child does not
# necessarily inherit the login PATH — so never depend on `herdr` being on it.
socket_path() {
  local s
  if [ -n "${HERDR_SOCKET:-}" ]; then
    printf '%s\n' "$HERDR_SOCKET"
    return
  fi
  if command -v herdr >/dev/null 2>&1; then
    s=$(herdr status server 2>/dev/null | awk '/^socket:/ {print $2}') || s=""
    if [ -n "$s" ]; then
      printf '%s\n' "$s"
      return
    fi
  fi
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/herdr/herdr.sock"
}

api() { # request JSON on stdin -> response JSON on stdout
  python3 -c '
import json, socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
s.sendall(sys.stdin.read().strip().encode() + b"\n")
s.settimeout(5)
buf = b""
while b"\n" not in buf:
    chunk = s.recv(65536)
    if not chunk:
        break
    buf += chunk
sys.stdout.write(buf.split(b"\n")[0].decode())
' "$1"
}

follower_pid() { # echoes the pid if a follower is alive
  local pid
  pid=$(cat "$PID_FILE" 2>/dev/null) || return 1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && printf '%s\n' "$pid"
}

# The follower applies the filter for the focused space immediately, then keeps
# re-applying it on every workspace.focused event — which is what makes the
# scope follow you around instead of pinning to one space.
scope_space() {
  local sock="$1" pid
  if pid=$(follower_pid); then
    log "follower already running (pid $pid)"
  else
    mkdir -p "$STATE_DIR"
    nohup python3 "$FOLLOWER" "$sock" "$SOURCE_ID" >>"$LOG_FILE" 2>&1 &
    printf '%s\n' "$!" >"$PID_FILE"
    log "follower started (pid $!)"
  fi
  printf 'space\n' >"$STATE_FILE"
}

stop_follower() {
  local pid
  if pid=$(follower_pid); then
    kill "$pid" 2>/dev/null || true
    log "follower stopped (pid $pid)"
  fi
  rm -f "$PID_FILE"
}

scope_all() {
  local sock="$1"
  stop_follower
  api "$sock" >/dev/null <<JSON
{"id":"$SOURCE_ID:clear","method":"agent.view.clear","params":{"source":"$SOURCE_ID"}}
JSON
  mkdir -p "$STATE_DIR"
  printf 'all\n' >"$STATE_FILE"
}

log "invoked: ${1:-toggle}"

sock=$(socket_path)
if [ ! -S "$sock" ]; then
  log "no socket at $sock"
  echo "herdr socket not found at $sock" >&2
  exit 1
fi

case "${1:-toggle}" in
  space) scope_space "$sock"; log "scoped to current space" ;;
  all)   scope_all "$sock";   log "scoped to all spaces" ;;
  toggle)
    if [ "$(cat "$STATE_FILE" 2>/dev/null || echo all)" = "space" ]; then
      scope_all "$sock"; log "toggled -> all spaces"
    else
      scope_space "$sock"; log "toggled -> current space"
    fi
    ;;
  *) echo "usage: $(basename "$0") [toggle|space|all]" >&2; exit 1 ;;
esac
