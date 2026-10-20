#!/usr/bin/env bash
# open-on-laptop.sh <url>... — open links in the laptop's browser, not on the
# headless mini (where `open` fails from an SSH login and nobody sees it).
# Used by tmux-fzf-url (@fzf-url-open). Needs the mini's key in the laptop's
# ~/.ssh/authorized_keys. Tailscale IP, as MagicDNS doesn't resolve here.
laptop=eddietindame@100.86.187.87
# %q: the remote shell would otherwise act on & ; ? in the URL
exec ssh -o BatchMode=yes -o ConnectTimeout=5 "$laptop" open "$(printf '%q ' "$@")"
