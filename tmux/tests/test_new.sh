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

# --- context directory (regression: wt new used to resolve the repo from $PWD,
# --- so a keybinding created the worktree in whatever repo the tmux client was
# --- attached from -- or failed outright when that was not a repo at all)
wt_make_repo beta >/dev/null
BETA="$WT_ROOTS/beta"

# from OUTSIDE any repo, an explicit context dir must still resolve correctly
BETA_EXP="$WT_ROOTS/beta-worktrees/ctx-branch"
(cd "$WT_TMP" && wt new ctx-branch "$BETA")
wt_assert_eq "$([ -d "$BETA_EXP" ] && echo yes || echo no)" "yes" \
  "wt new <branch> <dir> uses <dir>'s repo, not \$PWD"
wt_assert_eq "$(git -C "$BETA_EXP" branch --show-current)" "ctx-branch" \
  "context-dir worktree is on the requested branch"

# the context dir must win even when $PWD is a DIFFERENT valid repo
ALPHA_CTX="$WT_ROOTS/beta-worktrees/from-alpha-cwd"
(cd "$WT_ROOTS/alpha" && wt new from-alpha-cwd "$BETA")
wt_assert_eq "$([ -d "$ALPHA_CTX" ] && echo yes || echo no)" "yes" \
  "context dir beats \$PWD when both are repos"
wt_assert_eq "$([ -d "$WT_ROOTS/alpha-worktrees/from-alpha-cwd" ] && echo yes || echo no)" "no" \
  "nothing created in the \$PWD repo"

# a non-repo context dir still fails loudly rather than silently guessing
rc=0
(cd "$WT_ROOTS/alpha" && wt new should-not-exist "$WT_TMP") 2>/dev/null || rc=$?
wt_assert_eq "$rc" "1" "non-repo context dir exits 1"

# A context dir that does not exist reports "no such directory", distinct from
# an existing non-repo's "not in a git repo". Both exit 1 -- wt_main_for would
# fail either way -- so the message is the only thing that distinguishes them,
# and therefore the only thing worth asserting.
rc=0
err=$( (cd "$WT_ROOTS/alpha" && wt new never-created "$WT_TMP/no-such-dir") 2>&1 ) || rc=$?
wt_assert_eq "$rc" "1" "nonexistent context dir exits 1"
wt_assert_contains "$err" "no such directory" "nonexistent ctx says 'no such directory'"
wt_assert_eq "$([ -d "$WT_ROOTS/alpha-worktrees/never-created" ] && echo yes || echo no)" "no" \
  "nonexistent context dir creates nothing"
