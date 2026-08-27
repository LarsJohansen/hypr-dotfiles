# tmux + Claude Code worktree orchestration

Date: 2026-08-27
Status: approved design, not yet implemented

## Problem

Running several Claude Code sessions in parallel across git worktrees currently
means manual `tmux new-window`, manual `cd`, and no way to tell at a glance which
session is working, which is blocked on a permission prompt, and which is idle.

## Goals

- Switch between every worktree of every tracked repo from one fuzzy picker.
- One tmux window per worktree; one tmux session per repo.
- The status bar answers "which window needs me?" without switching to it.
- Per-worktree git state (branch, dirty, ahead/behind, diffstat) visible in the
  same place.

## Non-goals

- Owning worktree lifecycle. Claude Code creates most worktrees; `wt` discovers
  them. `wt` never deletes a worktree or a branch.
- Desktop notifications. Explicitly declined.
- A grid/dashboard view of several agents at once.

## Constraints discovered during design

These were verified on this machine (tmux 3.7b) and drive the architecture.

1. **`#()` does not work inside `window-status-format`.** A format of
   `#(basename #{pane_current_path})` renders empty for every window — tmux does
   not expand per-window `#{}` inside a shell-command substitution. Anything the
   status bar shows must therefore already be sitting in a window option by the
   time the status line renders. This is the reason a background poller exists.
2. **Window user-options and format conditionals do work.** Setting
   `@cc_state=waiting` on a window and rendering
   `#{?#{==:#{@cc_state},waiting},●,○}` correctly produced `●`.
3. **User-option truthiness behaves.** `#{?@wt_git,YES,NO}` yields `NO` when the
   option is unset *and* when it is set to the empty string, so the poller can
   blank a fragment without the status bar rendering a stray separator.
4. **Discovery is cheap enough to do eagerly.** 48 repos across the three roots
   are found in ~13ms; `git worktree list` costs ~2ms per repo. No cache layer.
5. **Worktrees arrive from three places and do not agree on location:**
   | Origin | Location |
   |---|---|
   | native `EnterWorktree` tool | `<repo>/.claude/worktrees/<name>`, hardcoded |
   | superpowers `using-git-worktrees` | `<repo>/.worktrees/`, overridable via CLAUDE.md |
   | manual / `wt new` | `<repo>-worktrees/<branch>` (our convention) |
   Discovery must therefore go through `git worktree list`, which finds all
   three regardless of path. The convention applies only to worktrees `wt`
   itself creates, plus those Claude creates once CLAUDE.md declares it.

## Architecture

Five components. State lives entirely in tmux window options, so it is created
with the window, is visible to the status format with zero I/O, and disappears
when the window closes. There are no state files and no cleanup path.

| Component | Path (stow package) | Responsibility |
|---|---|---|
| `wt` | `tmux/.local/bin/wt` | discovery, picker, open/new/close |
| `wt-hook` | `tmux/.local/bin/wt-hook` | Claude hook receiver → window options |
| `wt-poll` | `tmux/.local/bin/wt-poll` | periodic git state + liveness expiry |
| tmux config | `tmux/.tmux.conf` | keybinds, status format, poller startup |
| Claude config | `claude/.claude/settings.json`, `claude/.claude/CLAUDE.md` | hook registration, worktree convention |

### Data flow

```
Claude Code event ──stdin JSON──> wt-hook ──> tmux set -w @cc_state/@cc_since
                                                     │
git repo on disk ──5s loop──> wt-poll ──> tmux set -w @wt_git/@cc_elapsed
                                                     │
                                                     v
                                          window-status-format
                                        (pure format expansion)
```

### Window option schema

Set on each window `wt` manages:

| Option | Writer | Values |
|---|---|---|
| `@wt_path` | `wt open` | absolute worktree path; also the marker that a window is wt-managed |
| `@cc_state` | `wt-hook`, `wt-poll` | `busy` / `attention` / `idle` / unset |
| `@cc_since` | `wt-hook` | epoch seconds of last state transition |
| `@cc_elapsed` | `wt-poll` | pre-rendered elapsed string, e.g. `4m12s` (only while `busy`) |
| `@wt_git` | `wt-poll` | pre-rendered git fragment, e.g. `↑3 +142/-18 *` |

`@wt_path` is the lookup key. Windows are matched by this option rather than by
`pane_current_path`, so `cd`-ing inside a pane cannot break the association.

## Component specs

### `wt`

Subcommands:

- `wt list` — tab-separated `repo<TAB>worktree_path<TAB>branch<TAB>open_window_id`.
  Machine-readable; the picker and the tests both consume it.
- `wt menu` — `display-popup -E` running fzf over `wt list`. Enter → `wt open`.
- `wt open <path>` — idempotent. If a window already has `@wt_path == <path>`,
  select it. Otherwise create it in the repo's session (creating the session if
  needed), apply the layout, and set `@wt_path`.
- `wt new [branch]` — create a worktree, then `wt open` it.
- `wt close` — kill the current window only. The worktree stays on disk. If it
  is the session's last window, kill the session too rather than leaving an
  empty one behind.

**Discovery algorithm.** Roots default to `~/Projects ~/dev ~/.dotfiles`,
overridable via `WT_ROOTS`. Repos live at mixed depths (`~/dev/blog` is depth 1,
`~/dev/sgdn/*` is depth 2), so scan with
`find "$root" -maxdepth 3 -name .git -prune -print`. `-prune` stops descent into
`.git` itself. For each hit: if `.git` is a **directory** it is a main checkout —
run `git worktree list --porcelain` on it. If `.git` is a **file** it is a linked
worktree, so skip it; it will be enumerated via its main checkout. This avoids
double-listing and finds worktrees in all three locations from constraint 5.

**Naming.**
- Session name = repo directory basename, with leading dots stripped and `.` `:`
  replaced by `-` (tmux target syntax treats `.` and `:` specially). `.dotfiles`
  → session `dotfiles`.
- Window name = branch name with `/` → `-`. `wt-poll` renames the window if the
  branch changes, so the name stays truthful.

**`wt new` placement.** For a main checkout at `<parent>/<repo>`, the worktree
goes to `<parent>/<repo>-worktrees/<branch with / → ->`. The parent directory is
created if absent. If the branch already has a worktree, `wt new` does not error
— it falls through to `wt open` on the existing one.

**Layout.** Left pane runs `claude` in the worktree; right pane is a plain shell
at 35% width. Uses `split-window -h -l 35%` (tmux 3.x; `-p` is deprecated).

### `wt-hook`

Invoked by Claude Code hooks with the event JSON on stdin. Usage:
`wt-hook <state>` where state is `busy`, `attention`, or `clear`.

**Resolving the target window.** Primary: `$TMUX_PANE`, inherited from the pane
Claude was launched in, resolved via
`tmux display -t "$TMUX_PANE" -p '#{window_id}'`. Fallback if `TMUX_PANE` is
unset: read `.cwd` from the hook JSON with `jq` and find the window whose
`@wt_path` is a prefix of it. **This inheritance is unverified and is the first
thing implementation must confirm** — the fallback exists because the whole
design hangs off it.

**Attention suppression.** If the target window is currently the active window
of an attached client, `attention` is not set. The flag means "something happened
while you weren't looking", not merely "something happened".

Exits 0 unconditionally and never writes to stdout — a failing hook must not
disturb the Claude session.

### `wt-poll`

Started from `tmux.conf` via `run-shell -b`. Guarded against the double-start
that `prefix r` would otherwise cause by wrapping in `flock -n` on a lockfile;
a second invocation exits 1 immediately and harmlessly.

Each iteration, for every window with `@wt_path` set:

1. Compute and set `@wt_git`: branch (short SHA if detached), `*` if dirty,
   `↑n`/`↓n` ahead/behind if upstream exists, `+a/-b` diffstat. Uses
   `--ignore-submodules` so a dirty submodule does not mark the worktree dirty.
2. Set `@cc_elapsed` from `@cc_since` while `@cc_state` is `busy`.
3. **Liveness expiry:** if `@cc_state` is set but no pane in the window is
   running `claude`, clear `@cc_state`. This is why a crashed Claude does not
   leave a stuck `◐` — it is a process check, not a timeout, so a legitimately
   long-running turn is never wrongly cleared.
4. Rename the window if its branch changed.

Exits when `tmux ls` fails, so it dies with the tmux server. Interval defaults
to 5s (`WT_POLL_INTERVAL`), matching the existing `status-interval 5`.

Supports `--once` to run a single iteration and exit — the seam the tests use.

### tmux config additions

```
set -g window-status-format '#I:#W#{?#{==:#{@cc_state},busy},#[fg=yellow] ◐#{@cc_elapsed},}#{?#{==:#{@cc_state},attention},#[fg=red] ●,}#{?@wt_git, #[fg=blue]#{@wt_git},}'

bind w run-shell 'wt menu'
bind W command-prompt -p "branch:" 'run-shell "wt new %%"'
bind x run-shell 'wt close'

set-hook -g pane-focus-in 'if -F "#{==:#{@cc_state},attention}" "set -w @cc_state idle"'
run-shell -b 'flock -n /tmp/wt-poll.#{USER}.lock ~/.local/bin/wt-poll'
```

`prefix x` overrides tmux's default `kill-pane` binding — deliberate, and worth
calling out because it changes muscle memory.

### Claude config additions

`claude/.claude/settings.json` gains a `hooks` block:

| Event | Call | Meaning |
|---|---|---|
| `UserPromptSubmit` | `wt-hook busy` | a turn started |
| `Notification` | `wt-hook attention` | permission prompt or idle nudge |
| `Stop` | `wt-hook attention` | turn finished, awaiting you |
| `SessionEnd` | `wt-hook clear` | session gone |

`PreToolUse`/`PostToolUse` are deliberately not hooked — they fire far too often
to be worth a tmux round-trip per call.

`claude/.claude/CLAUDE.md` gains the worktree convention, which
`using-git-worktrees` reads and honors:

> Worktree directory preference: create git worktrees in a sibling directory
> named `<repo>-worktrees/`, e.g. `~/Projects/trav-analyse-worktrees/<branch>`.
> Do not use `.worktrees/` inside the repo.

## Rendered result

```
[trav-analyse] 1:main  2:feat-odds ●↑3 +142/-18*  3:fix-drift ◐4m12s  4:refactor
                        ^unseen, ahead, dirty      ^working

A clean, idle worktree renders as bare `#I:#W` — no icon, no git fragment.
Absence is the quiet state; every glyph means something needs reading.
```

## Error handling

| Case | Behavior |
|---|---|
| `wt` run outside tmux | clear error, exit 1 |
| repo with no linked worktrees | still listed — its main checkout is a worktree |
| detached HEAD | branch column shows short SHA |
| `wt new` on an existing branch | falls through to `wt open` |
| `TMUX_PANE` unset in hook | fall back to `cwd` matching |
| `wt-hook` fails for any reason | exit 0 silently; never disturb Claude |
| poller already running | `flock` exits 1, no second loop |
| tmux server dies | poller's `tmux ls` fails, loop exits |

## Testing

No test framework exists in this repo, so tests are a `tmux/tests/` directory of
shell scripts runnable individually and via a `run.sh`. Each drives a real tmux
server started with `-f /dev/null -L wt-test` so the user's live session is never
touched.

1. `wt list` against a scratch repo with two worktrees → asserts exact output.
2. `wt open` called twice on one path → asserts exactly one window exists.
3. `wt-hook busy` with `TMUX_PANE` set → asserts `@cc_state == busy`.
4. Suppression, both branches. With no client attached, `wt-hook attention` on
   the active window → asserts `@cc_state == attention` (nothing to suppress).
   Then with a client attached to the test server through a pty, repeat →
   asserts `@cc_state` is not set. The pty is the awkward part of this test; if
   it proves flaky, assert the predicate function directly instead of the
   end-to-end behavior.
5. `wt-hook` with `TMUX_PANE` unset and `cwd` in JSON → asserts fallback resolves.
6. `wt-poll --once` on a window in a dirty repo → asserts `@wt_git` is non-empty
   and contains the dirty marker.
7. `wt-poll --once` on a window whose `@cc_state` is set but with no `claude`
   process → asserts `@cc_state` was cleared.
8. `shellcheck` over all three scripts.

## Open questions for implementation

1. Does Claude's hook subprocess inherit `$TMUX_PANE`? Verify before anything
   else; the `cwd` fallback covers a no, but the answer decides which path is
   primary.
2. Exact `hooks` schema in `settings.json` (whether `matcher` is required for
   `Notification` / `Stop`). Verify against the installed Claude Code version
   rather than from memory.

## Deferred

- Catppuccin Macchiato colors for the status bar, to match the hypr theme. The
  design uses bare `yellow`/`red`/`blue` for now.
- `wt` awareness of `.claude/worktrees/` naming so native `EnterWorktree`
  worktrees get nicer window names than their random slugs.
