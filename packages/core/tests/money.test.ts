// fmtMoney/fmtMoneyTotals — currency formatting, and the never-blend join.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { fmtMoney, fmtMoneyTotals, monthlyEquiv, annualEquiv, cycleLabel } from '../src/domain/money'
import type { Commitment } from '../src/model'

test('fmtMoney trims trailing .00 by default', () => {
  assert.equal(fmtMoney(149, 'INR'), '₹149')
  assert.equal(fmtMoney(20, 'USD'), '$20')
})

test('fmtMoney with cents keeps two decimal places', () => {
  assert.equal(fmtMoney(20, 'USD', { cents: true }), '$20.00')
  assert.equal(fmtMoney(20.5, 'USD', { cents: true }), '$20.50')
})

test('fmtMoney approx drops decimals for whole-number currencies (INR/JPY)', () => {
  assert.equal(fmtMoney(1234.7, 'INR', { approx: true }), '₹1,235')
  assert.match(fmtMoney(1000, 'JPY', { approx: true }), /^.1,000$/, 'no decimal places for yen')
})

test('fmtMoney approx allows at most one decimal for other currencies', () => {
  const s = fmtMoney(10.9, 'USD', { approx: true })
  assert.match(s, /^\$10\.9$/)
})

test('fmtMoney falls back gracefully for a malformed currency code', () => {
  assert.equal(fmtMoney(50, 'ABCD'), 'ABCD 50', 'a 4-letter code is not well-formed ISO 4217 and Intl throws')
})

test('fmtMoneyTotals joins per-currency amounts with " + ", never blending', () => {
  const s = fmtMoneyTotals([
    { currency: 'INR', amount: 149 },
    { currency: 'USD', amount: 20 },
  ])
  assert.equal(s, '₹149 + $20')
})

function sub(p: Partial<Commitment>): Commitment {
  return {
    id: 'x', name: 'X', amount: 0, currency: 'INR',
    billing_cycle: 'monthly', custom_cycle_days: null, has_trial: false, trial_end_date: null,
    next_due_date: '2026-08-06', tag: null, status: 'active',
    account_id: null, member_id: null, notes: null,
    created_at: 'x', updated_at: 'x', ends_on: null, started_on: null, trial_kept: false,
    ...p,
  }
}

test('monthlyEquiv: yearly divides by 12, custom scales by real-days-per-month, once is zero', () => {
  assert.equal(monthlyEquiv(sub({ amount: 1200, billing_cycle: 'yearly' })), 100)
  assert.equal(monthlyEquiv(sub({ amount: 100, billing_cycle: 'monthly' })), 100)
  assert.equal(monthlyEquiv(sub({ amount: 500, billing_cycle: 'once' })), 0, 'a one-time payment is not recurring spend')
  const custom = monthlyEquiv(sub({ amount: 100, billing_cycle: 'custom', custom_cycle_days: 15 }))
  assert.ok(custom > 200 && custom < 204, 'roughly double a 30-day monthly equivalent')
})

test('annualEquiv: monthly times 12, yearly as-is, once is zero', () => {
  assert.equal(annualEquiv(sub({ amount: 100, billing_cycle: 'monthly' })), 1200)
  assert.equal(annualEquiv(sub({ amount: 1200, billing_cycle: 'yearly' })), 1200)
  assert.equal(annualEquiv(sub({ amount: 500, billing_cycle: 'once' })), 0)
})

test('cycleLabel reads in the product voice, not the raw enum value', () => {
  assert.equal(cycleLabel(sub({ billing_cycle: 'monthly' })), 'monthly')
  assert.equal(cycleLabel(sub({ billing_cycle: 'once' })), 'one-time')
  assert.equal(cycleLabel(sub({ billing_cycle: 'custom', custom_cycle_days: 90 })), 'every 90 days')
})
