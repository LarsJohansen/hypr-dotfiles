#!/bin/sh
set -u
. "$(dirname "$0")/helpers.sh"
trap wt_test_teardown EXIT
wt_test_setup

R=$(wt_make_repo alpha)
tmux -f /dev/null -L "$TMUX_SOCK" new-session -d -s alpha -c "$R"
WID=$(tmux -L "$TMUX_SOCK" list-windows -t alpha -F '#{window_id}' | head -n1)
tmux -L "$TMUX_SOCK" set -w -t "$WID" @wt_path "$R"
export TMUX
TMUX=$(tmux -L "$TMUX_SOCK" display -p '#{socket_path}'),0,0
opt() { tmux -L "$TMUX_SOCK" show -w -t "$WID" -v "$1" 2>/dev/null; }

# clean repo -> a fragment with the branch and no dirty marker
wt-poll --once
wt_assert_contains "$(opt @wt_git)" "main" "git fragment names the branch"
case "$(opt @wt_git)" in *'*'*) echo "FAIL clean repo marked dirty" >&2; exit 1;; esac
printf 'ok   clean repo has no dirty marker\n'

# dirty repo -> marker appears
echo change >> "$R/README"
wt-poll --once
wt_assert_contains "$(opt @wt_git)" "*" "dirty repo gets a marker"

# elapsed rendered only while busy
tmux -L "$TMUX_SOCK" set -w -t "$WID" @cc_state busy
tmux -L "$TMUX_SOCK" set -w -t "$WID" @cc_since "$(( $(date +%s) - 125 ))"
wt-poll --once
wt_assert_eq "$(opt @cc_elapsed)" "2m5s" "elapsed formatted from @cc_since"

# liveness: no pane is running claude, so a stale state must be cleared
wt_assert_eq "$(opt @cc_state)" "" "stale @cc_state cleared when no claude pane"

# a window with no @wt_path is left completely alone
tmux -L "$TMUX_SOCK" new-window -t alpha
OTHER=$(tmux -L "$TMUX_SOCK" list-windows -t alpha -F '#{window_id}' | tail -n1)
wt-poll --once
wt_assert_eq "$(tmux -L "$TMUX_SOCK" show -w -t "$OTHER" -v @wt_git 2>/dev/null)" "" "unmanaged window untouched"

# ahead/behind vs not-tracking, kept distinct from the clean/dirty cases above
# so a fixture with only one axis of state cannot make this assertion pass
# for the wrong reason.
BETA=$(wt_make_repo beta)
REMOTE="$WT_TMP/beta-remote.git"
git init -q --bare "$REMOTE"
git -C "$BETA" remote add origin "$REMOTE"
git -C "$BETA" push -q -u origin main
CLONE="$WT_TMP/beta-clone"
git clone -q "$REMOTE" "$CLONE"
git -C "$CLONE" config user.email t@t.t
git -C "$CLONE" config user.name t
echo remote >> "$CLONE/README"
git -C "$CLONE" commit -qam remote
git -C "$CLONE" push -q origin main
echo local >> "$BETA/README2"
git -C "$BETA" add README2
git -C "$BETA" commit -qam local
git -C "$BETA" fetch -q origin

tmux -L "$TMUX_SOCK" new-window -t alpha -c "$BETA"
WID2=$(tmux -L "$TMUX_SOCK" list-windows -t alpha -F '#{window_id}' | tail -n1)
tmux -L "$TMUX_SOCK" set -w -t "$WID2" @wt_path "$BETA"
wt-poll --once
FRAG=$(tmux -L "$TMUX_SOCK" show -w -t "$WID2" -v @wt_git 2>/dev/null)
# Anchored, not `wt_assert_contains`: "*1" would also match "*10", which
# would silently pass this assertion for the wrong count.
case "$FRAG" in
  *' ↑1 '*|*' ↑1') : ;;
  *) echo "FAIL ahead count not exact (e.g. ↑10 would wrongly pass contains): [$FRAG]" >&2; exit 1 ;;
esac
printf 'ok   ahead count appears exactly when local has unpushed commits\n'
case "$FRAG" in
  *' ↓1 '*|*' ↓1') : ;;
  *) echo "FAIL behind count not exact (e.g. ↓10 would wrongly pass contains): [$FRAG]" >&2; exit 1 ;;
esac
printf 'ok   behind count appears exactly when upstream has unfetched commits\n'

# a repo with no upstream configured must not show ahead/behind noise
GAMMA=$(wt_make_repo gamma)
tmux -L "$TMUX_SOCK" new-window -t alpha -c "$GAMMA"
WID3=$(tmux -L "$TMUX_SOCK" list-windows -t alpha -F '#{window_id}' | tail -n1)
tmux -L "$TMUX_SOCK" set -w -t "$WID3" @wt_path "$GAMMA"
wt-poll --once
FRAG3=$(tmux -L "$TMUX_SOCK" show -w -t "$WID3" -v @wt_git 2>/dev/null)
case "$FRAG3" in
  *'↑'*|*'↓'*) echo "FAIL no-upstream repo shows ahead/behind marker: [$FRAG3]" >&2; exit 1 ;;
esac
printf 'ok   no-upstream repo has no ahead/behind marker\n'

# liveness: @cc_state must SURVIVE while a pane is genuinely running claude.
# This is the safety-critical direction the "stale state cleared" case above
# does not exercise: a bug inverting that condition would clear every real
# session's busy flag while passing the rest of this suite. A stub `claude`
# on PATH gives pane_current_command a real, checkable "claude" without
# needing the actual CLI. A copy of a real binary is used rather than a
# `#!/bin/sh` script: Linux reports a shebang script's /proc/pid/comm as the
# INTERPRETER's name ("sh"), not the script's, so pane_current_command would
# never actually read "claude" and the precondition check below would rightly
# fail every run.
mkdir -p "$WT_TMP/bin"
cp "$(command -v sleep)" "$WT_TMP/bin/claude"
chmod +x "$WT_TMP/bin/claude"

tmux -L "$TMUX_SOCK" new-window -t alpha -c "$R" "PATH=\"$WT_TMP/bin:\$PATH\" claude 30"
LIVE=$(tmux -L "$TMUX_SOCK" list-windows -t alpha -F '#{window_id}' | tail -n1)
tmux -L "$TMUX_SOCK" set -w -t "$LIVE" @wt_path "$R"

i=0
while [ "$(tmux -L "$TMUX_SOCK" list-panes -t "$LIVE" -F '#{pane_current_command}' 2>/dev/null)" != claude ]; do
  i=$((i + 1))
  if [ "$i" -gt 50 ]; then
    echo "FAIL precondition: pane never ran claude (stub did not start in time)" >&2
    exit 1
  fi
  sleep 0.1
done
# Assert the precondition explicitly before asserting the outcome: if this
# never reads "claude", the outcome assertion below would pass vacuously.
wt_assert_eq "$(tmux -L "$TMUX_SOCK" list-panes -t "$LIVE" -F '#{pane_current_command}')" "claude" \
  "precondition: pane_current_command reports claude"

tmux -L "$TMUX_SOCK" set -w -t "$LIVE" @cc_state busy
tmux -L "$TMUX_SOCK" set -w -t "$LIVE" @cc_since "$(date +%s)"
wt-poll --once
wt_assert_eq "$(tmux -L "$TMUX_SOCK" show -w -t "$LIVE" -v @cc_state 2>/dev/null)" "busy" \
  "@cc_state survives while claude pane is actually running"

# detached HEAD: no branch, wt_git_fragment falls back to the short SHA.
DELTA=$(wt_make_repo delta)
SHA=$(git -C "$DELTA" rev-parse HEAD)
git -C "$DELTA" checkout -q --detach "$SHA"
. "$WT_LIB"
SHORT=$(git -C "$DELTA" rev-parse --short HEAD)
wt_assert_eq "$(wt_git_fragment "$DELTA")" "$SHORT" \
  "detached HEAD falls back to short SHA when there is no branch"
