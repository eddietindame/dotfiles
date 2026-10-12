#!/usr/bin/env bash
# start-rig.sh — worktrees + an OpenRig team for one feature branch, kept apart
# from the start-dev setup (see lib.sh for the layout).
#
#   start-rig.sh <branch> [-r REPO] [-n BUILDERS] [-b BASE] [--brief FILE]
#                [--name RIG] [--policy POLICY] [--no-install] [--plan]
#
#   -r, --repo     bertie-desktop (default), bertie-web, bertie-backend,
#                  bertie-packages — or bd, bw, bb, bp
#   -n, --builders number of builder seats/worktrees (default 2)
#   -b, --base     branch a new feature branch is cut from (default: whatever
#                  the base clone tracks, i.e. staging / main)
#   --brief FILE   seed the lead's living brief (.rig/BRIEF.md) with FILE
#                  (default: empty; you brief the lead in its session)
#   --name RIG     rig name, when the derived one is too long
#   --policy P     permission_policy for every seat, e.g. builtin:auto
#                  (default: OpenRig's team launch default)
#   --no-install   skip npm/pnpm install in new worktrees
#   --plan         set everything up, then `rig up --plan` instead of launching
#
# The team: lead (claude) on <branch>, builders b1..bN (claude) on <branch>-bN,
# reviewer r1 (codex) read-only in the lead's worktree. Sessions are
# orch-lead@<rig>, dev-b1@<rig>, review-r1@<rig>.
#
# Safe to re-run: existing worktrees, specs and briefs are left alone, and a rig
# that already exists is brought back with `rig up <rig> --existing`.
# Undo with cleanup-rig.sh <branch>.

set -euo pipefail
. "$(dirname "$0")/lib.sh"

branch="" repo=bertie-desktop builders=2 base="" brief_src="" rig_name=""
policy="" install=true plan=false

while [ $# -gt 0 ]; do
  case "$1" in
    -r|--repo)     repo=$(resolve_repo "$2") || die "start-rig: unknown repo '$2'"; shift 2 ;;
    -n|--builders) builders="$2"; shift 2 ;;
    -b|--base)     base="$2"; shift 2 ;;
    --brief)       brief_src="$2"; shift 2 ;;
    --name)        rig_name="$2"; shift 2 ;;
    --policy)      policy="$2"; shift 2 ;;
    --no-install)  install=false; shift ;;
    --plan)        plan=true; shift ;;
    -h|--help)     sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)            die "start-rig: unknown option $1" ;;
    *)             [ -z "$branch" ] || die "start-rig: one branch only"; branch="$1"; shift ;;
  esac
done

[ -n "$branch" ] || die "usage: start-rig <branch> [-r REPO] [-n BUILDERS] [-b BASE] [--brief FILE] [--name RIG] [--policy P] [--no-install] [--plan]"
case "$builders" in ''|*[!0-9]*|0) die "start-rig: -n wants a number of builders, 1 or more" ;; esac
[ -z "$brief_src" ] || [ -f "$brief_src" ] || die "start-rig: no such brief: $brief_src"
command -v rig >/dev/null || die "start-rig: rig not on PATH"
command -v jq >/dev/null || die "start-rig: jq not on PATH"

slug=$(branch_slug "$branch")
[ -n "$rig_name" ] || rig_name=$(rig_name_for "$repo" "$branch")
case "$rig_name" in *[!a-z0-9-]*|-*|'') die "start-rig: rig name '$rig_name' must be [a-z0-9-]" ;; esac

spec_dir="$SPECS_ROOT/$rig_name"
repo_dir="$RIG_ROOT/$repo"
lead_wt="$repo_dir/$slug"

# ~~~ the rig name must belong to this repo + branch, or be new ~~~
if [ -f "$spec_dir/rig.env" ]; then
  owner_repo=$(rig_env_get "$spec_dir/rig.env" REPO)
  owner_branch=$(rig_env_get "$spec_dir/rig.env" BRANCH)
  if [ "$owner_repo" != "$repo" ] || [ "$owner_branch" != "$branch" ]; then
    die "start-rig: rig '$rig_name' already belongs to $owner_branch in $owner_repo. Pick another with --name."
  fi
  prev_builders=$(rig_env_get "$spec_dir/rig.env" BUILDERS)
  if [ "$prev_builders" != "$builders" ]; then
    warn "start-rig: $rig_name was set up with $prev_builders builder(s); keeping that (cleanup-rig and start again to change it)"
    builders="$prev_builders"
  fi
else
  # Not ours, but known to the daemon: someone made it some other way.
  if rig ps --json 2>/dev/null | jq -e --arg n "$rig_name" 'any(.[]; .name == $n)' >/dev/null; then
    die "start-rig: the daemon already has a rig called '$rig_name' that start-rig did not create. Pick another with --name."
  fi
fi

# ~~~ base clone: its own, cloned from the same remote as the dev base ~~~
mkdir -p "$repo_dir"
if ! base_clone=$(find_base "$repo_dir"); then
  dev_base=$(find_base "$DEV_ROOT/$repo") || die "start-rig: no dev base for $repo in $DEV_ROOT to copy the remote from"
  remote=$(git -C "$dev_base" remote get-url origin)
  base_clone="$repo_dir/$(repo_prefix "$repo")-base"
  say "start-rig: cloning $remote → $base_clone"
  git clone --quiet "$remote" "$base_clone"
  # ensure-worktree copies .env from the base into each worktree, so the base
  # needs one. The dev base is where yours lives.
  [ -f "$dev_base/.env" ] && cp "$dev_base/.env" "$base_clone/.env"
fi
# The lead's progress notes live in .rig/ in its worktree; info/exclude is
# shared by every worktree of the clone.
exclude="$(git -C "$base_clone" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
grep -qx '.rig/' "$exclude" 2>/dev/null || { mkdir -p "$(dirname "$exclude")"; echo '.rig/' >>"$exclude"; }

# ~~~ worktrees ~~~
new_wts=()
[ -d "$lead_wt" ] || new_wts+=("$lead_wt")
# The lead's branch goes through ensure-worktree like start-dev's: resumes an
# existing local/remote branch, otherwise cuts it from the fetched remote base.
"$HOME/.config/tmuxinator/scripts/ensure-worktree.sh" "$base_clone" "$lead_wt" "$branch" ${base:+"$base"}

i=1
while [ "$i" -le "$builders" ]; do
  wt="$repo_dir/$slug-b$i"
  b="$branch-b$i"
  if [ ! -d "$wt" ]; then
    new_wts+=("$wt")
    # Not ensure-worktree: it cuts new branches only from origin/<base>, and the
    # feature branch is local until the human pushes it.
    if git -C "$base_clone" show-ref --verify --quiet "refs/heads/$b"; then
      git -C "$base_clone" worktree add --quiet "$wt" "$b"
    else
      git -C "$base_clone" worktree add --quiet -b "$b" "$wt" "$branch"
    fi
    [ -f "$base_clone/.env" ] && cp "$base_clone/.env" "$wt/.env"
    say "start-rig: $b → $wt"
  fi
  i=$((i + 1))
done

# ~~~ dependencies, in parallel: node_modules is the slow part ~~~
if $install && [ ${#new_wts[@]} -gt 0 ]; then
  mkdir -p "$spec_dir/logs"
  pids=() logs=()
  for wt in "${new_wts[@]}"; do
    [ -d "$wt/node_modules" ] && continue
    if [ -f "$wt/pnpm-lock.yaml" ]; then cmd="pnpm install"
    elif [ -f "$wt/package-lock.json" ]; then cmd="npm install"
    else continue; fi
    log="$spec_dir/logs/install-$(basename "$wt").log"
    say "start-rig: $cmd in $(basename "$wt") (log: $log)"
    (cd "$wt" && $cmd) >"$log" 2>&1 &
    pids+=($!) logs+=("$log")
  done
  failed=false
  [ ${#pids[@]} -gt 0 ] && for i in "${!pids[@]}"; do
    wait "${pids[$i]}" || { warn "start-rig: install failed, see ${logs[$i]}"; failed=true; }
  done
  $failed && die "start-rig: fix the install, then re-run (worktrees are kept)"
fi

# ~~~ spec, culture, guidance, brief ~~~
case "$repo" in
  bertie-desktop)  checks="npm run type-check && npm run lint && npm run test:unit" ;;
  bertie-web)      checks="pnpm typecheck && pnpm lint && pnpm test:run" ;;
  bertie-backend)  checks="pnpm typecheck && pnpm lint && pnpm test:run" ;;
  bertie-packages) checks="pnpm lint && pnpm test" ;;
  *)               checks="(see the repository's package.json)" ;;
esac

# Built-in agent specs ship inside the CLI package. The volta shim on PATH
# resolves to volta itself, so ask volta for the real binary; it links to
# <cli>/dist/bin-wrapper.js. Re-resolved on every new spec, so an OpenRig upgrade
# only affects rigs created before it.
rig_bin=$(readlink -f "$(volta which rig 2>/dev/null || command -v rig)")
agents="$(dirname "$(dirname "$rig_bin")")/daemon/specs/agents"
[ -d "$agents" ] || die "start-rig: can't find OpenRig's built-in agents at $agents"

sed_esc() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; } # & | \ are special in a sed replacement
render() { # <template> <dest>
  sed -e "s|@@RIG@@|$(sed_esc "$rig_name")|g" \
      -e "s|@@BRANCH@@|$(sed_esc "$branch")|g" \
      -e "s|@@REPO@@|$(sed_esc "$repo")|g" \
      -e "s|@@CHECKS@@|$(sed_esc "$checks")|g" \
      -e "s|@@BUILDERS@@|$(sed_esc "$builder_list")|g" \
      "$OPENRIG_DIR/templates/$1" >"$2"
}

if [ ! -f "$spec_dir/rig.yaml" ]; then
  mkdir -p "$spec_dir/guidance"

  seat_table="| lead | orch-lead@$rig_name | $lead_wt | $branch |"
  builder_list=""
  i=1
  while [ "$i" -le "$builders" ]; do
    seat_table="$seat_table
| b$i | dev-b$i@$rig_name | $repo_dir/$slug-b$i | $branch-b$i |"
    builder_list="$builder_list${builder_list:+, }dev-b$i@$rig_name"
    i=$((i + 1))
  done
  seat_table="$seat_table
| r1 (reviewer) | review-r1@$rig_name | $lead_wt (read-only) | — |"

  render CULTURE.md "$spec_dir/CULTURE.md.tmp"
  # Multi-line, so not through sed (and BSD awk refuses newlines in -v).
  while IFS= read -r line; do
    if [ "$line" = "@@SEAT_TABLE@@" ]; then printf '%s\n' "$seat_table"; else printf '%s\n' "$line"; fi
  done <"$spec_dir/CULTURE.md.tmp" >"$spec_dir/CULTURE.md"
  rm "$spec_dir/CULTURE.md.tmp"
  for f in lead builder reviewer; do render "$f.md" "$spec_dir/guidance/$f.md"; done

  {
    echo 'version: "0.2"'
    echo "name: $rig_name"
    echo "summary: $branch in $repo. Lead owns the feature branch, builders work slices on their own branches, the reviewer gates every merge."
    echo "culture_file: CULTURE.md"
    [ -z "$policy" ] || echo "permission_policy: $policy"
    echo "startup:"
    echo "  files:"
    echo "    - { path: BRIEF.md, delivery_hint: send_text, required: true }"
    echo "pods:"
    echo "  - id: orch"
    echo "    label: Orchestration"
    echo "    members:"
    echo "      - id: lead"
    echo "        agent_ref: \"path:$agents/orchestration/orchestrator\""
    echo "        runtime: claude-code"
    echo "        profile: default"
    echo "        cwd: \"$lead_wt\""
    echo "        startup:"
    echo "          files:"
    echo "            - { path: guidance/lead.md, delivery_hint: send_text, required: true }"
    echo "  - id: dev"
    echo "    label: Development"
    echo "    members:"
    i=1
    while [ "$i" -le "$builders" ]; do
      echo "      - id: b$i"
      echo "        agent_ref: \"path:$agents/development/implementer\""
      echo "        runtime: claude-code"
      echo "        profile: default"
      echo "        cwd: \"$repo_dir/$slug-b$i\""
      echo "        startup:"
      echo "          files:"
      echo "            - { path: guidance/builder.md, delivery_hint: send_text, required: true }"
      i=$((i + 1))
    done
    echo "  - id: review"
    echo "    label: Review"
    echo "    members:"
    echo "      - id: r1"
    echo "        agent_ref: \"path:$agents/review/independent-reviewer\""
    echo "        runtime: codex"
    echo "        profile: default"
    echo "        cwd: \"$lead_wt\""
    echo "        startup:"
    echo "          files:"
    echo "            - { path: guidance/reviewer.md, delivery_hint: send_text, required: true }"
    echo "edges:"
    i=1
    while [ "$i" -le "$builders" ]; do
      echo "  - { kind: delegates_to, from: orch.lead, to: dev.b$i }"
      echo "  - { kind: can_observe, from: review.r1, to: dev.b$i }"
      i=$((i + 1))
    done
    echo "  - { kind: delegates_to, from: orch.lead, to: review.r1 }"
  } >"$spec_dir/rig.yaml"

  {
    echo "RIG=$rig_name"
    echo "REPO=$repo"
    echo "BRANCH=$branch"
    echo "BUILDERS=$builders"
    echo "BASE_CLONE=$base_clone"
    echo "LEAD_WT=$lead_wt"
  } >"$spec_dir/rig.env"
  say "start-rig: spec written to $spec_dir"
fi

rig spec validate "$spec_dir/rig.yaml" >/dev/null || die "start-rig: generated spec is invalid: rig spec validate $spec_dir/rig.yaml"

# ~~~ the brief: a living file in the lead's worktree ~~~
# The lead keeps .rig/BRIEF.md current as the human and it agree things, so the
# knowledge outlives any one conversation. The startup file every seat gets is
# only a pointer to it: a seat primed fresh after a crash reads today's brief,
# not the launch-day one. It lives in the lead's worktree because that is where
# the lead can write without a permission prompt.
live_brief="$lead_wt/.rig/BRIEF.md"
mkdir -p "$lead_wt/.rig"
if [ ! -f "$live_brief" ]; then
  if [ -n "$brief_src" ]; then
    cp "$brief_src" "$live_brief"
  else
    printf '# Brief: %s (%s)\n\nNothing agreed yet. The lead fills this in with the human.\n' \
      "$branch" "$repo" >"$live_brief"
  fi
elif [ -n "$brief_src" ]; then
  warn "start-rig: $live_brief already exists; --brief ignored (the lead may have updated it)"
fi
cat >"$spec_dir/BRIEF.md" <<BRIEF
# Brief

The current brief for this rig is $live_brief.
The lead keeps it up to date with what the human has agreed; it is the
source of truth for scope and decisions, ahead of anything earlier in your
conversation.

- Lead and reviewer: read it now, and again after any restart.
- Builders: your queue item carries what your slice needs. If it seems to
  contradict the brief, ask the lead.
BRIEF

# ~~~ launch ~~~
if $plan; then
  rig up "$spec_dir/rig.yaml" --plan
  exit 0
fi

state=$(rig ps --json 2>/dev/null | jq -r --arg n "$rig_name" 'map(select(.name == $n))[0].status // empty' || true)
case "$state" in
  "")      rig up "$spec_dir/rig.yaml" ;;
  stopped) rig up "$rig_name" --existing ;;
  *)       say "start-rig: $rig_name is already $state" ;;
esac

say ""
say "start-rig: $rig_name"
say "  lead     rig send orch-lead@$rig_name \"...\"   (or prefix+A)"
say "  watch    rig ps --nodes --rig $rig_name   ·   rig tui"
say "  brief    $lead_wt/.rig/BRIEF.md"
say "  progress $lead_wt/.rig/PROGRESS.md"
say "  undo     cleanup-rig $branch${repo:+ -r $repo}"
