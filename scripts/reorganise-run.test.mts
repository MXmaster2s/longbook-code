// A reorganisation's parts against its ledger row: one share buys one pass, and a pass
// cannot be stretched past its parts or its hours.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { RUN_MS, partAsked, runVerdict } from '../supabase/functions/reorganise/run.ts'

const NOW = Date.parse('2026-10-27T10:00:00Z')
const row = (over: Partial<{ outcome: string; calls: number; started_at: string }> = {}) =>
  ({ outcome: 'read', calls: 1, started_at: new Date(NOW - 60_000).toISOString(), ...over })

test('a run starts at its first part and counts once', () => {
  assert.equal(runVerdict(null, 0, 8, NOW), 'new')
  assert.equal(runVerdict(null, 3, 8, NOW), 'stale', 'a later part needs a counted run')
  assert.equal(runVerdict(row(), 3, 8, NOW), 'continue')
  assert.equal(runVerdict(row(), 0, 8, NOW), 'continue', 'the first part asked again')
})

test('a run whose part gave nothing back is counted afresh when asked again', () => {
  assert.equal(runVerdict(row({ outcome: 'refused' }), 4, 8, NOW), 'new')
})

test('a run is bounded by its calls and its hours', () => {
  assert.equal(runVerdict(row({ calls: 17 }), 7, 8, NOW), 'continue', 'every part retried once, and one more')
  assert.equal(runVerdict(row({ calls: 18 }), 7, 8, NOW), 'stale')
  assert.equal(runVerdict(row({ started_at: new Date(NOW - RUN_MS - 1).toISOString() }), 2, 8, NOW), 'stale')
})

test('the part asked: absent is the whole book, which only fits one part', () => {
  assert.equal(partAsked(undefined, 1), 0)
  assert.equal(partAsked(undefined, 8), 'whole_too_large')
  assert.equal(partAsked(7, 8), 7)
  assert.equal(partAsked(8, 8), null)
  assert.equal(partAsked(-1, 8), null)
  assert.equal(partAsked(1.5, 8), null)
  assert.equal(partAsked('2', 8), null)
})
