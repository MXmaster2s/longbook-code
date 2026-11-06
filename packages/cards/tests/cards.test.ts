import { test } from 'node:test'
import assert from 'node:assert/strict'
import { cashflowChart, commitmentsList, nextPaymentCard, upcomingStrip } from '../src/cards.js'
import type { ChargeRow, CommitmentRow } from '../src/cards.js'

const charge = (over: Partial<ChargeRow> = {}): ChargeRow => ({
  commitment_id: 's1',
  name: 'Netflix',
  date: '2026-08-20',
  due: 'in 3 days',
  amount: 649,
  currency: 'INR',
  amount_text: '₹649',
  tag: 'Entertainment',
  member: null,
  account: null,
  paid: false,
  ...over,
})

const commitment = (over: Partial<CommitmentRow> = {}): CommitmentRow => ({
  id: 's1',
  name: 'Netflix',
  amount: 649,
  currency: 'INR',
  amount_text: '₹649',
  cycle: 'monthly',
  status: 'active',
  tag: 'Entertainment',
  member: null,
  account: null,
  next_charge: { date: '2026-08-20', due: 'in 3 days', amount: 649, amount_text: '₹649' },
  planned_through: '2028-07-20',
  charges: 24,
  ...over,
})

function renderAll(): [string, string][] {
  return [
    ['next_payment', nextPaymentCard({
      date: '2026-08-20', due: 'in 3 days',
      total: [{ currency: 'INR', amount: 42649, text: '₹42,649' }],
      total_text: '₹42,649',
      charges: [charge(), charge({ name: 'Rent', amount_text: '₹42,000', paid: true })],
    })],
    ['upcoming', upcomingStrip({
      window_days: 30, count: 2,
      total: [{ currency: 'INR', amount: 42649, text: '₹42,649' }],
      total_text: '₹42,649',
      charges: [charge(), charge({ name: 'Rent' })],
    })],
    ['cashflow', cashflowChart({
      note: 'approximate by design.',
      series: [{ currency: 'INR', months: [
        { month: '2026-08', total: 45828, total_text: '₹45,828', planned: false },
        { month: '2026-09', total: 43728, total_text: '₹43,728', planned: true },
      ] }],
    })],
    ['commitments', commitmentsList({ count: 2, commitments: [commitment(), commitment({ name: 'Rent' })], plans_running_short: [] })],
  ]
}

test('every card is one complete self-contained document', () => {
  for (const [name, html] of renderAll()) {
    assert.ok(html.startsWith('<!doctype html>'), `${name} is a whole document`)
    assert.ok(html.includes('--lb-canvas'), `${name} carries the tokens inline`)
    assert.doesNotMatch(html, /https?:\/\/|url\(|@import|<script|<link/, `${name} fetches nothing`)
  }
})

test('the cards show the numbers they were handed', () => {
  const [next, up, cash, list] = renderAll().map(([, html]) => html)
  assert.match(next!, /₹42,649/)
  assert.match(next!, /in 3 days/)
  assert.match(next!, />paid</)
  assert.match(up!, /NEXT 30 DAYS/)
  assert.match(up!, /2 payments/)
  assert.match(cash!, /Peak month ₹45,828/)
  assert.match(cash!, /opacity="0.45"/)
  assert.match(list!, /2 in the memory/)
  assert.match(list!, /monthly · in 3 days/)
})

test('a hostile name renders as text, never as markup', () => {
  const html = commitmentsList({
    count: 1,
    commitments: [commitment({ name: '<script>alert(1)</script>' })],
    plans_running_short: [],
  })
  assert.doesNotMatch(html, /<script>alert/)
  assert.match(html, /&lt;script&gt;/)
})

test('long lists fold with an honest count', () => {
  const many = Array.from({ length: 20 }, (_, i) => commitment({ name: `Row ${i}` }))
  const html = commitmentsList({ count: 20, commitments: many, plans_running_short: [] })
  assert.match(html, /and 8 more/)
  assert.doesNotMatch(html, /Row 15/)
})

test('a transfer is flagged on its row and figured on a line of its own', () => {
  const bill = charge({ name: 'Coral card bill', amount_text: '₹31,250', direction: 'transfer' })
  const figures = { transfer_count: 1, transfers_total_text: '₹31,250' }
  const total = [{ currency: 'INR', amount: 649, text: '₹649' }]

  const shared = nextPaymentCard({ date: '2026-08-20', due: 'in 3 days', total, total_text: '₹649', ...figures, charges: [charge(), bill] })
  assert.match(shared, /class="amount">₹649</, 'the headline stays the spending total')
  assert.match(shared, /1 transfer, ₹31,250 · between your own accounts, in no total/)
  assert.equal(shared.match(/>transfer</g)?.length, 1, 'only the transfer row wears the flag')

  const up = upcomingStrip({ window_days: 30, count: 2, total, total_text: '₹649', ...figures, charges: [charge(), bill] })
  assert.match(up, /1 payment · ₹649/, 'a transfer is not counted among the payments')
  assert.match(up, /1 transfer, ₹31,250/)
  assert.match(up, />transfer</)

  const list = commitmentsList({
    count: 3, plans_running_short: [],
    commitments: [commitment(), commitment({ name: 'To savings', direction: 'transfer' }), commitment({ name: 'Salary', direction: 'in' })],
  })
  assert.equal(list.match(/>transfer</g)?.length, 1)
  assert.equal(list.match(/>money in</g)?.length, 1)
})

test('a day that holds only a transfer leads with it, never with an empty total', () => {
  const html = nextPaymentCard({
    date: '2026-08-20', due: 'in 3 days', total: [], total_text: 'no spending',
    transfer_count: 1, transfers_total_text: '₹31,250',
    charges: [charge({ name: 'Coral card bill', amount_text: '₹31,250', direction: 'transfer' })],
  })
  assert.match(html, /class="amount">1 transfer</)
  assert.doesNotMatch(html, /no spending/)
  assert.match(html, /<p class="note"[^>]*>₹31,250 · between your own accounts, in no total/)
})

test('a list with no transfer says nothing about them', () => {
  const [next, up, , list] = renderAll().map(([, html]) => html)
  for (const html of [next!, up!, list!]) assert.doesNotMatch(html, /transfer|money in/)
})

test('an unreadable memory still renders a message card', () => {
  const html = nextPaymentCard({ message: 'Nothing is due.' })
  assert.ok(html.startsWith('<!doctype html>'))
  assert.match(html, /Nothing is due\./)
})
