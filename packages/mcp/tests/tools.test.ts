import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  accounts,
  cashflow,
  charges,
  commitments,
  members,
  nextPayment,
  search,
  spendingByAccount,
  spendingByCategory,
  spendingByMember,
  tags,
  upcoming,
} from '../src/tools.js'
import { parseVault } from '../src/parse.js'
import { TODAY, aMonthAfterInDays, fixture, inDays, inMonths, mkRow, mkSub, monthOf } from './fixtures.js'

test('next_payment stacks the soonest day and skips charges already marked paid', () => {
  const day = nextPayment(fixture(), TODAY)
  if (!('date' in day)) throw new Error('expected a payment day, got the empty message')
  assert.equal(day.date, inDays(3))
  // Netflix lands that day too, but its mark is on record — Rent and Claude still owe.
  assert.deepEqual(day.charges.map((c) => c.name), ['Rent', 'Claude'])
  assert.deepEqual(day.total, [
    { currency: 'INR', amount: 42000, text: '₹42,000' },
    { currency: 'USD', amount: 20, text: '$20' },
  ])
})

test('upcoming lists the rows in the window, sorted, totalled per currency, paid marks worn', () => {
  const result = upcoming(fixture(), 30, TODAY)
  const dates = result.charges.map((c) => c.date)
  assert.deepEqual(dates, [...dates].sort())
  // Netflix in 3 days, Rent, Claude, iCloud in 8, water cans on the 5th, 15th and 25th.
  assert.equal(result.count, 7)
  assert.equal(result.charges.find((c) => c.name === 'Netflix')?.paid, true)
  assert.equal(result.charges.find((c) => c.name === 'Netflix')?.basis, 'mark_paid')
  assert.deepEqual(
    result.total.map((t) => [t.currency, t.amount]),
    [['INR', 649 + 42000 + 179 + 900], ['USD', 20]],
  )
  assert.equal(result.total.length, 2)
  assert.match(result.total_text, /₹.*\+.*\$/)
})

test('upcoming names a plan that runs out inside its window', () => {
  const data = fixture()
  data.subs.push(mkSub({ id: 's-gas', name: 'Gas cylinder', amount: 1100 }))
  data.charges!.push(mkRow('s-gas', inDays(10), 1100))
  const result = upcoming(data, 30, TODAY)
  assert.deepEqual(result.plans_running_short.map((p) => p.name), ['Gas cylinder', 'Water cans'], 'soonest to run out first')
})

test('charges lists the ledger itself, one commitment or all, filtered by window and paid', () => {
  const all = charges(fixture(), {}, TODAY)
  if (!('count' in all)) throw new Error('expected rows')
  assert.equal(all.count, fixture().charges!.length)
  const netflix = charges(fixture(), { name: 'Netflix', paid: true }, TODAY)
  if (!('count' in netflix)) throw new Error('expected rows')
  assert.equal(netflix.count, 2)
  assert.deepEqual(netflix.charges.map((c) => c.basis), ['statement', 'mark_paid'])
  const past = charges(fixture(), { to: inDays(-1) }, TODAY)
  if (!('count' in past)) throw new Error('expected rows')
  assert.equal(past.count, 3, 'last month’s Netflix and two Hotstars — a cancelled commitment’s past still counts')
  const missing = charges(fixture(), { name: 'Nobody' }, TODAY)
  assert.ok('message' in missing)
})

test('cashflow sums the rows month by month, marks months ahead as the plan, filters by currency', () => {
  const result = cashflow(fixture(), 1, 12, 'INR', TODAY)
  assert.equal(result.series.length, 1)
  const months = result.series[0]!.months
  assert.equal(months.length, 14)
  assert.equal(months[1]!.month, monthOf(TODAY))
  assert.equal(months[0]!.planned, false)
  assert.equal(months[1]!.planned, false)
  assert.ok(months.slice(2).every((m) => m.planned))
  // Last month: Netflix 649 and Hotstar 299 landed.
  assert.equal(months[0]!.total, 649 + 299)
})

test('spending groups sum the rows in the window per currency; a past window shows what was spent', () => {
  const cats = spendingByCategory(fixture(), undefined, undefined, TODAY).groups
  const entertainment = cats.find((g) => g.tag === 'Entertainment')!
  // Twelve Netflix and twelve iCloud rows ahead, across the coming year.
  assert.deepEqual(entertainment.total, [{ currency: 'INR', amount: 12 * 649 + 12 * 179, text: '₹9,936' }])
  assert.equal(entertainment.commitments, 2)
  const insurance = cats.find((g) => g.tag === 'Insurance')!
  assert.equal(insurance.total[0]!.amount, 18400, 'a yearly charge is its full amount, never a twelfth')
  const work = cats.find((g) => g.tag === 'Work')!
  assert.deepEqual(work.total.map((m) => m.currency), ['USD'])

  const lastMonth = spendingByCategory(fixture(), inMonths(-1, 1), inDays(-1), TODAY).groups
  assert.equal(lastMonth.find((g) => g.tag === 'Entertainment')!.total[0]!.amount, 649 + 299)
})

test('spending by account and member name their groups from the vault', () => {
  const accounts = spendingByAccount(fixture(), undefined, undefined, TODAY).groups
  assert.ok(accounts.some((g) => g.account === 'HDFC Current account'))
  assert.ok(accounts.some((g) => g.account === 'Unassigned'))
  const members = spendingByMember(fixture(), undefined, undefined, TODAY).groups
  assert.ok(members.some((g) => g.member === 'Rohit'))
})

test('commitments filters by status, keeps yearly amounts yearly, and says how far each is planned', () => {
  const active = commitments(fixture(), 'active', TODAY)
  assert.equal(active.count, 7)
  const car = active.commitments.find((c) => c.name === 'Car insurance')!
  assert.equal(car.amount, 18400)
  assert.equal(car.cycle, 'yearly')
  assert.equal(car.planned_through, inDays(40))
  assert.equal(car.charges, 1)
  const netflix = active.commitments.find((c) => c.name === 'Netflix')!
  assert.equal(netflix.next_charge?.date, aMonthAfterInDays(3), 'the one in three days is paid; the next unpaid is a month on')
  const cancelled = commitments(fixture(), 'cancelled', TODAY)
  assert.deepEqual(cancelled.commitments.map((c) => c.name), ['Hotstar'])
  assert.ok(active.plans_running_short.some((p) => p.name === 'Water cans'))
})

test('a one-time commitment whose charge is behind today is a charge now, counted rather than listed', () => {
  const data = fixture()
  data.subs.push(mkSub({ id: 's-visa', name: 'Visa fee', amount: 1200, billing_cycle: 'once' }))
  data.charges!.push(mkRow('s-visa', inDays(-9), 1200))
  const active = commitments(data, 'active', TODAY)
  assert.equal(active.commitments.some((c) => c.name === 'Visa fee'), false)
  assert.equal(active.settled_one_time, 1)
  assert.match(active.note ?? '', /1 one-time commitment .* is not listed/)
  assert.ok(active.commitments.some((c) => c.name === 'Flight to Goa'), 'the one still ahead is a commitment')
  assert.ok(commitments(data, 'all', TODAY).commitments.some((c) => c.name === 'Visa fee'))
  assert.equal(commitments(fixture(), 'active', TODAY).note, undefined)
  const paid = charges(data, { name: 'Visa fee', paid: true }, TODAY)
  if (!('count' in paid)) throw new Error('expected rows')
  assert.equal(paid.count, 1, 'nobody marked it, but the day has passed')
  assert.equal(paid.charges[0]!.basis, 'plan')
})

test('a commitment with no rows has no next charge and no plan', () => {
  const data = fixture()
  data.subs.push(mkSub({ id: 's-empty', name: 'Nothing written', amount: 1 }))
  const row = commitments(data, 'active', TODAY).commitments.find((c) => c.name === 'Nothing written')!
  assert.equal(row.next_charge, null)
  assert.equal(row.planned_through, null)
  assert.equal(row.charges, 0)
})

test('cashflow keeps a currency alive when its only row is a one-time payment', () => {
  const data = fixture()
  data.subs.push(mkSub({ id: 's-visa', name: 'Visa fee', amount: 1200, currency: 'GBP', billing_cycle: 'once' }))
  data.charges!.push(mkRow('s-visa', inDays(20), 1200))
  const currencies = cashflow(data, 0, 12, undefined, TODAY).series.map((s) => s.currency)
  assert.ok(currencies.includes('GBP'))
})

/** The shared memory plus a card bill due in 2 days, a standing move to savings, and a salary. */
function withTransfers() {
  const data = fixture()
  data.subs.push(
    mkSub({ id: 's-bill', name: 'Coral card bill', amount: 31250, billing_cycle: 'once', direction: 'transfer', tag: 'Home', member_id: 'm-rohit', account_id: 'pm-icici' }),
    mkSub({ id: 's-save', name: 'To savings', amount: 5000, direction: 'transfer', account_id: 'pm-hdfc' }),
    mkSub({ id: 's-pay', name: 'Vertex Labs salary', amount: 214000, direction: 'in', account_id: 'pm-hdfc' }),
  )
  data.charges!.push(
    mkRow('s-bill', inDays(2), 31250, { basis: 'email' }),
    mkRow('s-save', inMonths(-1, 1), 5000, { paid: true, basis: 'statement' }),
    mkRow('s-save', inDays(3), 5000),
    mkRow('s-pay', inMonths(-1, 1), 214000, { paid: true, basis: 'statement' }),
  )
  return data
}

test('a transfer is listed and flagged wherever charges are, with a figure of its own', () => {
  const data = withTransfers()
  const plain = upcoming(fixture(), 30, TODAY)
  const result = upcoming(data, 30, TODAY)
  assert.equal(result.count, plain.count + 2, 'the bill and the move to savings are in the window')
  assert.deepEqual(result.total, plain.total, 'and the total is what it was without them')
  assert.equal(result.transfer_count, 2)
  assert.deepEqual(result.transfers_total, [{ currency: 'INR', amount: 36250, text: '₹36,250' }])
  assert.match(result.note ?? '', /never in total/)
  assert.equal(plain.transfer_count, undefined, 'a list with no transfer says nothing about them')
  const bill = result.charges.find((c) => c.name === 'Coral card bill')!
  assert.deepEqual([bill.direction, bill.date, bill.basis, bill.paid], ['transfer', inDays(2), 'email', false])
  assert.equal(result.charges.find((c) => c.name === 'Rent')!.direction, null)
  const dates = result.charges.map((c) => c.date)
  assert.deepEqual(dates, [...dates].sort(), 'one timeline, soonest first')

  // The bill is the next thing owed: its day is named, with nothing on it to spend.
  const day = nextPayment(data, TODAY)
  if (!('date' in day)) throw new Error('expected a day')
  assert.equal(day.date, inDays(2))
  assert.deepEqual(day.total, [])
  assert.equal(day.total_text, 'no spending')
  assert.equal(day.transfers_total_text, '₹31,250')
  assert.deepEqual(day.charges.map((c) => [c.name, c.direction]), [['Coral card bill', 'transfer']])

  const ledger = charges(data, {}, TODAY)
  if (!('count' in ledger)) throw new Error('expected rows')
  assert.equal(ledger.count, fixture().charges!.length + 3, 'three transfer rows beside the charges; money in is read by name')
  assert.deepEqual(ledger.total, (charges(fixture(), {}, TODAY) as typeof ledger).total)
  assert.equal(ledger.transfers_total![0]!.amount, 31250 + 5000 + 5000)
  const own = charges(data, { name: 'To savings' }, TODAY)
  if (!('count' in own)) throw new Error('expected rows')
  assert.deepEqual([own.count, own.total, own.transfers_total![0]!.amount], [2, [], 10000])

  const listed = commitments(data, 'active', TODAY).commitments
  assert.equal(listed.find((c) => c.name === 'Coral card bill')!.direction, 'transfer')
  assert.equal(listed.find((c) => c.name === 'Coral card bill')!.next_charge?.date, inDays(2))
  assert.deepEqual(search(data, 'coral', TODAY).commitments.map((c) => [c.name, c.direction]), [['Coral card bill', 'transfer']])
})

test('charges by a name two commitments share says so with both ids, never the first one silently', () => {
  const data = withTransfers()
  data.subs.push(mkSub({ id: 's-bill-2', name: ' coral CARD bill ', amount: 28900, billing_cycle: 'once', direction: 'transfer', status: 'paused' }))
  data.charges!.push(mkRow('s-bill-2', inDays(32), 28900, { basis: 'email' }))
  const shared = charges(data, { name: 'Coral card bill' }, TODAY)
  if (!('ambiguous' in shared)) throw new Error('expected the two matches, not rows')
  assert.match(shared.message ?? '', /"Coral card bill" matches more than one commitment — pass an id/)
  assert.deepEqual(shared.ambiguous, [
    { id: 's-bill', name: 'Coral card bill', status: 'active', cycle: 'one-time', direction: 'transfer', charges: 1, first_charge: inDays(2), last_charge: inDays(2) },
    { id: 's-bill-2', name: ' coral CARD bill ', status: 'paused', cycle: 'one-time', direction: 'transfer', charges: 1, first_charge: inDays(32), last_charge: inDays(32) },
  ])
  const byId = charges(data, { id: 's-bill-2' }, TODAY)
  if (!('count' in byId)) throw new Error('expected rows')
  assert.deepEqual(byId.charges.map((c) => c.date), [inDays(32)], 'an id is always one commitment')
  const single = charges(data, { name: 'to savings' }, TODAY)
  assert.ok('count' in single, 'a name only one commitment wears still reads its rows')
})

test('a transfer is in no sum: not a month, not a category, not an account, not a person', () => {
  const data = withTransfers()
  const same = <T>(read: (d: ReturnType<typeof fixture>) => T) => assert.deepEqual(read(data), read(fixture()))
  same((d) => cashflow(d, 1, 12, undefined, TODAY).series)
  same((d) => spendingByCategory(d, undefined, undefined, TODAY).groups)
  same((d) => spendingByAccount(d, undefined, undefined, TODAY).groups)
  same((d) => spendingByMember(d, undefined, undefined, TODAY).groups)
  same((d) => spendingByAccount(d, inMonths(-1, 1), inDays(-1), TODAY).groups)
  assert.match(cashflow(data, 0, 1, undefined, TODAY).note, /transfers between the owner's own accounts are in no month/)
  assert.match(spendingByCategory(data, undefined, undefined, TODAY).note, /money in and transfers/)
})

test('accounts reads every account as the owner would describe it, with what is billed to it', () => {
  const data = withTransfers()
  const [bank, card] = data.methods
  Object.assign(card!, {
    tag: 'credit card', last4: '9292', institution: 'ICICI', member_id: 'm-diya', parent_account_id: bank!.id,
    details: { card_name: 'Coral', due_day: 5 }, notes: 'Shared card.', balance: 31250, balance_date: inDays(-10),
  })
  data.methods.push({ ...bank!, id: 'pm-cash', name: 'Cash', name_key: 'cash' })
  const result = accounts(data, TODAY)
  assert.equal(result.count, 3)
  assert.deepEqual(result.accounts[1], {
    id: 'pm-icici', name: 'ICICI Joint Account', type: 'credit card', institution: 'ICICI', last4: '9292',
    belongs_to: 'Diya', linked_to: 'HDFC Current account', balance: 31250, balance_date: inDays(-10), notes: 'Shared card.',
    details: { card_name: 'Coral', due_day: 5 },
    commitments: 2, charges: 14,
    next_unpaid_charge: {
      commitment_id: 's-bill', name: 'Coral card bill', date: inDays(2), due: 'in 2 days',
      amount: 31250, currency: 'INR', amount_text: '₹31,250', direction: 'transfer',
    },
  })
  const hdfc = result.accounts[0]!
  assert.deepEqual([hdfc.type, hdfc.belongs_to, hdfc.linked_to, hdfc.balance, hdfc.notes], [null, null, null, null, null])
  assert.equal('last4' in hdfc, false, 'absent rather than null')
  assert.equal('details' in hdfc, false, 'an account holding no details carries no key')
  assert.equal('card_name' in result.accounts[1]!, false, 'the card name is read where it is stored')
  assert.equal(hdfc.commitments, 6, 'Rent, iCloud+, Car insurance, Claude, the move to savings and the salary')
  assert.equal(hdfc.next_unpaid_charge?.name, 'Rent', 'the salary is never owed; of two on one day, the bigger')
  assert.deepEqual(result.accounts[2]!.next_unpaid_charge, null)
  assert.equal(result.accounts[2]!.commitments, 0)
  assert.match(result.note, /linked_to is the account this one is linked to/)
  assert.match(result.note, /balance_note appears when the balance held is older than the newest confirmed charge/)

  // The card's statement row is a month old, older than its balance: nothing to say. A
  // newer statement row makes the balance stale; a plan row past the balance's day never does.
  assert.equal('balance_note' in result.accounts[1]!, false)
  data.charges!.push(mkRow('s-netflix', inDays(-3), 649), mkRow('s-netflix', inDays(-5), 649, { paid: true, basis: 'statement' }))
  const stale = accounts(data, TODAY)
  assert.equal(
    stale.accounts[1]!.balance_note,
    `Balance as of ${inDays(-10)}, older than the newest confirmed charge on ${inDays(-5)} — a statement that prints a closing balance updates it with update_account (balance_date its last day).`,
  )
  assert.equal('balance_note' in stale.accounts[0]!, false, 'an account holding no balance is never stale')
})

test('members reads every person with their tag, their accounts and what is for them', () => {
  const data = withTransfers()
  data.members[1]!.tag = 'family'
  data.members[1]!.email = 'diya@example.com'
  data.members[1]!.details = { relationship: 'sister', birth_date: '1994-03-02' }
  data.methods[1]!.member_id = 'm-diya'
  const result = members(data, TODAY)
  assert.equal(result.count, 2)
  assert.deepEqual(result.members[1], {
    id: 'm-diya', name: 'Diya', tag: 'family', email: 'diya@example.com', accounts: ['ICICI Joint Account'],
    details: { relationship: 'sister', birth_date: '1994-03-02' },
    commitments: 1, charges: 13,
    next_unpaid_charge: {
      commitment_id: 's-netflix', name: 'Netflix', date: aMonthAfterInDays(3), due: result.members[1]!.next_unpaid_charge!.due,
      amount: 649, currency: 'INR', amount_text: '₹649', direction: null,
    },
  })
  const first = result.members[0]!
  assert.deepEqual([first.tag, first.email, first.accounts], [null, null, []])
  assert.equal('details' in first, false, 'a person holding no details carries no key')
  assert.equal(first.commitments, 3, 'Rent, Car insurance and the card bill')
  assert.equal(first.next_unpaid_charge?.name, 'Coral card bill')
})

test('search reaches names, notes, members and accounts, case-insensitively', () => {
  const data = fixture()
  assert.deepEqual(search(data, 'landlord', TODAY).commitments.map((c) => c.name), ['Rent'])
  assert.deepEqual(search(data, 'ICICI', TODAY).commitments.map((c) => c.name), ['Netflix'])
  const byMember = search(data, 'rohit', TODAY).commitments.map((c) => c.name)
  assert.deepEqual(byMember.sort(), ['Car insurance', 'Rent'])
})

test('a commitment row carries the details it holds, from commitments and search alike', () => {
  const held = { lender: 'HDFC Bank', policy_doc: 'documents/loan.pdf', statement_line: 'EMI HDFC 4521' }
  const data = parseVault(JSON.stringify({
    app: 'longbook',
    version: 3,
    commitments: [
      { id: 's1', name: 'Home loan', amount: 32000, currency: 'INR', billing_cycle: 'monthly', status: 'active', notes: 'Loan ends: 2031-03-05', details: held },
      { id: 's2', name: 'Netflix', amount: 649, currency: 'INR', billing_cycle: 'monthly', status: 'active' },
      { id: 's3', name: 'Gym', amount: 1500, currency: 'INR', billing_cycle: 'monthly', status: 'paused', details: {} },
    ],
  }))
  const rows = commitments(data, 'all', TODAY).commitments
  assert.deepEqual(rows.find((c) => c.name === 'Home loan')?.details, held, 'every key, statement_line too, as stored')
  for (const bare of ['Netflix', 'Gym']) {
    assert.equal('details' in rows.find((c) => c.name === bare)!, false, `${bare}: a row holding none carries no key`)
  }
  assert.deepEqual(search(data, 'home loan', TODAY).commitments[0]?.details, held)
})

test('tags shows no template on any tag, even one the vault holds with a template', () => {
  const data = parseVault(JSON.stringify({
    app: 'longbook',
    version: 3,
    commitments: [{ id: 's1', name: 'Term plan', amount: 24600, currency: 'INR', billing_cycle: 'yearly', status: 'active', tag: 'insurance' }],
    tags: [
      { id: 't1', kind: 'commitment', name: 'insurance', name_key: 'insurance', is_default: true, template: [{ key: 'insurer', label: 'Insurer', hint: 'text' }] },
      { id: 't2', kind: 'account', name: 'credit card', name_key: 'credit card', is_default: true, template: [{ key: 'card_name', label: 'Card name', hint: 'text' }] },
      { id: 't3', kind: 'member', name: 'family', name_key: 'family', is_default: true, template: [{ key: 'relationship', label: 'Relationship', hint: 'text' }] },
    ],
  }))
  const answer = tags(data)
  assert.equal(answer.in_vault.find((t) => t.name === 'insurance')!.worn_by, 1)
  assert.equal(answer.in_vault.find((t) => t.name === 'credit card')!.icon, null, 'the rest of the entry reads as held')
  for (const tag of [...answer.in_vault, ...answer.library]) assert.equal('template' in tag, false, `${tag.kind} ${tag.name}`)
  assert.ok(answer.library.some((t) => t.kind === 'account' && t.name === 'debit card'), 'the library lists every kind')
  assert.match(answer.note, /notes, one per line/)
  assert.match(answer.note, /an account's details are lines of its notes too/)
})
