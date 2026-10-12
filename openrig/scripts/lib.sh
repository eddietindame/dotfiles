# Shared by start-rig.sh and cleanup-rig.sh. Sourced, not run.
#
# Layout, mirroring ~/Documents/bertie so the same habits apply:
#
#   ~/Documents/bertie-rigs/
#   ├── <repo>/<prefix>-base/        base clone, the anchor for rig worktrees only
#   ├── <repo>/<slug>/               lead worktree   → <branch>
#   ├── <repo>/<slug>-b1/            builder worktree → <branch>-b1
#   └── _specs/<rig>/                generated spec, guidance, brief, rig.env
#
# Nothing here touches ~/Documents/bertie: start-dev and cleanup-worktrees never
# see these checkouts, and these scripts never see yours.

DEV_ROOT="$HOME/Documents/bertie"
RIG_ROOT="${BERTIE_RIG_ROOT:-$HOME/Documents/bertie-rigs}"   # override for testing
SPECS_ROOT="$RIG_ROOT/_specs"
OPENRIG_DIR="$HOME/.config/openrig"

say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

# -r accepts the repo name or its prefix.
resolve_repo() {
  case "$1" in
    bd|bertie-desktop)  echo bertie-desktop ;;
    bb|bertie-backend)  echo bertie-backend ;;
    bp|bertie-packages) echo bertie-packages ;;
    bw|bertie-web)      echo bertie-web ;;
    ba|bertie-auth)     echo bertie-auth ;;
    *) return 1 ;;
  esac
}

repo_prefix() {
  case "$1" in
    bertie-desktop)  echo bd ;;
    bertie-backend)  echo bb ;;
    bertie-packages) echo bp ;;
    bertie-web)      echo bw ;;
    bertie-auth)     echo ba ;;
  esac
}

# Worktree folder name: same formula as start-dev / dev.yml.
branch_slug() { printf '%s' "${1//\//-}"; }

# Rig name: repo prefix + the branch without its type prefix, lowercased and
# reduced to [a-z0-9-]. Unique because a branch can only be checked out once per
# repo, and derivable again from the branch alone, which cleanup-rig relies on.
#   feat/BER-123-button-colour in bertie-desktop → bd-ber-123-button-colour
rig_name_for() { # <repo> <branch>
  local rest="$2"
  case "$rest" in */*) rest="${rest#*/}" ;; esac
  rest=$(printf '%s' "$rest" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' |
    tr -s '-' | sed 's/^-//; s/-$//')
  printf '%s-%s' "$(repo_prefix "$1")" "$rest"
}

# Base clone = the direct child whose .git is a directory (linked worktrees have
# a .git file). Same discovery rule as start-dev and dev.yml.
find_base() { # <dir>
  local c
  for c in "$1"/*/; do
    [ -d "${c}.git" ] && { printf '%s' "${c%/}"; return 0; }
  done
  return 1
}

# Every rig.env, one path per line.
all_rig_envs() {
  local f
  for f in "$SPECS_ROOT"/*/rig.env; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}

# Reads one key from a rig.env without sourcing it into the caller's scope.
rig_env_get() { # <file> <key>
  (. "$1" && eval "printf '%s' \"\${$2:-}\"")
}
