// Pure cache-state bookkeeping, kept apart from the hooks so it can be tested.

export const MIN = 60_000
export const MAIN_TTL = 60 * MIN // verified in transcripts: main writes to the 1h tier
export const SUB_TTL = 5 * MIN // subagents write to the 5m tier
const OVERAGE_TTL = 5 * MIN // main drops to 5m when the account is in usage overage
const FORGET_SUB_AFTER = 10 * MIN // stop listing a subagent this long after it went cold

export type Usage = {
  input_tokens: number
  output_tokens: number
  cache_read_input_tokens: number
  cache_creation_input_tokens: number
}

export type Loop = {
  lastAt: number
  ttl: number
  context: number // tokens the next request re-sends
  hitRatio: number // share of the last request's prompt served from cache
  unexpectedRebuild: boolean
  label: string
}

export type CacheState = { main: Loop | null; subs: Map<string, Loop> }

export const emptyState = (): CacheState => ({ main: null, subs: new Map() })

const isRebuild = (u: Usage) =>
  u.cache_creation_input_tokens > 0.5 * (u.cache_read_input_tokens + u.cache_creation_input_tokens + u.input_tokens)

// Records one model response. For the main loop, a rebuild after a gap the
// 1h cache should have covered means the TTL is really 5m (overage) or the
// prefix changed (model switch, MCP or CLAUDE.md change).
export function record(state: CacheState, now: number, usage: Usage, agentId?: string, label = ''): void {
  const prompt = usage.input_tokens + usage.cache_read_input_tokens + usage.cache_creation_input_tokens
  const prev = agentId ? state.subs.get(agentId) : state.main
  const gap = prev ? now - prev.lastAt : Infinity
  const rebuild = isRebuild(usage)

  let ttl = agentId ? SUB_TTL : (prev?.ttl ?? MAIN_TTL)
  if (!agentId && prev && gap > OVERAGE_TTL && gap < MAIN_TTL) ttl = rebuild ? OVERAGE_TTL : MAIN_TTL

  const loop: Loop = {
    lastAt: now,
    ttl,
    context: prompt + usage.output_tokens,
    hitRatio: prompt > 0 ? usage.cache_read_input_tokens / prompt : 0,
    unexpectedRebuild: rebuild && prev != null && gap < ttl && prev.context > 20_000,
    label: label || prev?.label || '',
  }
  if (agentId) state.subs.set(agentId, loop)
  else state.main = loop
}

export function forgetIdleSubs(state: CacheState, now: number): void {
  for (const [id, loop] of state.subs) if (now - loop.lastAt > loop.ttl + FORGET_SUB_AFTER) state.subs.delete(id)
}

export const fmtTokens = (n: number) => (n >= 1_000_000 ? `${(n / 1_000_000).toFixed(1)}M` : `${Math.round(n / 1000)}k`)

export function fmtDuration(ms: number): string {
  const m = Math.floor(ms / MIN)
  if (m < 1) return `${Math.max(0, Math.floor(ms / 1000))}s`
  return m < 60 ? `${m}m` : `${Math.floor(m / 60)}h${String(m % 60).padStart(2, '0')}m`
}

function describe(loop: Loop, now: number): string {
  const left = loop.lastAt + loop.ttl - now
  return left > 0 ? `● warm ${fmtDuration(left)}` : `○ cold (idle ${fmtDuration(now - loop.lastAt)})`
}

export function statusLine(state: CacheState, now: number): string {
  const { main } = state
  if (!main && state.subs.size === 0) return 'cache · no requests yet this session'
  const parts: string[] = []
  if (main) {
    const cold = now - main.lastAt >= main.ttl
    let s = `cache ${describe(main, now)} · ${fmtTokens(main.context)} ctx`
    s += cold ? ` · next turn rewrites ~${fmtTokens(main.context)}` : ` · last ${Math.round(main.hitRatio * 100)}% hit`
    if (main.ttl === OVERAGE_TTL) s += ' · TTL 5m (overage?)'
    if (main.unexpectedRebuild) s += ' · ⚠ unexpected rebuild'
    parts.push(s)
  }
  for (const [id, loop] of state.subs) {
    const name = (loop.label || id.slice(0, 6)).slice(0, 24)
    parts.push(`${name}: ${describe(loop, now)} · ${fmtTokens(loop.context)}`)
  }
  return parts.join('  │  ')
}
