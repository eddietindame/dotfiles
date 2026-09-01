#!/usr/bin/env bash
# herdr-pick.sh — fzf pickers for herdr, in the spirit of tmux-sessionx.
#
# Usage: herdr-pick.sh space|tab|agent
#
# Bound to popup keys in ../config.toml:
#   prefix+o        space picker   (mirrors tmux's sessionx bind)
#   prefix+ctrl+w   tab picker     (mirrors tmux's `w` list-windows)
#   prefix+a        agent picker   (no tmux equivalent)
#   prefix+u        url picker     (mirrors tmux-fzf-url)
#
# Note: config.toml calls this by absolute path, since herdr may exec the
# command directly rather than through a shell. Update that path if $HOME
# ever changes.

set -euo pipefail

FZF_OPTS=(
  --delimiter=$'\t'
  --with-nth=2..
  --height=100%
  --border=rounded
  --info=inline
  --pointer='▎'
  --no-multi
)

die() { printf '%s\n' "$1" >&2; sleep 1.5; exit 1; }

pick_space() {
  local rows sel
  rows=$(herdr workspace list | jq -r '
    .result.workspaces[]
    | [ .workspace_id
      , .label
      , "\(.tab_count) tabs, \(.pane_count) panes"
      , .agent_status
      ] | @tsv')
  [ -n "$rows" ] || die "no spaces"

  sel=$(printf '%s\n' "$rows" | fzf "${FZF_OPTS[@]}" \
        --prompt='spaces ❯ ' \
        --preview='herdr tab list --workspace {1} | jq -r ".result.tabs[] | \"  \(.number). \(.label)  [\(.agent_status)]\""' \
        --preview-window='right,45%,border-left') || exit 0
  herdr workspace focus "$(cut -f1 <<<"$sel")" >/dev/null
}

pick_tab() {
  local spaces rows sel
  spaces=$(herdr workspace list)
  rows=$(herdr tab list | jq -r --argjson spaces "$spaces" '
    ($spaces.result.workspaces | map({key: .workspace_id, value: .label}) | from_entries) as $names
    | .result.tabs[]
    | [ .tab_id
      , "\($names[.workspace_id] // .workspace_id)/\(.label)"
      , "\(.pane_count) panes"
      , .agent_status
      ] | @tsv')
  [ -n "$rows" ] || die "no tabs"

  sel=$(printf '%s\n' "$rows" | fzf "${FZF_OPTS[@]}" \
        --prompt='tabs ❯ ' \
        --preview='herdr pane list | jq -r --arg t {1} ".result.panes[] | select(.tab_id == \$t) | .pane_id" | awk 'NR==1' | xargs -r -I% herdr pane read % --source visible --lines 60 --format text' \
        --preview-window='right,60%,border-left') || exit 0
  herdr tab focus "$(cut -f1 <<<"$sel")" >/dev/null
}

pick_agent() {
  local rows sel
  rows=$(herdr agent list | jq -r '
    .result.agents[]
    | [ .pane_id
      , .agent
      , (.terminal_title_stripped // .cwd)
      , .agent_status
      ] | @tsv')
  [ -n "$rows" ] || die "no agents running"

  sel=$(printf '%s\n' "$rows" | fzf "${FZF_OPTS[@]}" \
        --prompt='agents ❯ ' \
        --preview='herdr pane read {1} --source visible --lines 60 --format text' \
        --preview-window='right,60%,border-left') || exit 0
  herdr agent focus "$(cut -f1 <<<"$sel")" >/dev/null
}


# tmux-fzf-url equivalent. Reads the focused pane's scrollback, since that is
# where the URL you just saw will be.
#
# Opening is the awkward part on a remote attach: this script runs on the herdr
# server, so `open <url>` would launch a browser there rather than on the
# machine you are sitting at. So:
#   - if ~/.config/herdr/client-ssh holds an ssh target (or HERDR_CLIENT_SSH is
#     set), run `open` over ssh there. An env var alone is not enough: this runs
#     as a child of the herdr server, which does not inherit your login shell.
#   - otherwise copy to the clipboard with OSC 52, which herdr forwards to the
#     attached client's terminal, and you paste where you want it
pick_url() {
  local pane rows sel url log="${XDG_STATE_HOME:-$HOME/.local/state}/herdr-pick.log"
  mkdir -p "$(dirname "$log")"

  # Inside a popup the UI-focused pane can be the popup itself, so prefer the
  # caller context herdr injects into the pane it spawned us from.
  pane="${HERDR_PANE_ID:-}"
  [ -n "$pane" ] ||
    pane=$(herdr pane list | jq -r '.result.panes[] | select(.focused) | .pane_id' | awk 'NR==1')
  printf '%s url: HERDR_PANE_ID=%s resolved=%s\n' "$(date '+%H:%M:%S')" "${HERDR_PANE_ID:-unset}" "${pane:-none}" >>"$log"
  [ -n "$pane" ] || die "no pane to read"

  rows=$(herdr pane read "$pane" --source recent --lines 2000 --format text \
         | grep -oE '(https?|ftp|file)://[^ \t"'"'"'<>()\[\]`|]+' \
         | sed 's/[.,;:!?]*$//' \
         | awk '!seen[$0]++' \
         | tail -r)
  printf '%s url: %s candidates from %s\n' "$(date '+%H:%M:%S')" "$(printf '%s' "$rows" | grep -c . || true)" "$pane" >>"$log"
  [ -n "$rows" ] || die "no urls in $pane"

  sel=$(printf '%s\n' "$rows" | fzf \
        --height=100% --border=rounded --info=inline --pointer='▎' --no-multi \
        --prompt='urls ❯ ') || exit 0
  url="$sel"

  local target="${HERDR_CLIENT_SSH:-}"
  [ -n "$target" ] || target=$(awk 'NR==1' "${XDG_CONFIG_HOME:-$HOME/.config}/herdr/client-ssh" 2>/dev/null || true)

  if [ -n "$target" ] &&
     ssh -o BatchMode=yes -o ConnectTimeout=3 "$target" "open '$url'" 2>/dev/null; then
    printf 'opened on %s\n' "$target"
  else
    # OSC 52: ask the attached terminal to put this on its own clipboard
    printf '\033]52;c;%s\a' "$(printf '%s' "$url" | base64 | tr -d '\n')"
    printf 'copied to clipboard: %s\n' "$url"
  fi
  sleep 1
}

case "${1:-}" in
  space|spaces|workspace) pick_space ;;
  tab|tabs)               pick_tab ;;
  agent|agents)           pick_agent ;;
  url|urls)               pick_url ;;
  *) die "usage: $(basename "$0") space|tab|agent|url" ;;
esac
