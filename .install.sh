#!/bin/bash

set -e

echo "📦 Installing essential packages..."
sudo pacman -S --needed - < pkglist.txt 

if ! command -v paru >/dev/null 2>&1; then
    echo "⚙️ Installing paru..."
    git clone https://aur.archlinux.org/paru.git ~/paru
    (cd ~/paru && makepkg -si)
fi

paru -S --needed - < aur-packages.txt

echo "📂 Cloning dotfiles..."
cd ~
git clone git@github.com:yourusername/dotfiles.git
cd dotfiles

echo "🔗 Stowing configs..."
stow zsh
stow hypr
stow nvim
stow waybar
stow kitty
stow scripts

echo "✅ Dotfiles applied!"
