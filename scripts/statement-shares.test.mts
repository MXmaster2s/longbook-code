// The monthly share of server-read statements: by Cloud, by grant, and when it opens again.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { MONTH_MS, shareFor, withinShare } from '../supabase/functions/_shared/statement-shares.ts'

const RULE = { free: 10, cloud: 50 }
const NOW = Date.parse('2026-10-13T12:00:00Z')
const daysAgo = (n: number): string => new Date(NOW - n * 24 * 60 * 60 * 1000).toISOString()

test('the share follows Cloud unless the account has its own grant', () => {
  assert.equal(shareFor(RULE, false, null), 10)
  assert.equal(shareFor(RULE, true, undefined), 50)
  assert.equal(shareFor(RULE, false, 200), 200)
  assert.equal(shareFor(RULE, true, 0), 0, 'a grant of none shuts the door even with Cloud')
})

test('files older than a month do not count', () => {
  const started = [daysAgo(31), daysAgo(45), daysAgo(2)]
  assert.deepEqual(withinShare(10, started, NOW), { allowed: 10, used: 1 })
})

test('the share is spent at the cap, and opens when the file that filled it is a month old', () => {
  const started = Array.from({ length: 10 }, (_, i) => daysAgo(20 - i))
  const answer = withinShare(10, started, NOW)
  assert.equal(answer.used, 10)
  // The oldest counted file started 20 days ago; the share opens 10 days from now.
  assert.equal(answer.resetsOn, new Date(NOW + 10 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10))
})

test('with Cloud the same month of files is well within the share', () => {
  const started = Array.from({ length: 10 }, (_, i) => daysAgo(20 - i))
  assert.deepEqual(withinShare(50, started, NOW), { allowed: 50, used: 10 })
})

test('a share of none waits a whole month and never divides by zero', () => {
  const answer = withinShare(0, [], NOW)
  assert.equal(answer.resetsOn, new Date(NOW + MONTH_MS).toISOString().slice(0, 10))
})
