#!/usr/bin/env bash
# compose.sh — write a message to an agent in a popup, then send it in one go.
#
#   compose.sh --open <client> <pane>   prefix+e: nvim in a popup over <pane>
#
# OpenRig delivers messages and queue wakes by typing into the agent's pane and
# pressing Enter, so a message half-typed into a lead's prompt gets submitted
# with theirs. Written here, nothing sits in the pane's input box while you
# type: agent messages arrive as normal, and yours is pasted whole when you
# save and quit (:wq, or ZZ). :cq sends nothing and keeps the draft, one per
# session, for the next prefix+e there (prefix+e again does the same, so it
# toggles); :q! sends nothing and drops it.

mode="${1:-}" client="${2:-}" pane="${3:-}"
DRAFTS="${XDG_CACHE_HOME:-$HOME/.cache}/compose"

case "$mode" in
  --open)
    session=$(tmux display-message -p -t "$pane" '#{session_name}') || exit 0
    tmux display-popup -c "$client" -E -w 80% -h 50% -b rounded \
      -T " to $session · :wq send · :cq or prefix+e keep draft · :q! discard " -s bg=terminal,fg=terminal \
      "'$0' --edit '$client' '$pane'"
    ;;

  --edit)   # runs inside the popup
    session=$(tmux display-message -p -t "$pane" '#{session_name}') || exit 0
    mkdir -p "$DRAFTS"
    draft="$DRAFTS/$(printf %s "$session" | tr -c 'A-Za-z0-9@._-' _).md"
    touch "$draft"
    # Sent only if saved this time: an old mtime marks "not written yet", so
    # :q on a kept draft doesn't send it.
    touch -t 200001010000 "$draft"
    # ZZ normally skips the write when nothing changed; here it always writes,
    # so a kept draft can be sent as it is. :cq saves the draft before leaving.
    # Tmux bindings don't fire inside a popup, so prefix+e reaches nvim: there
    # it closes the popup and keeps the draft, as :cq does.
    # Plain nvim plus only your keymaps: the full config's plugins are noise
    # here. -n: no swap file, so a reopened draft doesn't warn.
    keymaps="$HOME/.config/nvim/kickstart-modular/lua/keymaps.lua"
    if ! nvim --clean -n -c "lua vim.g.mapleader = ' '; pcall(dofile, '$keymaps')" \
        -c 'set wrap linebreak spell' -c 'nnoremap ZZ <Cmd>wq<CR>' \
        -c 'for k in ["<C-Space>e", "<C-@>e", "<Nul>e"] | exe "noremap" k "<Cmd>cq<CR>" | exe "inoremap" k "<Cmd>cq<CR>" | endfor' \
        -c 'autocmd VimLeavePre * if v:exiting != 0 | silent! write | endif' \
        -c 'startinsert!' "$draft"; then
      [ -s "$draft" ] && tmux display-message -c "$client" "compose: draft kept, not sent"
      exit 0
    fi
    if [ "$(stat -f %m "$draft")" -lt 946771200 ] || ! grep -q '[^[:space:]]' "$draft"; then
      : >"$draft"   # :q! drops it
      exit 0
    fi
    if ! tmux display-message -p -t "$pane" '' 2>/dev/null; then
      tmux display-message -c "$client" "compose: that pane has gone; draft kept"; exit 0
    fi
    # $(...) drops trailing newlines, so the paste doesn't submit early. -p
    # pastes it bracketed: the agent sees one paste, not typed lines.
    printf %s "$(cat "$draft")" | tmux load-buffer -b compose - &&
      tmux paste-buffer -p -d -b compose -t "$pane" || {
        tmux display-message -c "$client" "compose: paste failed; draft kept"; exit 0; }
    sleep 0.3   # let the agent take the paste before Enter
    tmux send-keys -t "$pane" Enter
    : >"$draft"
    ;;

  *)
    echo "usage: $(basename "$0") --open <client> <pane>" >&2
    exit 1
    ;;
esac
