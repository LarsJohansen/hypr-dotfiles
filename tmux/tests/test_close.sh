#!/bin/sh
set -u
. "$(dirname "$0")/helpers.sh"
trap wt_test_teardown EXIT
wt_test_setup

wt_make_repo alpha feat/one feat/two >/dev/null
WTP1="$WT_ROOTS/alpha-worktrees/feat-one"
WTP2="$WT_ROOTS/alpha-worktrees/feat-two"

tmux -f /dev/null -L "$TMUX_SOCK" new-session -d -s scratch
# Point wt at the test server directly rather than relying on run-shell to
# export TMUX. WT_SHELL keeps the test from launching a real Claude session.
export TMUX WT_SHELL
TMUX=$(tmux -L "$TMUX_SOCK" display -p '#{socket_path}'),0,0
WT_SHELL=1
T=$(printf '\t')

wt open "$WTP1"
wt open "$WTP2"

n=$(tmux -L "$TMUX_SOCK" list-windows -t "=alpha" | wc -l | tr -d ' ')
wt_assert_eq "$n" "2" "alpha session has two windows before closing"

# --- not-last-window branch: close one of two windows, session must survive ---
w1=$(tmux -L "$TMUX_SOCK" list-windows -a -F "#{window_id}${T}#{@wt_path}" | awk -F"$T" -v p="$WTP1" '$2==p{print $1}')
tmux -L "$TMUX_SOCK" select-window -t "$w1"
wt close

n=$(tmux -L "$TMUX_SOCK" list-windows -t "=alpha" | wc -l | tr -d ' ')
wt_assert_eq "$n" "1" "not-last-window close leaves session with one window"

remaining=$(tmux -L "$TMUX_SOCK" list-windows -t "=alpha" -F '#{@wt_path}')
wt_assert_eq "$remaining" "$WTP2" "the remaining window is the one that was not closed"

# --- last-window branch: closing the only remaining window kills the session ---
w2=$(tmux -L "$TMUX_SOCK" list-windows -a -F "#{window_id}${T}#{@wt_path}" | awk -F"$T" -v p="$WTP2" '$2==p{print $1}')
tmux -L "$TMUX_SOCK" select-window -t "$w2"
wt close

if tmux -L "$TMUX_SOCK" has-session -t "=alpha" 2>/dev/null; then
  still_there=yes
else
  still_there=no
fi
wt_assert_eq "$still_there" "no" "last-window close kills the session"

# --- the worktree itself must never be touched on disk ---
if [ -d "$WTP1" ] && [ -d "$WTP2" ]; then
  survived=yes
else
  survived=no
fi
wt_assert_eq "$survived" "yes" "worktrees remain on disk after close"
