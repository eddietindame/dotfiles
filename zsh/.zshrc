# Set config dir
export XDG_CONFIG_HOME="$HOME/.config"

# Path
export PATH="$HOME/bin:$PATH"
GOPATH=$HOME/go PATH=$PATH:/usr/local/go/bin:$GOPATH/bin

# Volta (node/npm/npx/pnpm/yarn shims) is set up in .zshenv so non-interactive
# shells get it too. It must be re-asserted here because login shells run
# /etc/zprofile -> path_helper AFTER .zshenv, and that reorders PATH so
# /opt/homebrew/bin (prettier's node) lands ahead of Volta's shims again.
# typeset -U dedupes, so this moves the entry rather than adding a second.
typeset -U path
path=("$VOLTA_HOME/bin" $path)

# The next line updates PATH for the Google Cloud SDK.
if [ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/google-cloud-sdk/path.zsh.inc"; fi

# The next line enables shell command completion for gcloud.
if [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/google-cloud-sdk/completion.zsh.inc"; fi

# Load local bin env
. "$HOME/.local/bin/env"

# Starship prompt
eval "$(starship init zsh)"

# Initialise zoxide unless disabled (Claude Code)
if [ -z "$DISABLE_ZOXIDE" ]; then
  eval "$(zoxide init --cmd cd zsh)"
fi

# History
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY
setopt HIST_FIND_NO_DUPS

if [[ -n "$TMUX" ]]; then
  mkdir -p "$HOME/.zsh_history.d"
  _tmux_session=$(tmux display-message -p '#S')
  _session_histfile="$HOME/.zsh_history.d/${_tmux_session//\//-}"
  _global_histfile="$HOME/.zsh_history"
  # Load session history first, then fill remaining slots with global
  HISTFILE="$_session_histfile"
  fc -R "$_global_histfile" 2>/dev/null
  fc -R "$_session_histfile" 2>/dev/null
  # Also append new commands to global history
  _last_hist_num=0
  precmd() {
    local cur_num=$(fc -l -1 | awk '{print $1}')
    if [[ "$cur_num" -gt "$_last_hist_num" ]]; then
      fc -AI "$HISTFILE"
      fc -l -1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' >>"$_global_histfile"
      _last_hist_num=$cur_num
    fi
  }
  # Toggle between session and global history
  toggle-history() {
    if [[ "$HISTFILE" == "$_session_histfile" ]]; then
      fc -P
      fc -p "$_global_histfile" $HISTSIZE $SAVEHIST
      echo "history: global"
    else
      fc -P
      fc -p "$_session_histfile" $HISTSIZE $SAVEHIST
      echo "history: session"
    fi
  }
else
  HISTFILE="$HOME/.zsh_history"
fi

# Bind up and down for command history
bindkey "^[[A" history-beginning-search-backward
bindkey "^[[B" history-beginning-search-forward

# Aliases to bring suspended apps to foreground
alias fg1="fg %1"
alias fg2="fg %2"
alias fg3="fg %3"

# Alias ls to eza
alias ls="eza"

# Log tmuxinator commands
tms() {
  echo "$(date '+%Y-%m-%d %H:%M') tmuxinator start $*" >>"$HOME/.tmuxinator_log"
  tmuxinator start "$@"
}

# Attach to the mac mini's herdr session.
# --remote-keybindings server is required, not cosmetic: a plain `herdr --remote`
# honours the built-in actions but ignores every [[keys.command]] binding, so the
# fzf pickers and the agent-view toggle silently do nothing.
alias hmini="herdr --remote mini --remote-keybindings server"

# Forward a dev instance's ports from the mini, so localhost:<port> here is
# localhost:<port> there. Matters because the generated .env files point at
# http://localhost:PORT, which only resolves correctly if the ports are local.
#   bertie-tunnel        # instance 1: backend 3001, postgres 5433, auth 3000
#   bertie-tunnel 2      # instance 2: backend 3002, postgres 5434, auth 3000
#   bertie-tunnel 2 5173 # ...plus a frontend dev server on 5173
bertie-tunnel() {
  local n="${1:-1}"
  shift 2>/dev/null
  local backend=$((3000 + n)) postgres=$((5432 + n))
  local -a forwards
  forwards=(
    -L "${backend}:localhost:${backend}"
    -L "${postgres}:localhost:${postgres}"
    -L "3000:localhost:3000"   # auth stack is fixed, not offset
  )
  local p
  for p in "$@"; do forwards+=(-L "${p}:localhost:${p}"); done

  echo "tunnelling from mini: backend $backend, postgres $postgres, auth 3000${*:+, extra $*}"
  echo "(ctrl-c to stop)"
  # ExitOnForwardFailure so a port already in use fails loudly instead of
  # leaving you wondering why localhost:3001 is the wrong app.
  ssh -N -o ExitOnForwardFailure=yes "${forwards[@]}" mini
}

# Always upgrade claude-code
alias claude="brew upgrade claude-code && claude"

# Alias glow with custom config
alias glow="glow --config $HOME/.config/glow/glow.yml"

# Neovim aliases
alias nvimd="command nvim"
alias nvim-chad="NVIM_APPNAME=nvim/nvchad command nvim"
alias nvim-kick="NVIM_APPNAME=nvim/kickstart-modular command nvim"
alias nvim="nvim-kick"

function nvims() {
  items=("nvim/nvchad" "nvim/kickstart-modular" "default")
  config=$(printf "%s\n" "${items[@]}" | fzf --prompt="Config: ")
  if [[ -n $config ]]; then
    if [[ $config == "default" ]]; then
      nvim "$@"
    else
      NVIM_APPNAME=$config nvim "$@"
    fi
  fi
}

cleanup-worktrees() {
  if [[ -z "$1" ]]; then
    echo "Usage: cleanup-worktrees <branch-name>"
    return 1
  fi

  local branch="$1"

  # Close the herdr space for this branch first, so its agents go down with the
  # checkout instead of being left in deleted directories. start-dev labels the
  # space with the frontend branch. No-op if herdr isn't running or has no
  # matching space.
  if command -v herdr >/dev/null 2>&1 && herdr status server >/dev/null 2>&1; then
    local space
    space=$(herdr workspace list 2>/dev/null |
      jq -r --arg l "$branch" '.result.workspaces[] | select(.label == $l) | .workspace_id' |
      head -1)
    if [[ -n "$space" ]]; then
      echo "Closing herdr space '$branch' ($space)"
      herdr workspace close "$space" >/dev/null
    fi
  fi

  for dir in */; do
    [[ -d "$dir/.git" || -f "$dir/.git" ]] || continue
    local worktree
    worktree=$(git -C "$dir" worktree list --porcelain |
      awk -v b="$branch" '/^worktree /{wt=$2} /^branch /{if ($2 == "refs/heads/"b) print wt}')
    if [[ -n "$worktree" ]]; then
      echo "Removing worktree for '$branch' in $dir -> $worktree"
      git -C "$dir" worktree remove --force "$worktree"
    fi
  done
}

# Increase memory for eslint
export NODE_OPTIONS="--max-old-space-size=8192"

# Yazi function to change directory after running yazi
function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  command yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd <"$tmp"
  [ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}

### Znap setup ###

ZSH_PLUGINS_DIR="$HOME/.config/zsh/plugins"
mkdir -p "$ZSH_PLUGINS_DIR"

# Download Znap, if it's not there yet.
[[ -r $ZSH_PLUGINS_DIR/znap/znap.zsh ]] ||
  git clone --depth 1 -- \
    https://github.com/marlonrichert/zsh-snap.git $ZSH_PLUGINS_DIR/znap
source $ZSH_PLUGINS_DIR/znap/znap.zsh # Start Znap
