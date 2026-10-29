#!/bin/sh
# wt _live / _livepick: windows with a Claude pane, any session.
set -u
. "$(dirname "$0")/helpers.sh"
trap wt_test_teardown EXIT
wt_test_setup

R=$(wt_make_repo alpha)
tmux -f /dev/null -L "$TMUX_SOCK" new-session -d -s alpha -c "$R"
export TMUX WT_CLAUDE_PROCS
TMUX=$(tmux -L "$TMUX_SOCK" display -p '#{socket_path}'),0,0

# `sleep` stands in for Claude: macOS names a process after the real binary, so
# neither a copy nor a symlink called claude shows up as "claude" there.
WT_CLAUDE_PROCS=sleep
tmux -L "$TMUX_SOCK" new-window -t alpha -n agent -c "$R" "sleep 30"
LIVE=$(tmux -L "$TMUX_SOCK" list-windows -t alpha -F '#{window_id}' | tail -n1)
i=0
until tmux -L "$TMUX_SOCK" list-panes -t "$LIVE" -F '#{pane_current_command}' | grep -qx sleep; do
  i=$((i + 1))
  if [ "$i" -gt 50 ]; then
    echo "FAIL precondition: pane never ran the stand-in" >&2
    tmux -L "$TMUX_SOCK" list-panes -a -F '  saw: #{pane_current_command} dead=#{pane_dead}' >&2
    exit 1
  fi
  sleep 0.1
done

rows=$(wt _live)
wt_assert_eq "$(printf '%s\n' "$rows" | grep -c .)" "1" "only the window running claude is listed"
wt_assert_eq "$(printf '%s' "$rows" | cut -f1)" "$LIVE" "row starts with its window id"
wt_assert_contains "$rows" "agent" "row shows the window name"

# a second claude pane in the same window still gives one row
tmux -L "$TMUX_SOCK" split-window -t "$LIVE" -c "$R" "sleep 30"
sleep 0.3
wt_assert_eq "$(wt _live | grep -c .)" "1" "one row per window, not per pane"

wt_assert_eq "$(WT_PICK_CMD='head -n1' wt _livepick)" "$LIVE" "_livepick prints the chosen window id"

# the defaults match the real process names, and nothing else
WT_CLAUDE_PROCS=
unset WT_CLAUDE_PROCS
wt_assert_eq "$(wt _live | grep -c .)" "0" "sleep is not claude by default"
