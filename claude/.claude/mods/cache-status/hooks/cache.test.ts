import { expect, test } from 'claude-code/testing'

import { MAIN_TTL, MIN, SUB_TTL, emptyState, forgetIdleSubs, record, statusLine } from './cache'

const hit = { input_tokens: 2, output_tokens: 500, cache_read_input_tokens: 200_000, cache_creation_input_tokens: 1_000 }
const rebuild = { input_tokens: 2, output_tokens: 500, cache_read_input_tokens: 0, cache_creation_input_tokens: 201_000 }

test('main is warm for an hour after a request, then cold with the rebuild size', () => {
  const s = emptyState()
  record(s, 0, hit)
  expect(s.main?.ttl).toBe(MAIN_TTL)
  expect(statusLine(s, 10 * MIN)).toContain('● warm 50m')
  expect(statusLine(s, 10 * MIN)).toContain('100% hit')
  expect(statusLine(s, 61 * MIN)).toContain('○ cold (idle 1h01m)')
  expect(statusLine(s, 61 * MIN)).toContain('next turn rewrites ~202k')
})

test('subagents go cold after five minutes and are forgotten later', () => {
  const s = emptyState()
  record(s, 0, hit, 'agent-1', 'Explore auth')
  expect(s.subs.get('agent-1')?.ttl).toBe(SUB_TTL)
  expect(statusLine(s, 4 * MIN)).toContain('Explore auth: ● warm 1m')
  expect(statusLine(s, 6 * MIN)).toContain('Explore auth: ○ cold')
  forgetIdleSubs(s, 16 * MIN)
  expect(s.subs.size).toBe(0)
})

test('a rebuild after a 20 minute gap means main is on the 5m TTL', () => {
  const s = emptyState()
  record(s, 0, hit)
  record(s, 20 * MIN, rebuild)
  expect(s.main?.ttl).toBe(5 * MIN)
  expect(statusLine(s, 20 * MIN)).toContain('TTL 5m (overage?)')
  expect(s.main?.unexpectedRebuild).toBe(false) // the cache had expired under the 5m TTL, so not unexpected
})

test('a rebuild within the TTL is flagged as unexpected', () => {
  const s = emptyState()
  record(s, 0, hit)
  record(s, 1 * MIN, rebuild)
  expect(statusLine(s, 1 * MIN)).toContain('⚠ unexpected rebuild')
  record(s, 2 * MIN, hit)
  expect(statusLine(s, 2 * MIN)).not.toContain('unexpected')
})

test('says so before the first request, so the mod is visibly loaded', () => {
  expect(statusLine(emptyState(), 0)).toBe('cache · no requests yet this session')
})
