// The write path over real temp vaults: every save validated, scanned, signed, and
// atomic — and every refusal leaving the file byte-for-byte as it was.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { existsSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { DATA_POLICY_REFUSAL, parseDate, stepFrom, toISO, todayMid } from '@longbook/core'

// A refusal's words before the reason it adds (what was found, where, how to file again).
const bare = (message: string): string => message.replace(/ Found what looks like [^.]+\. Remove it \(a card's last four digits are fine\) and file again\.$/, '')
import { NOTHING_TO_PLAN, checkProposal, dayTakenRefusal, noChargeRefusal, notActiveRefusal, pastCancellingRefusal } from '../src/proposal.js'
import { CAS_MESSAGE, writeVault } from '../src/vaultWrite.js'
import {
  addCharges, addCommitments, cancelCommitment, deleteCommitment, markPaid, promoteToRecurring, removeChargesTool,
  setPlannedCount, updateCharge, updateCommitment,
} from '../src/writeTools.js'

const SEED = {
  app: 'longbook',
  version: 3,
  commitments: [
    { id: 'c-net', name: 'Netflix', amount: 649, currency: 'INR', billing_cycle: 'monthly', status: 'active' },
    { id: 'c-gym-a', name: 'Gym', amount: 1500, currency: 'INR', billing_cycle: 'monthly', status: 'active' },
    { id: 'c-gym-b', name: 'gym ', amount: 900, currency: 'INR', billing_cycle: 'monthly', status: 'paused' },
    { id: 'c-old', name: 'Hotstar', amount: 299, currency: 'INR', billing_cycle: 'monthly', status: 'cancelled' },
  ],
  charges: [
    { commitment_id: 'c-net', date: '2026-09-01', amount: 649, paid: false, basis: 'plan' },
    { commitment_id: 'c-net', date: '2026-10-01', amount: 649, paid: false, basis: 'plan' },
    { commitment_id: 'c-net', date: '2026-11-01', amount: 649, paid: false, basis: 'plan' },
    { commitment_id: 'c-gym-a', date: '2026-09-05', amount: 1500, paid: false, basis: 'plan' },
  ],
  members: [{ id: 'm-rohit', name: 'Rohit', name_key: 'rohit' }],
  accounts: [{ id: 'a-hdfc', name: 'HDFC', name_key: 'hdfc' }],
}

function seeded(vault: unknown = SEED): { dir: string; file: string } {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-mcp-write-'))
  const file = join(dir, 'financial_memory.json')
  writeFileSync(file, JSON.stringify(vault, null, 2))
  return { dir, file }
}

const fileJson = (file: string) => JSON.parse(readFileSync(file, 'utf8')) as Record<string, any>
const noLitter = (dir: string) =>
  assert.deepEqual(readdirSync(dir).filter((f) => f.endsWith('.tmp')), [])

const ROW = {
  name: 'Claude',
  amount: 20,
  currency: 'USD',
  billing_cycle: 'monthly' as const,
  first_charge: '2026-09-10',
  plan_months: 3,
}
const one = (over: Record<string, unknown> = {}) => ({ rows: [{ ...ROW, ...over }] })

test('a batch lands every row in one write, signs each, resolves and creates entities', () => {
  const { dir, file } = seeded()
  const report = addCommitments(dir, 'claude', {
    rows: [
      { ...ROW, tag: 'work', notes: 'annual review in march', member: '  rohit ', account: 'ICICI Amazon' },
      { name: 'Car insurance', amount: 18400, currency: 'INR', billing_cycle: 'yearly', first_charge: '2024-03-12', plan_months: 36, tag: 'insurance', notes: 'Policy number: 88213\nDocument: documents/car-policy.pdf' },
      { name: 'Airport taxi', amount: 950, currency: 'INR', billing_cycle: 'once', date: '2026-04-08', paid: true, basis: 'statement' },
    ],
  }) as Record<string, any>

  const vault = fileJson(file)
  assert.equal(vault.commitments.length, 7)
  const claude = vault.commitments.find((c: any) => c.name === 'Claude')
  assert.equal(claude.member_id, 'm-rohit')
  assert.equal(vault.members.length, 1)
  const account = vault.accounts.find((a: any) => a.name === 'ICICI Amazon')
  assert.equal(claude.account_id, account.id)
  assert.equal(account.is_incomplete, true)

  const car = vault.commitments.find((c: any) => c.name === 'Car insurance')
  assert.equal(car.notes, 'Policy number: 88213\nDocument: documents/car-policy.pdf', 'the details that matter, one per line')
  assert.equal(car.details, undefined)
  const rowsOf = (id: string) => (vault.charges as any[]).filter((r) => r.commitment_id === id).map((r) => r.date)
  assert.deepEqual(rowsOf(car.id), ['2024-03-12', '2025-03-12', '2026-03-12'], 'a yearly plan of three years is three rows')
  assert.deepEqual(rowsOf(claude.id), ['2026-09-10', '2026-10-10', '2026-11-10'])
  const taxi = vault.commitments.find((c: any) => c.name === 'Airport taxi')
  const taxiRow = (vault.charges as any[]).find((r) => r.commitment_id === taxi.id)
  assert.equal(taxiRow.paid, true)
  assert.equal(taxiRow.basis, 'statement')
  assert.equal(report.charges_written, 7)

  for (const name of ['Claude', 'Car insurance', 'Airport taxi']) {
    const row = vault.commitments.find((c: any) => c.name === name)
    assert.equal(vault._provenance[row.id].edited_by, 'claude')
  }
  assert.equal(report.added, 3)
  assert.deepEqual(report.accounts_created, ['ICICI Amazon'])
  noLitter(dir)
})

test('a source rides into every touched row\'s provenance; a card-like source refuses', () => {
  const { dir, file } = seeded()
  addCommitments(dir, 'claude', { ...one(), source: ' documents/hdfc-2026.pdf ' })
  markPaid(dir, 'claude', { id: 'c-net', date: '2026-09-01', source: 'gmail:18c2a' })
  updateCommitment(dir, 'claude', { id: 'c-gym-a', set: { amount: 1600 } })
  const vault = fileJson(file)
  const claude = vault.commitments.find((c: any) => c.name === 'Claude')
  assert.equal(vault._provenance[claude.id].source, 'documents/hdfc-2026.pdf')
  assert.equal(vault._provenance['c-net'].source, 'gmail:18c2a')
  assert.equal(vault._provenance['c-gym-a'].source, undefined)
  assert.throws(
    () => cancelCommitment(dir, 'claude', { id: 'c-gym-a', source: 'card 4111 1111 1111 1111' }),
    new RegExp(DATA_POLICY_REFUSAL.slice(0, 30)),
  )
  assert.throws(() => cancelCommitment(dir, 'claude', { id: 'c-gym-a', source: 'x'.repeat(201) }), /200 characters/)
  noLitter(dir)
})

test('a worn library tag registers with its icon and no template; an invented one lands bare', () => {
  const { dir, file } = seeded()
  addCommitments(dir, 'claude', {
    rows: [
      { ...ROW, tag: 'Insurance' },
      { ...ROW, name: 'Society fund', tag: 'colony kitty' },
    ],
  })
  const tags = fileJson(file).tags as any[]
  const insurance = tags.find((t) => t.name_key === 'insurance')
  assert.equal(insurance.kind, 'commitment')
  assert.equal(insurance.icon, 'shield.checkered')
  assert.equal(insurance.is_default, true)
  assert.equal(insurance.template, undefined, 'a commitment tag carries no template')
  const kitty = tags.find((t) => t.name_key === 'colony kitty')
  assert.equal(kitty.is_default, false)
  assert.equal(kitty.icon, undefined)
  assert.match(kitty.id, /^[0-9a-f-]{36}$/)
})

test('a tag already registered is not registered twice', () => {
  const { dir, file } = seeded()
  addCommitments(dir, 'claude', one({ tag: 'insurance' }))
  addCommitments(dir, 'claude', one({ name: 'Bike insurance', tag: ' INSURANCE ' }))
  const tags = fileJson(file).tags as any[]
  assert.equal(tags.filter((t) => t.name_key === 'insurance').length, 1)
})

test('a batch answers with what it wrote, and asks nothing of a tag: a commitment tag has no fields', () => {
  const { dir } = seeded()
  const bare = addCommitments(dir, 'claude', one({ name: 'Term plan', tag: 'Insurance' })) as Record<string, any>
  assert.equal(bare.added, 1)
  assert.equal(bare.details_wanted, undefined)
  assert.equal(bare.details_note, undefined)
})

// details is longbook's own on a commitment. A write sending it is refused by name, in the
// hosted door's words, and the file is left as it was.
const DETAILS = "details is longbook's own — write a commitment's details as lines of its notes"

test('add_commitments refuses a row that sends details, naming the row, and writes nothing', () => {
  const { dir, file } = seeded()
  const before = readFileSync(file)
  assert.throws(
    () => addCommitments(dir, 'claude', {
      rows: [{ ...ROW }, { ...ROW, name: 'Term plan', tag: 'insurance', notes: 'Policy number: 88213', details: { insurer: 'HDFC ERGO', policy_doc: 'documents/term.pdf' } }],
    } as never),
    { message: `Nothing was written. Fix these and send the batch again — row 2 ("Term plan"): ${DETAILS}.` },
  )
  assert.deepEqual(readFileSync(file), before)
  noLitter(dir)
})

test('update_commitment refuses details beside a field it takes and alone, in the same words', () => {
  const { dir, file } = seeded({
    ...SEED,
    commitments: [
      ...SEED.commitments,
      { id: 'c-line', name: 'Netflix', amount: 649, currency: 'INR', billing_cycle: 'once', status: 'active', details: { statement_line: 'UPI-NETFLIX.COM' } },
    ],
  })
  const before = readFileSync(file)
  for (const set of [{ notes: 'Plan: Premium', details: { plan: 'Premium' } }, { details: { plan: 'Premium' } }]) {
    assert.throws(() => updateCommitment(dir, 'claude', { id: 'c-line', set } as never), { message: `Nothing was changed. Fix these — ${DETAILS}.` })
  }
  assert.deepEqual(readFileSync(file), before, 'nothing was written')

  // Details that say nothing refuse nothing: the rest is written, longbook's own line kept.
  updateCommitment(dir, 'claude', { id: 'c-line', set: { notes: 'Plan: Premium', details: {} } } as never)
  const row = fileJson(file).commitments.find((c: any) => c.id === 'c-line')
  assert.equal(row.notes, 'Plan: Premium')
  assert.deepEqual(row.details, { statement_line: 'UPI-NETFLIX.COM' })
  noLitter(dir)
})

test('promote_to_recurring refuses details it is sent, and carries the first row\'s own', () => {
  const { dir, file } = seeded({
    ...SEED,
    commitments: [
      ...SEED.commitments,
      { id: 'p1', name: 'Netflix', amount: 649, currency: 'INR', billing_cycle: 'once', status: 'active', details: { statement_line: 'UPI-NETFLIX.COM' } },
      { id: 'p2', name: 'Netflix', amount: 649, currency: 'INR', billing_cycle: 'once', status: 'active' },
    ],
    charges: [
      ...SEED.charges,
      { commitment_id: 'p1', date: '2026-07-05', amount: 649, paid: true, basis: 'statement' },
      { commitment_id: 'p2', date: '2026-08-05', amount: 649, paid: true, basis: 'statement' },
    ],
  })
  const before = readFileSync(file)
  assert.throws(
    () => promoteToRecurring(dir, 'claude', { ids: ['p1', 'p2'], billing_cycle: 'monthly', plan_months: 1, notes: 'Plan: Standard', details: { plan: 'Standard' } } as never),
    { message: `${DETAILS}.` },
  )
  assert.deepEqual(readFileSync(file), before, 'nothing was written')

  const report = promoteToRecurring(dir, 'claude', { ids: ['p1', 'p2'], billing_cycle: 'monthly', plan_months: 1, notes: 'Plan: Standard' }) as Record<string, any>
  const promoted = fileJson(file).commitments.find((c: any) => c.id === report.promoted.id)
  assert.equal(promoted.notes, 'Plan: Standard')
  assert.deepEqual(promoted.details, { statement_line: 'UPI-NETFLIX.COM' })
  noLitter(dir)
})

test('one bad row refuses the whole batch, naming each offender, file unchanged', () => {
  const { dir, file } = seeded()
  const before = readFileSync(file)
  assert.throws(
    () =>
      addCommitments(dir, 'claude', {
        rows: [
          { ...ROW },
          { ...ROW, name: 'Broken', amount: -5, first_charge: '2026-02-30' },
          { ...ROW, name: 'Also broken', billing_cycle: 'custom' as const },
        ],
      }),
    /row 2 \("Broken"\).*zero or more.*row 2.*real calendar day.*row 3 \("Also broken"\).*custom_cycle_days/s,
  )
  assert.deepEqual(readFileSync(file), before)
  noLitter(dir)
})

test('a recurring row needs a first charge; paid and basis belong to a one-time row; zero amounts are allowed', () => {
  const { dir, file } = seeded()
  assert.throws(() => addCommitments(dir, 'claude', one({ first_charge: undefined })), /first_charge/)
  assert.throws(() => addCommitments(dir, 'claude', one({ paid: true })), /one-time row/)
  assert.throws(() => addCommitments(dir, 'claude', one({ billing_cycle: 'once', first_charge: undefined })), /date/)
  addCommitments(dir, 'claude', one({ name: 'Health checkup', amount: 0 }))
  assert.equal(fileJson(file).commitments.find((c: any) => c.name === 'Health checkup').amount, 0)
})

test('a card number anywhere in a batch refuses, naming the row', () => {
  const { dir, file } = seeded()
  const before = readFileSync(file)
  assert.throws(
    () => addCommitments(dir, 'claude', one({ name: 'Visa', notes: 'card 4111 1111 1111 1111' })),
    new RegExp(`${DATA_POLICY_REFUSAL.slice(0, 30)}[^]*"Visa"`),
  )
  assert.deepEqual(readFileSync(file), before)
  noLitter(dir)
})

// A refusal an agent reads never repeats what it refused: a row whose name is the secret is
// named by its place in the batch, or by its id when it has none.
test('a secret refusal names a row by its name only when the name scans clean', () => {
  const { dir, file } = seeded()
  const before = readFileSync(file)
  const card = '4111 1111 1111 1111'
  const calls: [string, () => unknown, string][] = [
    ['a row named by the card', () => addCommitments(dir, 'claude', { rows: [{ ...ROW }, { ...ROW, name: card }] }), '(row 2)'],
    ['a member named by the card', () => addCommitments(dir, 'claude', { rows: [{ ...ROW, member: card }] }), '(row 1)'],
    ['a clean name, a card in its notes', () => addCommitments(dir, 'claude', one({ name: 'Visa', notes: `card ${card}` })), '(row 1: "Visa")'],
    ['a rename to the card', () => updateCommitment(dir, 'claude', { id: 'c-net', set: { name: card } }), '(row: "c-net")'],
  ]
  for (const [what, call, named] of calls) {
    assert.throws(call, (error: Error) => {
      assert.ok(error.message.startsWith(DATA_POLICY_REFUSAL), `${what}: ${error.message}`)
      assert.ok(bare(error.message).endsWith(named), `${what}: ${error.message}`)
      assert.ok(error.message.includes('Found what looks like'), `${what} says what it found`)
      assert.ok(!error.message.includes('4111'), `${what} never repeats what it refused: ${error.message}`)
      return true
    })
  }
  assert.deepEqual(readFileSync(file), before)
  noLitter(dir)
})

// A refusal no batch place can name names what the call addressed — a commitment by the name
// or id it was given, a promotion by its ids — in the hosted door's words, never an id the
// refused write would have made.
test('a secret refusal names what the call addressed, as the hosted door names it', () => {
  const { dir, file } = seeded({
    ...SEED,
    commitments: [...SEED.commitments,
      { id: 'p1', name: 'UPI-RAMESH', amount: 6000, currency: 'INR', billing_cycle: 'once', status: 'active' },
      { id: 'p2', name: 'UPI-RAMESH', amount: 6000, currency: 'INR', billing_cycle: 'once', status: 'active' }],
    charges: [...SEED.charges,
      { commitment_id: 'p1', date: '2026-07-01', amount: 6000, paid: true, basis: 'statement' },
      { commitment_id: 'p2', date: '2026-08-01', amount: 6000, paid: true, basis: 'statement' }],
  })
  const before = readFileSync(file)
  const card = '4111 1111 1111 1111'
  const write = (kind: string, args: Record<string, unknown>) =>
    kind === 'update_commitment' ? updateCommitment(dir, 'claude', args as never) : promoteToRecurring(dir, 'claude', args as never)
  const calls: [string, Record<string, unknown>, string][] = [
    ['update_commitment', { id: 'c-net', set: { member: card } }, '(row: "c-net")'],
    ['update_commitment', { name: 'Netflix', set: { account: card } }, '(row: "Netflix")'],
    ['promote_to_recurring', { ids: ['p1', 'p2'], billing_cycle: 'monthly', name: card }, '(ids: p1, p2)'],
    ['promote_to_recurring', { ids: ['p1', 'p2'], billing_cycle: 'monthly', name: 'Cook', member: card }, '(row: "Cook")'],
  ]
  for (const [kind, args, named] of calls) {
    const words = `${DATA_POLICY_REFUSAL} ${named}`
    assert.throws(() => write(kind, args), (error: Error) => bare(error.message) === words, `${kind} ${JSON.stringify(args)}`)
    assert.throws(() => checkProposal(kind, args), (error: Error) => bare(error.message) === words, `${kind}: the hosted door says the same`)
  }
  assert.deepEqual(readFileSync(file), before)
  noLitter(dir)
})

// Past a quadrillion a figure is a slip: refused wherever an amount is written, in the words
// the hosted door and the app give, and the limit itself is kept.
test('an amount past the limit is refused on every write that takes one', () => {
  const { dir, file } = seeded()
  const before = readFileSync(file)
  const huge = 9.3e18
  const words = /the amount can't be more than 1,000,000,000,000,000/i
  assert.throws(() => addCommitments(dir, 'claude', one({ amount: huge })), /row 1 \("Claude"\): the amount can't be more than 1,000,000,000,000,000/)
  assert.throws(() => updateCommitment(dir, 'claude', { id: 'c-net', set: { amount: huge } }), words)
  assert.throws(() => markPaid(dir, 'claude', { id: 'c-net', date: '2026-09-01', amount: huge }), (error: Error) =>
    error.message === "The amount can't be more than 1,000,000,000,000,000.")
  assert.throws(() => addCharges(dir, 'claude', { id: 'c-net', charges: [{ date: '2026-12-01', amount: huge }] }), /charge 1: the amount can't be more than/)
  assert.deepEqual(readFileSync(file), before)
  addCommitments(dir, 'claude', one({ name: 'At the limit', amount: 1e15 }))
  assert.equal(fileJson(file).commitments.find((c: any) => c.name === 'At the limit').amount, 1e15)
})

// Switching to one-time would leave one row standing for a commitment's history and plan.
test('a commitment holding several charges is never made one-time; a sole charge moves to the new date', () => {
  const { dir, file } = seeded({
    ...SEED,
    commitments: [...SEED.commitments,
      { id: 'c-sofa', name: 'Sofa', amount: 500, currency: 'INR', billing_cycle: 'once', status: 'active' },
      { id: 'c-fee', name: 'Visa fee', amount: 300, currency: 'INR', billing_cycle: 'monthly', status: 'active' }],
    charges: [...SEED.charges,
      { commitment_id: 'c-sofa', date: '2026-07-01', amount: 500, paid: true, basis: 'statement' },
      { commitment_id: 'c-fee', date: '2026-07-05', amount: 300, paid: true, basis: 'statement' }],
  })
  const before = readFileSync(file)
  assert.throws(
    () => updateCommitment(dir, 'claude', { id: 'c-net', set: { billing_cycle: 'once', date: '2026-09-01' } }),
    (error: Error) => error.message === 'One-time holds a single charge, and this has 3. Cancel it instead to stop its plan.',
  )
  assert.deepEqual(readFileSync(file), before, 'nothing was written')

  const days = (id: string) => fileJson(file).charges.filter((c: any) => c.commitment_id === id).map((c: any) => [c.date, c.paid])
  updateCommitment(dir, 'claude', { id: 'c-fee', set: { billing_cycle: 'once', date: '2026-08-05' } })
  assert.deepEqual(days('c-fee'), [['2026-08-05', true]], 'a sole charge moves to the one-time commitment\'s date, paid mark kept')
  updateCommitment(dir, 'claude', { id: 'c-sofa', set: { date: '2026-07-03' } })
  assert.deepEqual(days('c-sofa'), [['2026-07-03', true]], 'a commitment one-time already moves its charge')
})

// add_charges takes a one-time commitment, so one can hold two charges; a date cannot say which moves.
test('a one-time commitment holding several charges refuses a date, in the app\'s words, and nothing moves', () => {
  const { dir, file } = seeded({
    ...SEED,
    commitments: [...SEED.commitments, { id: 'c-sofa', name: 'Sofa', amount: 500, currency: 'INR', billing_cycle: 'once', status: 'active' }],
    charges: [...SEED.charges,
      { commitment_id: 'c-sofa', date: '2026-07-01', amount: 500, paid: true, basis: 'statement' },
      { commitment_id: 'c-sofa', date: '2026-09-01', amount: 500, paid: false, basis: 'user' }],
  })
  const before = readFileSync(file)
  for (const date of ['2026-09-10', '2026-09-01']) {
    assert.throws(
      () => updateCommitment(dir, 'claude', { id: 'c-sofa', set: { date, notes: 'Delivered in two parts' } }),
      (error: Error) => error.message === 'This one-time commitment has 2 charges. Move the one you mean from the charge itself.',
    )
  }
  assert.deepEqual(readFileSync(file), before, 'nothing was written')
  const report = updateCommitment(dir, 'claude', { id: 'c-sofa', set: { notes: 'Delivered in two parts' } })
  assert.deepEqual(report, { updated: { id: 'c-sofa', name: 'Sofa' }, fields: ['notes'] })
  assert.deepEqual(fileJson(file).charges.filter((c: any) => c.commitment_id === 'c-sofa').map((c: any) => c.date), ['2026-07-01', '2026-09-01'])
})

// A key the tool does not take is never reported as written: it is named, with the key meant
// where one is, and the rest of the write lands.
test('update_commitment answers with the fields it wrote and names the keys it does not take', () => {
  const { dir, file } = seeded()
  const report = updateCommitment(dir, 'claude', { id: 'c-net', set: { notes: 'Plan: Premium', cancelling_on: '2026-12-31', colour: 'red' } } as never)
  assert.deepEqual(report, {
    updated: { id: 'c-net', name: 'Netflix' },
    fields: ['notes'],
    ignored: ['cancelling_on — the cancelling date is ends_on', 'colour'],
  })
  const row = fileJson(file).commitments.find((c: any) => c.id === 'c-net')
  assert.equal(row.notes, 'Plan: Premium')
  assert.equal(row.ends_on, undefined)
  assert.equal(row.cancelling_on, undefined)

  // date moves only a one-time commitment's charge; on a recurring one it is named, not written.
  const moved = updateCommitment(dir, 'claude', { id: 'c-net', set: { amount: 699, date: '2026-09-03' } })
  assert.deepEqual(moved, {
    updated: { id: 'c-net', name: 'Netflix' },
    fields: ['amount'],
    ignored: ["date — only a one-time commitment's charge moves by date"],
  })
  assert.deepEqual(fileJson(file).charges.filter((c: any) => c.commitment_id === 'c-net').map((c: any) => c.date),
    ['2026-09-01', '2026-10-01', '2026-11-01'])
})

// Days are written only onto a custom cycle, and a date moves a one-time commitment's charge
// only when it holds one: otherwise each is named, never reported as written.
test('update_commitment names days off a custom cycle and a date with no charge to move as ignored', () => {
  const { dir, file } = seeded({
    ...SEED,
    commitments: [...SEED.commitments,
      { id: 'c-water', name: 'Water cans', amount: 300, currency: 'INR', billing_cycle: 'custom', custom_cycle_days: 10, status: 'active' },
      { id: 'c-deposit', name: 'Deposit', amount: 5000, currency: 'INR', billing_cycle: 'once', status: 'active' }],
  })
  const row = (id: string) => fileJson(file).commitments.find((c: any) => c.id === id)
  const days = 'custom_cycle_days — custom_cycle_days goes with billing_cycle custom'
  assert.deepEqual(updateCommitment(dir, 'claude', { id: 'c-net', set: { custom_cycle_days: 14, notes: 'Plan: Premium' } }),
    { updated: { id: 'c-net', name: 'Netflix' }, fields: ['notes'], ignored: [days] })
  assert.deepEqual([row('c-net').billing_cycle, row('c-net').custom_cycle_days, row('c-net').notes], ['monthly', null, 'Plan: Premium'])
  assert.deepEqual(updateCommitment(dir, 'claude', { id: 'c-water', set: { billing_cycle: 'monthly', custom_cycle_days: 7 } }),
    { updated: { id: 'c-water', name: 'Water cans' }, fields: ['billing_cycle'], ignored: [days] })
  assert.deepEqual([row('c-water').billing_cycle, row('c-water').custom_cycle_days], ['monthly', null])
  assert.deepEqual(updateCommitment(dir, 'claude', { id: 'c-water', set: { billing_cycle: 'custom', custom_cycle_days: 14 } }),
    { updated: { id: 'c-water', name: 'Water cans' }, fields: ['billing_cycle', 'custom_cycle_days'] })
  assert.deepEqual([row('c-water').billing_cycle, row('c-water').custom_cycle_days], ['custom', 14])
  assert.deepEqual(updateCommitment(dir, 'claude', { id: 'c-net', set: { custom_cycle_days: null } }),
    { updated: { id: 'c-net', name: 'Netflix' }, fields: ['custom_cycle_days'] })

  const date = 'date — the commitment holds no charge to move; add_charges writes one'
  assert.deepEqual(updateCommitment(dir, 'claude', { id: 'c-deposit', set: { date: '2026-10-01', notes: 'Refundable' } }),
    { updated: { id: 'c-deposit', name: 'Deposit' }, fields: ['notes'], ignored: [date] })
  assert.deepEqual(updateCommitment(dir, 'claude', { id: 'c-gym-b', set: { billing_cycle: 'once', date: '2026-10-05' } }),
    { updated: { id: 'c-gym-b', name: 'gym ' }, fields: ['billing_cycle'], ignored: [date] })
  assert.deepEqual(fileJson(file).charges.filter((c: any) => ['c-deposit', 'c-gym-b'].includes(c.commitment_id)), [], 'nothing was written for them')
})

// Another writer left a price past the limit: a write that keeps the price lands; one that
// changes it is held to the limit.
test('a stored price past the limit refuses only a write that changes the price', () => {
  const { dir, file } = seeded({
    ...SEED,
    commitments: [...SEED.commitments, { id: 'c-slip', name: 'Slip', amount: 9.3e18, currency: 'INR', billing_cycle: 'monthly', status: 'active' }],
  })
  assert.deepEqual(updateCommitment(dir, 'claude', { id: 'c-slip', set: { notes: 'Plan: Premium' } }),
    { updated: { id: 'c-slip', name: 'Slip' }, fields: ['notes'] })
  const row = () => fileJson(file).commitments.find((c: any) => c.id === 'c-slip')
  assert.equal(row().amount, 9.3e18)
  assert.equal(row().notes, 'Plan: Premium')
  cancelCommitment(dir, 'claude', { id: 'c-slip' })
  assert.equal(row().status, 'cancelled')
  assert.throws(() => updateCommitment(dir, 'claude', { id: 'c-slip', set: { amount: 2e15 } }),
    { message: "Nothing was changed. Fix these — the amount can't be more than 1,000,000,000,000,000." })
})

// Another writer left a custom cycle past a hundred years, as the app's own writer allows for:
// a write that keeps the days lands; one that changes them is held to 1 to 36,500.
test('a stored custom cycle past the limit refuses only a write that changes its days', () => {
  const { dir, file } = seeded({
    ...SEED,
    commitments: [...SEED.commitments,
      { id: 'c-gas', name: 'Gas', amount: 900, currency: 'INR', billing_cycle: 'custom', custom_cycle_days: 99_999, status: 'active' }],
  })
  const row = () => fileJson(file).commitments.find((c: any) => c.id === 'c-gas')
  assert.deepEqual(updateCommitment(dir, 'claude', { id: 'c-gas', set: { notes: 'Cylinder: 14 kg' } }),
    { updated: { id: 'c-gas', name: 'Gas' }, fields: ['notes'] })
  assert.deepEqual([row().custom_cycle_days, row().notes], [99_999, 'Cylinder: 14 kg'])
  const before = readFileSync(file)
  for (const days of [0, 36_501, 50_000]) {
    assert.throws(() => updateCommitment(dir, 'claude', { id: 'c-gas', set: { custom_cycle_days: days } }),
      { message: 'Nothing was changed. Fix these — custom_cycle_days is a whole number of days, 1 to 36,500.' })
  }
  assert.deepEqual(readFileSync(file), before, 'nothing was written')
  updateCommitment(dir, 'claude', { id: 'c-gas', set: { custom_cycle_days: 36_500 } })
  assert.equal(row().custom_cycle_days, 36_500)
})

/** The seed, plus one row whose details another writer left behind. */
const holding = (details: Record<string, unknown>) =>
  seeded({ ...SEED, commitments: [...SEED.commitments, { id: 'c-held', name: 'Term insurance', amount: 18400, currency: 'INR', billing_cycle: 'yearly', status: 'active', details }] })

// The rule: a details value is refused on what it says, never on what type it is held as.
// A number is a digit run, and a string-only scan never saw one.
test('a card number in the details a row holds refuses any write to it, whatever type holds it', () => {
  for (const value of [4111111111111111, '4111111111111111', '4111 1111 1111 1111', [4111111111111111], ['ok', 4111111111111111]]) {
    const { dir, file } = holding({ card_ref: value })
    const before = readFileSync(file)
    assert.throws(
      () => updateCommitment(dir, 'claude', { id: 'c-held', set: { notes: 'Policy number: 88213' } }),
      new RegExp(DATA_POLICY_REFUSAL.slice(0, 30)),
      `details.card_ref = ${JSON.stringify(value)} must be refused`,
    )
    assert.deepEqual(readFileSync(file), before, 'a refusal leaves the file untouched')
    noLitter(dir)
  }
})

test('an ordinary number in the details a row holds rides through an update, keeping its type', () => {
  const { dir, file } = holding({ statement_line: 'LIC OF INDIA PREMIUM', cover: 10000000, riders: 2, auto_debit: true })
  updateCommitment(dir, 'claude', { id: 'c-held', set: { notes: 'Policy number: 88213' } })
  const row = fileJson(file).commitments.find((c: any) => c.id === 'c-held')
  assert.deepEqual(row.details, { statement_line: 'LIC OF INDIA PREMIUM', cover: 10000000, riders: 2, auto_debit: true },
    'a figure is a figure, and the scan does not eat it')
  noLitter(dir)
})

test('update changes only the named fields and re-signs the row', () => {
  const { dir, file } = seeded()
  updateCommitment(dir, 'claude', { id: 'c-net', set: { amount: 699, notes: 'price rose in august' } })
  const vault = fileJson(file)
  const row = vault.commitments.find((c: any) => c.id === 'c-net')
  assert.equal(row.amount, 699)
  assert.equal(row.notes, 'price rose in august')
  assert.equal(row.name, 'Netflix')
  assert.equal(row.billing_cycle, 'monthly')
  assert.equal(vault._provenance['c-net'].edited_by, 'claude')
})

test('update: null clears an optional field; a cycle leaving custom sheds its days', () => {
  const { dir, file } = seeded({
    ...SEED,
    commitments: [
      { id: 'c-water', name: 'Water cans', amount: 300, currency: 'INR', billing_cycle: 'custom', custom_cycle_days: 10, next_due_date: '2026-09-01', status: 'active', notes: 'blue can supplier' },
    ],
  })
  updateCommitment(dir, 'claude', { id: 'c-water', set: { billing_cycle: 'monthly', notes: null } })
  const row = fileJson(file).commitments[0]
  assert.equal(row.billing_cycle, 'monthly')
  assert.equal(row.custom_cycle_days, null)
  assert.equal(row.notes, null)
})

test('update: member links by name; an amount change reaches only the plan ahead; invalid merges refuse', () => {
  const { dir, file } = seeded()
  updateCommitment(dir, 'claude', { name: 'netflix', set: { member: 'Rohit', amount: 799, from: '2026-10-01' } })
  const row = fileJson(file).commitments.find((c: any) => c.id === 'c-net')
  assert.equal(row.member_id, 'm-rohit')
  assert.equal(row.amount, 799)
  const amounts = (fileJson(file).charges as any[]).filter((r) => r.commitment_id === 'c-net').map((r) => r.amount)
  assert.deepEqual(amounts, [649, 799, 799], 'from October; September keeps its price')

  const before = readFileSync(file)
  assert.throws(
    () => updateCommitment(dir, 'claude', { id: 'c-net', set: { billing_cycle: 'custom' } }),
    /custom_cycle_days/,
  )
  assert.throws(() => updateCommitment(dir, 'claude', { id: 'c-net', set: {} }), /at least one field/)
  assert.throws(() => updateCommitment(dir, 'claude', { name: 'Gym', set: { amount: 1 } }), /more than one/)
  assert.deepEqual(readFileSync(file), before)
})

test('mark_paid flips the row the app flips, and paid: false takes it back', () => {
  const { dir, file } = seeded()
  const net = () => (fileJson(file).charges as any[]).filter((r) => r.commitment_id === 'c-net')
  markPaid(dir, 'claude', { id: 'c-net', date: '2026-09-01' })
  assert.equal(net().length, 3, 'a mark is not a second row')
  assert.equal(net()[0].paid, true)
  assert.equal(net()[0].basis, 'mark_paid')

  markPaid(dir, 'claude', { id: 'c-net', date: '2026-09-01' })
  assert.equal(net().length, 3, 'marking twice keeps one row')

  markPaid(dir, 'claude', { id: 'c-net', date: '2026-09-01', paid: false })
  assert.equal(net()[0].paid, false)
  assert.equal(net()[0].basis, 'plan')

  // A day nobody planned is written at the commitment's price.
  markPaid(dir, 'claude', { id: 'c-net', date: '2026-08-01', paid_on: '2026-08-02' })
  assert.equal(net()[0].date, '2026-08-01')
  assert.equal(net()[0].amount, 649)
  assert.equal(net()[0].paid_on, '2026-08-02')
  assert.throws(() => markPaid(dir, 'claude', { id: 'c-net', date: '2026-9-1' }), /real YYYY-MM-DD/)
})

test('a malformed tags entry refuses the write before a byte lands', () => {
  const { dir, file } = seeded({ ...SEED, tags: [{ id: 't1', kind: 'commitment', name: 'Home' }] })
  const before = readFileSync(file)
  assert.throws(() => addCommitments(dir, 'claude', one()), /tags\[0\] needs name_key/)
  assert.deepEqual(readFileSync(file), before)
  noLitter(dir)
})

test('cancel by id marks the row cancelled and signs it', () => {
  const { dir, file } = seeded()
  cancelCommitment(dir, 'claude', { id: 'c-net' })
  const vault = fileJson(file)
  const row = vault.commitments.find((c: any) => c.id === 'c-net')
  assert.equal(row.status, 'cancelled')
  assert.equal(vault._provenance['c-net'].edited_by, 'claude')
  noLitter(dir)
})

test('an ambiguous name refuses, naming every candidate; unknown and empty asks refuse', () => {
  const { dir, file } = seeded()
  const before = readFileSync(file)
  assert.throws(() => cancelCommitment(dir, 'claude', { name: 'Gym' }), /c-gym-a.*c-gym-b/s)
  assert.throws(() => cancelCommitment(dir, 'claude', { name: 'Chegg' }), /No commitment is named/)
  assert.throws(() => cancelCommitment(dir, 'claude', {}), /id, or its exact name/)
  assert.throws(() => cancelCommitment(dir, 'claude', { id: 'c-old' }), /already cancelled/)
  assert.deepEqual(readFileSync(file), before)
})

test('a write that finds the file moved refuses with the retry message', () => {
  const { dir, file } = seeded()
  const interloper = JSON.stringify({ ...SEED, commitments: [] }, null, 2)
  assert.throws(
    () =>
      writeVault(dir, 'claude', (vault) => {
        writeFileSync(file, interloper)
        return { touched: [], report: vault }
      }),
    new RegExp(CAS_MESSAGE.slice(0, 20)),
  )
  assert.equal(readFileSync(file, 'utf8'), interloper)
  noLitter(dir)
})

test('an unparseable vault refuses and is preserved; v1 refuses; nothing is ever created', () => {
  const { dir, file } = seeded()
  writeFileSync(file, 'not json {')
  assert.throws(() => addCommitments(dir, 'claude', one()), /not valid JSON/)
  assert.equal(readFileSync(file, 'utf8'), 'not json {')

  const v2 = seeded({ app: 'longbook', version: 2, commitments: [] })
  assert.throws(() => addCommitments(v2.dir, 'claude', one()), /format 2/)

  const empty = mkdtempSync(join(tmpdir(), 'longbook-mcp-empty-'))
  assert.throws(() => addCommitments(empty, 'claude', one()), /never creates one/)
  assert.equal(existsSync(join(empty, 'financial_memory.json')), false)
})

// Every charge is a row. These prove the charge-level tools reach the file the way the
// app's own writer does.

test('add_charges writes rows in by date, updates in place, prices from the commitment when unsaid', () => {
  const { dir, file } = seeded()
  addCharges(dir, 'test', { id: 'c-net', charges: [
    { date: '2026-07-01', amount: 599, paid: true, basis: 'statement' },
    { date: '2026-12-01' },
    { date: '2026-10-01', amount: 699 },
  ] })
  const net = (fileJson(file).charges as any[]).filter((r) => r.commitment_id === 'c-net')
  assert.deepEqual(net.map((r) => r.date), ['2026-07-01', '2026-09-01', '2026-10-01', '2026-11-01', '2026-12-01'])
  assert.equal(net[0].basis, 'statement')
  assert.equal(net[2].amount, 699)
  assert.equal(net[2].basis, 'user')
  assert.equal(net[4].amount, 649)
  assert.equal(net[4].basis, 'plan')
  noLitter(dir)
})

test('remove_charges takes only the days named', () => {
  const { dir, file } = seeded()
  const report = removeChargesTool(dir, 'test', { id: 'c-net', dates: ['2026-10-01', '2099-01-01'] }) as Record<string, any>
  assert.equal(report.removed, 1)
  const net = (fileJson(file).charges as any[]).filter((r) => r.commitment_id === 'c-net').map((r) => r.date)
  assert.deepEqual(net, ['2026-09-01', '2026-11-01'])
})

test('cancelling unwrites the plan ahead and keeps what happened', () => {
  const { dir, file } = seeded()
  addCharges(dir, 'test', { id: 'c-gym-a', charges: [
    { date: '2026-08-05', paid: true, basis: 'statement' },
    { date: '2031-01-05' },
  ] })
  cancelCommitment(dir, 'test', { id: 'c-gym-a' })
  const gym = (fileJson(file).charges as any[]).filter((r) => r.commitment_id === 'c-gym-a').map((r) => r.date)
  assert.ok(gym.includes('2026-08-05'), 'what happened stays')
  assert.ok(!gym.includes('2031-01-05'), 'what was only planned is unwritten')
})

test('promote_to_recurring keeps every fact, removes the one-time rows, and plans ahead', (t) => {
  // Promoted on 20 August, before the next cycle day: the plan continues from the step after the latest.
  t.mock.timers.enable({ apis: ['Date'], now: new Date(2026, 7, 20, 12) })
  const { dir, file } = seeded({
    ...SEED,
    commitments: [
      ...SEED.commitments,
      { id: 't1', name: 'UPI-RAMESH', amount: 6000, currency: 'INR', billing_cycle: 'once', status: 'active', tag: 'household help' },
      { id: 't2', name: 'UPI-RAMESH', amount: 6000, currency: 'INR', billing_cycle: 'once', status: 'active', tag: 'household help' },
      { id: 't3', name: 'UPI-RAMESH', amount: 6500, currency: 'INR', billing_cycle: 'once', status: 'active', tag: 'household help' },
    ],
    charges: [
      ...SEED.charges,
      { commitment_id: 't1', date: '2026-06-01', amount: 6000, paid: true, basis: 'statement' },
      { commitment_id: 't2', date: '2026-07-01', amount: 6000, paid: true, basis: 'statement' },
      { commitment_id: 't3', date: '2026-08-01', amount: 6500, paid: true, basis: 'statement' },
    ],
    tags: [{ id: 'tg1', kind: 'commitment', name: 'household help', name_key: 'household help', is_default: true, sort: 0, created_at: 'x' }],
  })
  const report = promoteToRecurring(dir, 'test', { ids: ['t1', 't2', 't3'], billing_cycle: 'monthly', name: 'Ramesh', member: 'Rohit', plan_months: 3 }) as Record<string, any>
  const vault = fileJson(file)
  const names = vault.commitments.map((c: any) => c.name)
  assert.ok(names.includes('Ramesh') && !names.includes('UPI-RAMESH'))
  const ramesh = vault.commitments.find((c: any) => c.name === 'Ramesh')
  assert.equal(ramesh.member_id, 'm-rohit')
  assert.equal(ramesh.tag, 'household help')
  assert.equal(ramesh.amount, 6000, 'the attributes start as the first row\'s')
  const rows = (vault.charges as any[]).filter((r) => r.commitment_id === ramesh.id)
  assert.deepEqual(rows.map((r) => r.date), ['2026-06-01', '2026-07-01', '2026-08-01', '2026-09-01', '2026-10-01', '2026-11-01'])
  assert.equal(rows[2].amount, 6500)
  assert.equal(rows[2].basis, 'statement')
  assert.equal(rows[3].basis, 'plan')
  assert.equal(report.carried, 3)
  assert.equal(report.planned, 3)
  assert.equal(vault._provenance.t1?.edited_by, 'test', 'the merged rows leave tombstones signed by the caller')
  assert.equal(ramesh.direction, undefined, 'a charge promoted stays a charge')
  assert.throws(() => promoteToRecurring(dir, 'test', { ids: ['c-old'], billing_cycle: 'monthly' }), /charge to carry/)
})

// Planning never writes a row before today, as the app plans: a promotion made months after
// the last charge plans from the first cycle day from today on, never the months between, and
// a cycle day on today itself is plan.
test('promote_to_recurring on a lapsed repeat plans from today on, a cycle day on today included', (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: new Date(2026, 6, 23, 12) })
  const { dir, file } = seeded({
    ...SEED,
    commitments: [...SEED.commitments,
      { id: 'g1', name: 'Gym', amount: 1500, currency: 'INR', billing_cycle: 'once', status: 'active' },
      { id: 'g2', name: 'Gym', amount: 1500, currency: 'INR', billing_cycle: 'once', status: 'active' },
      { id: 'f1', name: 'Fee', amount: 300, currency: 'INR', billing_cycle: 'once', status: 'active' },
      { id: 'f2', name: 'Fee', amount: 300, currency: 'INR', billing_cycle: 'once', status: 'active' }],
    charges: [...SEED.charges,
      { commitment_id: 'g1', date: '2026-02-05', amount: 1500, paid: true, basis: 'statement' },
      { commitment_id: 'g2', date: '2026-03-05', amount: 1500, paid: true, basis: 'statement' },
      { commitment_id: 'f1', date: '2026-05-23', amount: 300, paid: true, basis: 'statement' },
      { commitment_id: 'f2', date: '2026-06-23', amount: 300, paid: true, basis: 'statement' }],
  })
  const lines = (id: string) => (fileJson(file).charges as any[]).filter((r) => r.commitment_id === id)
    .map((r) => `${r.date} ${r.amount} ${r.paid ? 'paid' : 'unpaid'} ${r.basis}`)
  const gym = promoteToRecurring(dir, 'claude', { ids: ['g1', 'g2'], billing_cycle: 'monthly', name: 'Gym', plan_months: 3 }) as Record<string, any>
  assert.deepEqual(lines(gym.promoted.id), [
    '2026-02-05 1500 paid statement', '2026-03-05 1500 paid statement',
    '2026-08-05 1500 unpaid plan', '2026-09-05 1500 unpaid plan', '2026-10-05 1500 unpaid plan',
  ])
  assert.equal(gym.planned, 3)

  // Last charged 23 June, promoted on 23 July: the first new row is today's.
  const fee = promoteToRecurring(dir, 'claude', { ids: ['f1', 'f2'], billing_cycle: 'monthly', name: 'Fee', plan_months: 3 }) as Record<string, any>
  assert.deepEqual(lines(fee.promoted.id), [
    '2026-05-23 300 paid statement', '2026-06-23 300 paid statement',
    '2026-07-23 300 unpaid plan', '2026-08-23 300 unpaid plan', '2026-09-23 300 unpaid plan',
  ])
  assert.equal(fee.planned, 3)
})

test('promote_to_recurring carries direction: a repeating credit stays money in', () => {
  const { dir, file } = seeded({
    ...SEED,
    commitments: [
      ...SEED.commitments,
      { id: 'in1', name: 'Vertex Labs salary', amount: 214000, currency: 'INR', billing_cycle: 'once', status: 'active', direction: 'in' },
      { id: 'in2', name: 'Vertex Labs salary', amount: 214000, currency: 'INR', billing_cycle: 'once', status: 'active', direction: 'in' },
    ],
    charges: [
      ...SEED.charges,
      { commitment_id: 'in1', date: '2026-07-28', amount: 214000, paid: true, basis: 'statement' },
      { commitment_id: 'in2', date: '2026-08-28', amount: 214000, paid: true, basis: 'statement' },
    ],
  })
  promoteToRecurring(dir, 'test', { ids: ['in1', 'in2'], billing_cycle: 'monthly', plan_months: 2 })
  const vault = fileJson(file)
  const salary = vault.commitments.find((c: any) => c.name === 'Vertex Labs salary')
  assert.equal(salary.direction, 'in')
  assert.equal(salary.billing_cycle, 'monthly')
  assert.equal((vault.charges as any[]).filter((r) => r.commitment_id === salary.id).length, 4)
})

/** One-time rows of each direction, a charge apiece, for promotions that must not mix them. */
function directed() {
  const once = (id: string, name: string, direction?: string) => ({
    id, name, amount: 5000, currency: 'INR', billing_cycle: 'once', status: 'active', ...(direction ? { direction } : {}),
  })
  const paid = (id: string, date: string) => ({ commitment_id: id, date, amount: 5000, paid: true, basis: 'statement' })
  return seeded({
    ...SEED,
    commitments: [
      ...SEED.commitments,
      once('d-spend', 'Tuition'), once('d-out', 'Tuition', 'out'), once('d-move', 'To savings', 'transfer'),
      once('d-in', 'Interest', 'in'), once('d-lend-1', 'To a friend', 'lend'), once('d-lend-2', 'To a friend', 'lend'),
    ],
    charges: [
      ...SEED.charges,
      paid('d-spend', '2026-06-05'), paid('d-out', '2026-07-05'), paid('d-move', '2026-07-05'),
      paid('d-in', '2026-07-05'), paid('d-lend-1', '2026-06-09'), paid('d-lend-2', '2026-07-09'),
    ],
  })
}

test('promote_to_recurring refuses rows that do not share a direction; nothing moves between sums', () => {
  const { dir, file } = directed()
  const before = readFileSync(file)
  const mixed = /These rows do not share a direction: promote spending, money in and transfers separately/
  assert.throws(() => promoteToRecurring(dir, 'claude', { ids: ['d-spend', 'd-move'], billing_cycle: 'monthly' }), mixed)
  assert.throws(() => promoteToRecurring(dir, 'claude', { ids: ['d-in', 'd-move'], billing_cycle: 'monthly' }), mixed)
  assert.throws(() => promoteToRecurring(dir, 'claude', { ids: ['d-move', 'd-spend'], billing_cycle: 'monthly' }), /"To savings" is a transfer.*"Tuition" is spending/)
  assert.deepEqual(readFileSync(file), before)

  // "out" and nothing at all are one direction; a word from a newer contract rides along.
  promoteToRecurring(dir, 'claude', { ids: ['d-spend', 'd-out'], billing_cycle: 'monthly', plan_months: 1 })
  promoteToRecurring(dir, 'claude', { ids: ['d-lend-1', 'd-lend-2'], billing_cycle: 'monthly', plan_months: 1 })
  const vault = fileJson(file)
  assert.equal(vault.commitments.find((c: any) => c.name === 'Tuition').direction, undefined)
  assert.equal(vault.commitments.find((c: any) => c.name === 'To a friend').direction, 'lend')
})

test('update_commitment clears a direction with null, and leaves one it does not know alone', () => {
  const { dir, file } = directed()
  const direction = (id: string) => fileJson(file).commitments.find((c: any) => c.id === id).direction
  updateCommitment(dir, 'claude', { id: 'd-move', set: { direction: null } })
  assert.equal(direction('d-move'), null)
  updateCommitment(dir, 'claude', { id: 'd-lend-1', set: { notes: 'Back by March.' } })
  assert.equal(direction('d-lend-1'), 'lend', 'an edit that names no direction erases none')
})

test('a transfer is written, paid in place, promoted as a transfer, and turned back into a charge', () => {
  const { dir, file } = seeded()
  addCommitments(dir, 'claude', {
    rows: [
      { name: 'Coral card bill', amount: 31250, currency: 'INR', billing_cycle: 'once', date: '2026-10-05', paid: false, basis: 'email', direction: 'transfer', account: 'Coral card' },
      { name: 'To savings', amount: 5000, currency: 'INR', billing_cycle: 'once', date: '2026-08-05', paid: true, basis: 'statement', direction: 'transfer' },
      { name: 'To savings', amount: 5000, currency: 'INR', billing_cycle: 'once', date: '2026-09-05', paid: true, basis: 'statement', direction: 'transfer' },
      { name: 'Groceries', amount: 840, currency: 'INR', billing_cycle: 'once', date: '2026-09-06', paid: true, direction: 'out' },
    ],
    source: 'gmail:18c2a',
  })
  let vault = fileJson(file)
  const bill = vault.commitments.find((c: any) => c.name === 'Coral card bill')
  assert.equal(bill.direction, 'transfer')
  assert.equal(vault.commitments.find((c: any) => c.name === 'Groceries').direction, undefined, '"out" is absence, as it always was')
  const billRow = (vault.charges as any[]).find((r) => r.commitment_id === bill.id)
  assert.deepEqual([billRow.date, billRow.amount, billRow.paid, billRow.basis], ['2026-10-05', 31250, false, 'email'])

  // The bill's payment marks that row paid, in place: one row, never a second.
  addCharges(dir, 'claude', { id: bill.id, charges: [{ date: '2026-10-05', paid: true, paid_on: '2026-10-03', basis: 'email' }] })
  vault = fileJson(file)
  const paid = (vault.charges as any[]).filter((r) => r.commitment_id === bill.id)
  assert.equal(paid.length, 1)
  assert.deepEqual([paid[0].paid, paid[0].paid_on, paid[0].amount], [true, '2026-10-03', 31250])

  const savings = vault.commitments.filter((c: any) => c.name === 'To savings').map((c: any) => c.id)
  promoteToRecurring(dir, 'claude', { ids: savings, billing_cycle: 'monthly', plan_months: 2 })
  vault = fileJson(file)
  assert.equal(vault.commitments.find((c: any) => c.name === 'To savings').direction, 'transfer', 'direction rides along')

  updateCommitment(dir, 'claude', { id: bill.id, set: { direction: 'out' } })
  assert.equal(fileJson(file).commitments.find((c: any) => c.id === bill.id).direction, null)
  updateCommitment(dir, 'claude', { id: bill.id, set: { direction: 'transfer' } })
  assert.equal(fileJson(file).commitments.find((c: any) => c.id === bill.id).direction, 'transfer')
  assert.throws(() => addCommitments(dir, 'claude', one({ direction: 'sideways' })), /"transfer" for a movement between the owner's own accounts/)
})

// ---- update_charge, set_planned_count, delete_commitment ----------------------------------
// Dated from today on the 10th of each month, so no clamping and no day-of-month flake: the
// writer counts the plan from today, and these rows sit a month apart either side of it.

const TODAY = todayMid()
const onTenth = (monthsAhead: number, day = 10) => toISO(new Date(TODAY.getFullYear(), TODAY.getMonth() + monthsAhead, day))
const MONTHLY = { billing_cycle: 'monthly' as const, custom_cycle_days: null }
const step = (from: string, k: number) => toISO(stepFrom(MONTHLY, parseDate(from), k))
const [PAST, P1, P2, P3] = [onTenth(-1), onTenth(1), onTenth(2), onTenth(3)] as [string, string, string, string]

function planned(over: Record<string, unknown> = {}, rows?: Record<string, unknown>[]) {
  return seeded({
    app: 'longbook',
    version: 3,
    commitments: [
      { id: 'c-net', name: 'Netflix', amount: 649, currency: 'INR', billing_cycle: 'monthly', status: 'active', ...over },
      { id: 'c-sofa', name: 'Sofa', amount: 500, currency: 'INR', billing_cycle: 'once', status: 'active' },
    ],
    charges: rows ?? [
      { commitment_id: 'c-net', date: PAST, amount: 649, paid: true, basis: 'statement', paid_on: onTenth(-1, 12), note: 'from the statement' },
      { commitment_id: 'c-net', date: P1, amount: 649, paid: false, basis: 'plan' },
      { commitment_id: 'c-net', date: P2, amount: 649, paid: false, basis: 'plan' },
      { commitment_id: 'c-net', date: P3, amount: 649, paid: false, basis: 'plan' },
      { commitment_id: 'c-sofa', date: P1, amount: 500, paid: false, basis: 'plan' },
    ],
    _provenance: {
      'c-net': { edited_by: 'longbook-mac', edited_at: '2026-01-01T00:00:00Z' },
      [`c-net@${P1}`]: { edited_by: 'longbook-mac', edited_at: '2026-01-01T00:00:00Z' },
      'c-sofa': { edited_by: 'claude', edited_at: '2026-01-01T00:00:00Z' },
    },
  })
}
const netRows = (file: string) => (fileJson(file).charges as any[]).filter((r) => r.commitment_id === 'c-net')
const netDates = (file: string) => netRows(file).map((r) => r.date as string)

test('update_charge moves one charge alone: the row keeps its amount as the owner\'s fact, the rest stay', () => {
  const { dir, file } = planned()
  const report = updateCharge(dir, 'claude', { name: 'Netflix', date: P1, set: { date: onTenth(1, 12) } })
  assert.deepEqual(netDates(file), [PAST, onTenth(1, 12), P2, P3])
  const moved = netRows(file)[1]!
  assert.equal(moved.basis, 'user', 'a day the owner chose is the owner\'s word')
  assert.equal(moved.amount, 649)
  const signed = fileJson(file)._provenance
  assert.equal(signed['c-net'].edited_by, 'claude', 'the commitment is signed')
  assert.equal(signed[`c-net@${P1}`].edited_by, 'claude', 'the day it left is a tombstone of the caller\'s, not the app\'s')
  assert.equal(signed[`c-net@${onTenth(1, 12)}`].edited_by, 'claude', 'the day it landed on is signed too')
  assert.deepEqual(report, { commitment: { id: 'c-net', name: 'Netflix' }, date: P1, fields: ['date'], moved_to: onTenth(1, 12), rows_moved: 1 })
  noLitter(dir)
})

test('update_charge with and_later carries the unpaid planned rows after it a cycle apart, amounts kept, paid rows left', () => {
  const { dir, file } = planned()
  const to = onTenth(1, 12)
  const report = updateCharge(dir, 'claude', { id: 'c-net', date: P1, set: { date: to, and_later: true } }) as Record<string, any>
  assert.deepEqual(netDates(file), [PAST, to, step(to, 1), step(to, 2)])
  assert.ok(netRows(file).slice(1).every((r) => r.amount === 649 && r.paid === false && r.basis === 'plan'))
  assert.equal(report.rows_moved, 3)

  // A paid row in the run stays where it is; only the plan behind it follows.
  const paid = planned({}, [
    { commitment_id: 'c-net', date: P1, amount: 649, paid: false, basis: 'plan' },
    { commitment_id: 'c-net', date: P2, amount: 649, paid: true, basis: 'mark_paid' },
    { commitment_id: 'c-net', date: P3, amount: 649, paid: false, basis: 'plan' },
  ])
  updateCharge(paid.dir, 'claude', { id: 'c-net', date: P1, set: { date: to, and_later: true } })
  assert.deepEqual(netDates(paid.file).sort(), [to, P2, step(to, 1)].sort())
})

test('update_charge reprices one charge by hand, and with and_later the plan after it and the commitment\'s price', () => {
  const alone = planned()
  updateCharge(alone.dir, 'claude', { id: 'c-net', date: P2, set: { amount: 699 } })
  assert.deepEqual(netRows(alone.file).map((r) => [r.amount, r.basis]), [[649, 'statement'], [649, 'plan'], [699, 'user'], [649, 'plan']])
  assert.equal(fileJson(alone.file).commitments[0].amount, 649, 'one row\'s price is not the commitment\'s')

  const { dir, file } = planned()
  const report = updateCharge(dir, 'claude', { id: 'c-net', date: P1, set: { amount: 799, and_later: true } }) as Record<string, any>
  assert.deepEqual(netRows(file).map((r) => [r.amount, r.basis]), [[649, 'statement'], [799, 'user'], [799, 'plan'], [799, 'plan']])
  assert.equal(fileJson(file).commitments[0].amount, 799, 'the price now, so more plan is written at it')
  assert.deepEqual(report.fields, ['amount'])

  // A one-time commitment is its charge: a new amount is its price too.
  updateCharge(dir, 'claude', { name: 'Sofa', date: P1, set: { amount: 600, paid: true } })
  const sofa = fileJson(file)
  assert.equal(sofa.commitments.find((c: any) => c.id === 'c-sofa').amount, 600)
  const row = sofa.charges.find((r: any) => r.commitment_id === 'c-sofa')
  assert.deepEqual([row.amount, row.paid, row.basis], [600, true, 'user'])
})

test('update_charge clears paid_on and the note with null, and marks paid or unpaid in place', () => {
  const { dir, file } = planned()
  const report = updateCharge(dir, 'claude', { id: 'c-net', date: PAST, set: { paid_on: null, note: null } }) as Record<string, any>
  const past = netRows(file)[0]!
  assert.equal('paid_on' in past, false)
  assert.equal('note' in past, false)
  assert.equal(past.basis, 'statement', 'clearing a word reprices nothing and rebases nothing')
  assert.deepEqual(report.fields, ['paid_on', 'note'])
  updateCharge(dir, 'claude', { id: 'c-net', date: P1, set: { paid: true, paid_on: onTenth(1, 9), note: 'paid ahead' } })
  const marked = netRows(file)[1]!
  assert.deepEqual([marked.paid, marked.paid_on, marked.note, marked.basis], [true, onTenth(1, 9), 'paid ahead', 'mark_paid'])
  assert.throws(() => updateCharge(dir, 'claude', { id: 'c-net', date: P1, set: { note: 'card 4111 1111 1111 1111' } }), new RegExp(DATA_POLICY_REFUSAL))
})

test('update_charge refuses a day already taken, a move past the cancelling date, and a charge that is not there', () => {
  const { dir, file } = planned({ ends_on: P2 })
  const before = readFileSync(file)
  assert.throws(() => updateCharge(dir, 'claude', { id: 'c-net', date: P1, set: { date: P2 } }), (e: Error) => e.message === dayTakenRefusal(P2))
  assert.throws(() => updateCharge(dir, 'claude', { id: 'c-net', date: P1, set: { date: onTenth(2, 12), and_later: true } }), (e: Error) => e.message === pastCancellingRefusal(P2))
  assert.throws(() => updateCharge(dir, 'claude', { id: 'c-net', date: onTenth(1, 11), set: { paid: true } }), (e: Error) => e.message === noChargeRefusal(onTenth(1, 11), 'Netflix'))
  assert.throws(() => updateCharge(dir, 'claude', { id: 'c-net', date: P1, set: {} }), /set must name at least one field/)
  assert.throws(() => updateCharge(dir, 'claude', { id: 'c-net', date: P1, set: { and_later: true } }), /set names none of date, amount, paid, paid_on, note/)
  assert.throws(() => updateCharge(dir, 'claude', { id: 'c-net', date: P1, set: { amount: 1e16 } }), /1,000,000,000,000,000/)
  assert.throws(() => updateCharge(dir, 'claude', { id: 'c-net', date: '2026-02-30', set: { paid: true } }), /real YYYY-MM-DD/)
  assert.throws(() => updateCharge(dir, 'claude', { date: P1, set: { paid: true } }), /id, or its exact name/)
  for (const [args, local] of [
    [{ id: 'c-net', date: P1, set: {} }, 'set must name at least one field to change.'],
    [{ id: 'c-net', date: P1, set: { date: '2026-02-30' } }, 'Nothing was changed. Fix these — date is the day to move the charge to, a real YYYY-MM-DD day.'],
  ] as [Record<string, unknown>, string][]) {
    assert.throws(() => checkProposal('update_charge', args), (e: Error) => e.message === local, 'both doors word it alike')
  }
  assert.deepEqual(readFileSync(file), before)
  noLitter(dir)
})

test('set_planned_count writes more a cycle apart after the last row, or unwrites the latest planned rows', () => {
  const { dir, file } = planned()
  const grown = setPlannedCount(dir, 'claude', { name: 'Netflix', count: 5 }) as Record<string, any>
  assert.deepEqual(netDates(file), [PAST, P1, P2, P3, step(P3, 1), step(P3, 2)])
  assert.ok(netRows(file).slice(4).every((r) => r.amount === 649 && r.basis === 'plan' && r.paid === false && r.written_at))
  assert.deepEqual(grown, { commitment: { id: 'c-net', name: 'Netflix' }, count: 5, ahead: 5, written: 2, unwritten: 0 })
  assert.equal(fileJson(file)._provenance['c-net'].edited_by, 'claude')

  const cut = setPlannedCount(dir, 'claude', { id: 'c-net', count: 1 }) as Record<string, any>
  assert.deepEqual(netDates(file), [PAST, P1], 'the latest planned rows go first; the past stays')
  assert.deepEqual(cut, { commitment: { id: 'c-net', name: 'Netflix' }, count: 1, ahead: 1, written: 0, unwritten: 4 })
  const same = setPlannedCount(dir, 'claude', { id: 'c-net', count: 1 }) as Record<string, any>
  assert.deepEqual(same, { commitment: { id: 'c-net', name: 'Netflix' }, count: 1, ahead: 1, written: 0, unwritten: 0 })
  assert.deepEqual(netDates(file), [PAST, P1], 'the count already stands: nothing changes')
})

test('set_planned_count keeps paid and hand-set rows, stops at the cancelling date, and refuses a one-time commitment', () => {
  const held = planned({}, [
    { commitment_id: 'c-net', date: P1, amount: 649, paid: false, basis: 'plan' },
    { commitment_id: 'c-net', date: P2, amount: 649, paid: false, basis: 'plan' },
    { commitment_id: 'c-net', date: P3, amount: 700, paid: false, basis: 'user' },
  ])
  const report = setPlannedCount(held.dir, 'claude', { id: 'c-net', count: 1 }) as Record<string, any>
  assert.deepEqual(netDates(held.file), [P3], 'a row the owner priced is never taken, and it counts: the plan around it goes')
  assert.equal(report.ahead, 1)

  const ending = planned({ ends_on: P2 })
  const stopped = setPlannedCount(ending.dir, 'claude', { id: 'c-net', count: 6 }) as Record<string, any>
  assert.equal(stopped.written, 0, 'nothing is planned past the cancelling date')

  // A plan that lapsed resumes from today on, never back-filled.
  const lapsed = planned({}, [
    { commitment_id: 'c-net', date: onTenth(-2), amount: 649, paid: true, basis: 'statement' },
    { commitment_id: 'c-net', date: PAST, amount: 649, paid: true, basis: 'statement' },
  ])
  const resumed = setPlannedCount(lapsed.dir, 'claude', { id: 'c-net', count: 2 }) as Record<string, any>
  const ahead = netDates(lapsed.file).filter((d) => parseDate(d) >= TODAY)
  assert.equal(ahead.length, 2)
  assert.ok(ahead.every((d) => d.endsWith('-10')), 'the rhythm runs from the last charge')
  assert.deepEqual([resumed.written, resumed.ahead], [2, 2])

  const { dir, file } = planned()
  const before = readFileSync(file)
  assert.throws(() => setPlannedCount(dir, 'claude', { name: 'Sofa', count: 3 }), (e: Error) => e.message === NOTHING_TO_PLAN)
  assert.throws(() => setPlannedCount(dir, 'claude', { id: 'c-net', count: 0 }), /1 to 240/)
  assert.throws(() => setPlannedCount(dir, 'claude', { id: 'c-net', count: 241 }), /1 to 240/)
  assert.throws(() => setPlannedCount(dir, 'claude', { id: 'c-net', count: 2.5 }), /whole number/)
  assert.throws(() => checkProposal('set_planned_count', { id: 'c-net', count: 241 }), /count is a whole number of charges, 1 to 240\./)
  assert.deepEqual(readFileSync(file), before)
})

test('set_planned_count refuses a paused, cancelled or lapsed commitment: the form never plans under one', () => {
  const { dir, file } = seeded()
  const before = readFileSync(file)
  assert.throws(() => setPlannedCount(dir, 'claude', { id: 'c-gym-b', count: 3 }), (e: Error) => e.message === notActiveRefusal('gym ', 'paused'))
  assert.throws(() => setPlannedCount(dir, 'claude', { name: 'Hotstar', count: 12 }), (e: Error) => e.message === notActiveRefusal('Hotstar', 'cancelled'))
  assert.deepEqual(readFileSync(file), before, 'nothing is written under a commitment that is not active')

  // An active row past its cancelling date reads as cancelled, as the app reads it.
  const lapsed = planned({ ends_on: onTenth(-1, 12) })
  assert.throws(() => setPlannedCount(lapsed.dir, 'claude', { id: 'c-net', count: 3 }), (e: Error) => e.message === notActiveRefusal('Netflix', 'cancelled'))
  assert.equal(notActiveRefusal('Hotstar', 'cancelled'), '"Hotstar" is cancelled; set its status to active first, then plan.', 'the sentence the app says too')
})

// A Keep on the other device, or the app's own tap, leaves an app mark on a charge key.
// Every charge tool signs the keys it touches, so that mark never vouches for a later edit.
test('every charge tool signs the charge keys it touched, replacing an app mark the key held', () => {
  const { dir, file } = planned()
  const kept = fileJson(file)
  kept._provenance[`c-net@${P2}`] = { edited_by: 'claude', edited_at: '2026-01-01T00:00:00Z', reviewed_by: 'longbook-phone', reviewed_at: '2026-01-02T00:00:00Z' }
  writeFileSync(file, JSON.stringify(kept, null, 2))
  const signed = () => fileJson(file)._provenance as Record<string, Record<string, unknown>>

  markPaid(dir, 'claude', { id: 'c-net', date: P1 })
  assert.deepEqual(signed()[`c-net@${P1}`]!.edited_by, 'claude', 'the app\'s own signature on the day is replaced')
  updateCharge(dir, 'claude', { id: 'c-net', date: P2, set: { amount: 999 } })
  assert.deepEqual(Object.keys(signed()[`c-net@${P2}`]!).sort(), ['edited_at', 'edited_by'], 'the Keep\'s mark goes with the whole entry')
  assert.equal(signed()[`c-net@${P2}`]!.edited_by, 'claude')

  updateCharge(dir, 'claude', { id: 'c-net', date: P3, set: { amount: 700, and_later: true } })
  setPlannedCount(dir, 'claude', { id: 'c-net', count: 5 })
  const grown = step(P3, 1)
  for (const day of [P3, grown, step(P3, 2)]) assert.equal(signed()[`c-net@${day}`]!.edited_by, 'claude', `${day}: written or repriced, so signed`)

  addCharges(dir, 'claude', { id: 'c-net', charges: [{ date: onTenth(6), amount: 650 }] })
  assert.equal(signed()[`c-net@${onTenth(6)}`]!.edited_by, 'claude')
  removeChargesTool(dir, 'claude', { id: 'c-net', dates: [grown, '2099-01-01'] })
  assert.equal(signed()[`c-net@${grown}`]!.edited_by, 'claude', 'a removed day leaves a tombstone')
  assert.equal(signed()['c-net@2099-01-01'], undefined, 'a day that held nothing signs nothing')
  setPlannedCount(dir, 'claude', { id: 'c-net', count: 1 })
  assert.equal(signed()[`c-net@${step(P3, 2)}`]!.edited_by, 'claude', 'an unwritten day leaves a tombstone')
  assert.ok(Object.keys(signed()).every((k) => k === 'c-sofa' || signed()[k]!.edited_by === 'claude'), 'nothing of the app\'s remains on Netflix')
})

test('delete_commitment removes the row and every charge it had by id alone, leaving tombstones signed by the caller', () => {
  const { dir, file } = planned()
  const report = deleteCommitment(dir, 'claude', { id: 'c-net', source: 'gmail:18c2a' })
  const vault = fileJson(file)
  assert.deepEqual(vault.commitments.map((c: any) => c.id), ['c-sofa'])
  assert.deepEqual(vault.charges.map((r: any) => r.commitment_id), ['c-sofa'])
  assert.deepEqual(Object.keys(vault._provenance).sort(), ['c-net', `c-net@${P1}`, `c-net@${P2}`, `c-net@${P3}`, `c-net@${PAST}`, 'c-sofa'].sort(),
    'the commitment\'s and its charges\' entries outlive the rows, as the app\'s own delete leaves them')
  for (const key of ['c-net', `c-net@${PAST}`, `c-net@${P1}`]) {
    assert.equal(vault._provenance[key].edited_by, 'claude', `${key}: the removal names who made it`)
    assert.equal(vault._provenance[key].source, 'gmail:18c2a')
  }
  assert.deepEqual(report, { deleted: { id: 'c-net', name: 'Netflix' }, charges_removed: 4, paid_charges_removed: 1 })

  const before = readFileSync(file)
  assert.throws(() => deleteCommitment(dir, 'claude', { id: '' }), /pass its id\. delete_commitment takes no name/)
  assert.throws(() => deleteCommitment(dir, 'claude', { id: 'c-gone' }), /No commitment has the id c-gone/)
  assert.throws(() => checkProposal('delete_commitment', { name: 'Sofa' }), /pass its id\. delete_commitment takes no name/)
  assert.deepEqual(readFileSync(file), before)
  noLitter(dir)
})

test('add_commitments plans by plan_count when given — exactly that many from the first charge', () => {
  const { dir, file } = seeded()
  addCommitments(dir, 'claude', {
    rows: [
      { ...ROW, plan_count: 3 },
      { name: 'Term plan', amount: 24600, currency: 'INR', billing_cycle: 'yearly', first_charge: '2026-05-22', plan_count: 2, plan_months: 1 },
      { name: 'Water', amount: 300, currency: 'INR', billing_cycle: 'custom', custom_cycle_days: 10, first_charge: '2026-09-01', plan_count: 4 },
    ],
  })
  const vault = fileJson(file)
  const dates = (name: string) => {
    const id = vault.commitments.find((c: any) => c.name === name).id
    return vault.charges.filter((r: any) => r.commitment_id === id).map((r: any) => r.date)
  }
  assert.deepEqual(dates('Claude'), ['2026-09-10', '2026-10-10', '2026-11-10'])
  assert.deepEqual(dates('Term plan'), ['2026-05-22', '2027-05-22'], 'the count is read; plan_months is not')
  assert.deepEqual(dates('Water'), ['2026-09-01', '2026-09-11', '2026-09-21', '2026-10-01'])
  assert.throws(() => addCommitments(dir, 'claude', one({ billing_cycle: 'once', date: '2026-09-10', plan_count: 2 })), /plan_count belongs to a recurring row/)
  assert.throws(() => addCommitments(dir, 'claude', one({ plan_count: 241 })), /count is a whole number of charges, 1 to 240/)
})

test('update_commitment marks a free trial with free_trial and takes the mark off; mark_paid takes a note and clears with null', () => {
  const { dir, file } = seeded()
  const on = updateCommitment(dir, 'claude', { id: 'c-net', set: { free_trial: true } }) as Record<string, any>
  assert.equal(fileJson(file).commitments[0].free_trial, true)
  assert.deepEqual(on.fields, ['free_trial'])
  assert.equal(fileJson(file).charges.filter((r: any) => r.commitment_id === 'c-net').length, 3, 'no charge row changes')
  updateCommitment(dir, 'claude', { id: 'c-net', set: { free_trial: false } })
  assert.equal('free_trial' in fileJson(file).commitments[0], false, 'false takes the key out')
  assert.throws(() => updateCommitment(dir, 'claude', { id: 'c-net', set: { free_trial: 'yes' as unknown as boolean } }), /free_trial is true or false/)

  markPaid(dir, 'claude', { id: 'c-net', date: '2026-10-01', paid_on: '2026-10-02', note: 'paid by hand' })
  const row = () => fileJson(file).charges.find((r: any) => r.commitment_id === 'c-net' && r.date === '2026-10-01')
  assert.deepEqual([row().paid, row().paid_on, row().note], [true, '2026-10-02', 'paid by hand'])
  markPaid(dir, 'claude', { id: 'c-net', date: '2026-10-01', paid_on: null, note: null })
  assert.equal('paid_on' in row(), false)
  assert.equal('note' in row(), false)
  assert.equal(row().paid, true, 'clearing a word is not unmarking')
  assert.throws(() => markPaid(dir, 'claude', { id: 'c-net', date: '2026-10-01', note: 'x'.repeat(301) }), /under 300 characters, or null/)
  addCharges(dir, 'claude', { id: 'c-net', charges: [{ date: '2026-11-01', note: 'late', paid_on: '2026-11-03' }] })
  addCharges(dir, 'claude', { id: 'c-net', charges: [{ date: '2026-11-01', note: null, paid_on: null }] })
  const nov = fileJson(file).charges.find((r: any) => r.commitment_id === 'c-net' && r.date === '2026-11-01')
  assert.equal('note' in nov, false)
  assert.equal('paid_on' in nov, false)
})
