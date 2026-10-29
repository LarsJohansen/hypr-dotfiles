# shellcheck shell=sh
# Test fixtures. Source this; it sets WT_TMP, WT_ROOTS, WT_LIB, TMUX_SOCK.
WT_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export WT_LIB="$WT_REPO_ROOT/.local/lib/wt/lib.sh"
export PATH="$WT_REPO_ROOT/.local/bin:$PATH"
TMUX_SOCK=wt-test

wt_test_setup() {
  # pwd -P: macOS mktemp hands out /var/..., a symlink to /private/var/...,
  # and git reports the resolved form, so expected paths must match it.
  WT_TMP=$(CDPATH= cd -- "$(mktemp -d)" && pwd -P)
  export WT_TMP
  export WT_ROOTS="$WT_TMP/projects"
  # Redirect tmux's socket lookup into the scratch dir and drop any
  # inherited server, so a bare `tmux` in library code cannot reach the
  # user's real session.
  export TMUX_TMPDIR="$WT_TMP/tmux"
  mkdir -p "$WT_ROOTS" "$TMUX_TMPDIR"
  unset TMUX
}

wt_test_teardown() {
  tmux -L "$TMUX_SOCK" kill-server 2>/dev/null || true
  [ -n "${WT_TMP:-}" ] && rm -rf "$WT_TMP"
}

# wt_make_repo <name> [branch...] -- main checkout plus one worktree per branch
wt_make_repo() {
  name=$1; shift
  r="$WT_ROOTS/$name"
  mkdir -p "$r"
  git -C "$r" init -q -b main
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
  echo hello > "$r/README"
  git -C "$r" add README
  git -C "$r" commit -qm init
  for b in "$@"; do
    d="$WT_ROOTS/$name-worktrees/$(printf '%s' "$b" | tr '/' '-')"
    mkdir -p "$(dirname "$d")"
    git -C "$r" worktree add -q -b "$b" "$d" >/dev/null 2>&1
  done
  printf '%s\n' "$r"
}

wt_assert_eq() {
  if [ "$1" != "$2" ]; then
    printf 'FAIL %s\n  expected: [%s]\n  actual:   [%s]\n' "$3" "$2" "$1" >&2
    exit 1
  fi
  printf 'ok   %s\n' "$3"
}

wt_assert_contains() {
  case "$1" in
    *"$2"*) printf 'ok   %s\n' "$3" ;;
    *) printf 'FAIL %s\n  expected to contain: [%s]\n  actual: [%s]\n' "$3" "$2" "$1" >&2; exit 1 ;;
  esac
}
