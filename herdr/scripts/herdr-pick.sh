#!/usr/bin/env bash
# herdr-pick.sh — fzf pickers for herdr, in the spirit of tmux-sessionx.
#
# Usage: herdr-pick.sh space|tab|agent
#
# Bound to popup keys in ../config.toml:
#   prefix+o        space picker   (mirrors tmux's sessionx bind)
#   prefix+ctrl+w   tab picker     (mirrors tmux's `w` list-windows)
#   prefix+a        agent picker   (no tmux equivalent)
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
        --preview='herdr pane list | jq -r --arg t {1} ".result.panes[] | select(.tab_id == \$t) | .pane_id" | head -1 | xargs -r -I% herdr pane read % --source visible --lines 60 --format text' \
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

case "${1:-}" in
  space|spaces|workspace) pick_space ;;
  tab|tabs)               pick_tab ;;
  agent|agents)           pick_agent ;;
  *) die "usage: $(basename "$0") space|tab|agent" ;;
esac
