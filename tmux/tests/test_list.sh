#!/bin/sh
set -u
. "$(dirname "$0")/helpers.sh"
trap wt_test_teardown EXIT
wt_test_setup

wt_make_repo alpha feat/one fix-two >/dev/null
wt_make_repo beta >/dev/null

out=$(wt list | sort)

# alpha: main checkout + 2 worktrees; beta: main checkout only = 4 rows
wt_assert_eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "4" "lists 4 worktrees"
T=$(printf '\t')
wt_assert_eq "$(printf '%s\n' "$out" | grep -c "^alpha${T}$WT_ROOTS/alpha${T}main${T}\$")" "1" "alpha main checkout"
wt_assert_eq "$(printf '%s\n' "$out" | grep -c "^alpha${T}$WT_ROOTS/alpha-worktrees/feat-one${T}feat/one${T}\$")" "1" "branch with slash keeps real name"
wt_assert_eq "$(printf '%s\n' "$out" | grep -c "^beta${T}$WT_ROOTS/beta${T}main${T}\$")" "1" "beta main checkout"

# linked worktrees must not be double-listed as their own repo
wt_assert_eq "$(printf '%s\n' "$out" | cut -f1 | sort -u | tr '\n' ',')" "alpha,beta," "only real repos named"
