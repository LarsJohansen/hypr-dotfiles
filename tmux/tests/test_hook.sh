#!/bin/sh
set -u
. "$(dirname "$0")/helpers.sh"
trap wt_test_teardown EXIT
wt_test_setup

R=$(wt_make_repo alpha)
tmux -f /dev/null -L "$TMUX_SOCK" new-session -d -s alpha -c "$R"
WID=$(tmux -L "$TMUX_SOCK" list-windows -t alpha -F '#{window_id}' | head -n1)
PANE=$(tmux -L "$TMUX_SOCK" list-panes -t "$WID" -F '#{pane_id}' | head -n1)
tmux -L "$TMUX_SOCK" set -w -t "$WID" @wt_path "$R"
export TMUX
TMUX=$(tmux -L "$TMUX_SOCK" display -p '#{socket_path}'),0,0

opt() { tmux -L "$TMUX_SOCK" show -w -t "$1" -v "$2" 2>/dev/null; }

# `show -w` (no -v) lists only the options explicitly set on that window; an
# unset option is simply absent from the listing. `-v` alone cannot tell
# "unset" apart from "set to the empty string" -- it prints "" for both -- so
# the clear-really-unsets assertions below use this instead of opt().
is_unset() { ! tmux -L "$TMUX_SOCK" show -w -t "$1" 2>/dev/null | grep -q "^$2 "; }

# 1. TMUX_PANE path
echo '{}' | TMUX_PANE="$PANE" wt-hook busy
wt_assert_eq "$(opt "$WID" @cc_state)" "busy" "busy set via TMUX_PANE"
wt_assert_eq "$(opt "$WID" @cc_since | grep -cE '^[0-9]+$')" "1" "@cc_since is epoch seconds"

# 2. no client attached, so nothing to suppress
echo '{}' | TMUX_PANE="$PANE" wt-hook attention
wt_assert_eq "$(opt "$WID" @cc_state)" "attention" "attention set when no client attached"
# NOTE: the spec's other suppression branch (client attached AND window active
# => flag NOT set) needs a pty and is covered by manual acceptance step 5
# instead. The predicate itself is one tmux format: #{&&:window_active,session_attached}.

# 3. clear unsets @cc_state, @cc_since AND @cc_elapsed -- not just the first.
# @cc_elapsed is never written by busy/attention, so it must be pre-set here
# or the is_unset assertion below would trivially pass even if wt-hook's
# clear branch dropped that line entirely.
tmux -L "$TMUX_SOCK" set -w -t "$WID" @cc_elapsed 42
echo '{}' | TMUX_PANE="$PANE" wt-hook clear
wt_assert_eq "$(opt "$WID" @cc_state)" "" "clear reads @cc_state as empty"
wt_assert_eq "$(is_unset "$WID" @cc_state; echo $?)" "0" "clear truly unsets @cc_state (absent, not just empty)"
wt_assert_eq "$(is_unset "$WID" @cc_since; echo $?)" "0" "clear truly unsets @cc_since"
wt_assert_eq "$(is_unset "$WID" @cc_elapsed; echo $?)" "0" "clear truly unsets @cc_elapsed"

# 4a. cwd fallback resolves to the more specific of two open windows whose
# @wt_path values collide as strings ("feat" is a string-prefix of "feat-two").
FEAT=$(wt_make_repo feat)
FEAT2=$(wt_make_repo feat-two)
WID_FEAT=$(tmux -L "$TMUX_SOCK" new-window -d -t alpha -P -F '#{window_id}')
tmux -L "$TMUX_SOCK" set -w -t "$WID_FEAT" @wt_path "$FEAT"
WID_FEAT2=$(tmux -L "$TMUX_SOCK" new-window -d -t alpha -P -F '#{window_id}')
tmux -L "$TMUX_SOCK" set -w -t "$WID_FEAT2" @wt_path "$FEAT2"

printf '{"cwd":"%s/subdir"}' "$FEAT2" | env -u TMUX_PANE wt-hook busy
wt_assert_eq "$(opt "$WID_FEAT2" @cc_state)" "busy" "cwd under feat-two resolves to the feat-two window"
wt_assert_eq "$(opt "$WID_FEAT" @cc_state)" "" "cwd under feat-two does not misroute to the open feat window"

# 4b. the actual regression: only the SHORTER window is open, and the cwd
# belongs to an unrelated sibling directory that merely shares its string
# prefix (feat vs feat-two -- same shape as the user's real Dahl.Core vs
# Dahl.Core.AppConfiguration). A naive index(c,$2)==1 prefix match (the
# pre-fix code) wrongly resolves this to the feat window; the path-boundary
# fix must leave it unresolved (no window open for feat-two here).
tmux -L "$TMUX_SOCK" kill-window -t "$WID_FEAT2"
printf '{"cwd":"%s/subdir"}' "$FEAT2" | env -u TMUX_PANE wt-hook busy
wt_assert_eq "$(opt "$WID_FEAT" @cc_state)" "" "unrelated sibling dir does not misroute to the string-prefix-colliding window"

# 5. never fails loudly, whatever happens -- and prints nothing on stdout,
# which is the single most important behavioral requirement of the hook.
OUT=$(echo 'not json' | env -u TMUX_PANE wt-hook busy 2>/dev/null)
RC=$?
wt_assert_eq "$RC" "0" "hook exits 0 on garbage input"
wt_assert_eq "$OUT" "" "hook prints nothing to stdout on garbage input"

OUT2=$(env -u TMUX_PANE wt-hook bogus-state < /dev/null 2>/dev/null)
RC2=$?
wt_assert_eq "$RC2" "0" "hook exits 0 on an unknown state word"
wt_assert_eq "$OUT2" "" "hook prints nothing to stdout on an unknown state word"

# 6. session-window-changed clears @cc_state=attention on the window being
# switched TO, and leaves every other window's flag untouched. This is the
# actual mechanism wired into tmux.conf: pane-focus-in (tried first) never
# fires for in-tmux window switches -- only for OS-level terminal focus -- so
# it never cleared anything in practice. Verified live against tmux 3.7b and
# replaced. This block also fails loudly if tmux.conf's hook line drifts from
# what is exercised here.
HOOK_ACTION='if -F "#{==:#{@cc_state},attention}" "set -w @cc_state idle"'
grep -qF "set-hook -g session-window-changed '$HOOK_ACTION'" "$WT_REPO_ROOT/.tmux.conf" \
  || { echo "FAIL tmux.conf session-window-changed hook line is missing or has drifted from what this test exercises" >&2; exit 1; }
tmux -L "$TMUX_SOCK" set-hook -g session-window-changed "$HOOK_ACTION"

tmux -L "$TMUX_SOCK" set -w -t "$WID" @cc_state attention
tmux -L "$TMUX_SOCK" set -w -t "$WID_FEAT" @cc_state attention
tmux -L "$TMUX_SOCK" select-window -t "$WID_FEAT"
i=0
while [ "$i" -lt 40 ] && [ "$(opt "$WID_FEAT" @cc_state)" = "attention" ]; do i=$((i + 1)); sleep 0.05; done
wt_assert_eq "$(opt "$WID_FEAT" @cc_state)" "idle" "switching TO a window clears its own attention flag (targets the window switched TO)"
wt_assert_eq "$(opt "$WID" @cc_state)" "attention" "switching away leaves the previous window's flag untouched (does not target the FROM window)"
