#!/bin/sh
set -u
. "$(dirname "$0")/helpers.sh"
trap wt_test_teardown EXIT
wt_test_setup

R=$(wt_make_repo alpha)
tmux -f /dev/null -L "$TMUX_SOCK" new-session -d -s scratch -c "$R"
export TMUX WT_SHELL
TMUX=$(tmux -L "$TMUX_SOCK" display -p '#{socket_path}'),0,0
WT_SHELL=1
cd "$R"   # wt new reads $PWD to find the repo

wt new feat/three
EXP="$WT_ROOTS/alpha-worktrees/feat-three"
wt_assert_eq "$([ -d "$EXP" ] && echo yes || echo no)" "yes" "worktree created at sibling <repo>-worktrees"
wt_assert_eq "$(git -C "$EXP" branch --show-current)" "feat/three" "branch keeps its slash"
wt_assert_eq "$(tmux -L "$TMUX_SOCK" list-windows -a -F '#{@wt_path}' | grep -c "^$EXP$")" "1" "new opens a window"

# second call on the same branch must not error or duplicate
wt new feat/three
rc=$?
wt_assert_eq "$rc" "0" "new on existing branch falls through to open without erroring"
wt_assert_eq "$(tmux -L "$TMUX_SOCK" list-windows -a -F '#{@wt_path}' | grep -c "^$EXP$")" "1" "new on existing branch is idempotent"

# nothing was deleted
wt_assert_eq "$([ -d "$EXP" ] && echo yes || echo no)" "yes" "existing worktree untouched"
