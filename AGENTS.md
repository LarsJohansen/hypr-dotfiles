# Repository Guidelines

## Project Structure & Module Organization
- This repository is a set of GNU Stow-able dotfiles.
- Top-level directories map to config targets, e.g. `hypr/`, `nvim/`, `waybar/`, `kitty/`, `tmux/`, `zsh/`, `wofi/`, `wlogout/`, `swaync/`, `tuigreet/`, `starship/`, `syspower/`.
- Package lists live in `pkglist.txt` (pacman) and `aur-packages.txt` (AUR).
- Stow exclusions are tracked in `.stow-local-ignore`.

## Build, Test, and Development Commands
- `./.install.sh` installs packages and stows configs (Arch-based, uses `pacman` and `paru`).
- `stow zsh` (or any top-level dir) applies just that module.
- `stow -D zsh` removes a module if you need to revert a link.

## Coding Style & Naming Conventions
- Preserve existing formatting within each config directory; follow the style already used in that file.
- Shell scripts: keep POSIX/`bash` style, `set -e` at the top, and prefer explicit, readable commands.
- Naming: module directories match the target app name (e.g. `hypr`, `kitty`, `waybar`).

## Testing Guidelines
- No automated test suite is present. Validate changes manually by reloading the relevant app or restarting the service.
- Example: `hyprctl reload` after editing `hypr/`, or restart Waybar after editing `waybar/`.

## Commit & Pull Request Guidelines
- Git history uses short, informal subjects (e.g., "Several fixes"). There is no enforced convention.
- Keep commits scoped to a single module when possible.
- PRs should describe what changed, why, and include screenshots for UI-facing changes (Waybar, Wofi, Hyprland, etc.).

## Security & Configuration Tips
- Avoid committing secrets or tokens in configs; use environment variables or local overrides instead.
- If a config has machine-specific paths, add them to `.stow-local-ignore` or document in the PR.
