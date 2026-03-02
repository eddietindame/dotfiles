# Set config dir
export XDG_CONFIG_HOME="$HOME/.config"

# Path
export PATH="$HOME/bin:$PATH"
GOPATH=$HOME/go  PATH=$PATH:/usr/local/go/bin:$GOPATH/bin

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
      fc -l -1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' >> "$_global_histfile"
      _last_hist_num=$cur_num
    fi
  }
  # Toggle between session and global history
  toggle-history() {
    if [[ "$HISTFILE" == "$_session_histfile" ]]; then
      fc -P; fc -p "$_global_histfile" $HISTSIZE $SAVEHIST
      echo "history: global"
    else
      fc -P; fc -p "$_session_histfile" $HISTSIZE $SAVEHIST
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
  echo "$(date '+%Y-%m-%d %H:%M') tmuxinator start $*" >> "$HOME/.tmuxinator_log"
  tmuxinator start "$@"
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

# Increase memory for eslint
export NODE_OPTIONS="--max-old-space-size=8192"

# Yazi function to change directory after running yazi
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
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
source $ZSH_PLUGINS_DIR/znap/znap.zsh  # Start Znap
