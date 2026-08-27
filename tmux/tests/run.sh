#!/bin/sh
# Runs every test_*.sh in this directory.
set -u
d=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fail=0
for t in "$d"/test_*.sh; do
  printf '\n=== %s ===\n' "$(basename "$t")"
  if sh "$t"; then :; else fail=1; fi
done
[ "$fail" -eq 0 ] && printf '\nALL PASS\n' || printf '\nFAILURES\n'
exit "$fail"
