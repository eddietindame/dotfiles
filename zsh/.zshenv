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

# Volta only manages pnpm as a first-class package manager behind this flag.
# Without it the ~/.volta/bin/pnpm shim fails with "Could not find executable",
# even though `volta list` shows pnpm installed.
export VOLTA_FEATURE_PNPM=1

# Volta shims (node/npm/npx/pnpm/yarn). Prepended AFTER the Homebrew block
# above so it lands ahead of /opt/homebrew/bin — prettier pulls in a Homebrew
# node that otherwise shadows Volta's. Lives here rather than .zshrc because
# tmux panes, start-dev.sh and `ssh host -- cmd` all run non-interactively and
# would otherwise get the wrong node and no pnpm at all.
export VOLTA_HOME="$HOME/.volta"
case ":$PATH:" in
  *":$VOLTA_HOME/bin:"*) ;;
  *) export PATH="$VOLTA_HOME/bin:$PATH" ;;
esac
