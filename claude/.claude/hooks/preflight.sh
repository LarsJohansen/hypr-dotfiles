#!/usr/bin/env bash
# SessionStart preflight for Claude Code.
#
# Prints the environment facts that sessions kept rediscovering the hard way:
# which checkout this is, whether git can reach the remote, whether gh is the
# working credential, Node vs .nvmrc, stale worktrees, open port/migration
# claims, .env drift. Output lands in Claude's context at session start.
#
# Always exits 0 and never blocks: a broken preflight must not break a session.
# Every external call is bounded with `timeout` so a hung network cannot stall
# startup. Registered in ~/.claude/settings.json under hooks.SessionStart.
set -u
export LC_ALL=C

json=$(cat 2>/dev/null || true)
cwd=$(printf '%s' "$json" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -n "$cwd" ] || cwd=$PWD

warn() { printf '  ! %s\n' "$*"; }
ok()   { printf '  - %s\n' "$*"; }

echo "## Preflight $(date '+%Y-%m-%d %H:%M') ($(hostname))"

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || {
  echo "  cwd: $cwd (not a git repository)"
  exit 0
}
common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
main_tree=$(dirname "$common")
branch=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')
dirty=$(git -C "$root" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

echo "### Checkout"
if [ "$root" != "$main_tree" ]; then
  ok "WORKTREE $root  (branch: $branch; main checkout: $main_tree)"
else
  ok "MAIN checkout $root  (branch: $branch)"
fi
ok "run every command with absolute paths under $root — the shell cwd does not persist between tool calls"
[ "$dirty" != "0" ] && warn "$dirty uncommitted change(s) in this checkout (git status)"

# ---- Git / auth ---------------------------------------------------------------
echo "### Git & auth"
gh_line=$(timeout 5 gh auth status 2>&1 | grep -m1 -E 'Logged in to' || true)
if [ -n "$gh_line" ]; then
  ok "gh: ${gh_line#*✓ }"
  gh_ok=1
else
  warn "gh: NOT authenticated (gh auth login)"
  gh_ok=0
fi
# A hook inherits the env of the app that spawned it, so a long-running Claude Code can
# hand us an SSH_AUTH_SOCK from before gcr-ssh-agent was set up (2026-09-16) -- an agent
# with no keys. The socket path is fixed, so prefer it whenever the inherited agent is empty.
gcr_sock="${XDG_RUNTIME_DIR:-/run/user/$UID}/gcr/ssh"
if [ -S "$gcr_sock" ] && [ "$SSH_AUTH_SOCK" != "$gcr_sock" ] \
   && ! timeout 3 ssh-add -l >/dev/null 2>&1; then
  export SSH_AUTH_SOCK="$gcr_sock"
fi
ids=$(timeout 3 ssh-add -l 2>/dev/null | grep -vc 'no identities' || true)
[ "$ids" = "" ] && ids=0
remote_url=$(git -C "$root" remote get-url origin 2>/dev/null || true)
if [ -n "$remote_url" ]; then
  if timeout 8 git -C "$root" ls-remote --exit-code -q origin HEAD >/dev/null 2>&1; then
    ok "origin reachable ($remote_url); ssh-agent identities: $ids"
  else
    warn "origin NOT reachable: $remote_url (ssh-agent identities: $ids)"
    case "$remote_url" in
      git@*|ssh://*)
        key=$(awk -v h="${remote_url#git@}" 'BEGIN{h=substr(h,1,index(h,":")-1)} $1=="Host"{m=($2==h)} m&&$1=="IdentityFile"{print $2}' ~/.ssh/config 2>/dev/null | head -1)
        host=${remote_url#git@}; host=${host%%:*}
        if [ "$gh_ok" = 1 ]; then
          warn "  gh IS authenticated — do not debug SSH. Since 2026-09-16 the keys live in gnome-keyring: check SSH_AUTH_SOCK is \$XDG_RUNTIME_DIR/gcr/ssh and \`ssh-add -l\` lists the key; if the socket is gone, \`systemctl --user start gcr-ssh-agent.socket\`. Fallback: gh for remote reads (gh pr, gh api) and push over HTTPS: \`gh auth setup-git\` once, then \`git -c url.https://github.com/.insteadOf=git@${host}: push ...\`"
        else
          warn "  keys live in gnome-keyring (gcr-ssh-agent): check SSH_AUTH_SOCK is \$XDG_RUNTIME_DIR/gcr/ssh, then \`systemctl --user start gcr-ssh-agent.socket\`. Only if the keyring lost it does Lars need \`! ssh-add ${key:-~/.ssh/<key>}\` once"
        fi
        ;;
    esac
  fi
  fetch_age=""
  if [ -f "$common/FETCH_HEAD" ]; then
    fetch_age=$(( ( $(date +%s) - $(stat -c %Y "$common/FETCH_HEAD") ) / 60 ))
    [ "$fetch_age" -gt 180 ] && warn "last fetch was ${fetch_age} min ago — origin/main may be stale; fetch before claiming a migration number or a port"
  fi
fi

# ---- Toolchain ----------------------------------------------------------------
if [ -f "$root/.nvmrc" ]; then
  echo "### Toolchain"
  want=$(tr -d 'v \n' < "$root/.nvmrc")
  have=$(node -v 2>/dev/null | tr -d 'v' || echo none)
  case "$have" in
    "$want"|"$want".*) ok "node $have (.nvmrc wants $want)";;
    *) warn "node $have but .nvmrc wants $want — run \`fnm use\` (pnpm will refuse with ERR_PNPM_UNSUPPORTED_ENGINE)";;
  esac
fi
if [ -d "$root/.githooks" ]; then
  hp=$(git -C "$root" config --get core.hooksPath 2>/dev/null || true)
  [ -z "$hp" ] && warn "core.hooksPath is unset but .githooks/ exists — run \`make hooks\` once (missing hooks fail silently)"
fi

# ---- Worktrees ----------------------------------------------------------------
echo "### Worktrees"
base=$(git -C "$root" rev-parse --verify -q origin/main 2>/dev/null || git -C "$root" rev-parse --verify -q main 2>/dev/null || true)
n=0; stale=0
while IFS= read -r line; do
  case "$line" in
    "worktree "*) wt=${line#worktree }; n=$((n+1)) ;;
    "branch refs/heads/"*)
      b=${line#branch refs/heads/}
      [ "$wt" = "$main_tree" ] && continue
      merged=""
      if [ -n "$base" ] && git -C "$root" merge-base --is-ancestor "$b" "$base" 2>/dev/null; then
        merged=" [MERGED into origin/main — candidate for /cleanup]"; stale=$((stale+1))
      fi
      ok "$wt  ($b)$merged"
      ;;
  esac
done < <(git -C "$root" worktree list --porcelain 2>/dev/null)
ok "$n worktree(s) total; $stale with a branch already merged"

# ---- Project ledgers (third-shift style) --------------------------------------
if [ -f "$root/PORTS.md" ]; then
  echo "### Port claims (PORTS.md)"
  rows=$(awk '/^## Open claims/{f=1;next} /^## /{f=0} f && /^\| *[0-9]+ *\|/' "$root/PORTS.md")
  if [ -n "$rows" ]; then
    while IFS= read -r r; do
      p=$(printf '%s' "$r" | awk -F'|' '{gsub(/[ `]/,"",$2); print $2}')
      if ss -ltn 2>/dev/null | grep -q ":$p "; then s="LISTENING"; else s="not bound"; fi
      ok "$r  → $s"
    done <<< "$rows"
  else
    ok "no open claims"
  fi
  for p in 5038 5273; do
    if ss -ltn 2>/dev/null | grep -q ":$p "; then
      pid=$(ss -ltnp 2>/dev/null | grep ":$p " | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2)
      pcwd=$( [ -n "${pid:-}" ] && readlink "/proc/$pid/cwd" 2>/dev/null || echo '?')
      ok "default port $p is in use (pid ${pid:-?}, cwd $pcwd)"
    fi
  done
fi
claims=$(find "$root" -maxdepth 6 -name CLAIMS.md -path '*Migrations*' -not -path '*/node_modules/*' 2>/dev/null | head -1)
if [ -n "$claims" ]; then
  echo "### Migrations"
  mdir=$(dirname "$claims")
  top=$(ls "$mdir" 2>/dev/null | grep -E '^[0-9]{3}_' | sort | tail -1)
  ok "highest on disk: ${top:-none}  (in this checkout; check origin/main too)"
  rows=$(awk '/^## Open claims/{f=1;next} /^## /{f=0} f && /^\| *[0-9]+/' "$claims")
  if [ -n "$rows" ]; then
    while IFS= read -r r; do ok "claimed: $r"; done <<< "$rows"
  else
    ok "no open claims in CLAIMS.md"
  fi
fi

# ---- .env drift ---------------------------------------------------------------
drift=0
while IFS= read -r ex; do
  env_file="${ex%.example}"
  [ -f "$env_file" ] || { warn ".env missing next to ${ex#$root/}"; drift=1; continue; }
  missing=$(comm -23 <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$ex" | sort -u) <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$env_file" | sort -u) | tr -d '=' | tr '\n' ' ')
  [ -n "$missing" ] && { warn "${env_file#$root/} lacks keys from example: $missing"; drift=1; }
done < <(find "$root" -maxdepth 3 -name '.env.example' -not -path '*/node_modules/*' 2>/dev/null)
[ "$drift" = 0 ] && [ -n "$(find "$root" -maxdepth 3 -name '.env.example' -not -path '*/node_modules/*' 2>/dev/null)" ] && { echo "### Env"; ok ".env files match their .env.example keys"; }

exit 0
