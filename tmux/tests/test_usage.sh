#!/bin/sh
set -u
. "$(dirname "$0")/helpers.sh"
trap wt_test_teardown EXIT
wt_test_setup

# Synthetic transcript corpus. WT_USAGE_ROOT points wt-usage away from ~/.claude.
export WT_USAGE_ROOT="$WT_TMP/projects"
export WT_USAGE_CACHE="$WT_TMP/usage-cache"
mkdir -p "$WT_USAGE_ROOT/proj-a"

now=$(date -u +%s)
mk() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

# two records inside the current 5h block, one 3 days old, one 30 days old
{
  printf '{"timestamp":"%s","message":{"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":40}}}\n' "$(mk $((now - 600)))"
  printf '{"timestamp":"%s","message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4}}}\n' "$(mk $((now - 1200)))"
  printf '{"timestamp":"%s","message":{"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":100}}}\n' "$(mk $((now - 259200)))"
  printf '{"timestamp":"%s","message":{"usage":{"input_tokens":999,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":999}}}\n' "$(mk $((now - 2592000)))"
} > "$WT_USAGE_ROOT/proj-a/session.jsonl"

j=$(wt-usage --json)

# 5h block: only the two recent records = 100 + 10 = 110
wt_assert_eq "$(printf '%s' "$j" | jq -r .block_tokens)" "110" "5h block sums only current-block records"
# 7d: those two plus the 3-day-old one = 110 + 200 = 310; the 30-day one excluded
wt_assert_eq "$(printf '%s' "$j" | jq -r .week_tokens)" "310" "7d window excludes records older than 7 days"

# no budgets configured -> raw counts, no percentage
out=$(wt-usage)
wt_assert_contains "$out" "5h" "renders a 5h segment"
wt_assert_contains "$out" "7d" "renders a 7d segment"
case "$out" in *%*) echo "FAIL percentage shown without a budget" >&2; exit 1;; esac
printf 'ok   no percentage without a configured budget\n'

# budgets configured -> percentage appears
out=$(WT_5H_BUDGET=220 WT_WEEK_BUDGET=620 wt-usage)
wt_assert_contains "$out" "50%" "5h percentage computed from WT_5H_BUDGET"

# cache: a second call within the TTL must not rescan
wt-usage >/dev/null
wt_assert_eq "$([ -f "$WT_USAGE_CACHE" ] && echo yes || echo no)" "yes" "cache file written"
echo '{"block_tokens":1,"week_tokens":2,"rendered":"SENTINEL"}' > "$WT_USAGE_CACHE"
wt_assert_contains "$(wt-usage)" "SENTINEL" "fresh cache is reused, not recomputed"

# stale cache is recomputed
touch -d "2 hours ago" "$WT_USAGE_CACHE" 2>/dev/null || touch -t 200001010000 "$WT_USAGE_CACHE"
case "$(wt-usage)" in *SENTINEL*) echo "FAIL stale cache reused" >&2; exit 1;; esac
printf 'ok   stale cache is recomputed\n'
