#!/bin/sh
set -u
. "$(dirname "$0")/helpers.sh"
trap wt_test_teardown EXIT
wt_test_setup

wt_make_repo alpha feat/one feat/two >/dev/null
MAIN="$WT_ROOTS/alpha"
WTP1="$WT_ROOTS/alpha-worktrees/feat-one"
WTP2="$WT_ROOTS/alpha-worktrees/feat-two"

tmux -f /dev/null -L "$TMUX_SOCK" new-session -d -s scratch
export TMUX WT_SHELL
TMUX=$(tmux -L "$TMUX_SOCK" display -p '#{socket_path}'),0,0
WT_SHELL=1

# A window opened on the MAIN checkout, standing in for a planning session that
# Claude has since teleported into a worktree via EnterWorktree.
wt open "$MAIN"
WID=$(tmux -L "$TMUX_SOCK" list-windows -a -F "#{window_id}	#{@wt_path}" \
  | awk -F'\t' -v p="$MAIN" '$2==p{print $1}')
tmux -L "$TMUX_SOCK" select-window -t "$WID"

opt() { tmux -L "$TMUX_SOCK" show -w -t "$WID" -v "$1" 2>/dev/null; }

# 1. explicit path re-points the current window at the worktree
wt adopt "$WTP1"
wt_assert_eq "$(opt @wt_path)" "$WTP1" "adopt <path> repoints @wt_path"

# 2. the window is renamed after the adopted worktree's branch
wt_assert_eq "$(tmux -L "$TMUX_SOCK" display -t "$WID" -p '#{window_name}')" \
  "feat-one" "adopt renames the window to the branch"

# 3. no second window was created -- adoption is in place, not a new window
wt_assert_eq "$(tmux -L "$TMUX_SOCK" list-windows -a -F '#{@wt_path}' \
  | grep -c "^$WTP1$")" "1" "adopt does not create a second window"

# 4. a subdirectory resolves up to the worktree root
mkdir -p "$WTP2/src/deep"
(cd "$WTP2/src/deep" && wt adopt)
wt_assert_eq "$(opt @wt_path)" "$WTP2" "bare adopt uses \$PWD, resolved to the worktree root"

# 5. refuses to adopt a path another window already tracks, and leaves the
#    current window's tracking untouched when it refuses
wt open "$WTP1"
tmux -L "$TMUX_SOCK" select-window -t "$WID"
rc=0
(cd "$WTP1" && wt adopt) 2>/dev/null || rc=$?
wt_assert_eq "$rc" "1" "adopt refuses a path another window already tracks"
wt_assert_eq "$(opt @wt_path)" "$WTP2" "refused adopt leaves @wt_path unchanged"

# 6. errors outside a git repository rather than silently setting garbage
rc=0
(cd "$WT_TMP" && wt adopt) 2>/dev/null || rc=$?
wt_assert_eq "$rc" "1" "adopt outside a git repo exits 1"

# 7. never touches the worktree on disk
wt_assert_eq "$([ -d "$WTP1" ] && [ -d "$WTP2" ] && echo yes || echo no)" "yes" \
  "adopt leaves every worktree on disk"
