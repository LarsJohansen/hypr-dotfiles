#!/bin/sh
# Per-repo git config (wt.dir, wt.base, wt.claude) and the -d / -p flags.
set -u
. "$(dirname "$0")/helpers.sh"
trap wt_test_teardown EXIT
wt_test_setup

R=$(wt_make_repo gamma)
# A bare "server" repo as origin, one commit ahead of the local checkout, so a
# branch off origin/main only has that commit if wt fetched first.
SRV="$WT_TMP/server.git"
git clone -q --bare "$R" "$SRV"
git -C "$R" remote add origin "$SRV"
git -C "$R" fetch -q origin
UP="$WT_TMP/upstream"
git clone -q "$SRV" "$UP"
git -C "$UP" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m upstream
git -C "$UP" push -q origin main
UPSHA=$(git -C "$UP" rev-parse HEAD)

git -C "$R" config wt.dir .claude/worktrees
git -C "$R" config wt.base origin/main
git -C "$R" config wt.claude rclaude

tmux -f /dev/null -L "$TMUX_SOCK" new-session -d -s scratch -c "$R"
export TMUX WT_SHELL
TMUX=$(tmux -L "$TMUX_SOCK" display -p '#{socket_path}'),0,0
WT_SHELL=1

wt new BACK-1/thing "$R" >/dev/null
EXP="$R/.claude/worktrees/BACK-1-thing"
wt_assert_eq "$([ -d "$EXP" ] && echo yes || echo no)" "yes" "wt.dir places the worktree inside the repo"
wt_assert_eq "$(git -C "$EXP" rev-parse HEAD)" "$UPSHA" "wt.base is fetched, then used as the start point"
wt_assert_eq "$(git -C "$EXP" config --get branch.BACK-1/thing.remote || echo none)" "none" "new branch has no upstream"

# without config: old behaviour, sibling folder, start from HEAD
D=$(wt_make_repo delta)
wt new plain "$D" >/dev/null
wt_assert_eq "$([ -d "$WT_ROOTS/delta-worktrees/plain" ] && echo yes || echo no)" "yes" "default is still the sibling folder"

# command typed into the left pane
wt_assert_eq "$(wt _cmd "$EXP")" "rclaude" "wt.claude replaces claude"
wt_assert_eq "$(wt _cmd "$WT_ROOTS/delta-worktrees/plain")" "claude" "default command is claude"
printf 'do the thing\n' > "$WT_TMP/brief.md"
wt_assert_eq "$(wt -p "$WT_TMP/brief.md" _cmd "$EXP")" "rclaude \"\$(cat '$WT_TMP/brief.md')\"" "-p passes the brief via the pane's shell"

# -d: background window, id printed, current window unchanged
before=$(tmux -L "$TMUX_SOCK" display -p -t scratch '#{window_id}')
wid=$(wt -d new BACK-2/bg "$R")
wt_assert_contains "$wid" "@" "-d prints the new window id"
wt_assert_eq "$(tmux -L "$TMUX_SOCK" display -p -t scratch '#{window_id}')" "$before" "-d leaves focus alone"
again=$(wt -d open "$R/.claude/worktrees/BACK-2-bg")
wt_assert_eq "$again" "$wid" "-d open on an open worktree prints the same id"
