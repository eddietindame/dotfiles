#!/usr/bin/env zsh
# Sourced by EVERY zsh invocation — including non-interactive, non-login ones
# such as `ssh host -- cmd`. Keep it minimal; scripts pay this cost too.
#
# Why this exists: /usr/libexec/path_helper is only run from /etc/zprofile,
# which macOS reserves for login shells. So /etc/paths and /etc/paths.d are
# invisible to `ssh host -- cmd`, and Homebrew's own /etc/paths.d/homebrew
# drop-in does nothing there. mosh breaks on exactly this — it starts the
# remote end by running `ssh host -- mosh-server new`, which cannot find
# /opt/homebrew/bin/mosh-server without the line below.

# Guarded so nested shells don't keep prepending; login shells get Homebrew
# from path_helper as well, and this avoids a duplicate entry.
case ":$PATH:" in
  *":/opt/homebrew/bin:"*) ;;
  *) export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH" ;;
esac
