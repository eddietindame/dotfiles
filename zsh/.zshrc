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

# Bind up and down for command history
bindkey "^[[A" history-beginning-search-backward
bindkey "^[[B" history-beginning-search-forward

# Aliases to bring suspended apps to foreground
alias fg1="fg %1"
alias fg2="fg %2"
alias fg3="fg %3"

# Alias ls to eza
alias ls="eza"

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
