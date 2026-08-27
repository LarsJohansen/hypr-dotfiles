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

opt() { tmux -L "$TMUX_SOCK" show -w -t "$WID" -v "$1" 2>/dev/null; }

# 1. TMUX_PANE path
echo '{}' | TMUX_PANE="$PANE" wt-hook busy
wt_assert_eq "$(opt @cc_state)" "busy" "busy set via TMUX_PANE"
wt_assert_eq "$(opt @cc_since | grep -cE '^[0-9]+$')" "1" "@cc_since is epoch seconds"

# 2. no client attached, so nothing to suppress
echo '{}' | TMUX_PANE="$PANE" wt-hook attention
wt_assert_eq "$(opt @cc_state)" "attention" "attention set when no client attached"
# NOTE: the spec's other suppression branch (client attached AND window active
# => flag NOT set) needs a pty and is covered by manual acceptance step 5
# instead. The predicate itself is one tmux format: #{&&:window_active,session_attached}.

# 3. clear
echo '{}' | TMUX_PANE="$PANE" wt-hook clear
wt_assert_eq "$(opt @cc_state)" "" "clear unsets @cc_state"

# 4. cwd fallback when TMUX_PANE is absent
printf '{"cwd":"%s/subdir"}' "$R" | env -u TMUX_PANE wt-hook busy
wt_assert_eq "$(opt @cc_state)" "busy" "cwd prefix match resolves the window"

# 5. never fails loudly, whatever happens
echo 'not json' | env -u TMUX_PANE wt-hook busy 2>/dev/null
wt_assert_eq "$?" "0" "hook exits 0 on garbage input"
