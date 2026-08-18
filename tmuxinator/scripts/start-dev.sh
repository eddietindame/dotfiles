#!/usr/bin/env bash
# start-dev.sh — start the tmuxinator "dev" environment, then mirror only its
# agent windows into a herdr space.
#
# tmux keeps everything it always had (docker, servers, nvim, sqlite panes).
# herdr gets one tab per agent window — bb, bd, bp — each running claude as a
# tracked agent, so the sidebar shows idle/working/blocked and prefix+J/K jumps
# between them. Run the two in separate Ghostty windows.
#
# The two halves are independent. -c/--claude controls tmux's claude panes,
# --no-herdr/--herdr-only control the herdr space; any combination is valid:
#
#   start-dev.sh <branch>                 # claude in herdr only          (default)
#   start-dev.sh <branch> -c              # claude in both
#   start-dev.sh <branch> -c --no-herdr   # claude in tmux only  (original setup)
#   start-dev.sh <branch> --no-herdr      # no claude anywhere
#   start-dev.sh --herdr-only <branch>    # rebuild just the herdr space
#
# All dev.yml options are forwarded verbatim: -be, -d, -b, -bfe, -bbe, -r, -c.
# See ../README.md for what they do.

set -euo pipefail

REPO_ROOT="$HOME/Documents/bertie"
AGENT_KIND=claude

herdr_only=false
skip_herdr=false
fe_branch=""
be_branch=""
forward=()

while [ $# -gt 0 ]; do
  case "$1" in
    --herdr-only) herdr_only=true; shift ;;
    --no-herdr)   skip_herdr=true; shift ;;
    -be|--backend)
      be_branch="$2"; forward+=("$1" "$2"); shift 2 ;;
    -d|--docker|-b|--base|-bfe|--base-fe|-bbe|--base-be)
      forward+=("$1" "$2"); shift 2 ;;
    -r|--rebase|-c|--claude)
      forward+=("$1"); shift ;;
    *)
      [ -z "$fe_branch" ] && fe_branch="$1"
      forward+=("$1"); shift ;;
  esac
done

if [ -z "$fe_branch" ]; then
  cat >&2 <<USAGE
usage: $(basename "$0") <branch> [-be BRANCH] [-d N] [-b BASE] [-bfe BASE] [-bbe BASE] [-r] [-c]
       $(basename "$0") --herdr-only <branch> [-be BRANCH]
       $(basename "$0") --no-herdr <branch> [...]

  -c, --claude    also run claude in tmux's bb/bd/bp windows (default: herdr only)
  --no-herdr      skip the herdr space
  --herdr-only    build only the herdr space, don't touch tmux

See ~/.config/tmuxinator/README.md for the dev.yml options.
USAGE
  exit 1
fi
be_branch="${be_branch:-$fe_branch}"

# Same path formula as dev.yml
fe_slug="${fe_branch//\//-}"
be_slug="${be_branch//\//-}"
frontend_root="$REPO_ROOT/bertie-desktop/$fe_slug"
backend_root="$REPO_ROOT/bertie-backend/$be_slug"
packages_root="$REPO_ROOT/bertie-packages/$fe_slug"

# ~~~ tmux side: unchanged, just detached so we can build the herdr space ~~~
if ! $herdr_only; then
  echo "$(date '+%Y-%m-%d %H:%M') tmuxinator start dev ${forward[*]}" >>"$HOME/.tmuxinator_log"
  tmuxinator start dev "${forward[@]}" --no-attach
fi

# ~~~ herdr side: one tab per agent window ~~~
# Agent names must match [a-z][a-z0-9_-]{0,31} and be unique among live agents.
sanitize() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g'; }
short=$(sanitize "$fe_slug"); short="${short:0:28}"

json_get() { jq -r "$1"; }

start_agent() { # <pane_id> <prefix>
  local pane="$1" name="$2-$short"
  if ! herdr agent start "$name" --kind "$AGENT_KIND" --pane "$pane" --timeout 60000 >/dev/null; then
    echo "herdr: could not start $AGENT_KIND in $pane (pane left as a shell)" >&2
  fi
}

add_agent_tab() { # <workspace_id> <label> <cwd>
  local ws="$1" label="$2" cwd="$3" pane
  pane=$(herdr tab create --workspace "$ws" --cwd "$cwd" --label "$label" --no-focus \
         | json_get .result.root_pane.pane_id)
  start_agent "$pane" "$label"
}

build_herdr_space() {
  local existing ws_json ws pane missing=false d

  for d in "$backend_root" "$frontend_root" "$packages_root"; do
    if [ ! -d "$d" ]; then
      echo "herdr: $d does not exist yet" >&2
      missing=true
    fi
  done
  if $missing; then
    echo "herdr: run without --herdr-only first so the worktrees get created" >&2
    return 1
  fi

  existing=$(herdr workspace list \
             | jq -r --arg l "$fe_branch" '.result.workspaces[] | select(.label == $l) | .workspace_id' \
             | head -1)
  if [ -n "$existing" ]; then
    echo "herdr: space '$fe_branch' already exists ($existing) — not touching it"
    return 0
  fi

  # workspace create makes the space, its first tab, and that tab's pane
  ws_json=$(herdr workspace create --cwd "$backend_root" --label "$fe_branch" --no-focus)
  ws=$(json_get .result.workspace.workspace_id <<<"$ws_json")
  pane=$(json_get .result.root_pane.pane_id <<<"$ws_json")
  herdr tab rename "$(json_get .result.tab.tab_id <<<"$ws_json")" bb >/dev/null
  start_agent "$pane" bb

  add_agent_tab "$ws" bd "$frontend_root"
  add_agent_tab "$ws" bp "$packages_root"

  echo "herdr: space '$fe_branch' ($ws) ready — bb, bd, bp"
}

if ! $skip_herdr; then
  if herdr status server 2>/dev/null | grep -q '^status: running'; then
    build_herdr_space || true
  else
    echo "herdr: server not running — start herdr in its Ghostty window, then:" >&2
    echo "  $0 --herdr-only $fe_branch${be_branch:+ -be $be_branch}" >&2
  fi
fi

# ~~~ land in tmux, as before ~~~
if ! $herdr_only; then
  session="$fe_branch"
  tmux has-session -t "=$session" 2>/dev/null || session="${fe_branch//./_}"
  if [ -n "${TMUX:-}" ]; then
    exec tmux switch-client -t "=$session"
  else
    exec tmux attach -t "=$session"
  fi
fi
