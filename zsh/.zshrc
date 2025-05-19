# ┌────────────────────────────────────────────────────┐
# │                Lars' Fancy ZSH Shell               │
# └────────────────────────────────────────────────────┘

# ─[ Starship Prompt ]──────────────────────────────────
eval "$(starship init zsh)"

# ─[ History Settings ]─────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt append_history
setopt hist_ignore_dups
setopt share_history

# ─[ Plugins ]──────────────────────────────────────────
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ─[ FZF Setup ]────────────────────────────────────────
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
[ -f /usr/share/fzf/key-bindings.zsh ] && source /usr/share/fzf/key-bindings.zsh
[ -f /usr/share/fzf/completion.zsh ] && source /usr/share/fzf/completion.zsh

# ─[ FZF Customization ]────────────────────────────────
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"


# ─[ Aliases ]──────────────────────────────────────────
alias cat='bat'
alias ls='ls --color=auto'
alias ll='ls -lAh'
alias grep='rg'
alias g='git'
alias dotnet8="$HOME/.dotnet8/dotnet"
alias dotnet8test='dotnet8 test --filter Category!=Integration'

# ─[ Prompt Title ]─────────────────────────────────────
precmd() { print -Pn "\e]0;%n@%m: %~\a" }

# ─[ Welcome Message (optional) ]───────────────────────

if [[ $- == *i* && -z "$ZSH_CHILD" ]]; then
  export ZSH_CHILD=1
  fastfetch
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
