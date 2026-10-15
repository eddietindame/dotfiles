#!/usr/bin/env bash
# start-rig.sh — an OpenRig team for one feature branch, with a worktree of
# every repo it needs per seat, kept apart from the start-dev setup (see lib.sh
# for the layout).
#
#   start-rig.sh <branch> [-r REPOS] [-n BUILDERS] [-b BASE] [--brief FILE] [-e]
#                [--name RIG] [--policy POLICY] [--no-install] [--plan]
#                [-s SEATS]
#
#   -r, --repo     comma-separated repos, by name or prefix: bd, bp, bw, bb, ba, bt
#                  (default bd,bp). Every seat gets a worktree of each.
#   -n, --builders number of builder seats (default 2)
#   -b, --base     branch a new feature branch is cut from, in every repo
#                  (default: whatever each base clone tracks, i.e. staging for
#                  most repos, main for packages)
#   --brief FILE   seed the lead's living brief (lead/BRIEF.md) with FILE
#                  (default: empty; you brief the lead in its session)
#   -e, --edit-brief  open the brief in nvim and launch once you quit it.
#                  Installs run in the background meanwhile. Works with --brief
#                  (edit the seeded copy) and on an existing rig.
#   --name RIG     rig name, when the one derived from the branch is too long
#   --policy P     permission_policy for every seat, e.g. builtin:auto
#                  (default: OpenRig's team launch default)
#   --no-install   skip npm/pnpm install in new worktrees
#   --plan         set everything up, then `rig up --plan` instead of launching
#   -s, --seat     existing rig only: also give these builders a worktree of the
#                  -r repos, e.g. -s b1,b2 or -s all (default: the lead only)
#   --from-lead    used by add-repo.sh: print the news for the lead instead of
#                  sending it, and leave the rig's running state alone
#
# The team: lead (claude) on <branch>, builders b1..bN (claude) on <branch>-bN,
# the same branch names in every repo, and reviewer r1 (codex) read-only in the
# lead's folder. Sessions are orch-lead@<rig>, dev-b1@<rig>, review-r1@<rig>.
# With desktop and packages both in the rig, each seat's desktop is linked to
# that seat's packages worktree (npm run link:ui), so package edits show up
# without a publish.
#
# Safe to re-run: existing worktrees, specs and briefs are left alone, and a rig
# that already exists is brought back with `rig up <rig> --existing`.
#
# The repos a rig starts with go to every seat. Re-running with -r on an
# existing rig adds repos to the lead's folder only, and the lead decides which
# builders need them (-s); each addition re-renders the culture and guidance and
# tells the lead. Repos are never removed this way; that is cleanup-rig and
# start again.
#   start-rig feat/BER-123-thing -r bw          lead gets bertie-web
#   start-rig feat/BER-123-thing -r bw -s b1    and so does b1
# Undo with cleanup-rig.sh <branch>.

set -euo pipefail
# Braced so bash reads the whole file before running any of it: a run takes
# minutes, and bash otherwise reads a script as it goes, so editing it mid-run
# breaks the run.
{
. "$(dirname "$0")/lib.sh"

branch="" repo_args=() added=() builders=2 builders_given=false base="" brief_src="" rig_name=""
policy="" install=true plan=false from_lead=false edit_brief=false seat_args=""

while [ $# -gt 0 ]; do
  case "$1" in
    -r|--repo)     need_value "$@"; repo_args+=("$2"); shift 2 ;;
    -n|--builders) need_value "$@"; builders="$2"; builders_given=true; shift 2 ;;
    -b|--base)     need_value "$@"; base="$2"; shift 2 ;;
    --brief)       need_value "$@"; brief_src="$2"; shift 2 ;;
    -e|--edit-brief) edit_brief=true; shift ;;
    --name)        need_value "$@"; rig_name="$2"; shift 2 ;;
    --policy)      need_value "$@"; policy="$2"; shift 2 ;;
    --no-install)  install=false; shift ;;
    --plan)        plan=true; shift ;;
    -s|--seat)     need_value "$@"; seat_args="$seat_args${seat_args:+,}$2"; shift 2 ;;
    --from-lead)   from_lead=true; shift ;;
    -h|--help)     sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)            die "start-rig: unknown option $1" ;;
    *)             [ -z "$branch" ] || die "start-rig: one branch only"; branch="$1"; shift ;;
  esac
done

[ -n "$branch" ] || die "usage: start-rig <branch> [-r REPOS] [-n BUILDERS] [-b BASE] [--brief FILE] [--name RIG] [--policy P] [--no-install] [--plan]"
case "$builders" in ''|*[!0-9]*|0) die "start-rig: -n wants a number of builders, 1 or more" ;; esac
[ -z "$brief_src" ] || [ -f "$brief_src" ] || die "start-rig: no such brief: $brief_src"
command -v rig >/dev/null || die "start-rig: rig not on PATH"
command -v jq >/dev/null || die "start-rig: jq not on PATH"

# -r bd,bp and -r bd -r bp both work; duplicates dropped, order kept.
repos_given=true
[ ${#repo_args[@]} -gt 0 ] || { repo_args=(bd,bp); repos_given=false; }
repos=()
for arg in "${repo_args[@]}"; do
  IFS=',' read -r -a parts <<<"$arg"
  for p in "${parts[@]}"; do
    p="${p//[[:space:]]/}"
    [ -n "$p" ] || continue
    r=$(resolve_repo "$p") || die "start-rig: unknown repo '$p'"
    case " ${repos[*]-} " in *" $r "*) ;; *) repos+=("$r") ;; esac
  done
done
[ ${#repos[@]} -gt 0 ] || die "start-rig: -r named no repos"

[ -n "$rig_name" ] || rig_name=$(rig_name_for "$branch")
case "$rig_name" in *[!a-z0-9-]*|-*|'') die "start-rig: rig name '$rig_name' must be [a-z0-9-]" ;; esac
# Names the rig root already uses for other things.
case "$rig_name" in base|bertie-*) die "start-rig: '$rig_name' is reserved under $RIG_ROOT; pick another with --name" ;; esac

rig_dir="$RIG_ROOT/$rig_name"
spec_dir="$rig_dir/.rig"
lead_dir="$rig_dir/lead"

# ~~~ the rig name must belong to this branch, or be new ~~~
if [ -f "$spec_dir/rig.env" ]; then
  owner_branch=$(rig_env_get "$spec_dir/rig.env" BRANCH)
  [ "$owner_branch" = "$branch" ] ||
    die "start-rig: rig '$rig_name' already belongs to $owner_branch. Pick another with --name."
  prev_builders=$(rig_env_get "$spec_dir/rig.env" BUILDERS)
  if $builders_given && [ "$prev_builders" != "$builders" ]; then
    warn "start-rig: $rig_name was set up with $prev_builders builder(s); keeping that (cleanup-rig and start again to change it)"
  fi
  builders="$prev_builders"
  # -r on an existing rig adds repos to it; it never drops one.
  read -r -a prev_repos <<<"$(rig_env_get "$spec_dir/rig.env" REPOS)"
  # Repos every seat gets: the ones the rig started with. Rigs from before
  # lead-only additions gave every seat every repo.
  shared=$(rig_env_get "$spec_dir/rig.env" SHARED_REPOS)
  read -r -a shared_repos <<<"${shared:-${prev_repos[*]}}"
  wanted=("${repos[@]}")
  repos=("${prev_repos[@]}")
  if $repos_given; then
    for r in "${wanted[@]}"; do
      case " ${prev_repos[*]} " in *" $r "*) ;; *) repos+=("$r") added+=("$r") ;; esac
    done
  else
    wanted=()
  fi
else
  [ -z "$seat_args" ] || die "start-rig: -s adds repos to builders of an existing rig; a new rig gives every seat every -r repo"
  shared_repos=("${repos[@]}")
  wanted=()
  [ ! -e "$rig_dir" ] || die "start-rig: $rig_dir exists but is not a rig from start-rig. Pick another with --name."
  # A rig from before per-rig folders, on the same branch, would be duplicated
  # rather than extended.
  while IFS= read -r f; do
    [ "$(rig_env_get "$f" LAYOUT)" != 2 ] && [ "$(rig_env_get "$f" BRANCH)" = "$branch" ] &&
      die "start-rig: $branch already has an old-layout rig, $(rig_env_get "$f" RIG), which can't be extended. Finish it and cleanup-rig it first."
  done < <(all_rig_envs)
  # Not ours, but known to the daemon: someone made it some other way.
  if rig ps --json 2>/dev/null | jq -e --arg n "$rig_name" 'any(.[]; .name == $n)' >/dev/null; then
    die "start-rig: the daemon already has a rig called '$rig_name' that start-rig did not create. Pick another with --name."
  fi
fi

# Written first, so a run that dies halfway can be re-run or cleaned up.
if [ ! -f "$spec_dir/rig.env" ]; then
  mkdir -p "$spec_dir"
  {
    echo "LAYOUT=2"
    echo "RIG=$rig_name"
    echo "BRANCH='$branch'"
    echo "REPOS='${repos[*]}'"
    echo "SHARED_REPOS='${repos[*]}'"
    echo "BUILDERS=$builders"
    echo "RIG_DIR='$rig_dir'"
  } >"$spec_dir/rig.env"
fi

if [ ${#added[@]} -gt 0 ]; then
  say "start-rig: adding ${added[*]} to $rig_name (lead only; -s for builders)"
  sed -i '' "s|^REPOS=.*|REPOS='${repos[*]}'|" "$spec_dir/rig.env"
fi

has_repo() { case " ${repos[*]} " in *" $1 "*) return 0 ;; esac; return 1; }

seats=(lead)
i=1
while [ "$i" -le "$builders" ]; do seats+=("b$i"); i=$((i + 1)); done
# -s: which builders get the -r repos on top of the shared ones.
target_seats=()
if [ -n "$seat_args" ]; then
  [ ${#wanted[@]} -gt 0 ] || die "start-rig: -s needs -r, the repos to give those builders"
  IFS=',' read -r -a parts <<<"$seat_args"
  for p in "${parts[@]}"; do
    p="${p//[[:space:]]/}"
    case "$p" in
      '') continue ;;
      all) target_seats=("${seats[@]:1}"); break ;;
    esac
    case " ${seats[*]:1} " in *" $p "*) ;; *) die "start-rig: no builder '$p' in $rig_name (it has ${seats[*]:1})" ;; esac
    case " ${target_seats[*]-} " in *" $p "*) ;; *) target_seats+=("$p") ;; esac
  done
fi
is_shared() { case " ${shared_repos[*]} " in *" $1 "*) return 0 ;; esac; return 1; }
is_wanted() { case " ${wanted[*]-} " in *" $1 "*) return 0 ;; esac; return 1; }
is_target() { case " ${target_seats[*]-} " in *" $1 "*) return 0 ;; esac; return 1; }
seat_branch() { [ "$1" = lead ] && printf '%s' "$branch" || printf '%s-%s' "$branch" "$1"; }

# ~~~ base clones: their own, cloned from the same remote as the dev base ~~~
mkdir -p "$BASES_ROOT" "$spec_dir/logs"
for repo in "${repos[@]}"; do
  base_clone="$BASES_ROOT/$repo"
  [ -d "$base_clone/.git" ] && continue
  dev_base=$(dev_base_for "$repo") || die "start-rig: no dev base for $repo in $DEV_ROOT to copy the remote from"
  remote=$(git -C "$dev_base" remote get-url origin)
  say "start-rig: cloning $remote → $base_clone"
  git clone --quiet "$remote" "$base_clone"
  # ensure-worktree copies .env from the base into each worktree, so the base
  # needs one. The dev base is where yours lives.
  [ -f "$dev_base/.env" ] && cp "$dev_base/.env" "$base_clone/.env"
done

# ~~~ worktrees: <seat>/<repo> ~~~
new_wts=() seat_added=()   # seat_added: builder worktrees made by this run
for repo in "${repos[@]}"; do
  base_clone="$BASES_ROOT/$repo"
  # The lead's branch goes through ensure-worktree like start-dev's: resumes an
  # existing local/remote branch, otherwise cuts it from the fetched remote
  # base, which is each base clone's own upstream unless -b says otherwise.
  [ -d "$lead_dir/$repo" ] || new_wts+=("$lead_dir/$repo")
  mkdir -p "$lead_dir"
  "$HOME/.config/tmuxinator/scripts/ensure-worktree.sh" "$base_clone" "$lead_dir/$repo" "$branch" ${base:+"$base"}

  for seat in "${seats[@]:1}"; do
    wt="$rig_dir/$seat/$repo"
    b=$(seat_branch "$seat")
    [ -d "$wt" ] && continue
    is_shared "$repo" || { is_target "$seat" && is_wanted "$repo"; } || continue
    new_wts+=("$wt") seat_added+=("$seat/$repo")
    mkdir -p "$rig_dir/$seat"
    # Not ensure-worktree: it cuts new branches only from origin/<base>, and the
    # feature branch is local until the human pushes it.
    if git -C "$base_clone" show-ref --verify --quiet "refs/heads/$b"; then
      git -C "$base_clone" worktree add --quiet "$wt" "$b"
    else
      git -C "$base_clone" worktree add --quiet -b "$b" "$wt" "$branch"
    fi
    [ -f "$base_clone/.env" ] && cp "$base_clone/.env" "$wt/.env"
    say "start-rig: $b → $wt"
  done
done

# ~~~ the brief: seeded now, so -e can be written while installs run ~~~
live_brief="$lead_dir/BRIEF.md"
if [ ! -f "$live_brief" ]; then
  if [ -n "$brief_src" ]; then
    cp "$brief_src" "$live_brief"
  elif $edit_brief; then
    printf '# Brief: %s\n\n## Goal\n\n## Scope\n\n## Out of scope\n\n## Decisions\n\n## Open questions\n' "$branch" >"$live_brief"
  else
    printf '# Brief: %s\n\nNothing agreed yet. The lead fills this in with the human.\n' "$branch" >"$live_brief"
  fi
elif [ -n "$brief_src" ]; then
  warn "start-rig: $live_brief already exists; --brief ignored (the lead may have updated it)"
fi

# ~~~ dependencies, in parallel: node_modules is the slow part ~~~
pids=() logs=()
if $install && [ ${#new_wts[@]} -gt 0 ]; then
  for wt in "${new_wts[@]}"; do
    [ -d "$wt/node_modules" ] && continue
    if [ -f "$wt/pnpm-lock.yaml" ]; then cmd="pnpm install"
    elif [ -f "$wt/package-lock.json" ]; then cmd="npm install"
    else continue; fi
    seat=$(basename "$(dirname "$wt")")
    log="$spec_dir/logs/install-$seat-$(basename "$wt").log"
    say "start-rig: $cmd in $seat/$(basename "$wt") (log: $log)"
    (cd "$wt" && $cmd) >"$log" 2>&1 &
    pids+=($!) logs+=("$log")
  done
fi

if $edit_brief && ! $from_lead; then
  if [ -t 0 ] && [ -t 1 ]; then
    [ ${#pids[@]} -eq 0 ] || say "start-rig: installs carry on in the background; the rig launches when you quit nvim"
    # Scripts don't see the zsh alias, which is what picks the kickstart config.
    NVIM_APPNAME="${NVIM_APPNAME:-nvim/kickstart-modular}" ${EDITOR:-nvim} "$live_brief" || warn "start-rig: nvim exited with an error; carrying on with $live_brief as it is"
  else
    warn "start-rig: -e needs a terminal; not opening the brief"
  fi
fi

failed=false
[ ${#pids[@]} -gt 0 ] && for i in "${!pids[@]}"; do
  wait "${pids[$i]}" || { warn "start-rig: install failed, see ${logs[$i]}"; failed=true; }
done
$failed && die "start-rig: fix the install, then re-run (worktrees are kept)"

# ~~~ each seat's desktop uses that seat's packages ~~~
# Desktop pins @bertie-technology/ui from the registry, so without this a seat's
# package edits are invisible to its desktop. Linked seats stay linked across
# re-runs; an `npm install` in desktop undoes it, and the culture file says so.
linked=false
if has_repo bertie-desktop && has_repo bertie-packages; then
  for seat in "${seats[@]}"; do
    desk="$rig_dir/$seat/bertie-desktop"
    pkgs="$rig_dir/$seat/bertie-packages"
    [ -d "$desk" ] && [ -d "$pkgs" ] || continue   # a seat given only one of them
    grep -q '"link:ui"' "$desk/package.json" 2>/dev/null || { warn "start-rig: $seat/bertie-desktop has no link:ui script; not linked"; continue; }
    [ -d "$desk/node_modules" ] || { warn "start-rig: $seat/bertie-desktop has no node_modules yet; not linked (re-run without --no-install)"; continue; }
    [ "$(readlink "$desk/node_modules/@bertie-technology/ui" 2>/dev/null)" = "$pkgs/packages/internal/ui" ] && { linked=true; continue; }
    if (cd "$desk" && npm run --silent link:ui -- "$pkgs") >>"$spec_dir/logs/link-ui.log" 2>&1; then
      say "start-rig: $seat/bertie-desktop uses $seat/bertie-packages for @bertie-technology/ui"
      linked=true
    else
      warn "start-rig: link:ui failed for $seat, see $spec_dir/logs/link-ui.log"
    fi
  done
fi

# ~~~ spec, culture, guidance, brief ~~~
checks_for() {
  case "$1" in
    bertie-desktop)  echo '`npm run type-check && npm run lint && npm run test:unit`' ;;
    bertie-web)      echo '`pnpm typecheck && pnpm lint && pnpm test:run`' ;;
    bertie-backend)  echo '`pnpm typecheck && pnpm lint && pnpm test:run`' ;;
    bertie-packages) echo '`pnpm lint && pnpm test`' ;;
    bertie-terraform) echo '`terraform fmt -check -recursive`, then in each root module you changed `terraform init -backend=false && terraform validate`' ;;
    *)               echo "(see the repository's package.json)" ;;
  esac
}

# Built-in agent specs ship inside the CLI package. The volta shim on PATH
# resolves to volta itself, so ask volta for the real binary; it links to
# <cli>/dist/bin-wrapper.js. Re-resolved on every new spec, so an OpenRig upgrade
# only affects rigs created before it.
rig_bin=$(readlink -f "$(volta which rig 2>/dev/null || command -v rig)")
agents="$(dirname "$(dirname "$rig_bin")")/daemon/specs/agents"
[ -d "$agents" ] || die "start-rig: can't find OpenRig's built-in agents at $agents"

# Culture and guidance are rendered again when repos are added; rig.yaml is
# only ever written once, so a running rig's spec never changes under it.
changed=false
[ ${#added[@]} -gt 0 ] || [ ${#seat_added[@]} -gt 0 ] && [ -f "$spec_dir/rig.yaml" ] && changed=true
if [ ! -f "$spec_dir/rig.yaml" ] || $changed; then
  mkdir -p "$spec_dir/guidance"

  repo_list=""
  for repo in "${repos[@]}"; do repo_list="$repo_list${repo_list:+, }$repo"; done
  builder_list=""
  for seat in "${seats[@]:1}"; do builder_list="$builder_list${builder_list:+, }dev-$seat@$rig_name"; done

  seat_repos() { # <seat>: the repos in its folder, from disk
    local r out=""
    for r in "${repos[@]}"; do [ -d "$rig_dir/$1/$r" ] && out="$out${out:+, }$r"; done
    printf '%s' "${out:-none}"
  }
  seat_table=""
  for seat in "${seats[@]}"; do
    [ "$seat" = lead ] && addr="orch-lead@$rig_name" || addr="dev-$seat@$rig_name"
    seat_table="$seat_table| $seat | $addr | $rig_dir/$seat | \`$(seat_branch "$seat")\` | $(seat_repos "$seat") |
"
  done
  seat_table="$seat_table| r1 (reviewer) | review-r1@$rig_name | $lead_dir (read-only) | — | $(seat_repos lead) |"

  checks=""
  for repo in "${repos[@]}"; do
    checks="$checks- \`$repo\`: $(checks_for "$repo")
"
  done
  checks="${checks%
}"

  link_note=""
  $linked && link_note="If your folder has both, your \`bertie-desktop\` is linked to your own \`bertie-packages\`
(\`node_modules/@bertie-technology/ui\` points at its \`packages/internal/ui\`), so
a package edit shows up in desktop straight away; restart desktop's dev server
to pick it up. An \`npm install\` in desktop undoes the link: re-link with
\`npm run link:ui -- ../bertie-packages\` from desktop."

  tf_note=""
  has_repo bertie-terraform && tf_note="- \`bertie-terraform\` is real infrastructure. Never run \`terraform apply\`,
  \`destroy\`, \`import\`, \`state\` or \`plan\` against a real backend, and never
  write credentials or \`*.tfvars\` values into the repo. Checks are \`fmt\` and
  \`validate\` with \`-backend=false\` only; applying is the human's job."

  sed_esc() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; } # & | \ are special in a sed replacement
  render() { # <template> <dest>
    local line
    sed -e "s|@@RIG@@|$(sed_esc "$rig_name")|g" \
        -e "s|@@BRANCH@@|$(sed_esc "$branch")|g" \
        -e "s|@@REPOS@@|$(sed_esc "$repo_list")|g" \
        -e "s|@@BUILDERS@@|$(sed_esc "$builder_list")|g" \
        -e "s|@@LEAD_DIR@@|$(sed_esc "$lead_dir")|g" \
        -e "s|@@ADD_REPO@@|$(sed_esc "$OPENRIG_DIR/scripts/add-repo.sh")|g" \
        "$OPENRIG_DIR/templates/$1" |
    # Multi-line values replace a line of their own, not through sed (and BSD
    # awk refuses newlines in -v). An empty value drops the line.
    while IFS= read -r line; do
      case "$line" in
        @@SEAT_TABLE@@) printf '%s\n' "$seat_table" ;;
        @@CHECKS@@)     printf '%s\n' "$checks" ;;
        @@LINK_NOTE@@)  [ -z "$link_note" ] || printf '%s\n' "$link_note" ;;
        @@TERRAFORM_NOTE@@) [ -z "$tf_note" ] || printf '%s\n' "$tf_note" ;;
        *)              printf '%s\n' "$line" ;;
      esac
    done >"$2"
  }
  render CULTURE.md "$spec_dir/CULTURE.md"
  for f in lead builder reviewer; do render "$f.md" "$spec_dir/guidance/$f.md"; done

  {
    echo 'version: "0.2"'
    echo "name: $rig_name"
    echo "summary: $branch in $repo_list. Lead owns the feature branch, builders work slices on their own branches, the reviewer gates every merge."
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
    echo "        cwd: \"$lead_dir\""
    echo "        startup:"
    echo "          files:"
    echo "            - { path: guidance/lead.md, delivery_hint: send_text, required: true }"
    echo "  - id: dev"
    echo "    label: Development"
    echo "    members:"
    for seat in "${seats[@]:1}"; do
      echo "      - id: $seat"
      echo "        agent_ref: \"path:$agents/development/implementer\""
      echo "        runtime: claude-code"
      echo "        profile: default"
      echo "        cwd: \"$rig_dir/$seat\""
      echo "        startup:"
      echo "          files:"
      echo "            - { path: guidance/builder.md, delivery_hint: send_text, required: true }"
    done
    echo "  - id: review"
    echo "    label: Review"
    echo "    members:"
    echo "      - id: r1"
    echo "        agent_ref: \"path:$agents/review/independent-reviewer\""
    echo "        runtime: codex"
    echo "        profile: default"
    echo "        cwd: \"$lead_dir\""
    echo "        startup:"
    echo "          files:"
    echo "            - { path: guidance/reviewer.md, delivery_hint: send_text, required: true }"
    echo "edges:"
    for seat in "${seats[@]:1}"; do
      echo "  - { kind: delegates_to, from: orch.lead, to: dev.$seat }"
      echo "  - { kind: can_observe, from: review.r1, to: dev.$seat }"
    done
    echo "  - { kind: delegates_to, from: orch.lead, to: review.r1 }"
  } >"$spec_dir/rig.yaml.new"
  if [ -f "$spec_dir/rig.yaml" ]; then
    rm "$spec_dir/rig.yaml.new"
    say "start-rig: culture and guidance updated in $spec_dir"
  else
    mv "$spec_dir/rig.yaml.new" "$spec_dir/rig.yaml"
    say "start-rig: spec written to $spec_dir"
  fi
fi

rig spec validate "$spec_dir/rig.yaml" >/dev/null || die "start-rig: generated spec is invalid: rig spec validate $spec_dir/rig.yaml"

# ~~~ the brief: a living file in the lead's folder ~~~
# The lead keeps BRIEF.md current as the human and it agree things, so the
# knowledge outlives any one conversation. The startup file every seat gets is
# only a pointer to it: a seat primed fresh after a crash reads today's brief,
# not the launch-day one. It sits in the lead's cwd, outside every repo, so the
# lead writes it without a prompt and nothing needs git-ignoring.
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

# ~~~ added repos: the running agents loaded the old culture ~~~
news=""
if $changed; then
  if [ ${#added[@]} -gt 0 ]; then
    list=""
    for r in "${added[@]}"; do list="$list${list:+, }lead/$r"; done
    news="start-rig added ${added[*]} to your folder ($list, on $branch)."
    for r in "${added[@]}"; do news="$news Checks in $r: $(checks_for "$r" | tr -d '\`')."; done
  fi
  if [ ${#seat_added[@]} -gt 0 ]; then
    list=""
    for w in "${seat_added[@]}"; do list="$list${list:+, }$w on $branch-${w%%/*}"; done
    news="$news${news:+ }Builder worktrees added: $list. Tell those builders before you assign them work there."
  fi
  missing=""
  for r in "${wanted[@]-}"; do
    [ -n "$r" ] && ! is_shared "$r" || continue
    for seat in "${seats[@]:1}"; do [ -d "$rig_dir/$seat/$r" ] || missing="$missing${missing:+, }$seat/$r"; done
  done
  [ -z "$missing" ] || news="$news Builders without these yet: $missing. Before assigning a slice that needs one, run \`$OPENRIG_DIR/scripts/add-repo.sh <repo> --seat bN\` from your folder (it installs dependencies: minutes, so in the background)."
  $linked && [ ${#seat_added[@]} -gt 0 ] && news="$news Seats with both bertie-desktop and bertie-packages have desktop linked to their own packages for @bertie-technology/ui; restart desktop dev servers to pick it up."
  news="$news The culture file ($spec_dir/CULTURE.md) is updated; its seat table shows who has which repo. Update BRIEF.md if this changes the plan."
fi
tell_lead() {
  [ -n "$news" ] || return 0
  if $from_lead; then say ""; say "$news"; return 0; fi
  if rig send "orch-lead@$rig_name" "$news" >/dev/null 2>&1; then
    say "start-rig: told orch-lead@$rig_name about the new worktrees"
  else
    warn "start-rig: couldn't reach the lead; tell it yourself:"
    warn "  rig send orch-lead@$rig_name '$news'"
  fi
}

# ~~~ launch ~~~
# The lead adding a repo is already running; there is nothing to launch.
if $from_lead; then
  [ -n "$news" ] && tell_lead || say "add-repo: nothing to add; those seats already have ${wanted[*]-those repos}"
  exit 0
fi
if $plan; then
  rig up "$spec_dir/rig.yaml" --plan
  [ -z "$news" ] || { say ""; say "start-rig: once it is running, tell the lead:"; say "  rig send orch-lead@$rig_name '$news'"; }
  exit 0
fi

state=$(rig ps --json 2>/dev/null | jq -r --arg n "$rig_name" 'map(select(.name == $n))[0].status // empty' || true)
case "$state" in
  "")      rig up "$spec_dir/rig.yaml" ;;
  stopped) rig up "$rig_name" --existing; tell_lead ;;
  *)       say "start-rig: $rig_name is already $state"; tell_lead ;;
esac

say ""
say "start-rig: $rig_name"
say "  lead     rig send orch-lead@$rig_name \"...\"   (or prefix+A)"
say "  watch    rig ps --nodes --rig $rig_name   ·   rig tui"
say "  brief    $lead_dir/BRIEF.md"
say "  progress $lead_dir/PROGRESS.md"
say "  undo     cleanup-rig $branch"
exit
}
