// The ledger read by the hosted server and the npm bin, pinned to the SAME cases as
// packages/swift-core's SelectorTests — if they disagree, the app and the server disagree
// about one file. Every fixture is SYNTHETIC; this repo is public.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  allCharges,
  chargesOf,
  chargesInRange,
  nextChargeOnOrAfter,
  nextPaymentDay,
  nextDueDay,
  transferCharges,
  incomeCharges,
  isSpending,
  storedDirection,
  activeUpcoming,
  liveCommitments,
  plannedThrough,
  plansRunningShort,
  planCharges,
  stepFrom,
  sumByCurrency,
  spendSeriesRange,
} from '../src/ledger'
import { parseDate, toISO } from '../src/domain/dates'
import type { Commitment, ChargeRow } from '../src/model'

const today = parseDate('2026-07-21')

function sub(p: Partial<Commitment> & { id: string }): Commitment {
  return {
    name: p.id.toUpperCase(), amount: 100, currency: 'INR', billing_cycle: 'monthly', custom_cycle_days: null,
    tag: null, status: 'active', account_id: null, member_id: null, notes: null,
    ends_on: null, created_at: 'x', updated_at: 'x', ...p,
  }
}

function row(commitment_id: string, date: string, extra: Partial<ChargeRow> = {}): ChargeRow {
  return { commitment_id, date, amount: 100, paid: false, basis: 'plan', ...extra }
}

function monthly(id: string, first: string, months: number): ChargeRow[] {
  const start = parseDate(first)
  return Array.from({ length: months }, (_, k) => {
    const d = new Date(start.getFullYear(), start.getMonth() + k, start.getDate())
    return row(id, toISO(d))
  })
}

test('a row whose commitment is gone, or whose date is unreadable, is never a charge', () => {
  const subs = [sub({ id: 'a' })]
  const rows = [row('ghost', '2026-07-22'), row('a', 'not a day'), row('a', '2026-07-23')]
  assert.deepEqual(allCharges(subs, rows).map((c) => c.row.date), ['2026-07-23'])
})

test('the next payment day is the soonest unpaid row on or after today, both charges, biggest first', () => {
  const subs = [sub({ id: 'a' }), sub({ id: 'b' })]
  const rows = [
    row('a', '2026-07-20', { paid: true }),
    row('a', '2026-07-21', { amount: 40 }),
    row('b', '2026-07-21', { amount: 60 }),
    row('a', '2026-08-21', { amount: 40 }),
  ]
  const day = nextPaymentDay(subs, rows, today)!
  assert.equal(day.days, 0)
  assert.deepEqual(day.charges.map((c) => c.sub.name), ['B', 'A'])
})

test('money in is never the next payment owed', () => {
  const salary = sub({ id: 's', name: 'Salary', direction: 'in' })
  const rent = sub({ id: 'r', name: 'Rent' })
  const rows = [row('s', '2026-07-21', { amount: 150000 }), row('r', '2026-07-25', { amount: 42000 })]
  const day = nextPaymentDay([salary, rent], rows, today)!
  assert.deepEqual(day.charges.map((c) => c.sub.name), ['Rent'])
  assert.equal(nextPaymentDay([salary], rows, today), null)
})

test('a transfer is shown and owed, and is never a charge that a sum could reach', () => {
  const bill = sub({ id: 'bill', name: 'Coral card bill', billing_cycle: 'once', direction: 'transfer' })
  const save = sub({ id: 'save', name: 'To savings', direction: 'transfer' })
  const rent = sub({ id: 'rent', name: 'Rent' })
  const subs = [bill, save, rent]
  const rows = [
    row('save', '2026-07-05', { amount: 5000, paid: true }),
    row('bill', '2026-07-23', { amount: 31250 }),
    row('rent', '2026-07-25', { amount: 42000 }),
    row('save', '2026-08-05', { amount: 5000 }),
  ]
  assert.deepEqual(allCharges(subs, rows, today).map((c) => c.sub.id), ['rent'], 'only spending is a charge')
  assert.deepEqual(transferCharges(subs, rows, today).map((c) => c.sub.id), ['save', 'bill', 'save'])
  assert.deepEqual(incomeCharges(subs, rows, today), [], 'a transfer is not money in either')
  assert.deepEqual([bill, save, rent].map(isSpending), [false, false, true])
  assert.equal(sumByCurrency(chargesInRange(subs, rows, parseDate('2026-07-01'), parseDate('2026-08-31'), today))[0]!.amount, 42000)
  assert.deepEqual(spendSeriesRange(subs, rows, 'INR', 0, 1, today).map((p) => p.total), [42000, 0])

  // The day spending is next owed keeps its meaning; nothing else is due on it here.
  const spend = nextPaymentDay(subs, rows, today)!
  assert.equal(toISO(spend.date), '2026-07-25')
  assert.deepEqual(spend.transfers, [])
  // The day anything is next owed is the bill's, with nothing to sum on it.
  const due = nextDueDay(subs, rows, today)!
  assert.equal(toISO(due.date), '2026-07-23')
  assert.deepEqual(due.charges, [])
  assert.deepEqual(due.transfers.map((c) => c.sub.name), ['Coral card bill'])
  assert.equal(nextPaymentDay([bill, save], rows, today), null, 'a transfer alone is never a payment day')
  assert.equal(toISO(nextDueDay([bill, save], rows, today)!.date), '2026-07-23')

  // Owed like a charge: live while unpaid, in the upcoming list, and a plan that can run short.
  assert.deepEqual(liveCommitments(subs, rows, today).map((s) => s.id), ['bill', 'save', 'rent'])
  assert.deepEqual(activeUpcoming(subs, rows, today).map((d) => d.sub.id), ['bill', 'rent', 'save'])
  assert.deepEqual(plansRunningShort(subs, rows, 90, today).map((p) => p.sub.id), ['rent', 'save'])
})

test('a stored direction is absence for a charge, and a word from a newer contract is kept as written', () => {
  assert.deepEqual([undefined, null, '', 'out', 7].map(storedDirection), [null, null, null, null, null])
  assert.deepEqual(['in', 'transfer', 'lend'].map(storedDirection), ['in', 'transfer', 'lend'])
  // Read, an unknown direction is spending: it is in the sums until a version names it.
  const lend = sub({ id: 'l', name: 'To a friend', direction: 'lend' })
  assert.equal(isSpending(lend), true)
  assert.deepEqual(allCharges([lend], [row('l', '2026-07-22')], today).map((c) => c.sub.id), ['l'])
})

test('a transfer due on a spending day rides beside that day’s charges, apart from them', () => {
  const subs = [sub({ id: 'rent', name: 'Rent' }), sub({ id: 'bill', name: 'Coral card bill', billing_cycle: 'once', direction: 'transfer' })]
  const rows = [row('rent', '2026-07-25', { amount: 42000 }), row('bill', '2026-07-25', { amount: 31250 })]
  for (const day of [nextPaymentDay(subs, rows, today)!, nextDueDay(subs, rows, today)!]) {
    assert.deepEqual(day.charges.map((c) => c.sub.id), ['rent'])
    assert.deepEqual(day.transfers.map((c) => c.sub.id), ['bill'])
  }
})

test('a charge marked paid is skipped for the next one, but is still the next charge', () => {
  const a = sub({ id: 'a' })
  const rows = [row('a', '2026-07-21', { paid: true }), row('a', '2026-08-21')]
  assert.equal(nextPaymentDay([a], rows, today)!.days, 31)
  assert.equal(nextChargeOnOrAfter(a, rows, today)!.row.date, '2026-07-21')
})

test('a paused or lapsed commitment is not payable', () => {
  const subs = [sub({ id: 'p', status: 'paused' }), sub({ id: 'e', ends_on: '2026-07-01' })]
  const rows = [row('p', '2026-07-25'), row('e', '2026-07-25')]
  assert.equal(nextPaymentDay(subs, rows, today), null)
})

test('activeUpcoming is soonest first and only rows ahead; a settled one-time drops out', () => {
  const subs = [sub({ id: 'a' }), sub({ id: 'b' }), sub({ id: 'c' }), sub({ id: 'd', billing_cycle: 'once' })]
  const rows = [row('a', '2026-09-01'), row('b', '2026-08-01'), row('c', '2026-07-01'), row('d', '2026-06-10', { paid: true })]
  assert.deepEqual(activeUpcoming(subs, rows, today).map((d) => d.sub.name), ['B', 'A'])
  assert.equal(activeUpcoming(subs, rows, today)[0]!.days, 11)
})

test('a charge behind today reads paid whatever its row says; today and ahead keep their mark', () => {
  const subs = [sub({ id: 'a' })]
  const rows = [row('a', '2026-07-20'), row('a', '2026-07-21'), row('a', '2026-08-21', { paid: true })]
  const charges = allCharges(subs, rows, today)
  assert.deepEqual(charges.map((c) => c.paid), [true, false, true])
  assert.equal(charges[0]!.row.paid, false)
  assert.equal(chargesOf(subs[0]!, rows, parseDate('2026-07-22'))[1]!.paid, true)
})

test('a one-time commitment is live until its charge is behind today or marked paid; a recurring one while active', () => {
  const subs = [
    sub({ id: 'ahead', billing_cycle: 'once' }), sub({ id: 'behind', billing_cycle: 'once' }),
    sub({ id: 'early', billing_cycle: 'once' }), sub({ id: 'blank', billing_cycle: 'once' }),
    sub({ id: 'short' }), sub({ id: 'paused', status: 'paused' }),
  ]
  const rows = [row('ahead', '2026-07-21'), row('behind', '2026-07-20'), row('early', '2026-08-01', { paid: true }), row('short', '2026-06-01')]
  assert.deepEqual(liveCommitments(subs, rows, today).map((s) => s.id), ['ahead', 'blank', 'short'])
})

test('planned through is the last row, and short plans are named — never a one-time or an ending one', () => {
  const subs = [sub({ id: 'short' }), sub({ id: 'long' }), sub({ id: 'once', billing_cycle: 'once' }), sub({ id: 'ending', ends_on: '2026-09-01' })]
  const rows = [
    ...monthly('short', '2026-07-01', 3), ...monthly('long', '2026-07-01', 24),
    row('once', '2026-08-01'), ...monthly('ending', '2026-07-01', 3),
  ]
  assert.equal(toISO(plannedThrough(subs[0]!, rows)!), '2026-09-01')
  assert.deepEqual(plansRunningShort(subs, rows, 90, today).map((p) => p.sub.id), ['short'])
  assert.deepEqual(plansRunningShort(subs, rows, 30, today), [])
})

test('twenty-four months is twenty-four rows, horizon exclusive', () => {
  const rows = planCharges(sub({ id: 'a' }), parseDate('2026-09-01'), 24, 649, new Set(), 't')
  assert.equal(rows.length, 24)
  assert.equal(rows[0]!.date, '2026-09-01')
  assert.equal(rows[23]!.date, '2028-08-01')
  assert.ok(rows.every((r) => r.basis === 'plan' && !r.paid && r.amount === 649 && r.written_at === 't'))
})

test('yearly and custom cycles step their own way; once gets one', () => {
  assert.deepEqual(planCharges(sub({ id: 'y', billing_cycle: 'yearly' }), parseDate('2026-03-15'), 24, 1, new Set(), 't').map((r) => r.date),
    ['2026-03-15', '2027-03-15'])
  assert.deepEqual(planCharges(sub({ id: 'w', billing_cycle: 'custom', custom_cycle_days: 10 }), parseDate('2026-07-01'), 1, 1, new Set(), 't').map((r) => r.date),
    ['2026-07-01', '2026-07-11', '2026-07-21', '2026-07-31'])
  assert.deepEqual(planCharges(sub({ id: 'o', billing_cycle: 'once' }), parseDate('2026-08-10'), 24, 5, new Set(), 't').map((r) => r.date),
    ['2026-08-10'])
})

test('days a file holds past what any write takes step as a hundred years, and fewer than one as one', () => {
  const far = sub({ id: 'f', billing_cycle: 'custom', custom_cycle_days: 99_999_999_999_999_999 })
  const anchor = parseDate('2026-07-01')
  assert.equal(toISO(stepFrom(far, anchor, 1)), '2126-06-07')
  assert.equal(toISO(stepFrom(far, anchor, 93)), '11320-04-28')
  assert.equal(toISO(stepFrom(sub({ id: 'z', billing_cycle: 'custom', custom_cycle_days: 0 }), anchor, 3)), '2026-07-04')
  assert.deepEqual(planCharges(far, anchor, 2400, 1, new Set(), 't').map((r) => r.date), ['2026-07-01', '2126-06-07', '2226-05-14'])
})

test('the cancelling date is inclusive, a first charge past it writes nothing, and written days are skipped', () => {
  const a = sub({ id: 'a', ends_on: '2026-10-01' })
  assert.deepEqual(planCharges(a, parseDate('2026-08-01'), 24, 1, new Set(), 't').map((r) => r.date),
    ['2026-08-01', '2026-09-01', '2026-10-01'])
  assert.deepEqual(planCharges(a, parseDate('2026-11-01'), 24, 1, new Set(), 't'), [])
  assert.deepEqual(planCharges(sub({ id: 'b' }), parseDate('2026-08-01'), 3, 1, new Set(['2026-09-01']), 't').map((r) => r.date),
    ['2026-08-01', '2026-10-01'])
})

test('month ends clamp rather than overflow', () => {
  assert.deepEqual(planCharges(sub({ id: 'a' }), parseDate('2026-01-31'), 3, 1, new Set(), 't').map((r) => r.date),
    ['2026-01-31', '2026-02-28', '2026-03-31'])
})

test('sums never blend and honour a row’s own currency; the series reads rows and leaves empty months empty', () => {
  const subs = [sub({ id: 'a' })]
  const rows = [row('a', '2026-07-21', { amount: 100 }), row('a', '2026-09-21', { amount: 2, currency: 'USD' })]
  assert.deepEqual(sumByCurrency(allCharges(subs, rows)).map((s) => `${s.currency}:${s.amount}`), ['INR:100', 'USD:2'])
  const series = spendSeriesRange(subs, rows, 'INR', 1, 3, today)
  assert.deepEqual(series.map((p) => p.total), [0, 100, 0, 0, 0])
  assert.equal(series[1]!.estimated, false)
  assert.equal(series[2]!.estimated, true)
  assert.equal(chargesInRange(subs, rows, parseDate('2026-08-01'), parseDate('2026-08-31')).length, 0)
  assert.equal(chargesOf(subs[0]!, rows).length, 2)
})
