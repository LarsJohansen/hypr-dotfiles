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
wt_assert_contains "$FRAG" "↑1" "ahead count appears when local has unpushed commits"
wt_assert_contains "$FRAG" "↓1" "behind count appears when upstream has unfetched commits"

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
