import type { EngineInterface, Register } from 'claude-code'

import { type CacheState, emptyState, forgetIdleSubs, record, statusLine } from './cache'

const TICK_MS = 15_000

async function draw($: EngineInterface, state: CacheState): Promise<void> {
  const now = await $.clock.now()
  forgetIdleSubs(state, now)
  $.ui.status(statusLine(state, now))
}

export const register: Register = on => {
  const state = emptyState()
  let tick: { cancel: () => void } | undefined

  on('session.start', async ($, e, next) => {
    tick?.cancel()
    tick = $.clock.every(TICK_MS, () => void draw($, state))
    await draw($, state)
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    const response = yield* next(e)
    if (response.usage) {
      let label = ''
      if (e.agentId && !state.subs.has(e.agentId)) {
        const agent = (await $.agent.list()).find(a => a.id === e.agentId)
        label = agent?.description ?? agent?.type ?? ''
      }
      record(state, await $.clock.now(), response.usage, e.agentId, label)
      await draw($, state)
    }
    return response
  })
}
