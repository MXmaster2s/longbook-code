// Spend by group is summed from the rows in a window — never amortised from a rule, never
// blended across currencies. Every fixture is SYNTHETIC; this repo is public.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spendByTag, spendByMember, spendByMethod, defaultWindow } from '../src/selectors'
import { parseDate, toISO } from '../src/domain/dates'
import type { Commitment, ChargeRow, Member, Account } from '../src/model'

const today = parseDate('2026-07-21')

function sub(p: Partial<Commitment> & { id: string }): Commitment {
  return {
    name: p.id, amount: 100, currency: 'INR', billing_cycle: 'monthly', custom_cycle_days: null,
    tag: null, status: 'active', account_id: null, member_id: null, notes: null,
    ends_on: null, created_at: 'x', updated_at: 'x', ...p,
  }
}

function row(commitment_id: string, date: string, amount = 100, extra: Partial<ChargeRow> = {}): ChargeRow {
  return { commitment_id, date, amount, paid: false, basis: 'plan', ...extra }
}

const members: Member[] = [{ id: 'm1', name: 'Aditi', name_key: 'aditi', tag: null, avatar_seed: '', is_incomplete: false, email: null, created_at: 'x' }]
const methods: Account[] = [{ id: 'a1', name: 'HDFC', name_key: 'hdfc', nickname: null, institution: null, last4: null, tag: null, member_id: null, parent_account_id: null, is_incomplete: false, created_at: 'x' }]

test('the default window is the twelve months from today, inclusive of the last day', () => {
  const w = defaultWindow(today)
  assert.equal(toISO(w.from), '2026-07-21')
  assert.equal(toISO(w.to), '2027-07-20')
})

test('spendByTag sums the rows in the window and keeps currencies apart', () => {
  const subs = [sub({ id: 'a', tag: 'streaming' }), sub({ id: 'b', tag: 'streaming', currency: 'USD' }), sub({ id: 'c' })]
  const rows = [
    row('a', '2026-08-01', 649), row('a', '2026-09-01', 649),
    row('b', '2026-08-01', 20),
    row('c', '2026-08-01', 5),
    row('a', '2025-01-01', 9999), // outside the window
  ]
  const w = defaultWindow(today)
  const out = spendByTag(subs, rows, w.from, w.to)
  const streaming = out.find((g) => g.name === 'streaming')!
  assert.deepEqual(streaming.totalByCurrency, { INR: 1298, USD: 20 })
  assert.deepEqual(streaming.countByCurrency, { INR: 2, USD: 1 })
  assert.equal(streaming.commitments, 2)
  assert.equal(out.find((g) => g.name === 'Untagged')!.totalByCurrency.INR, 5)
  assert.equal(out[0]!.name, 'streaming', 'biggest first')
})

test('a row in its own currency is counted in that currency', () => {
  const subs = [sub({ id: 'a', tag: 'travel' })]
  const rows = [row('a', '2026-08-01', 100), row('a', '2026-09-01', 30, { currency: 'USD' })]
  const w = defaultWindow(today)
  assert.deepEqual(spendByTag(subs, rows, w.from, w.to)[0]!.totalByCurrency, { INR: 100, USD: 30 })
})

test('spendByMember attributes to the real name and buckets unassigned as Unknown', () => {
  const subs = [sub({ id: 'a', member_id: 'm1' }), sub({ id: 'b' })]
  const rows = [row('a', '2026-08-01', 100), row('b', '2026-08-01', 40)]
  const w = defaultWindow(today)
  const out = spendByMember(subs, rows, members, w.from, w.to)
  assert.deepEqual(out.map((g) => [g.name, g.totalByCurrency.INR]), [['Aditi', 100], ['Unknown', 40]])
})

test('spendByMethod attributes to the real account and buckets unassigned separately', () => {
  const subs = [sub({ id: 'a', account_id: 'a1' }), sub({ id: 'b' })]
  const rows = [row('a', '2026-08-01', 100), row('b', '2026-08-01', 40)]
  const w = defaultWindow(today)
  const out = spendByMethod(subs, rows, methods, w.from, w.to)
  assert.deepEqual(out.map((g) => [g.name, g.totalByCurrency.INR]), [['HDFC', 100], ['Unassigned', 40]])
})

test('a cancelled commitment’s past rows still count in a past window', () => {
  const subs = [sub({ id: 'a', tag: 'gym', status: 'cancelled' })]
  const rows = [row('a', '2026-05-01', 1500, { paid: true, basis: 'statement' })]
  const out = spendByTag(subs, rows, parseDate('2026-05-01'), parseDate('2026-05-31'))
  assert.equal(out[0]!.totalByCurrency.INR, 1500)
})

test('a transfer and money in are in no group, whatever tag, account or person they name', () => {
  const subs = [
    sub({ id: 'a', tag: 'home', member_id: 'm1', account_id: 'a1' }),
    sub({ id: 't', tag: 'home', member_id: 'm1', account_id: 'a1', direction: 'transfer' }),
    sub({ id: 'i', tag: 'home', member_id: 'm1', account_id: 'a1', direction: 'in' }),
  ]
  const rows = [row('a', '2026-08-01', 100), row('t', '2026-08-02', 31250), row('i', '2026-08-03', 90000)]
  const w = defaultWindow(today)
  assert.deepEqual(spendByTag(subs, rows, w.from, w.to).map((g) => g.totalByCurrency), [{ INR: 100 }])
  assert.deepEqual(spendByMethod(subs, rows, methods, w.from, w.to).map((g) => [g.name, g.totalByCurrency.INR, g.count]), [['HDFC', 100, 1]])
  assert.deepEqual(spendByMember(subs, rows, members, w.from, w.to).map((g) => [g.name, g.totalByCurrency.INR, g.commitments]), [['Aditi', 100, 1]])
})
