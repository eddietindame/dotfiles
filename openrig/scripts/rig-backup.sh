#!/usr/bin/env bash
# rig-backup.sh — keep every rig recoverable from GitHub, so it can be resumed
# on another machine when the one running it is down or out of reach.
#
#   rig-backup.sh backup [rig...]   back up these rigs (default: all here) now
#   rig-backup.sh --start           start the 10-minute loop once (tmux.base.conf)
#   rig-backup.sh list              rigs with a backup on GitHub
#   rig-backup.sh resume <rig> [--no-launch]
#                                   rebuild a rig here from its backup and start it
#   rig-backup.sh claim <rig>       make this machine the rig's owner again
#   rig-backup.sh forget <rig>      delete a finished rig's backup from GitHub
#
# Everything goes into the rig's own repos on GitHub, in refs outside
# refs/heads: they don't show up as branches, nobody fetches them by default
# and no workflow runs on them (all of ours trigger on named branches only).
# Per repo, for rig <rig>:
#
#   refs/rigs/<rig>/heads/<branch>        every branch a seat has checked out,
#                                         and local branches named <BRANCH>*
#   refs/rigs/<rig>/detached/<seat>/<dir> a worktree's commit when it has no branch
#   refs/rigs/<rig>/wip/<seat>/<dir>      uncommitted changes to tracked files
#                                         (git stash create; untracked files aren't kept)
#   refs/rigs/<rig>/state                 the rig's files: .rig/ (spec, culture,
#                                         guidance, rig.env), the lead's BRIEF.md and
#                                         PROGRESS.md, its open queue items and a
#                                         manifest of its worktrees. A history.
#
# Only what changed is pushed, with --no-verify so no pre-push hook runs.
# The state records which machine owns the rig. `resume` claims it for the
# machine it runs on; the old owner's next backup sees that, stops backing the
# rig up and tells its lead, so two copies never overwrite each other.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

ORG_URL="git@github.com:bertie-technology"
KNOWN_REPOS="bertie-desktop bertie-packages bertie-backend bertie-web bertie-auth bertie-terraform bertie-integrations bertie-dashboard"
INTERVAL="${RIG_BACKUP_INTERVAL:-600}"
CACHE="$HOME/.cache/rig-backup"
HOST=${RIG_BACKUP_HOST:-$(scutil --get LocalHostName 2>/dev/null || hostname -s)}   # override: tests only
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
export PATH="$HOME/.local/bin:$HOME/.volta/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p "$CACHE"
log() { echo "$(date '+%F %T') $*" >>"$CACHE/log"; }

# ~~~ backup ~~~

# worktrees <rig_dir>: "seat<TAB>dir<TAB>path" for every git checkout in a seat folder.
worktrees() {
  local s w
  for s in "$1"/*/; do
    s="${s%/}"
    for w in "$s"/*/; do
      w="${w%/}"
      [ -e "$w/.git" ] && printf '%s\t%s\t%s\n' "${s##*/}" "${w##*/}" "$w"
    done
  done
}

# queue_export <rig>: the rig's open queue items, stable fields only, as JSON.
queue_export() {
  rig queue list --json --full --state pending,in-progress,blocked --limit 500 2>/dev/null |
    python3 -c '
import json, sys
rig = sys.argv[1]
try: items = json.load(sys.stdin)
except Exception: items = []
keep = ("qitemId", "sourceSession", "destinationSession", "state", "priority",
        "summary", "body", "tags", "blockedOn", "tsCreated")
def ours(s): return str(s or "").split("@host-")[0].endswith("@" + rig)
out = [{k: i.get(k) for k in keep} for i in items
       if ours(i.get("destinationSession")) or ours(i.get("sourceSession"))]
print(json.dumps(sorted(out, key=lambda i: i["qitemId"]), indent=1))
' "$1"
}

# backup_rig <rig_dir> [claim]: push what changed. With claim, take ownership
# even if another machine holds it (resume does this).
backup_rig() {
  local rig_dir="$1" claim="${2:-}" rig BRANCH bk tmp line seat dir wt url repo common br sha wip
  [ -f "$rig_dir/.rig/rig.env" ] || return 0
  rig=$(rig_env_get "$rig_dir/.rig/rig.env" RIG); BRANCH=$(rig_env_get "$rig_dir/.rig/rig.env" BRANCH)
  bk="$rig_dir/.rig/backup"; mkdir -p "$bk"
  if [ -f "$bk/handed-over" ] && [ -z "$claim" ]; then return 0; fi
  tmp=$(mktemp -d "$CACHE/tmp.XXXXXX")

  # What to push, per repo: "<sha> <ref>" lines in $tmp/<repo>.refs.
  printf '# seat\tdir\trepo\turl\tbranch\tcommit\n' >"$tmp/manifest"
  while IFS=$'\t' read -r seat dir wt; do
    url=$(git -C "$wt" remote get-url origin 2>/dev/null) || continue
    case "$url" in *github.com*) ;; *) continue ;; esac   # e.g. the laptop's offload clones
    repo=$(basename "$url" .git)
    common=$(cd "$wt" && cd "$(git rev-parse --git-common-dir)" && pwd)
    # Grouped per clone: a worktree can hang off another clone of the same repo.
    key="$repo-$(printf '%s' "$common" | md5 -q | cut -c1-8)"
    printf '%s\n' "$common" >"$tmp/$key.common"; printf '%s\n' "$url" >"$tmp/$key.url"
    sha=$(git -C "$wt" rev-parse -q --verify HEAD) || continue
    br=$(git -C "$wt" symbolic-ref -q --short HEAD || true)
    if [ -n "$br" ]; then echo "$sha refs/rigs/$rig/heads/$br" >>"$tmp/$key.refs"
    else echo "$sha refs/rigs/$rig/detached/$seat/$dir" >>"$tmp/$key.refs"; fi
    wip=$(git -C "$wt" stash create 2>/dev/null || true)
    [ -n "$wip" ] && echo "$wip refs/rigs/$rig/wip/$seat/$dir" >>"$tmp/$key.refs"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$seat" "$dir" "$repo" "$url" "${br:--}" "$sha" >>"$tmp/manifest"
  done < <(worktrees "$rig_dir")
  for f in "$tmp"/*.common; do
    [ -e "$f" ] || continue
    repo=$(basename "$f" .common)   # the key
    git -C "$(cat "$f")" for-each-ref --format='%(objectname) refs/rigs/'"$rig"'/heads/%(refname:short)' \
      "refs/heads/$BRANCH" "refs/heads/$BRANCH-*" "refs/heads/$BRANCH/*" >>"$tmp/$repo.refs"
    sort -u -k2 "$tmp/$repo.refs" -o "$tmp/$repo.refs"
  done

  { echo "OWNER=$HOST"; echo "OWNER_HOME=$HOME"; echo "RIG_DIR=$rig_dir"; echo "RIG=$rig"; echo "BRANCH=$BRANCH"; } >"$tmp/info"
  queue_export "$rig" >"$tmp/queue.json"

  local pushed=0 failed=0 urls_done=" "
  for f in "$tmp"/*.common; do
    [ -e "$f" ] || continue
    repo=$(basename "$f" .common); common=$(cat "$f"); url=$(cat "$tmp/$repo.url")   # repo: the clone's key
    # The state tree, built in this repo with a scratch index.
    local idx tree rel last_tree remote last parent owner commit specs
    idx="$tmp/$repo.index"
    (
      export GIT_INDEX_FILE="$idx"
      cd "$rig_dir" || exit 1
      { find .rig -type f ! -path '.rig/logs/*' ! -path '.rig/backup/*' ! -path '.rig/offload/*' ! -name '*.pid' ! -name '.DS_Store'
        # Seat folders' own files (plans, slice briefs), not the repos in them and
        # not what OpenRig and Claude write there at launch; big files are evidence.
        for seat in */; do
          seat="${seat%/}"
          find "$seat" -mindepth 1 \( -exec test -e {}/.git \; -o -name node_modules -o -name .claude -o -name .openrig \) -prune -o \
            -type f -size -512k ! -name .mcp.json ! -name CLAUDE.md ! -name AGENTS.md ! -name .DS_Store ! -name "*.log" -print
        done
      } | while IFS= read -r rel; do
        git -C "$common" update-index --add --cacheinfo "100644,$(git -C "$common" hash-object -w "$rig_dir/$rel"),${rel#./}"
      done
      for rel in manifest info queue.json; do
        git -C "$common" update-index --add --cacheinfo "100644,$(git -C "$common" hash-object -w "$tmp/$rel"),.rig-state/$rel"
      done
    ) || { log "$rig: couldn't build the state tree in $repo"; failed=1; continue; }
    tree=$(GIT_INDEX_FILE="$idx" git -C "$common" write-tree)
    last_tree=$(cat "$bk/$repo.tree" 2>/dev/null)

    # Branch refs that changed, and ones to delete (gone since the last push).
    specs=()
    while read -r sha ref; do specs+=("+$sha:$ref"); done < <(comm -13 <(sort "$bk/$repo.refs" 2>/dev/null) <(sort "$tmp/$repo.refs" 2>/dev/null))
    while read -r sha ref; do
      grep -q " $ref\$" "$tmp/$repo.refs" 2>/dev/null || specs+=(":$ref")
    done < <(comm -23 <(sort "$bk/$repo.refs" 2>/dev/null) <(sort "$tmp/$repo.refs" 2>/dev/null))

    # The state goes to each GitHub repo once, from its first clone.
    local want_state=false
    case "$urls_done" in *" $url "*) ;; *) { [ "$tree" != "$last_tree" ] || [ -n "$claim" ]; } && want_state=true ;; esac
    [ ${#specs[@]} -gt 0 ] || $want_state || continue

    # Before pushing anything: has another machine taken this rig over?
    remote=$(git -C "$common" ls-remote origin "refs/rigs/$rig/state" 2>/dev/null | cut -f1)
    last=$(cat "$bk/$repo.state" 2>/dev/null)
    parent=""
    if [ -n "$remote" ]; then
      if [ "$remote" != "$last" ]; then
        git -C "$common" fetch -q origin "+refs/rigs/$rig/state:refs/rigs/$rig/state" 2>/dev/null
        owner=$(git -C "$common" show "$remote:.rig-state/info" 2>/dev/null | sed -n 's/^OWNER=//p')
        if [ -n "$owner" ] && [ "$owner" != "$HOST" ] && [ -z "$claim" ]; then
          handed_over "$rig_dir" "$rig" "$owner"; rm -rf "$tmp"; return 0
        fi
        want_state=true   # ours, but pushed from elsewhere: bring it up to date
      fi
      parent="-p $remote"
    fi
    if $want_state; then
      # shellcheck disable=SC2086
      commit=$(git -C "$common" commit-tree "$tree" $parent -m "rig $rig: state from $HOST at $(date '+%F %T')")
      specs+=("$commit:refs/rigs/$rig/state")
    fi
    [ ${#specs[@]} -gt 0 ] || continue
    if git -C "$common" push -q --no-verify origin "${specs[@]}" 2>"$tmp/push.err"; then
      cp "$tmp/$repo.refs" "$bk/$repo.refs" 2>/dev/null || : >"$bk/$repo.refs"
      echo "$tree" >"$bk/$repo.tree"
      [ -n "${commit:-}" ] && echo "$commit" >"$bk/$repo.state" && git -C "$common" update-ref "refs/rigs/$rig/state" "$commit"
      pushed=$((pushed + 1)); urls_done="$urls_done$url "
    else
      log "$rig: push to ${repo%-*} failed: $(grep -v '^remote:' "$tmp/push.err" | tr '\n' ' ')"; failed=1
    fi
    commit=""
  done
  rm -rf "$tmp"
  [ -n "$claim" ] && rm -f "$bk/handed-over"
  date '+%F %T' >"$bk/last"
  [ "$pushed" -gt 0 ] && log "$rig: backed up to $pushed repo(s)"
  return "$failed"
}

# Another machine resumed this rig: stop backing it up here and say so.
handed_over() { # <rig_dir> <rig> <owner>
  echo "$3" >"$1/.rig/backup/handed-over"
  log "$2: resumed on $3; no longer backed up from here"
  [ -n "${RIG_BACKUP_TEST:-}" ] && return 0   # tests: don't message the real lead
  rig send "orch-lead@$2" "rig-backup: this rig has been resumed on $3, which now owns it. Work done here from now on is not backed up and will not reach that copy. Stop, and tell the human." >/dev/null 2>&1 || true
  tmux display-message -d 10000 "rig $2 now runs on $3; stop it here (rig down $2)" 2>/dev/null || true
}

backup_all() {
  local d rc=0
  if [ $# -gt 0 ]; then
    for d in "$@"; do backup_rig "$RIG_ROOT/$d" || rc=1; done
  else
    for d in "$RIG_ROOT"/*/; do [ -f "$d.rig/rig.env" ] && { backup_rig "${d%/}" || rc=1; }; done
  fi
  return "$rc"
}

# ~~~ list / forget ~~~

candidate_urls() {
  local r b
  { for r in $KNOWN_REPOS; do echo "$ORG_URL/$r.git"; done
    for b in "$BASES_ROOT"/*/; do git -C "$b" remote get-url origin 2>/dev/null; done
  } | grep github.com | sed 's|\.git$||; s|$|.git|' | sort -u
}

list_backups() {
  local url
  for url in $(candidate_urls); do
    git ls-remote "$url" 'refs/rigs/*/state' 2>/dev/null | sed -E "s|.*refs/rigs/(.*)/state$|\1 $(basename "$url" .git)|"
  done | awk '{ r[$1] = r[$1] " " $2 } END { for (k in r) print k ":" r[k] }' | sort
}

forget() { # <rig>
  local url refs
  for url in $(candidate_urls); do
    refs=$(git ls-remote "$url" "refs/rigs/$1/*" 2>/dev/null | cut -f2 | sed 's/^/:/')
    [ -n "$refs" ] || continue
    # shellcheck disable=SC2086
    git push -q --no-verify "$url" $refs && say "rig-backup: removed $(echo "$refs" | wc -l | tr -d ' ') ref(s) from $(basename "$url" .git)"
  done
  rm -rf "$RIG_ROOT/$1/.rig/backup"
}

# ~~~ resume ~~~

resume() { # <rig> [--no-launch]
  local rig="$1" launch=true url home_url base dev rig_dir info old_dir old_home owner BRANCH
  [ "${2:-}" = --no-launch ] && launch=false
  rig_dir="$RIG_ROOT/$rig"
  [ ! -e "$rig_dir" ] || die "rig-backup: $rig_dir already exists here. If it's a stale copy, move it aside first."

  for url in $(candidate_urls); do
    git ls-remote --exit-code "$url" "refs/rigs/$rig/state" >/dev/null 2>&1 && { home_url="$url"; break; }
  done
  [ -n "${home_url:-}" ] || die "rig-backup: no backup of '$rig' on GitHub (rig-backup.sh list)"

  ensure_base() { # <repo> <url>: the base clone, made if missing, with the rig's refs fetched
    local b="$BASES_ROOT/$1" dv
    if [ ! -d "$b/.git" ]; then
      mkdir -p "$BASES_ROOT"
      dv=$(dev_base_for "$1" 2>/dev/null || true)
      say "rig-backup: cloning $2 → $b"
      git clone -q ${dv:+--reference-if-able "$dv" --dissociate} "$2" "$b" || die "rig-backup: clone of $2 failed"
      [ -n "$dv" ] && [ -f "$dv/.env" ] && cp "$dv/.env" "$b/.env"
    fi
    git -C "$b" fetch -q origin || warn "rig-backup: fetch of $1 failed; carrying on with what's here"
    git -C "$b" fetch -q origin "+refs/rigs/$rig/*:refs/rigs/$rig/*" || die "rig-backup: couldn't fetch $rig's refs from $1"
  }

  ensure_base "$(basename "$home_url" .git)" "$home_url"
  base="$BASES_ROOT/$(basename "$home_url" .git)"
  info=$(git -C "$base" show "refs/rigs/$rig/state:.rig-state/info")
  old_dir=$(sed -n 's/^RIG_DIR=//p' <<<"$info"); old_home=$(sed -n 's/^OWNER_HOME=//p' <<<"$info")
  owner=$(sed -n 's/^OWNER=//p' <<<"$info"); BRANCH=$(sed -n 's/^BRANCH=//p' <<<"$info")
  say "rig-backup: $rig was last backed up by $owner: $(git -C "$base" log -1 --format='%cr (%ci)' "refs/rigs/$rig/state")"

  # Files.
  mkdir -p "$rig_dir"
  git -C "$base" archive "refs/rigs/$rig/state" | tar -x -C "$rig_dir"
  if [ "$old_dir" != "$rig_dir" ] || [ "$old_home" != "$HOME" ]; then
    grep -rlI -e "$old_dir" -e "$old_home/" "$rig_dir/.rig" "$rig_dir/lead" 2>/dev/null |
      while IFS= read -r f; do LC_ALL=C sed -i '' -e "s|$old_dir|$rig_dir|g" -e "s|$old_home/|$HOME/|g" "$f"; done
  fi

  # Branches, then worktrees.
  local seat dir repo rurl br sha wt ref b loc stamp new_wts=()
  stamp=$(date +%Y%m%d%H%M)
  while IFS=$'\t' read -r seat dir repo rurl br sha; do
    case "$seat" in '#'*|'') continue ;; esac
    b="$BASES_ROOT/$repo"
    [ -f "$b/.rig-resume-$rig" ] || {
      ensure_base "$repo" "$rurl"
      git -C "$b" for-each-ref --format='%(refname)' "refs/rigs/$rig/heads/" | while read -r ref; do
        local name="${ref#refs/rigs/$rig/heads/}" want have
        want=$(git -C "$b" rev-parse "$ref"); have=$(git -C "$b" rev-parse -q --verify "refs/heads/$name" || true)
        if [ -z "$have" ]; then git -C "$b" update-ref "refs/heads/$name" "$want"
        elif [ "$have" != "$want" ]; then
          if git -C "$b" worktree list --porcelain | grep -qx "branch refs/heads/$name"; then
            warn "rig-backup: $repo: $name is checked out elsewhere here and differs from the backup; left alone"
          elif git -C "$b" merge-base --is-ancestor "$have" "$want"; then git -C "$b" update-ref "refs/heads/$name" "$want"
          else
            git -C "$b" update-ref "refs/heads/$name-pre-resume-$stamp" "$have"
            git -C "$b" update-ref "refs/heads/$name" "$want"
            warn "rig-backup: $repo: local $name differed from the backup; kept it as $name-pre-resume-$stamp"
          fi
        fi
      done
      touch "$b/.rig-resume-$rig"
    }
    wt="$rig_dir/$seat/$dir"
    [ -e "$wt" ] && continue
    mkdir -p "$rig_dir/$seat"
    if [ "$br" != "-" ]; then
      git -C "$b" worktree add -q "$wt" "$br" 2>/dev/null ||
        { warn "rig-backup: $repo: $br is in use here; $seat/$dir gets it detached"; git -C "$b" worktree add -q --detach "$wt" "refs/rigs/$rig/heads/$br"; }
    else
      git -C "$b" worktree add -q --detach "$wt" "refs/rigs/$rig/detached/$seat/$dir"
    fi
    [ -f "$b/.env" ] && cp "$b/.env" "$wt/.env"
    if git -C "$b" rev-parse -q --verify "refs/rigs/$rig/wip/$seat/$dir" >/dev/null; then
      git -C "$wt" stash apply -q "refs/rigs/$rig/wip/$seat/$dir" 2>/dev/null ||
        warn "rig-backup: $seat/$dir: uncommitted changes didn't apply cleanly; they're at refs/rigs/$rig/wip/$seat/$dir"
    fi
    { [ -f "$wt/pnpm-lock.yaml" ] || [ -f "$wt/package-lock.json" ]; } && new_wts+=("$wt")
    say "rig-backup: $seat/$dir ← $repo ${br/#-/(detached)}"
  done < <(git -C "$base" show "refs/rigs/$rig/state:.rig-state/manifest")
  rm -f "$BASES_ROOT"/*/.rig-resume-"$rig"

  if ! $launch; then
    say "rig-backup: $rig rebuilt in $rig_dir (not launched, not claimed: --no-launch)"
    return 0
  fi

  # Dependencies, one worktree at a time in the background (the lead is told).
  mkdir -p "$rig_dir/.rig/logs"
  if [ ${#new_wts[@]} -gt 0 ]; then
    nohup bash -c '
      rig="$1"; shift; fails=""
      for wt in "$@"; do
        log="'"$rig_dir"'/.rig/logs/install-$(basename "$(dirname "$wt")")-$(basename "$wt").log"
        if [ -f "$wt/pnpm-lock.yaml" ]; then (cd "$wt" && CI=true pnpm install) >"$log" 2>&1 || fails="$fails $wt"
        else (cd "$wt" && npm install) >"$log" 2>&1 || fails="$fails $wt"; fi
      done
      rig send "orch-lead@$rig" "rig-backup: dependency installs after the resume are done.${fails:+ Failed:$fails (logs in .rig/logs).}" >/dev/null 2>&1' \
      _ "$rig" "${new_wts[@]}" >/dev/null 2>&1 &
  fi

  "$(dirname "$SELF")/start-rig.sh" "$BRANCH" --name "$rig" --no-install || die "rig-backup: start-rig failed; the rig's files and worktrees are in $rig_dir"

  # Open queue items, recreated here.
  local n
  n=$(git -C "$base" show "refs/rigs/$rig/state:.rig-state/queue.json" | python3 -c '
import json, subprocess, sys
rig, n = sys.argv[1], 0
for i in json.load(sys.stdin):
    dst = str(i.get("destinationSession") or "")
    if not dst.endswith("@" + rig): continue   # items for seats on other hosts stay there
    src = str(i.get("sourceSession") or "").split("@host-")[0] or "orch-lead@" + rig
    body = "Recreated on resume (was %s, %s).\n\n%s" % (i["qitemId"], i.get("state"), i.get("body") or "")
    r = subprocess.run(["rig", "queue", "create", "--source", src, "--destination", dst,
                        "--summary", (i.get("summary") or "(resumed)").replace("\n", " "),
                        "--body", body, "--no-nudge"], capture_output=True)
    n += r.returncode == 0
print(n)
' "$rig")

  backup_rig "$rig_dir" claim || warn "rig-backup: couldn't claim $rig on GitHub yet; the loop will retry"

  rig send "orch-lead@$rig" "rig-backup: this rig was resumed on $HOST from its GitHub backup (last from $owner). Every seat's worktree is back on its branch, with uncommitted tracked changes re-applied (untracked files were not kept). $n open queue item(s) were recreated, marked 'Recreated on resume'. Dependencies are installing in the background; you'll be told when they're done, so hold checks until then. Read PROGRESS.md and the queue, check each builder's state, and carry on." >/dev/null 2>&1 || true
  say "rig-backup: $rig resumed here and claimed; $n queue item(s) recreated"
}

case "${1:-}" in
  backup) shift; lockf -t 900 "$CACHE/lock" "$SELF" --backup "$@" ;;
  --backup) shift; backup_all "$@" ;;
  --start)
    pid=$(cat "$CACHE/pid" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && exit 0
    nohup "$SELF" --run >/dev/null 2>&1 &
    echo $! >"$CACHE/pid" ;;
  --run) while :; do lockf -t 900 "$CACHE/lock" "$SELF" --backup; sleep "$INTERVAL"; done ;;
  list) list_backups ;;
  resume) shift; [ -n "${1:-}" ] || die "usage: rig-backup.sh resume <rig> [--no-launch]"; resume "$@" ;;
  claim) shift; [ -n "${1:-}" ] || die "usage: rig-backup.sh claim <rig>"   # this machine owns it from now on
    backup_rig "$RIG_ROOT/$1" claim && say "rig-backup: $1 is owned by $HOST" ;;
  forget) shift; [ -n "${1:-}" ] || die "usage: rig-backup.sh forget <rig>"; forget "$1" ;;
  *) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
