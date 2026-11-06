// The licence's launch pricing: which price is on sale, how many seats are left, and when a step opens.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { WEB_SEATS_FROM, isWebSeat, seatsFor, tiersDue } from '../supabase/functions/_shared/licence-seats.ts'
import { soldSeats, steppedTier } from '../supabase/functions/_shared/seat-count.ts'

test('the first hundred seats sell at the first price', () => {
  assert.deepEqual(seatsFor(0), { sold: 0, tier: 0, price: '38', left: 100, next: '98' })
  assert.deepEqual(seatsFor(99), { sold: 99, tier: 0, price: '38', left: 1, next: '98' })
})

test('the 101st buyer meets the second price, with 250 seats', () => {
  assert.deepEqual(seatsFor(100), { sold: 100, tier: 1, price: '98', left: 250, next: '149' })
  assert.deepEqual(seatsFor(349), { sold: 349, tier: 1, price: '98', left: 1, next: '149' })
})

test('after 350 the last price holds for good', () => {
  assert.deepEqual(seatsFor(350), { sold: 350, tier: 2, price: '149', left: null, next: null })
  assert.deepEqual(seatsFor(10_000).price, '149')
})

test('a step is due once the sale that fills a tier is recorded, and stays due', () => {
  assert.deepEqual(tiersDue(99), [])
  assert.deepEqual(tiersDue(100), [1])
  assert.deepEqual(tiersDue(101), [1], 'a sale that raced past the hundredth still finds the step')
  assert.deepEqual(tiersDue(350), [1, 2])
})

test('nonsense counts read as none sold', () => {
  assert.equal(seatsFor(-3).sold, 0)
})

test('a charged web order from launch pricing on is a seat; earlier, refunded, sandbox or free orders are not', () => {
  const sale = { status: 'paid', amount: 3800, environment: 'production', paid_at: '2026-10-31T10:00:00Z' }
  assert.equal(isWebSeat(sale), true)
  assert.equal(isWebSeat({ ...sale, paid_at: WEB_SEATS_FROM }), true, 'the first day counts')
  assert.equal(isWebSeat({ ...sale, paid_at: '2026-08-14T09:12:00Z' }), false, 'an August order')
  assert.equal(isWebSeat({ ...sale, paid_at: '2026-09-20T23:59:59Z' }), false)
  assert.equal(isWebSeat({ ...sale, status: 'refunded' }), false)
  assert.equal(isWebSeat({ ...sale, environment: 'sandbox' }), false)
  assert.equal(isWebSeat({ ...sale, amount: 0 }), false, 'a free order is no sale')
})

test('App Store and web sales share the one count', () => {
  assert.deepEqual(seatsFor(60 + 40), seatsFor(100), 'a hundred sales between the two sellers fill the first tier')
  assert.deepEqual(tiersDue(99 + 1), [1])
})

test('refunds lower the count, never the price: freed seats are offered at the price already reached', () => {
  assert.deepEqual(seatsFor(98, undefined, 1), { sold: 98, tier: 1, price: '98', left: 252, next: '149' })
  assert.deepEqual(seatsFor(120, undefined, 0).tier, 1, 'a count past a tier still steps on its own')
  assert.deepEqual(seatsFor(10, undefined, 9).tier, 2, 'a step past the last tier holds at the last')
})

/** A query that records each filter and answers what it is given, as supabase-js chains read. */
function fakeService(answer: { count?: number; data?: unknown[] }) {
  const calls: string[] = []
  const chain: Record<string, unknown> = {}
  for (const name of ['select', 'eq', 'not', 'or', 'gt', 'gte', 'order', 'limit']) {
    chain[name] = (...args: unknown[]) => { calls.push(`${name} ${JSON.stringify(args)}`); return chain }
  }
  chain.then = (resolve: (v: unknown) => void) => resolve({ count: answer.count ?? null, data: answer.data ?? null, error: null })
  return { calls, service: { from: (table: string) => { calls.push(`from ${table}`); return chain } } as never }
}

test('a seat is a production App Store purchase still active, or a paid web order: refunds, family copies and sandbox are not', async () => {
  const { calls, service } = fakeService({ count: 7 })
  assert.equal(await soldSeats(service), 14, 'seven of each seller')
  assert.ok(calls.includes('from entitlements'))
  assert.ok(calls.includes('from web_orders'))
  assert.ok(calls.includes('eq ["status","paid"]'), 'a refunded web order is no seat')
  assert.ok(calls.includes('eq ["apple_environment","Production"]'))
  assert.ok(calls.includes('eq ["status","active"]'), 'a refunded licence is revoked and not counted')
  assert.ok(calls.includes('not ["apple_original_transaction_id","is",null]'))
  assert.ok(calls.includes('or ["apple_ownership.is.null,apple_ownership.eq.PURCHASED"]'))
})

test('the price already reached is the highest step claimed, or the first price', async () => {
  assert.equal(await steppedTier(fakeService({ data: [{ tier: 2 }] }).service), 2)
  assert.equal(await steppedTier(fakeService({ data: [] }).service), 0)
  const seats = readFileSync(new URL('../supabase/functions/seats/index.ts', import.meta.url), 'utf8')
  assert.ok(seats.includes('seatsFor(sold, TIERS, stepped)'), 'the bar never shows a price the App Store stepped past')
})
