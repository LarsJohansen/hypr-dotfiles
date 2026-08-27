# shellcheck shell=sh
# Shared helpers for wt, wt-hook, wt-poll. Source only; do not execute.

: "${WT_ROOTS:=$HOME/Projects $HOME/dev $HOME/.dotfiles}"

WT_TAB=$(printf '\t')

# tmux session names: strip leading dots, replace . and : which are target syntax
wt_sanitize_session() {
  printf '%s' "$1" | sed 's/^\.*//; s/[.:]/-/g'
}

# tmux window names: slashes would read as nested paths
wt_sanitize_window() {
  printf '%s' "$1" | tr '/' '-'
}

# Absolute path of every main checkout under WT_ROOTS.
# A .git DIRECTORY is a main checkout; a .git FILE is a linked worktree, which
# we skip because git worktree list will report it via its main checkout.
wt_main_checkouts() {
  for root in $WT_ROOTS; do
    [ -d "$root" ] || continue
    find "$root" -maxdepth 3 -name .git -prune -print 2>/dev/null
  done | while IFS= read -r g; do
    [ -d "$g" ] || continue
    dirname "$g"
  done
}

# Main checkout directory for any path inside a repo or worktree.
wt_main_for() {
  c=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  dirname "$c"
}

# window_id whose @wt_path equals $1, else empty.
wt_window_for_path() {
  tmux list-windows -a -F "#{window_id}${WT_TAB}#{@wt_path}" 2>/dev/null |
    awk -F"${WT_TAB}" -v p="$1" '$2==p {print $1; exit}'
}

# window_id whose @wt_path is the longest prefix of $1, else empty.
wt_window_for_cwd() {
  tmux list-windows -a -F "#{window_id}${WT_TAB}#{@wt_path}" 2>/dev/null |
    awk -F"${WT_TAB}" -v c="$1" '
      $2 != "" && (c == $2 || index(c, $2 "/") == 1) && length($2) > best {
        best = length($2); id = $1
      }
      END { if (id != "") print id }'
}

# TSV: repo <tab> worktree_path <tab> branch <tab> window_id
wt_list() {
  wt_main_checkouts | while IFS= read -r repo; do
    rname=$(basename "$repo")
    git -C "$repo" worktree list --porcelain 2>/dev/null | awk -v repo="$rname" -v T="$WT_TAB" '
      /^worktree /  { path = substr($0, 10); br = ""; sha = "" }
      /^HEAD /      { sha = substr($0, 6, 7) }
      /^branch /    { br = substr($0, 8); sub("refs/heads/", "", br) }
      /^detached$/  { br = "" }
      /^$/          { if (path != "") { print repo T path T (br == "" ? sha : br); path = "" } }
      END           { if (path != "") print repo T path T (br == "" ? sha : br) }
    '
  done | while IFS="$WT_TAB" read -r r p b; do
    printf '%s\t%s\t%s\t%s\n' "$r" "$p" "$b" "$(wt_window_for_path "$p")"
  done
}

# "2m5s", "45s", "1h3m"
wt_fmt_elapsed() {
  s=$1
  if [ "$s" -lt 60 ]; then
    printf '%ds' "$s"
  elif [ "$s" -lt 3600 ]; then
    printf '%dm%ds' "$((s / 60))" "$((s % 60))"
  else
    printf '%dh%dm' "$((s / 3600))" "$(((s % 3600) / 60))"
  fi
}

# "main ^3 +12/-3 *" — branch, ahead/behind, diffstat, dirty marker.
# --ignore-submodules so a dirty submodule does not mark the worktree dirty.
wt_git_fragment() {
  p=$1
  git -C "$p" rev-parse --git-dir >/dev/null 2>&1 || return 0
  br=$(git -C "$p" branch --show-current 2>/dev/null || true)
  [ -n "$br" ] || br=$(git -C "$p" rev-parse --short HEAD 2>/dev/null || echo '?')
  out=$br

  ab=$(git -C "$p" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || true)
  if [ -n "$ab" ]; then
    behind=$(printf '%s' "$ab" | cut -f1)
    ahead=$(printf '%s' "$ab" | cut -f2)
    [ "${ahead:-0}" -gt 0 ] 2>/dev/null && out="$out ↑$ahead"
    [ "${behind:-0}" -gt 0 ] 2>/dev/null && out="$out ↓$behind"
  fi

  stat=$(git -C "$p" diff --numstat --ignore-submodules 2>/dev/null |
    awk '{a += $1; d += $2} END {if (NR > 0) printf "+%d/-%d", a, d}')
  [ -n "$stat" ] && out="$out $stat"

  [ -n "$(git -C "$p" status --porcelain --ignore-submodules 2>/dev/null)" ] && out="$out *"
  printf '%s' "$out"
}
