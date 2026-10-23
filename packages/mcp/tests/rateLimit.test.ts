import { test } from 'node:test'
import assert from 'node:assert/strict'
import { RateLimiter } from '../src/rateLimit.js'

test('the window admits its limit, refuses the next, and forgets in time', () => {
  const limiter = new RateLimiter(3, 60_000)
  const t0 = 1_000_000
  assert.equal(limiter.allow('u1', t0).allowed, true)
  assert.equal(limiter.allow('u1', t0 + 1_000).allowed, true)
  assert.equal(limiter.allow('u1', t0 + 2_000).allowed, true)
  const refused = limiter.allow('u1', t0 + 3_000)
  assert.equal(refused.allowed, false)
  assert.ok(refused.retryAfterSeconds >= 1)
  // Another key is untouched; the first key recovers once the window slides past.
  assert.equal(limiter.allow('u2', t0 + 3_000).allowed, true)
  assert.equal(limiter.allow('u1', t0 + 61_000).allowed, true)
})
