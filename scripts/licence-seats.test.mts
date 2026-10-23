// The licence's launch pricing: which price is on sale, how many seats are left, and when a step opens.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { seatsFor, tiersDue } from '../supabase/functions/_shared/licence-seats.ts'

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
