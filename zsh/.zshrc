# ┌────────────────────────────────────────────────────┐
# │                Lars' Fancy ZSH Shell               │
# └────────────────────────────────────────────────────┘

case "$(uname -s)" in
  Darwin) export DOTFILES_OS=mac ;;
  Linux)  export DOTFILES_OS=linux ;;
esac

# ─[ History Settings ]─────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt append_history
setopt hist_ignore_dups
setopt share_history


if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# ─[ Starship Prompt ]──────────────────────────────────
eval "$(starship init zsh)"

# -[ direnv hook ]-----------
eval "$(direnv hook zsh)"

# --- portable "source if exists" helper
source_if_exists() {
  [[ -f "$1" ]] && source "$1"
}

# --- zscaler
export NODE_EXTRA_CA_CERTS="$HOME/.certs/zscaler.pem"

# --- zsh-autosuggestions
source_if_exists /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source_if_exists /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source_if_exists /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# ─[ FZF Setup ]────────────────────────────────────────
if [[ -f ~/.fzf.zsh ]]; then
  source ~/.fzf.zsh
else
  source_if_exists /opt/homebrew/opt/fzf/shell/key-bindings.zsh
  source_if_exists /opt/homebrew/opt/fzf/shell/completion.zsh
  source_if_exists /usr/local/opt/fzf/shell/key-bindings.zsh
  source_if_exists /usr/local/opt/fzf/shell/completion.zsh
  source_if_exists /usr/share/fzf/key-bindings.zsh
  source_if_exists /usr/share/fzf/completion.zsh
fi

# ─[ FZF Customization ]────────────────────────────────
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"

export GITHUB_TOKEN=$(security find-generic-password -a "$USER" -s "github_pat_aidn" -w 2>/dev/null)
export NODE_AUTH_TOKEN="$GITHUB_TOKEN"
export NuGetPackageSourceCredentials_github_aidnas="Username=AidnLars;Password=$GITHUB_TOKEN"

# ─[ Aliases ]──────────────────────────────────────────
alias cat='bat'
if [[ "$DOTFILES_OS" == "linux" ]]; then
  alias ls='ls --color=auto'
  alias dotnet8="$HOME/.dotnet8/dotnet"
  alias dotnet8test='dotnet8 test --filter Category!=Integration'
  alias dotnet9="DOTNET_ROOT=$HOME/.dotnet $HOME/.dotnet/dotnet"
else
  alias ls='ls -G'
fi
alias ll='ls -lAh'
alias grep='rg'
alias g='git'

# ─[ Prompt Title ]─────────────────────────────────────
precmd() { print -Pn "\e]0;%n@%m: %~\a" }

# ─[ Welcome Message (optional) ]───────────────────────

if [[ $- == *i* && -z "$ZSH_CHILD" ]]; then
  export ZSH_CHILD=1
  if command -v fastfetch >/dev/null 2>&1; then
    fastfetch
  fi
fi

# ─[ Load zoxide if installed ]─────────────────────────
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
fi

# - FUZZY GIT 
gitf() {
  git log --graph --pretty=format:'%C(yellow)%h%Creset %s %C(blue)(%cr) %Cgreen<%an>%Creset' --abbrev-commit |
    fzf --ansi --no-sort --reverse --preview "echo {} | cut -d' ' -f1 | xargs git show --color=always" |
    cut -d' ' -f1 | xargs -r git checkout
}


gstash() {
  git stash list | fzf --preview "echo {} | cut -d: -f1 | xargs -I@ git stash show -p @" |
  cut -d: -f1 | xargs -r git stash apply
}

# - Git Autocomplete
autoload -Uz compinit && compinit

if [[ "$DOTFILES_OS" == "linux" ]]; then
  # Track explicitly installed packages
  export DOTFILES_LOG="$HOME/.dotfiles/pkglist.txt"
  export AUR_LOG="$HOME/.dotfiles/aur-packages.txt"
  export XDG_CURRENT_DESKTOP=GNOME
  
  # Wrap pacman installs
  function pacman() {
      if [[ "$1" == "-S" || "$1" == "-Syu" ]]; then
          for pkg in "${@:2}"; do
              if ! pacman -Qqe | grep -q "^$pkg$"; then
                  echo "$pkg" >> "$DOTFILES_LOG"
  #                changed=1
              fi
          done
      fi
      command pacman "$@"
  #    [[ $changed -eq 1 ]] && aconfmgr save
  }
  
  # Wrap paru installs
  function paru() {
      if [[ "$1" == "-S" ]]; then
          for pkg in "${@:2}"; do
              if pacman -Qm | grep -q "^$pkg"; then
                  echo "$pkg" >> "$AUR_LOG"
  #                changed=1
              fi
          done
      fi
      command paru "$@"
  #    [[ $changed -eq 1 ]] && aconfmgr save
  }
  # Source the secrets file if it exists
  [[ -f ~/.secrets/env.sh ]] && source ~/.secrets/env.sh
  
  # Created by `pipx` on 2025-05-08 21:14:40
  export PATH="$PATH:/home/lars/.local/bin"
fi

# TheFuck
if command -v thefuck >/dev/null 2>&1; then
  eval "$(thefuck --alias)"
fi

export PATH="$PATH:$HOME/.local/bin"
## Tmux sessions
workon() {
  local name=$(basename "$PWD")
  tmux has-session -t "$name" 2>/dev/null

  if [ $? != 0 ]; then
    tmux new-session -ds "$name" -c "$PWD" \; \
      send-keys "nvim" C-m \; \
      split-window -v -c "$PWD" \; \
      send-keys "dotnet watch dotnet8test" C-m \; \
      select-pane -t 1 \; \
      split-window -h -c "$PWD" \; \
      send-keys "clear && echo 'Git shell ready'" C-m \; \
      select-pane -t 0
  fi

  tmux attach-session -t "$name"
}
export PATH=~/.npm-global/bin:$PATH

# --- zsh-syntax-highlighting (must be sourced near the end of .zshrc)
source_if_exists /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source_if_exists /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source_if_exists /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Start SSH agent if not already running
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" >/dev/null
fi
# Commented out to use system dotnet (version 10) as default
# Use dotnet8 and dotnet9 aliases for older versions
# export PATH="$HOME/.dotnet:$PATH"
# export DOTNET_ROOT="$HOME/.dotnet"

export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
