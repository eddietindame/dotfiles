#!/usr/bin/env bash
# Copy command for tmux-yank. tmux itself already sends every copy to the
# attached terminal over OSC 52 (set-clipboard on), which is what reaches the
# laptop over ssh. pbcopy on top of that only fills this machine's pasteboard,
# and over ssh it stops the laptop's clipboard getting the text, so skip it
# there. $SSH_CONNECTION comes from the session environment, which tmux
# refreshes on each attach (update-environment).
if [ -n "$SSH_CONNECTION" ]; then
  cat >/dev/null
else
  exec pbcopy
fi
