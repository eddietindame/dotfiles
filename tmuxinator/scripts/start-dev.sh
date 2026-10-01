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
agents_arg=""          # empty means all of them
forward=()

# Tab order in the space, and the worktree each agent runs in.
AGENT_ORDER=(bb bd bp)

while [ $# -gt 0 ]; do
  case "$1" in
    --herdr-only) herdr_only=true; shift ;;
    --no-herdr)   skip_herdr=true; shift ;;
    -a|--agents)
      # start-dev's own flag, deliberately not forwarded to tmuxinator
      agents_arg="$2"; shift 2 ;;
    -be|--backend)
      be_branch="$2"; forward+=("$1" "$2"); shift 2 ;;
    -d|--docker|-b|--base|-bfe|--base-fe|-bbe|--base-be)
      forward+=("$1" "$2"); shift 2 ;;
    -r|--rebase|-c|--claude|-l|--desktop-local)
      forward+=("$1"); shift ;;
    *)
      [ -z "$fe_branch" ] && fe_branch="$1"
      forward+=("$1"); shift ;;
  esac
done

if [ -z "$fe_branch" ]; then
  cat >&2 <<USAGE
usage: $(basename "$0") <branch> [-be BRANCH] [-d N] [-b BASE] [-bfe BASE] [-bbe BASE] [-r] [-c] [-l] [-a LIST]
       $(basename "$0") --herdr-only <branch> [-be BRANCH] [-a LIST]
       $(basename "$0") --no-herdr <branch> [...]

  -c, --claude    also run claude in tmux's bb/bd/bp windows (default: herdr only)
  --no-herdr      skip the herdr space
  --herdr-only    build only the herdr space, don't touch tmux
  -a, --agents    comma-separated herdr agents to start: bb, bd, bp
                  (default: all three; order is always bb,bd,bp)
                  e.g. -a bb         just the backend agent
                       -a bb,bp      backend and packages

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

agent_root() {
  case "$1" in
    bb) printf '%s' "$backend_root" ;;
    bd) printf '%s' "$frontend_root" ;;
    bp) printf '%s' "$packages_root" ;;
  esac
}

# Resolve --agents into AGENTS, deduped and in AGENT_ORDER regardless of the
# order given, so the tabs always read bb, bd, bp.
AGENTS=()
if [ -z "$agents_arg" ]; then
  AGENTS=("${AGENT_ORDER[@]}")
else
  IFS=',' read -r -a _requested <<<"$agents_arg"
  for _a in "${_requested[@]}"; do
    _a="${_a//[[:space:]]/}"
    [ -z "$_a" ] && continue
    case "$_a" in
      bb|bd|bp) ;;
      *) echo "start-dev: unknown agent '$_a' (expected bb, bd or bp)" >&2; exit 1 ;;
    esac
  done
  for _a in "${AGENT_ORDER[@]}"; do
    for _r in "${_requested[@]}"; do
      [ "${_r//[[:space:]]/}" = "$_a" ] && { AGENTS+=("$_a"); break; }
    done
  done
  if [ ${#AGENTS[@]} -eq 0 ]; then
    echo "start-dev: --agents was given but named none of bb, bd, bp" >&2
    exit 1
  fi
fi

# ~~~ preflight: the repos have to be cloned before any of this makes sense ~~~
# ensure-worktree.sh checks this too, but tmuxinator would already have built a
# session by then. Check up front so nothing is created on a broken setup, and
# report every missing repo at once rather than one per re-run.
if ! $herdr_only; then
  # Same discovery rule as dev.yml: the base clone is the subdirectory whose
  # .git is a directory. Linked worktrees have .git as a file pointing back at
  # it, so this finds the clone whatever the folder is called.
  missing_repos=()
  for repo in bertie-desktop bertie-backend bertie-packages bertie-auth; do
    found=""
    for candidate in "$REPO_ROOT/$repo"/*/; do
      [ -d "${candidate}.git" ] && { found="$candidate"; break; }
    done
    [ -n "$found" ] || missing_repos+=("$REPO_ROOT/$repo")
  done
  if [ ${#missing_repos[@]} -gt 0 ]; then
    echo "start-dev: no base checkout found in:" >&2
    printf '  %s\n' "${missing_repos[@]}" >&2
    echo "Clone them before starting a dev environment." >&2
    exit 1
  fi
fi

# ~~~ tmux side: unchanged, just detached so we can build the herdr space ~~~
if ! $herdr_only; then
  echo "$(date '+%Y-%m-%d %H:%M') tmuxinator start dev ${forward[*]}" >>"$HOME/.tmuxinator_log"
  # tmuxinator exits 1, with no output, when the session already exists. Under
  # `set -e` that killed the script right here — after the log line above but
  # before the herdr half and before say()/warn() are even defined, so it
  # failed completely silently. The effect was that cleanup-worktrees followed
  # by a plain re-run never rebuilt the herdr space, because the tmux session
  # from the first run was still alive.
  #
  # Only fatal if no session actually materialised; an existing one is fine.
  tmux_rc=0
  tmuxinator start dev "${forward[@]}" --no-attach || tmux_rc=$?
  if [ "$tmux_rc" -ne 0 ]; then
    if tmux has-session -t "=$fe_branch" 2>/dev/null ||
       tmux has-session -t "=${fe_branch//./_}" 2>/dev/null; then
      echo "start-dev: tmux session for '$fe_branch' already exists — reusing it"
    else
      echo "start-dev: tmuxinator failed (exit $tmux_rc) and no session exists" >&2
      exit "$tmux_rc"
    fi
  fi
fi

# ~~~ herdr side: one tab per agent window ~~~
# Agent names must match [a-z][a-z0-9_-]{0,31} and be unique among live agents.
sanitize() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g'; }
short=$(sanitize "$fe_slug"); short="${short:0:28}"

json_get() { jq -r "$1"; }

LOG="$HOME/.start-dev.log"
problems=0
say() { # everything the herdr half reports goes to the terminal *and* a log,
        # because `exec tmux attach` wipes the screen a moment later
  printf '%s\n' "$1" >&2
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" >>"$LOG"
}
warn() { problems=$((problems + 1)); say "$1"; }

start_agent() { # <pane_id> <prefix>
  local pane="$1" name="$2-$short" err
  err=$(herdr agent start "$name" --kind "$AGENT_KIND" --pane "$pane" --timeout 60000 2>&1 >/dev/null) && return 0

  # `agent start` only returns 0 once the agent is ready for input. A fresh
  # worktree makes claude open its "do you trust this folder?" gate first, so
  # it reports agent_not_ready even though the agent launched fine.
  if herdr agent list | jq -e --arg p "$pane" '.result.agents[] | select(.pane_id == $p)' >/dev/null 2>&1; then
    say "herdr: $name started but is waiting on a prompt (trust dialog?) — answer it in $pane"
    return 0
  fi
  warn "herdr: could not start $AGENT_KIND in $pane (pane left as a shell): ${err:-unknown error}"
}

add_agent_tab() { # <workspace_id> <label> <cwd>
  local ws="$1" label="$2" cwd="$3" pane
  pane=$(herdr tab create --workspace "$ws" --cwd "$cwd" --label "$label" --no-focus \
         | json_get .result.root_pane.pane_id)
  start_agent "$pane" "$label"
}

build_herdr_space() {
  local existing ws_json ws pane missing=false d a first

  # Only the worktrees we are actually going to use: checking all three would
  # refuse `-a bb` just because an unrelated repo was not checked out.
  #
  # A directory is not enough: on_project_start's `mkdir -p .../tmp` creates
  # these paths even when the worktree step failed, so an empty non-repo folder
  # would pass a -d test and get agents started in it.
  for a in "${AGENTS[@]}"; do
    d=$(agent_root "$a")
    if ! git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
      warn "herdr: $d is not a git worktree"
      missing=true
    fi
  done
  if $missing; then
    warn "herdr: run without --herdr-only first so the worktrees get created"
    return 1
  fi

  existing=$(herdr workspace list \
             | jq -r --arg l "$fe_branch" '.result.workspaces[] | select(.label == $l) | .workspace_id' \
             | awk 'NR==1')
  if [ -n "$existing" ]; then
    say "herdr: space '$fe_branch' already exists ($existing) — not touching it"
    return 0
  fi

  # workspace create makes the space, its first tab, and that tab's pane, so the
  # first selected agent lands in the root tab and the rest get tabs added.
  first="${AGENTS[0]}"
  ws_json=$(herdr workspace create --cwd "$(agent_root "$first")" --label "$fe_branch" --no-focus)
  ws=$(json_get .result.workspace.workspace_id <<<"$ws_json")
  pane=$(json_get .result.root_pane.pane_id <<<"$ws_json")
  herdr tab rename "$(json_get .result.tab.tab_id <<<"$ws_json")" "$first" >/dev/null
  start_agent "$pane" "$first"

  for a in "${AGENTS[@]:1}"; do
    add_agent_tab "$ws" "$a" "$(agent_root "$a")"
  done

  # ${AGENTS[*]} would join on IFS (a space); keep the original comma phrasing.
  local list
  printf -v list '%s, ' "${AGENTS[@]}"
  say "herdr: space '$fe_branch' ($ws) ready — ${list%, }"
}

if ! $skip_herdr; then
  # No pipeline here on purpose: under `set -o pipefail`, `herdr status | grep -q`
  # reports failure whenever grep matches the first line and exits, because the
  # closed pipe kills herdr with SIGPIPE. That silently skipped the whole herdr
  # half whenever the server *was* running.
  server_status=$(herdr status server 2>/dev/null || true)
  if [[ "$server_status" == *"status: running"* ]]; then
    build_herdr_space || true
  else
    warn "herdr: server not running — no space created. Open herdr, then run:"
    warn "  $0 --herdr-only $fe_branch${be_branch:+ -be $be_branch}"
  fi
fi

# ~~~ land in tmux, as before ~~~
if ! $herdr_only; then
  # attaching wipes the screen, so hold anything gone wrong long enough to read
  if [ "$problems" -gt 0 ]; then
    say "herdr: $problems problem(s) above — also logged to $LOG"
    sleep 4
  fi
  session="$fe_branch"
  tmux has-session -t "=$session" 2>/dev/null || session="${fe_branch//./_}"
  if [ -n "${TMUX:-}" ]; then
    exec tmux switch-client -t "=$session"
  else
    exec tmux attach -t "=$session"
  fi
fi
