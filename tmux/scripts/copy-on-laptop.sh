#!/usr/bin/env bash
# copy-on-laptop.sh — stdin to the laptop's clipboard. pbcopy here would fill
# the mini's, and mosh drops OSC 52. Used by tmux-fzf-url (@fzf-url-copy-cmd).
# Needs the mini's key in the laptop's ~/.ssh/authorized_keys; Tailscale IP, as
# MagicDNS doesn't resolve here.
exec ssh -o BatchMode=yes -o ConnectTimeout=5 eddietindame@100.86.187.87 pbcopy
