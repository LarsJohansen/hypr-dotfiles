#!/bin/sh
set -u
. "$(dirname "$0")/helpers.sh"
trap wt_test_teardown EXIT
wt_test_setup

wt_make_repo alpha feat/one >/dev/null
WTP="$WT_ROOTS/alpha-worktrees/feat-one"

tmux -f /dev/null -L "$TMUX_SOCK" new-session -d -s scratch
# Point wt at the test server directly rather than relying on run-shell to
# export TMUX. WT_SHELL keeps the test from launching a real Claude session.
export TMUX WT_SHELL
TMUX=$(tmux -L "$TMUX_SOCK" display -p '#{socket_path}'),0,0
WT_SHELL=1
T=$(printf '\t')

wt open "$WTP"
n=$(tmux -L "$TMUX_SOCK" list-windows -a -F '#{@wt_path}' | grep -c "^$WTP$")
wt_assert_eq "$n" "1" "open creates exactly one window"

sess=$(tmux -L "$TMUX_SOCK" list-windows -a -F "#{session_name}${T}#{@wt_path}" | awk -F"$T" -v p="$WTP" '$2==p{print $1}')
wt_assert_eq "$sess" "alpha" "window lands in a session named after the repo"

win=$(tmux -L "$TMUX_SOCK" list-windows -a -F "#{window_name}${T}#{@wt_path}" | awk -F"$T" -v p="$WTP" '$2==p{print $1}')
wt_assert_eq "$win" "feat-one" "window named after the branch, slash sanitized"

panes=$(tmux -L "$TMUX_SOCK" list-windows -a -F "#{window_panes}${T}#{@wt_path}" | awk -F"$T" -v p="$WTP" '$2==p{print $1}')
wt_assert_eq "$panes" "2" "window has two panes"

# idempotency: opening the same path again must not create a second window
wt open "$WTP"
n=$(tmux -L "$TMUX_SOCK" list-windows -a -F '#{@wt_path}' | grep -c "^$WTP$")
wt_assert_eq "$n" "1" "open is idempotent"
