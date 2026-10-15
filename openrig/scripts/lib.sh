# Shared by start-rig.sh and cleanup-rig.sh. Sourced, not run.
#
# Layout: a rig is a feature branch, and the repos are something it contains.
#
#   ~/Documents/bertie-rigs/
#   ├── base/<repo>/                 base clones, one per repo, cloned on first use
#   └── <rig>/                       one folder per rig = per feature branch
#       ├── .rig/                    spec, culture, guidance, rig.env, logs
#       ├── lead/                    lead's cwd (the reviewer shares it, read-only)
#       │   ├── BRIEF.md             living brief, kept by the lead
#       │   ├── PROGRESS.md          slice plan, kept by the lead
#       │   └── <repo>/              worktree → <branch>
#       └── b1/<repo>/               worktree → <branch>-b1, and so on
#
# Seats run in their folder, not in a repo, so the files OpenRig writes into a
# seat's cwd (AGENTS.md block, .claude/, .mcp.json, .openrig/) never show up in
# git.
#
# Rigs made before this layout keep their rig.env in _specs/<rig>/ and their
# worktrees in <repo>/<slug>[-bN]; cleanup-rig still handles them.
#
# Nothing here touches ~/Documents/bertie: start-dev and cleanup-worktrees never
# see these checkouts, and these scripts never see yours.

DEV_ROOT="$HOME/Documents/bertie"
RIG_ROOT="${BERTIE_RIG_ROOT:-$HOME/Documents/bertie-rigs}"   # override for testing
BASES_ROOT="$RIG_ROOT/base"
SPECS_ROOT="$RIG_ROOT/_specs"   # old layout only
OPENRIG_DIR="$HOME/.config/openrig"

say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

# For option parsing: the option in $1 must be followed by a value, not by
# nothing (set -u would die on $2) or by the next option.
need_value() { # "$@" of the caller
  [ $# -ge 2 ] && [ -n "$2" ] && [ "${2#-}" = "$2" ] ||
    die "$(basename "$0" .sh): $1 needs a value"
}

# -r accepts the repo name or its prefix.
resolve_repo() {
  case "$1" in
    bd|bertie-desktop)  echo bertie-desktop ;;
    bb|bertie-backend)  echo bertie-backend ;;
    bp|bertie-packages) echo bertie-packages ;;
    bw|bertie-web)      echo bertie-web ;;
    ba|bertie-auth)     echo bertie-auth ;;
    bt|bertie-terraform) echo bertie-terraform ;;
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
    bertie-terraform) echo bt ;;
  esac
}

# Worktree folder name in the old layout: same formula as start-dev / dev.yml.
branch_slug() { printf '%s' "${1//\//-}"; }

# Rig name: the branch without its type prefix, lowercased and reduced to
# [a-z0-9-]. One branch is one rig, and cleanup-rig can derive it again.
#   feat/BER-123-button-colour → ber-123-button-colour
rig_name_for() { # <branch>
  local rest="$1"
  case "$rest" in */*) rest="${rest#*/}" ;; esac
  printf '%s' "$rest" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' |
    tr -s '-' | sed 's/^-//; s/-$//'
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

# The dev clone of a repo: <repo>/<prefix>-base for most, or the <repo> folder
# itself when it is the clone (bertie-terraform).
dev_base_for() { # <repo>
  [ -d "$DEV_ROOT/$1/.git" ] && { printf '%s' "$DEV_ROOT/$1"; return 0; }
  find_base "$DEV_ROOT/$1"
}

# Every rig.env, new layout and old, one path per line.
all_rig_envs() {
  local f
  for f in "$RIG_ROOT"/*/.rig/rig.env "$SPECS_ROOT"/*/rig.env; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}

# Reads one key from a rig.env without sourcing it into the caller's scope.
rig_env_get() { # <file> <key>
  (. "$1" && eval "printf '%s' \"\${$2:-}\"")
}

# Every base clone a rig worktree could hang off: the rig bases, the old
# layout's <repo>/<prefix>-base, and the dev bases (an agent once made a rig
# worktree from one).
all_bases() {
  local d b
  for d in "$BASES_ROOT"/*/; do [ -d "${d}.git" ] && printf '%s\n' "${d%/}"; done
  for d in "$RIG_ROOT"/bertie-*/ "$DEV_ROOT"/*/; do
    if [ -d "${d}.git" ]; then printf '%s\n' "${d%/}"
    else b=$(find_base "${d%/}") && printf '%s\n' "$b"; fi
  done
  return 0
}

# "<base>\t<worktree>" for every linked worktree under <dir>, in any base.
worktrees_under() { # <dir>
  local base wt
  while IFS= read -r base; do
    git -C "$base" worktree list --porcelain 2>/dev/null |
      sed -n 's/^worktree //p' |
      while IFS= read -r wt; do
        case "$wt" in "$1"/*) printf '%s\t%s\n' "$base" "$wt" ;; esac
      done
  done < <(all_bases)
}
