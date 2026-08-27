#!/bin/sh
set -u
. "$(dirname "$0")/helpers.sh"
trap wt_test_teardown EXIT
wt_test_setup

wt_make_repo alpha feat/one >/dev/null

# WT_PICK_CMD substitutes a deterministic picker for fzf
rows=$(WT_PICK_CMD='head -n1' wt _pick)
wt_assert_contains "$rows" "$WT_ROOTS/alpha" "_pick prints a worktree path"
wt_assert_eq "$(printf '%s' "$rows" | wc -l | tr -d ' ')" "0" "_pick prints exactly one line, no trailing newline count"

# the menu rows must be human-readable, not raw TSV
disp=$(wt _rows)
wt_assert_contains "$disp" "alpha" "rows include repo name"
wt_assert_contains "$disp" "feat/one" "rows include branch name"
