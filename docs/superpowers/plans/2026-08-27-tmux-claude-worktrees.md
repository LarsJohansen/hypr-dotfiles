# tmux + Claude Code Worktree Orchestration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Manage parallel Claude Code sessions across git worktrees from tmux, with a fuzzy switcher and a status bar that shows which session is working, which needs attention, and each worktree's git state.

**Architecture:** Three POSIX shell scripts sharing one sourced library. All state lives in tmux *window options* — no state files, no cleanup path. Claude Code hooks push instantaneous state (`@cc_state`); a `flock`-guarded background poller writes git state (`@wt_git`) and expires dead sessions. `window-status-format` is pure format expansion, because tmux cannot run `#()` per-window (see Global Constraints).

**Tech Stack:** POSIX `sh`, tmux 3.7b, git worktrees, `jq`, `fzf`, `flock` (util-linux). All present on this machine. `gum` is NOT installed — do not use it.

**Spec:** `docs/superpowers/specs/2026-08-27-tmux-claude-worktrees-design.md`

## Global Constraints

- **Shell:** POSIX `sh`, not bash. `set -eu` at the top of every script (repo `AGENTS.md`: "keep POSIX/`bash` style, `set -e` at the top").
- **shellcheck clean** with `-s sh` for all scripts. It is not currently installed; `sudo pacman -S shellcheck` is a **user action** — the agent cannot run sudo. If unavailable, skip that step and note it.
- **Stow layout:** every file lives under a top-level package dir mirroring its target. `tmux/.local/bin/wt` → `~/.local/bin/wt`.
- **Repo roots default:** `$HOME/Projects $HOME/dev $HOME/.dotfiles`, overridable via `WT_ROOTS`.
- **Worktree convention:** `wt new` creates at `<parent>/<repo>-worktrees/<branch with / → ->`.
- **Never delete a worktree or branch.** `wt` has no removal path. This is a hard rule from the spec.
- **Tests never touch the live tmux server.** Always `tmux -f /dev/null -L wt-test`.
- **Verified facts (do not re-litigate):**
  - `#()` inside `window-status-format` renders empty. Everything shown must already be in a window option.
  - `#{?@opt,A,B}` is false for both unset and empty-string. Blanking an option is safe.
  - Claude hook subprocesses **do** inherit `$TMUX_PANE` and `$TMUX`. Confirmed by running `claude` inside tmux with a `SessionStart` hook.
  - `pane_current_command` reports exactly `claude` for a running session. The liveness check is a string compare, not a process-tree walk.
  - Hook JSON on stdin always contains `.cwd`. Non-tool events use `"matcher": "*"`.
  - `#{&&:x,y}` and `#{USER}` are valid tmux formats.
  - `pane-focus-in` does NOT fire on tmux window switches (OS terminal focus
    only, and gated behind `focus-events`, off by default). Use
    `session-window-changed`. Verified empirically on tmux 3.7b.
  - `find` on this machine is **bfs**, not GNU findutils. Relative timestamps
    (`-newermt "7 days ago"`) are rejected; `-mtime -7` works. All `find` flags
    used in this plan are bfs-compatible.
  - Claude plan limits are NOT discoverable locally — only the tier name, in
    `.credentials.json`. Any percentage must come from a user-supplied budget.
    Never hardcode a limit table.

---

## File Structure

| File | Responsibility |
|---|---|
| `tmux/.local/lib/wt/lib.sh` | shared: roots, sanitizers, repo discovery, window lookup, git fragment |
| `tmux/.local/bin/wt` | user-facing CLI: `list`, `open`, `close`, `new`, `menu` |
| `tmux/.local/bin/wt-hook` | Claude hook receiver → window options |
| `tmux/.local/bin/wt-poll` | background loop → git state, elapsed, liveness expiry, rename |
| `tmux/tests/helpers.sh` | scratch repo + scratch tmux server fixtures |
| `tmux/tests/test_*.sh` | one file per task's behavior |
| `tmux/tests/run.sh` | runs every `test_*.sh`, reports pass/fail |
| `tmux/.tmux.conf` | *modify*: keybinds, status format, `pane-focus-in` hook, poller startup |
| `claude/.claude/settings.json` | *modify*: `hooks` block |
| `claude/.claude/CLAUDE.md` | *modify*: worktree directory convention |

Scripts locate the library relative to their own path (`$(dirname $0)/../lib/wt/lib.sh`), which resolves correctly both in-repo and through stow symlinks. `WT_LIB` overrides it for tests.

---

### Task 1: Shared library, discovery, and `wt list`

**Files:**
- Create: `tmux/.local/lib/wt/lib.sh`
- Create: `tmux/.local/bin/wt`
- Create: `tmux/tests/helpers.sh`
- Create: `tmux/tests/run.sh`
- Test: `tmux/tests/test_list.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `wt_sanitize_session(name)->string`, `wt_sanitize_window(branch)->string`, `wt_main_checkouts()->paths on stdout`, `wt_window_for_path(path)->window_id or empty`, `wt_list()->TSV`. TSV columns are exactly: `repo`, `worktree_path`, `branch`, `window_id` (empty if not open).

- [ ] **Step 1: Write the failing test**

Create `tmux/tests/helpers.sh`:

```sh
# shellcheck shell=sh
# Test fixtures. Source this; it sets WT_TMP, WT_ROOTS, WT_LIB, TMUX_SOCK.
WT_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export WT_LIB="$WT_REPO_ROOT/.local/lib/wt/lib.sh"
export PATH="$WT_REPO_ROOT/.local/bin:$PATH"
TMUX_SOCK=wt-test

wt_test_setup() {
  WT_TMP=$(mktemp -d)
  export WT_TMP
  export WT_ROOTS="$WT_TMP/projects"
  mkdir -p "$WT_TMP/projects"
}

wt_test_teardown() {
  tmux -L "$TMUX_SOCK" kill-server 2>/dev/null || true
  [ -n "${WT_TMP:-}" ] && rm -rf "$WT_TMP"
}

# wt_make_repo <name> [branch...] -- main checkout plus one worktree per branch
wt_make_repo() {
  name=$1; shift
  r="$WT_ROOTS/$name"
  mkdir -p "$r"
  git -C "$r" init -q -b main
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
  echo hello > "$r/README"
  git -C "$r" add README
  git -C "$r" commit -qm init
  for b in "$@"; do
    d="$WT_ROOTS/$name-worktrees/$(printf '%s' "$b" | tr '/' '-')"
    mkdir -p "$(dirname "$d")"
    git -C "$r" worktree add -q -b "$b" "$d" >/dev/null 2>&1
  done
  printf '%s\n' "$r"
}

wt_assert_eq() {
  if [ "$1" != "$2" ]; then
    printf 'FAIL %s\n  expected: [%s]\n  actual:   [%s]\n' "$3" "$2" "$1" >&2
    exit 1
  fi
  printf 'ok   %s\n' "$3"
}

wt_assert_contains() {
  case "$1" in
    *"$2"*) printf 'ok   %s\n' "$3" ;;
    *) printf 'FAIL %s\n  expected to contain: [%s]\n  actual: [%s]\n' "$3" "$2" "$1" >&2; exit 1 ;;
  esac
}
```

Create `tmux/tests/run.sh`:

```sh
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
```

Create `tmux/tests/test_list.sh`:

```sh
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
wt_assert_contains "$out" "alpha${T}$WT_ROOTS/alpha${T}main${T}"   "alpha main checkout"
wt_assert_contains "$out" "alpha${T}$WT_ROOTS/alpha-worktrees/feat-one${T}feat/one${T}" "branch with slash keeps real name"
wt_assert_contains "$out" "beta${T}$WT_ROOTS/beta${T}main${T}"     "beta main checkout"

# linked worktrees must not be double-listed as their own repo
wt_assert_eq "$(printf '%s\n' "$out" | cut -f1 | sort -u | tr '\n' ',')" "alpha,beta," "only real repos named"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tmux/tests/test_list.sh`
Expected: FAIL — `wt: command not found` (or `wt list` produces nothing).

- [ ] **Step 3: Write the library**

Create `tmux/.local/lib/wt/lib.sh`:

```sh
# shellcheck shell=sh
# Shared helpers for wt, wt-hook, wt-poll. Source only; do not execute.

: "${WT_ROOTS:=$HOME/Projects $HOME/dev $HOME/.dotfiles}"

WT_TAB=$(printf '\t')

# tmux session names: strip leading dots, replace . and : which are target syntax
wt_sanitize_session() {
  printf '%s' "$1" | sed 's/^\.*//; s/[.:]/-/g'
}

# tmux window names: slashes would read as nested paths
wt_sanitize_window() {
  printf '%s' "$1" | tr '/' '-'
}

# Absolute path of every main checkout under WT_ROOTS.
# A .git DIRECTORY is a main checkout; a .git FILE is a linked worktree, which
# we skip because git worktree list will report it via its main checkout.
wt_main_checkouts() {
  for root in $WT_ROOTS; do
    [ -d "$root" ] || continue
    find "$root" -maxdepth 3 -name .git -prune -print 2>/dev/null
  done | while IFS= read -r g; do
    [ -d "$g" ] || continue
    dirname "$g"
  done
}

# Main checkout directory for any path inside a repo or worktree.
wt_main_for() {
  c=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  dirname "$c"
}

# window_id whose @wt_path equals $1, else empty.
wt_window_for_path() {
  tmux list-windows -a -F "#{window_id}${WT_TAB}#{@wt_path}" 2>/dev/null |
    awk -F"${WT_TAB}" -v p="$1" '$2==p {print $1; exit}'
}

# window_id whose @wt_path is the longest prefix of $1, else empty.
wt_window_for_cwd() {
  tmux list-windows -a -F "#{window_id}${WT_TAB}#{@wt_path}" 2>/dev/null |
    awk -F"${WT_TAB}" -v c="$1" '
      $2 != "" && index(c, $2) == 1 && length($2) > best {
        best = length($2); id = $1
      }
      END { if (id != "") print id }'
}

# TSV: repo <tab> worktree_path <tab> branch <tab> window_id
wt_list() {
  wt_main_checkouts | while IFS= read -r repo; do
    rname=$(basename "$repo")
    git -C "$repo" worktree list --porcelain 2>/dev/null | awk -v repo="$rname" -v T="$WT_TAB" '
      /^worktree /  { path = substr($0, 10); br = ""; sha = "" }
      /^HEAD /      { sha = substr($0, 6, 7) }
      /^branch /    { br = substr($0, 8); sub("refs/heads/", "", br) }
      /^detached$/  { br = "" }
      /^$/          { if (path != "") { print repo T path T (br == "" ? sha : br); path = "" } }
      END           { if (path != "") print repo T path T (br == "" ? sha : br) }
    '
  done | while IFS="$WT_TAB" read -r r p b; do
    printf '%s\t%s\t%s\t%s\n' "$r" "$p" "$b" "$(wt_window_for_path "$p")"
  done
}
```

- [ ] **Step 4: Write the `wt` entry point**

Create `tmux/.local/bin/wt` (mode 755):

```sh
#!/bin/sh
set -eu
_d=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${WT_LIB:-$_d/../lib/wt/lib.sh}"

usage() {
  cat >&2 <<EOF
usage: wt <command>
  list          TSV of every worktree: repo, path, branch, window_id
EOF
  exit 2
}

cmd=${1:-}
[ -n "$cmd" ] || usage
shift || true

case "$cmd" in
  list) wt_list ;;
  *)    usage ;;
esac
```

- [ ] **Step 5: Run test to verify it passes**

Run: `chmod +x tmux/.local/bin/wt tmux/tests/run.sh && sh tmux/tests/test_list.sh`
Expected: PASS — five `ok` lines.

- [ ] **Step 6: Commit**

```bash
git add tmux/.local/lib/wt/lib.sh tmux/.local/bin/wt tmux/tests/
git commit -m "tmux: add wt worktree discovery and list"
```

---

### Task 2: `wt open` and `wt close`

**Files:**
- Modify: `tmux/.local/bin/wt`
- Test: `tmux/tests/test_open.sh`

**Interfaces:**
- Consumes: `wt_window_for_path`, `wt_main_for`, `wt_sanitize_session`, `wt_sanitize_window` from Task 1.
- Produces: `wt open <path>` — idempotent, sets `@wt_path` on the window, leaves the left pane running `claude` and a 35% right pane as a shell. `wt close` — kills the current window, or the whole session if it was the last window.

- [ ] **Step 1: Write the failing test**

Create `tmux/tests/test_open.sh`:

```sh
#!/bin/sh
set -u
. "$(dirname "$0")/helpers.sh"
trap wt_test_teardown EXIT
wt_test_setup

wt_make_repo alpha feat/one >/dev/null
WTP="$WT_ROOTS/alpha-worktrees/feat-one"

tmux -f /dev/null -L "$TMUX_SOCK" new-session -d -s scratch
# Point wt at the test server directly rather than relying on run-shell to
# export TMUX. WT_SHELL keeps the test from launching a real Claude session.
export TMUX WT_SHELL
TMUX=$(tmux -L "$TMUX_SOCK" display -p '#{socket_path}'),0,0
WT_SHELL=1
T=$(printf '\t')

wt open "$WTP"
n=$(tmux -L "$TMUX_SOCK" list-windows -a -F '#{@wt_path}' | grep -c "^$WTP$")
wt_assert_eq "$n" "1" "open creates exactly one window"

sess=$(tmux -L "$TMUX_SOCK" list-windows -a -F "#{session_name}${T}#{@wt_path}" | awk -F"$T" -v p="$WTP" '$2==p{print $1}')
wt_assert_eq "$sess" "alpha" "window lands in a session named after the repo"

win=$(tmux -L "$TMUX_SOCK" list-windows -a -F "#{window_name}${T}#{@wt_path}" | awk -F"$T" -v p="$WTP" '$2==p{print $1}')
wt_assert_eq "$win" "feat-one" "window named after the branch, slash sanitized"

panes=$(tmux -L "$TMUX_SOCK" list-windows -a -F "#{window_panes}${T}#{@wt_path}" | awk -F"$T" -v p="$WTP" '$2==p{print $1}')
wt_assert_eq "$panes" "2" "window has two panes"

# idempotency: opening the same path again must not create a second window
wt open "$WTP"
n=$(tmux -L "$TMUX_SOCK" list-windows -a -F '#{@wt_path}' | grep -c "^$WTP$")
wt_assert_eq "$n" "1" "open is idempotent"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tmux/tests/test_open.sh`
Expected: FAIL on "open creates exactly one window" — actual `0`, because `wt open` does not exist yet.

- [ ] **Step 3: Implement `wt open` and `wt close`**

In `tmux/.local/bin/wt`, replace the `usage` heredoc body and `case` block with:

```sh
usage() {
  cat >&2 <<EOF
usage: wt <command>
  list           TSV of every worktree: repo, path, branch, window_id
  open <path>    focus the window for <path>, creating it if needed
  close          kill the current window (worktree is left on disk)
EOF
  exit 2
}

require_tmux() {
  [ -n "${TMUX:-}" ] || { echo "wt: not inside tmux" >&2; exit 1; }
}

wt_open() {
  path=$1
  require_tmux
  [ -d "$path" ] || { echo "wt: no such worktree: $path" >&2; exit 1; }

  existing=$(wt_window_for_path "$path")
  if [ -n "$existing" ]; then
    tmux select-window -t "$existing"
    tmux switch-client -t "$existing" 2>/dev/null || true
    return 0
  fi

  main=$(wt_main_for "$path") || { echo "wt: not a git worktree: $path" >&2; exit 1; }
  sess=$(wt_sanitize_session "$(basename "$main")")
  br=$(git -C "$path" branch --show-current 2>/dev/null || true)
  [ -n "$br" ] || br=$(git -C "$path" rev-parse --short HEAD 2>/dev/null || echo detached)
  win=$(wt_sanitize_window "$br")

  if tmux has-session -t "=$sess" 2>/dev/null; then
    wid=$(tmux new-window -t "=$sess:" -c "$path" -n "$win" -P -F '#{window_id}')
  else
    tmux new-session -d -s "$sess" -c "$path" -n "$win"
    wid=$(tmux list-windows -t "=$sess" -F '#{window_id}' | head -n1)
  fi

  tmux set -w -t "$wid" @wt_path "$path"
  p0=$(tmux list-panes -t "$wid" -F '#{pane_id}' | head -n1)
  tmux split-window -h -l 35% -t "$p0" -c "$path"
  # WT_SHELL=1 keeps tests from launching a real Claude session
  [ -n "${WT_SHELL:-}" ] || tmux send-keys -t "$p0" 'claude' Enter
  tmux select-pane -t "$p0"
  tmux select-window -t "$wid"
  tmux switch-client -t "$wid" 2>/dev/null || true
}

wt_close() {
  require_tmux
  sess=$(tmux display -p '#{session_name}')
  n=$(tmux list-windows -t "=$sess" | wc -l | tr -d ' ')
  if [ "$n" -le 1 ]; then
    tmux kill-session -t "=$sess"
  else
    tmux kill-window -t "$(tmux display -p '#{window_id}')"
  fi
}

cmd=${1:-}
[ -n "$cmd" ] || usage
shift || true

case "$cmd" in
  list)  wt_list ;;
  open)  [ $# -ge 1 ] || usage; wt_open "$1" ;;
  close) wt_close ;;
  *)     usage ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sh tmux/tests/test_open.sh`
Expected: PASS — five `ok` lines.

- [ ] **Step 5: Commit**

```bash
git add tmux/.local/bin/wt tmux/tests/test_open.sh
git commit -m "tmux: add wt open and wt close"
```

---

### Task 3: `wt new`

**Files:**
- Modify: `tmux/.local/bin/wt`
- Test: `tmux/tests/test_new.sh`

**Interfaces:**
- Consumes: `wt_main_for`, `wt_sanitize_window`, `wt_open` from Tasks 1–2.
- Produces: `wt new <branch>` — creates the worktree at `<parent>/<repo>-worktrees/<sanitized branch>` and opens it. Falls through to `wt open` when the branch already has a worktree. Never deletes anything.

- [ ] **Step 1: Write the failing test**

Create `tmux/tests/test_new.sh`:

```sh
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
wt_assert_eq "$(tmux -L "$TMUX_SOCK" list-windows -a -F '#{@wt_path}' | grep -c "^$EXP$")" "1" "new on existing branch is idempotent"

# nothing was deleted
wt_assert_eq "$([ -d "$EXP" ] && echo yes || echo no)" "yes" "existing worktree untouched"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tmux/tests/test_new.sh`
Expected: FAIL on "worktree created at sibling <repo>-worktrees" — actual `no`.

- [ ] **Step 3: Implement `wt new`**

Add to `tmux/.local/bin/wt`, above the `case` block:

```sh
wt_new() {
  branch=$1
  require_tmux
  main=$(wt_main_for "$PWD") || { echo "wt: not in a git repo" >&2; exit 1; }
  parent=$(dirname "$main")
  repo=$(basename "$main")
  dir="$parent/$repo-worktrees/$(wt_sanitize_window "$branch")"

  if [ -d "$dir" ]; then
    wt_open "$dir"
    return 0
  fi

  mkdir -p "$parent/$repo-worktrees"
  if git -C "$main" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$main" worktree add -q "$dir" "$branch"
  else
    git -C "$main" worktree add -q -b "$branch" "$dir"
  fi
  wt_open "$dir"
}
```

Add to `usage`:

```
  new <branch>   create a worktree at <repo>-worktrees/<branch> and open it
```

Add to the `case` block, before `*)`:

```sh
  new)   [ $# -ge 1 ] || usage; wt_new "$1" ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sh tmux/tests/test_new.sh`
Expected: PASS — five `ok` lines.

- [ ] **Step 5: Commit**

```bash
git add tmux/.local/bin/wt tmux/tests/test_new.sh
git commit -m "tmux: add wt new with <repo>-worktrees convention"
```

---

### Task 4: `wt menu` and tmux keybinds

**Files:**
- Modify: `tmux/.local/bin/wt`
- Modify: `tmux/.tmux.conf`
- Test: `tmux/tests/test_menu.sh`

**Interfaces:**
- Consumes: `wt_list` (Task 1), `wt_open` (Task 2).
- Produces: `wt menu` opens an fzf popup; `wt _pick` prints the chosen path (the testable seam — `menu` is the untestable popup wrapper around it).

- [ ] **Step 1: Write the failing test**

`display-popup` needs an attached client, so the test targets `_pick`, which is the whole logic. Create `tmux/tests/test_menu.sh`:

```sh
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tmux/tests/test_menu.sh`
Expected: FAIL — `wt: usage` on stderr and empty output, because `_pick` is not a command yet.

- [ ] **Step 3: Implement `_rows`, `_pick`, and `menu`**

Add to `tmux/.local/bin/wt`, above the `case` block:

```sh
# Human-readable picker rows. Field 1 stays the path so _pick can cut it back
# out; the rest is display only.
wt_rows() {
  wt_list | while IFS="$WT_TAB" read -r repo path branch wid; do
    mark=' '
    [ -n "$wid" ] && mark='*'
    printf '%s\t%s %-22s %s\n' "$path" "$mark" "$repo" "$branch"
  done
}

wt_pick() {
  # WT_PICK_CMD replaces the whole picker; tests set it to something
  # deterministic. Overriding just the binary would break, because the fzf
  # flags below are not portable to another command.
  if [ -n "${WT_PICK_CMD:-}" ]; then
    wt_rows | sh -c "$WT_PICK_CMD" | cut -f1
  else
    wt_rows | fzf --with-nth=2.. --delimiter="$WT_TAB" --no-sort --reverse \
      --prompt='worktree> ' 2>/dev/null | cut -f1
  fi
}

wt_menu() {
  require_tmux
  # $0 may be a bare name; the popup gets its own PATH, so resolve it here.
  self="$_d/wt"
  tmux display-popup -E -w 80% -h 60% \
    "sel=\$($self _pick); [ -n \"\$sel\" ] && $self open \"\$sel\""
}
```

Add to `usage`:

```
  menu           fzf popup over every worktree; Enter opens it
```

Add to the `case` block, before `*)`:

```sh
  menu)  wt_menu ;;
  _rows) wt_rows ;;
  _pick) wt_pick ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sh tmux/tests/test_menu.sh`
Expected: PASS — four `ok` lines.

- [ ] **Step 5: Add the keybinds**

Append to `tmux/.tmux.conf`, after the `### --- Reload Config --- ###` block:

```
### --- Claude worktrees (wt) --- ###
bind w run-shell 'wt menu'
bind W command-prompt -p "branch:" 'run-shell "wt new %%"'
bind x run-shell 'wt close'
```

Note in the commit message that `bind x` replaces tmux's default `kill-pane` binding — this is intentional per the spec, and `prefix &` still kills a window if needed.

- [ ] **Step 6: Verify the binds parse**

Run: `tmux -f tmux/.tmux.conf -L wt-cfgtest new-session -d 2>&1 | head; tmux -L wt-cfgtest list-keys | grep -E "bind.*wt |wt menu|wt close" ; tmux -L wt-cfgtest kill-server`
Expected: no parse errors; the three `wt` bindings are listed.

- [ ] **Step 7: Commit**

```bash
git add tmux/.local/bin/wt tmux/tests/test_menu.sh tmux/.tmux.conf
git commit -m "tmux: add wt menu picker and prefix w/W/x keybinds

prefix x now closes the wt window instead of the default kill-pane."
```

---

### Task 5: `wt-hook` and Claude Code wiring

**Files:**
- Create: `tmux/.local/bin/wt-hook`
- Modify: `tmux/.tmux.conf`
- Modify: `claude/.claude/settings.json`
- Modify: `claude/.claude/CLAUDE.md`
- Test: `tmux/tests/test_hook.sh`

**Interfaces:**
- Consumes: `wt_window_for_cwd` (Task 1), `@wt_path` set by `wt open` (Task 2).
- Produces: window options `@cc_state` ∈ {`busy`,`attention`,unset} and `@cc_since` (epoch seconds), consumed by Task 6's poller and the status format.

- [ ] **Step 1: Write the failing test**

Create `tmux/tests/test_hook.sh`:

```sh
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tmux/tests/test_hook.sh`
Expected: FAIL on "busy set via TMUX_PANE" — `wt-hook: command not found`.

- [ ] **Step 3: Implement `wt-hook`**

Create `tmux/.local/bin/wt-hook` (mode 755):

```sh
#!/bin/sh
# Claude Code hook receiver. Usage: wt-hook <busy|attention|clear>
# Reads the hook event JSON on stdin. Always exits 0 and prints nothing:
# a failing hook must never disturb the Claude session.
set -u
_d=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${WT_LIB:-$_d/../lib/wt/lib.sh}" 2>/dev/null || exit 0

state=${1:-}
[ -n "$state" ] || exit 0
json=$(cat 2>/dev/null || true)
[ -n "${TMUX:-}" ] || exit 0

wid=""
if [ -n "${TMUX_PANE:-}" ]; then
  wid=$(tmux display -t "$TMUX_PANE" -p '#{window_id}' 2>/dev/null || true)
fi
if [ -z "$wid" ]; then
  cwd=$(printf '%s' "$json" | jq -r '.cwd // empty' 2>/dev/null || true)
  [ -n "$cwd" ] && wid=$(wt_window_for_cwd "$cwd" || true)
fi
[ -n "$wid" ] || exit 0

case "$state" in
  clear)
    tmux set -w -t "$wid" -u @cc_state 2>/dev/null || true
    tmux set -w -t "$wid" -u @cc_since 2>/dev/null || true
    tmux set -w -t "$wid" -u @cc_elapsed 2>/dev/null || true
    ;;
  attention)
    # If you are already looking at this window, there is nothing to flag.
    seen=$(tmux display -t "$wid" -p '#{&&:#{window_active},#{session_attached}}' 2>/dev/null || echo 0)
    [ "$seen" = "1" ] && exit 0
    tmux set -w -t "$wid" @cc_state attention 2>/dev/null || true
    tmux set -w -t "$wid" @cc_since "$(date +%s)" 2>/dev/null || true
    ;;
  busy)
    tmux set -w -t "$wid" @cc_state busy 2>/dev/null || true
    tmux set -w -t "$wid" @cc_since "$(date +%s)" 2>/dev/null || true
    ;;
esac
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x tmux/.local/bin/wt-hook && sh tmux/tests/test_hook.sh`
Expected: PASS — six `ok` lines.

- [ ] **Step 5: Add the focus-clears-attention tmux hook**

Append to the `### --- Claude worktrees (wt) --- ###` block in `tmux/.tmux.conf`:

```
# Looking at the window is what clears the flag: ● means "unseen".
# NOT pane-focus-in: that fires on OS-level terminal focus, not tmux window
# switching, and is gated behind focus-events (off by default) — it never fires
# here. session-window-changed fires on every switch path.
set-hook -g session-window-changed 'if -F "#{==:#{@cc_state},attention}" "set -w @cc_state idle"'
```

- [ ] **Step 6: Register the Claude hooks**

Modify `claude/.claude/settings.json` — add a top-level `"hooks"` key alongside the existing `"permissions"`, `"model"`, etc. Do not disturb the existing keys.

```json
  "hooks": {
    "UserPromptSubmit": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "wt-hook busy" } ] }
    ],
    "Notification": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "wt-hook attention" } ] }
    ],
    "Stop": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "wt-hook attention" } ] }
    ],
    "SessionEnd": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "wt-hook clear" } ] }
    ]
  }
```

`PreToolUse`/`PostToolUse` are deliberately absent — they fire far too often to be worth a tmux round-trip each.

- [ ] **Step 7: Verify the settings file is still valid JSON**

Run: `jq -e '.hooks.Stop[0].hooks[0].command' claude/.claude/settings.json && jq -e '.permissions.defaultMode' claude/.claude/settings.json`
Expected: prints `"wt-hook attention"` then `"auto"`. If the second fails, the existing settings were clobbered — restore and redo.

- [ ] **Step 8: Declare the worktree convention**

Append to `claude/.claude/CLAUDE.md`:

```markdown
- Worktree directory preference: create git worktrees in a sibling directory named `<repo>-worktrees/`, e.g. `~/Projects/trav-analyse-worktrees/<branch>`. Do not use `.worktrees/` inside the repo.
```

- [ ] **Step 9: Commit**

```bash
git add tmux/.local/bin/wt-hook tmux/tests/test_hook.sh tmux/.tmux.conf claude/.claude/settings.json claude/.claude/CLAUDE.md
git commit -m "claude: push session state into tmux window options via hooks"
```

---

### Task 6: `wt-poll` and the status bar

**Files:**
- Create: `tmux/.local/bin/wt-poll`
- Modify: `tmux/.local/lib/wt/lib.sh`
- Modify: `tmux/.tmux.conf`
- Test: `tmux/tests/test_poll.sh`

**Interfaces:**
- Consumes: `@wt_path` (Task 2), `@cc_state`/`@cc_since` (Task 5).
- Produces: `wt_git_fragment(path)->string` and `wt_fmt_elapsed(seconds)->string` in `lib.sh`; window options `@wt_git` and `@cc_elapsed`, which the status format reads.

- [ ] **Step 1: Write the failing test**

Create `tmux/tests/test_poll.sh`:

```sh
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tmux/tests/test_poll.sh`
Expected: FAIL on "git fragment names the branch" — `wt-poll: command not found`.

- [ ] **Step 3: Add the formatting helpers to `lib.sh`**

Append to `tmux/.local/lib/wt/lib.sh`:

```sh
# "2m5s", "45s", "1h3m"
wt_fmt_elapsed() {
  s=$1
  if [ "$s" -lt 60 ]; then
    printf '%ds' "$s"
  elif [ "$s" -lt 3600 ]; then
    printf '%dm%ds' "$((s / 60))" "$((s % 60))"
  else
    printf '%dh%dm' "$((s / 3600))" "$(((s % 3600) / 60))"
  fi
}

# "main ^3 +12/-3 *" — branch, ahead/behind, diffstat, dirty marker.
# --ignore-submodules so a dirty submodule does not mark the worktree dirty.
wt_git_fragment() {
  p=$1
  git -C "$p" rev-parse --git-dir >/dev/null 2>&1 || return 0
  br=$(git -C "$p" branch --show-current 2>/dev/null || true)
  [ -n "$br" ] || br=$(git -C "$p" rev-parse --short HEAD 2>/dev/null || echo '?')
  out=$br

  ab=$(git -C "$p" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || true)
  if [ -n "$ab" ]; then
    behind=$(printf '%s' "$ab" | cut -f1)
    ahead=$(printf '%s' "$ab" | cut -f2)
    [ "${ahead:-0}" -gt 0 ] 2>/dev/null && out="$out ↑$ahead"
    [ "${behind:-0}" -gt 0 ] 2>/dev/null && out="$out ↓$behind"
  fi

  stat=$(git -C "$p" diff --numstat --ignore-submodules 2>/dev/null |
    awk '{a += $1; d += $2} END {if (NR > 0) printf "+%d/-%d", a, d}')
  [ -n "$stat" ] && out="$out $stat"

  [ -n "$(git -C "$p" status --porcelain --ignore-submodules 2>/dev/null)" ] && out="$out *"
  printf '%s' "$out"
}
```

- [ ] **Step 4: Implement `wt-poll`**

Create `tmux/.local/bin/wt-poll` (mode 755):

```sh
#!/bin/sh
# Background loop: git state, elapsed time, liveness expiry, window rename.
# Exits when the tmux server goes away. --once runs a single iteration.
set -u
_d=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${WT_LIB:-$_d/../lib/wt/lib.sh}"

: "${WT_POLL_INTERVAL:=5}"
once=0
[ "${1:-}" = "--once" ] && once=1

while :; do
  windows=$(tmux list-windows -a -F \
    "#{window_id}${WT_TAB}#{@wt_path}${WT_TAB}#{@cc_state}${WT_TAB}#{@cc_since}${WT_TAB}#{window_name}" \
    2>/dev/null) || break

  now=$(date +%s)
  printf '%s\n' "$windows" | while IFS="$WT_TAB" read -r wid path state since wname; do
    [ -n "$path" ] || continue
    [ -d "$path" ] || continue

    tmux set -w -t "$wid" @wt_git "$(wt_git_fragment "$path")" 2>/dev/null || true

    if [ "$state" = busy ] && [ -n "$since" ]; then
      tmux set -w -t "$wid" @cc_elapsed "$(wt_fmt_elapsed "$((now - since))")" 2>/dev/null || true
    else
      tmux set -w -t "$wid" @cc_elapsed "" 2>/dev/null || true
    fi

    # Liveness is a process check, not a timeout: a legitimately long turn is
    # never wrongly cleared, and a crashed Claude never leaves a stuck flag.
    if [ -n "$state" ] && [ "$state" != idle ]; then
      if ! tmux list-panes -t "$wid" -F '#{pane_current_command}' 2>/dev/null | grep -qx claude; then
        tmux set -w -t "$wid" -u @cc_state 2>/dev/null || true
      fi
    fi

    br=$(git -C "$path" branch --show-current 2>/dev/null || true)
    if [ -n "$br" ]; then
      want=$(wt_sanitize_window "$br")
      [ "$want" = "$wname" ] || tmux rename-window -t "$wid" "$want" 2>/dev/null || true
    fi
  done

  [ "$once" -eq 1 ] && break
  sleep "$WT_POLL_INTERVAL"
done
exit 0
```

- [ ] **Step 5: Run test to verify it passes**

Run: `chmod +x tmux/.local/bin/wt-poll && sh tmux/tests/test_poll.sh`
Expected: PASS — six `ok` lines.

- [ ] **Step 6: Wire up the status format and start the poller**

Append these lines to the `### --- Claude worktrees (wt) --- ###` block in `tmux/.tmux.conf`. Leave the existing `set -g status-right` line alone — it is Task 7's to change, not this task's.

```
# Absence is the quiet state; every glyph means something needs reading.
set -g window-status-format '#I:#W#{?#{==:#{@cc_state},busy},#[fg=yellow] ◐#{@cc_elapsed},}#{?#{==:#{@cc_state},attention},#[fg=red] ●,}#{?@wt_git, #[fg=blue]#{@wt_git},}#[default]'
set -g window-status-current-format '#[fg=cyan,bold]#I:#W#{?@wt_git, #[fg=blue,nobold]#{@wt_git},}#[default]'
set -g status-interval 5

# flock keeps `prefix r` from starting a second poller; the loser exits 1.
run-shell -b 'flock -n /tmp/wt-poll.#{USER}.lock ~/.local/bin/wt-poll'
```

- [ ] **Step 7: Verify the format renders and the poller is single-instance**

Run:
```bash
tmux -f tmux/.tmux.conf -L wt-cfgtest new-session -d
sleep 2
pgrep -fc 'wt-poll' 
tmux -L wt-cfgtest source-file tmux/.tmux.conf
sleep 2
pgrep -fc 'wt-poll'
tmux -L wt-cfgtest display -p '#{window-status-format}'
tmux -L wt-cfgtest kill-server
```
Expected: `pgrep -fc` prints `1` both times — sourcing the config twice must not produce a second poller. The format string prints without a parse error.

- [ ] **Step 8: Run the whole suite**

Run: `sh tmux/tests/run.sh`
Expected: `ALL PASS`.

- [ ] **Step 9: shellcheck**

Run: `shellcheck -s sh tmux/.local/bin/wt tmux/.local/bin/wt-hook tmux/.local/bin/wt-poll tmux/.local/lib/wt/lib.sh`
Expected: no output. If `shellcheck` is not installed, note it and move on — installing it needs sudo, which is a user action.

- [ ] **Step 10: Commit**

```bash
git add tmux/.local/bin/wt-poll tmux/.local/lib/wt/lib.sh tmux/tests/test_poll.sh tmux/.tmux.conf
git commit -m "tmux: add wt-poll and worktree-aware status bar"
```

---

---

### Task 7: `wt-usage` and the status-right gauge

**Files:**
- Create: `tmux/.local/bin/wt-usage`
- Modify: `tmux/.local/bin/wt-poll`
- Modify: `tmux/.tmux.conf`
- Test: `tmux/tests/test_usage.sh`

**Interfaces:**
- Consumes: `WT_TAB` from `lib.sh` (Task 1); the poll loop from Task 6.
- Produces: `wt-usage [--json]` printing the rendered gauge on stdout; tmux
  **server** option `@wt_usage` (server-scoped, not window-scoped — it is one
  global number, unlike every other option in this project).

**Facts established by probe — do not re-derive:**
- A full 7-day scan of `~/.claude/projects/*/*.jsonl` costs ~2s (247MB, 584
  files, 41k usage records). Far too slow for the 5s loop; hence the 60s cache.
- `find` on this machine is **bfs**, not GNU findutils. It rejects relative
  timestamps (`-newermt "7 days ago"` → "Invalid timestamp"). Use `-mtime -7`.
- Numeric plan limits are NOT available locally. `.credentials.json` has only
  the tier name (`subscriptionType`, `rateLimitTier`); no rate-limit headers are
  cached anywhere. Percentages are therefore opt-in via user-supplied budgets.
  **Never invent a limit table.**
- `stats-cache.json` is pre-aggregated but goes stale for days. Do not use it.
- Per-record token total is
  `input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens`.
  Records live at `.message.usage`; the timestamp is top-level `.timestamp` (ISO 8601).

- [ ] **Step 1: Write the failing test**

Create `tmux/tests/test_usage.sh`. The test builds a synthetic transcript tree
so it never depends on the real `~/.claude`:

```sh
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tmux/tests/test_usage.sh`
Expected: FAIL on "5h block sums only current-block records" — `wt-usage: command not found`.

- [ ] **Step 3: Implement `wt-usage`**

Create `tmux/.local/bin/wt-usage` (mode 755):

```sh
#!/bin/sh
# Rolling 5h-block and trailing-7d token usage, from Claude Code transcripts.
# Cached, because a full scan costs ~2s. --json prints the raw numbers.
set -u

: "${WT_USAGE_ROOT:=$HOME/.claude/projects}"
: "${WT_USAGE_CACHE:=${XDG_CACHE_HOME:-$HOME/.cache}/wt-usage.json}"
: "${WT_USAGE_TTL:=60}"
: "${WT_BLOCK_HOURS:=5}"

want_json=0
[ "${1:-}" = "--json" ] && want_json=1

emit() {
  if [ "$want_json" -eq 1 ]; then
    cat "$WT_USAGE_CACHE"
  else
    jq -r '.rendered' "$WT_USAGE_CACHE" 2>/dev/null
  fi
}

# Reuse a cache younger than the TTL.
if [ -f "$WT_USAGE_CACHE" ]; then
  age=$(( $(date +%s) - $(stat -c %Y "$WT_USAGE_CACHE" 2>/dev/null || echo 0) ))
  if [ "$age" -lt "$WT_USAGE_TTL" ]; then
    emit
    exit 0
  fi
fi

now=$(date -u +%s)
week_start=$((now - 604800))
block_span=$((WT_BLOCK_HOURS * 3600))

# One pass: emit "<epoch> <tokens>" per usage record from the last 7 days.
# -mtime -7 because find here is bfs, which rejects relative -newermt strings.
records=$(find "$WT_USAGE_ROOT" -name '*.jsonl' -mtime -7 -print0 2>/dev/null |
  xargs -0 -r jq -r --argjson since "$week_start" '
    select(.message.usage != null and .timestamp != null)
    | (.timestamp | fromdateiso8601) as $t
    | select($t >= $since)
    | [ $t,
        ( .message.usage.input_tokens
        + .message.usage.cache_creation_input_tokens
        + .message.usage.cache_read_input_tokens
        + .message.usage.output_tokens ) ]
    | @tsv' 2>/dev/null)

# Block boundaries, ccusage-style: a block opens at the first record after a
# gap of >= WT_BLOCK_HOURS, and stays open for WT_BLOCK_HOURS. The "current"
# block is the last one opened, provided it has not already expired.
set -- $(printf '%s\n' "$records" | sort -n | awk -v span="$block_span" -v now="$now" '
  NF != 2 { next }
  {
    if (start == "" || $1 - last >= span || $1 - start >= span) { start = $1; sum = 0 }
    sum += $2
    last = $1
    week += $2
  }
  END {
    if (start != "" && now - start < span) { print sum, week, start + span }
    else { print 0, week + 0, 0 }
  }')
block_tokens=${1:-0}
week_tokens=${2:-0}
block_end=${3:-0}

fmt() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000) printf "%.1fM", n / 1000000
    else if (n >= 1000) printf "%.0fk", n / 1000
    else printf "%d", n
  }'
}

# A bar and a percentage only when the user supplied a budget; the real plan
# limits are not discoverable locally, so anything else would be invented.
seg() {
  label=$1; used=$2; budget=${3:-}
  if [ -n "$budget" ] && [ "$budget" -gt 0 ] 2>/dev/null; then
    pct=$((used * 100 / budget))
    [ "$pct" -gt 100 ] && pct=100
    filled=$((pct * 8 / 100))
    bar=""
    i=0
    while [ "$i" -lt 8 ]; do
      if [ "$i" -lt "$filled" ]; then bar="$bar▪"; else bar="$bar▫"; fi
      i=$((i + 1))
    done
    printf '%s %s %d%%' "$label" "$bar" "$pct"
  else
    printf '%s %s' "$label" "$(fmt "$used")"
  fi
}

rendered=$(printf '%s · %s' \
  "$(seg 5h "$block_tokens" "${WT_5H_BUDGET:-}")" \
  "$(seg 7d "$week_tokens" "${WT_WEEK_BUDGET:-}")")

if [ "$block_end" -gt "$now" ]; then
  mins=$(( (block_end - now) / 60 ))
  rendered=$(printf '%s (%dh%02dm left)' "$rendered" "$((mins / 60))" "$((mins % 60))")
fi

mkdir -p "$(dirname "$WT_USAGE_CACHE")"
jq -n --argjson b "$block_tokens" --argjson w "$week_tokens" \
      --argjson e "$block_end" --arg r "$rendered" \
  '{block_tokens: $b, week_tokens: $w, block_end: $e, rendered: $r}' > "$WT_USAGE_CACHE"

emit
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x tmux/.local/bin/wt-usage && sh tmux/tests/test_usage.sh`
Expected: PASS — eight `ok` lines.

- [ ] **Step 5: Call it from the poll loop on a slower cadence**

In `tmux/.local/bin/wt-poll`, add a counter so the ~2s scan runs once a minute
rather than every iteration. Directly after `: "${WT_POLL_INTERVAL:=5}"`, add:

```sh
: "${WT_USAGE_EVERY:=12}"   # every 12th tick at 5s = 60s
tick=0
```

and inside the `while :; do` loop, directly before the `[ "$once" -eq 1 ] && break`
line, add:

```sh
  # Skipped under --once: the scan reaches the real ~/.claude corpus and takes
  # ~2s, which a test must never do.
  if [ "$once" -eq 0 ] && [ "$((tick % WT_USAGE_EVERY))" -eq 0 ]; then
    # Server-scoped: one global number, unlike the per-window options above.
    tmux set -s @wt_usage "$(wt-usage 2>/dev/null)" 2>/dev/null || true
  fi
  tick=$((tick + 1))
```

- [ ] **Step 6: Show it in status-right**

In `tmux/.tmux.conf`, replace the existing line

```
set -g status-right '#(date +%H:%M\ %d-%b)'
```

with

```
set -g status-right '#{?@wt_usage,#[fg=magenta]#{@wt_usage}#[default]  ,}#(date +%H:%M\ %d-%b)'
```

- [ ] **Step 7: Verify end to end against the real transcript corpus**

Run:
```bash
time ~/.dotfiles/tmux/.local/bin/wt-usage
time ~/.dotfiles/tmux/.local/bin/wt-usage
WT_5H_BUDGET=5000000 ~/.dotfiles/tmux/.local/bin/wt-usage --json | jq .
```
Expected: the first call takes ~2s and prints something like `5h 3.2M · 7d 18.4M`;
the second returns instantly from cache. The JSON has non-negative
`block_tokens` and `week_tokens`, with `week_tokens >= block_tokens`.

- [ ] **Step 8: Run the whole suite**

Run: `sh tmux/tests/run.sh`
Expected: `ALL PASS`.

- [ ] **Step 9: Commit**

```bash
git add tmux/.local/bin/wt-usage tmux/.local/bin/wt-poll tmux/tests/test_usage.sh tmux/.tmux.conf
git commit -m "tmux: add wt-usage 5h-block and 7d token gauge"
```

## Manual acceptance (after Task 7)

These need a real terminal and cannot be automated here. Run them yourself:

1. `stow tmux claude` from `~/.dotfiles`, then start a fresh tmux and `prefix r`.
2. `prefix w` — the popup lists every worktree across `~/Projects`, `~/dev`, `~/.dotfiles`.
3. Pick one. A window appears with `claude` on the left and a shell at 35% on the right.
4. Send Claude a prompt, switch away with `prefix n`. The window shows `◐` and a climbing timer.
5. Wait for it to finish. The flag turns to a red `●`. Switch to the window — the `●` clears.
6. `prefix W`, type a branch name. A worktree appears at `<repo>-worktrees/<branch>`.
7. Kill Claude with `C-c` in its pane. Within ~5s the flag disappears (liveness expiry).
8. Within a minute, status-right shows the usage gauge. Compare it against what
   `/usage` reports in a Claude session, and set `WT_5H_BUDGET` / `WT_WEEK_BUDGET`
   in your shell profile to calibrate the percentages.

## Deferred (not in this plan)

- Catppuccin Macchiato colors for the status bar, to match hypr. Bare `yellow`/`red`/`blue` for now.
- Nicer window names for native `EnterWorktree` worktrees, which land in `<repo>/.claude/worktrees/<random-slug>`.
