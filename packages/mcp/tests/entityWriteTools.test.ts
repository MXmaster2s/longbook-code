// Accounts and people through the local door — renamed, described, and refused exactly
// as the app's own form refuses — with the hosted validator holding the same line.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { DATA_POLICY_REFUSAL, toISO, todayMid } from '@longbook/core'
import { addAccount, addCharges, addCommitments, addMember, deleteTag, renameTag, updateAccount, updateMember } from '../src/writeTools.js'
import {
  ACCOUNT_DETAILS_REFUSAL, EMPTY_NAME_REFUSAL, MEMBER_DETAILS_REFUSAL, UPDATE_ACCOUNT_SPEC, UPDATE_MEMBER_SPEC,
  checkProposal, entityTwinRefusal, payloadTexts, tagTwinRefusal,
} from '../src/proposal.js'

const SEED = {
  app: 'longbook',
  version: 3,
  commitments: [],
  members: [
    { id: 'm-rohit', name: 'Rohit', name_key: 'rohit' },
    { id: 'm-diya', name: 'Diya', name_key: 'diya', email: 'diya@example.com' },
  ],
  accounts: [
    { id: 'a-hdfc', name: 'HDFC', name_key: 'hdfc' },
    { id: 'a-visa', name: 'HDFC Visa', name_key: 'hdfc visa', is_incomplete: true },
    { id: 'a-amazon', name: 'Amazon Pay', name_key: 'amazon pay' },
    { id: 'a-cash-1', name: 'Cash', name_key: 'cash' },
    { id: 'a-cash-2', name: 'cash ', name_key: 'cash' },
  ],
}

function seeded(): { dir: string; file: string } {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-mcp-entity-'))
  const file = join(dir, 'financial_memory.json')
  writeFileSync(file, JSON.stringify(SEED, null, 2))
  return { dir, file }
}

const fileJson = (file: string) => JSON.parse(readFileSync(file, 'utf8')) as Record<string, any>
const accountIn = (file: string, id: string) => (fileJson(file).accounts as any[]).find((a) => a.id === id)
const memberIn = (file: string, id: string) => (fileJson(file).members as any[]).find((m) => m.id === id)

test('update_account renames, types, and prices an account in one write; a bare balance is dated today', () => {
  const { dir, file } = seeded()
  const report = updateAccount(dir, 'claude', {
    name: 'hdfc visa',
    set: { name: ' Visa 9292 ', tag: 'Credit card', balance: 18400.5 },
  }) as Record<string, any>
  const visa = accountIn(file, 'a-visa')
  assert.equal(visa.name, 'Visa 9292')
  assert.equal(visa.name_key, 'visa 9292')
  assert.equal(visa.is_incomplete, false, 'a named thing is no longer only a name')
  assert.equal(visa.tag, 'Credit card')
  assert.equal(visa.balance, 18400.5)
  assert.equal(visa.balance_date, toISO(todayMid()))
  const registered = (fileJson(file).tags as any[]).find((t) => t.kind === 'account' && t.name_key === 'credit card')
  assert.equal(registered.is_default, true, 'the library entry, whole')
  assert.equal(registered.icon, 'creditcard.fill')
  assert.equal(fileJson(file)._provenance['a-visa'].edited_by, 'claude')
  assert.deepEqual(report, { updated: { id: 'a-visa', name: 'Visa 9292' }, fields: ['name', 'tag', 'balance'] })
})

test('update_account: renaming onto another account refuses rather than merging; the file is untouched', () => {
  const { dir, file } = seeded()
  const before = readFileSync(file)
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-visa', set: { name: ' hdfc ' } }), /There's already an account called hdfc\./)
  assert.throws(
    () => updateAccount(dir, 'claude', { id: 'a-visa', set: { name: 'Visa 4111 1111 1111 1111' } }),
    new RegExp(DATA_POLICY_REFUSAL.slice(0, 30)),
  )
  assert.deepEqual(readFileSync(file), before)
})

test('update_account: a balance with its day; null clears both; a day and a null never mix', () => {
  const { dir, file } = seeded()
  updateAccount(dir, 'claude', { id: 'a-hdfc', set: { balance: 250000, balance_date: '2026-08-31' } })
  assert.equal(accountIn(file, 'a-hdfc').balance, 250000)
  assert.equal(accountIn(file, 'a-hdfc').balance_date, '2026-08-31')

  updateAccount(dir, 'claude', { id: 'a-hdfc', set: { balance_date: '2026-09-01' } })
  assert.equal(accountIn(file, 'a-hdfc').balance_date, '2026-09-01', 'the day alone can move')
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-hdfc', set: { balance_date: null } }), /set balance to null to clear both/)
  assert.equal(accountIn(file, 'a-hdfc').balance_date, '2026-09-01', 'a balance is never left undated')

  updateAccount(dir, 'claude', { id: 'a-hdfc', set: { balance: null } })
  assert.equal(accountIn(file, 'a-hdfc').balance, null)
  assert.equal(accountIn(file, 'a-hdfc').balance_date, null)

  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-hdfc', set: { balance_date: '2026-09-02' } }), /no balance to date/)
  assert.equal(accountIn(file, 'a-hdfc').balance_date, null, 'a day never stands without its balance')
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-visa', set: { balance_date: '2026-09-02' } }), /no balance to date/)
  assert.equal(accountIn(file, 'a-visa').balance_date, undefined)

  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-hdfc', set: { balance: null, balance_date: '2026-01-01' } }), /clears its day too/)
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-hdfc', set: { balance: 1, balance_date: null } }), /carries its day/)
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-hdfc', set: { balance: Infinity } }), /balance is a number/)
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-hdfc', set: { balance: 1, balance_date: '2026-02-30' } }), /real YYYY-MM-DD/)
})

test('add_commitments and add_charges say when the rows just written outrun an account\'s balance; a bare account is silent', () => {
  const { dir, file } = seeded()
  const today = todayMid()
  const day = (n: number) => toISO(new Date(today.getFullYear(), today.getMonth(), today.getDate() + n))
  const once = (name: string, date: string, over: Record<string, unknown> = {}) =>
    ({ name, amount: 900, currency: 'INR', billing_cycle: 'once' as const, date, paid: true, basis: 'statement' as const, account: 'HDFC', ...over })
  updateAccount(dir, 'claude', { id: 'a-hdfc', set: { balance: 250000, balance_date: day(-10) } })

  // Older than the balance, a recurring row's plan past its day, a statement row still ahead: nothing to say.
  const quiet = addCommitments(dir, 'claude', { rows: [
    once('Water cans', day(-12)),
    { name: 'Gym', amount: 1500, currency: 'INR', billing_cycle: 'monthly', first_charge: day(-5), plan_months: 2, account: 'HDFC' },
    once('Flight', day(2)),
  ] }) as Record<string, any>
  assert.equal(quiet.balance_note, undefined)

  // The newest confirmed day names the line; an account holding no balance is left out.
  const stale = addCommitments(dir, 'claude', { rows: [once('Taxi', day(-3)), once('Dinner', day(-1)), once('Top-up', day(-2), { account: 'Amazon Pay' })] }) as Record<string, any>
  assert.equal(
    stale.balance_note,
    `HDFC: balance as of ${day(-10)} is older than the newest charge written, ${day(-1)} — when the statement prints a closing balance, update_account with balance and balance_date its last day.`,
  )

  // add_charges on a commitment billed to the account says the same; a plan row says nothing.
  const gym = (fileJson(file).commitments as any[]).find((c) => c.name === 'Gym').id as string
  const planned = addCharges(dir, 'claude', { id: gym, charges: [{ date: day(-6) }] }) as Record<string, any>
  assert.equal(planned.balance_note, undefined)
  const proved = addCharges(dir, 'claude', { id: gym, charges: [{ date: day(-4), paid: true, basis: 'statement' }] }) as Record<string, any>
  assert.equal(
    proved.balance_note,
    `HDFC: balance as of ${day(-10)} is older than the newest charge written, ${day(-4)} — when the statement prints a closing balance, update_account with balance and balance_date its last day.`,
  )
  assert.equal(proved.written, 1)
})

test('update_account: a linked account by name or id, one level only in both directions, never itself', () => {
  const { dir, file } = seeded()
  updateAccount(dir, 'claude', { id: 'a-visa', set: { linked_to: 'hdfc' } })
  assert.equal(accountIn(file, 'a-visa').parent_account_id, 'a-hdfc', 'a name resolves to the id; the file key keeps its name')

  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-amazon', set: { linked_to: 'a-visa' } }), /already linked to another — one level only/)
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-hdfc', set: { linked_to: 'Amazon Pay' } }), /are linked to this one/)
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-amazon', set: { linked_to: 'a-amazon' } }), /linked to itself/)
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-amazon', set: { linked_to: 'Nobody' } }), /linked account isn't in the vault/)

  // The older names still work, and linked_to wins when a set carries both.
  updateAccount(dir, 'claude', { id: 'a-amazon', set: { parent: 'HDFC' } })
  assert.equal(accountIn(file, 'a-amazon').parent_account_id, 'a-hdfc')
  updateAccount(dir, 'claude', { id: 'a-amazon', set: { linked_to: null, parent_account: 'HDFC' } })
  assert.equal(accountIn(file, 'a-amazon').parent_account_id, null)

  // A name two accounts share resolves to neither; a twin is reached by its id.
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-visa', set: { parent_account: 'cash' } }), /more than one account.*a-cash-1.*a-cash-2/s)
  assert.equal(accountIn(file, 'a-visa').parent_account_id, 'a-hdfc', 'an ambiguous parent changes nothing')
  updateAccount(dir, 'claude', { id: 'a-visa', set: { parent_account: 'a-cash-2' } })
  assert.equal(accountIn(file, 'a-visa').parent_account_id, 'a-cash-2')

  updateAccount(dir, 'claude', { id: 'a-visa', set: { parent_account: null } })
  assert.equal(accountIn(file, 'a-visa').parent_account_id, null)
  updateAccount(dir, 'claude', { id: 'a-visa', set: { tag: null } })
  assert.equal(accountIn(file, 'a-visa').tag, null)
})

test('update_account: the card name is a line of its notes; the person it belongs to — set and cleared', () => {
  const { dir, file } = seeded()
  const report = updateAccount(dir, 'claude', {
    id: 'a-visa',
    set: { tag: 'credit card', notes: 'Card name: Platinum Reserve\nLounge access; fee waived above 4 lakh a year.', member: 'diya' },
  }) as Record<string, any>
  const visa = accountIn(file, 'a-visa')
  assert.equal(visa.notes, 'Card name: Platinum Reserve\nLounge access; fee waived above 4 lakh a year.')
  assert.equal(visa.details, undefined, 'nothing is written to details')
  assert.equal(visa.member_id, 'm-diya', 'a name resolves to the id')
  assert.deepEqual(report.fields, ['tag', 'notes', 'member'])
  const registered = (fileJson(file).tags as any[]).find((t) => t.kind === 'account' && t.name_key === 'credit card')
  assert.deepEqual([registered.icon, registered.is_default], ['creditcard.fill', true])
  assert.equal('template' in registered, false, 'an account tag registers with no template')

  // Details the account holds ride through every write untouched.
  const raw = fileJson(file)
  raw.accounts.find((a: any) => a.id === 'a-visa').details = { card_name: 'Coral', due_day: 5 }
  writeFileSync(file, JSON.stringify(raw, null, 2))
  updateAccount(dir, 'claude', { id: 'a-visa', set: { notes: null, member: '' } })
  const cleared = accountIn(file, 'a-visa')
  assert.deepEqual(cleared.details, { card_name: 'Coral', due_day: 5 })
  assert.equal(cleared.notes, null)
  assert.equal(cleared.member_id, null)
  updateAccount(dir, 'claude', { id: 'a-visa', set: { member: 'm-rohit' } })
  assert.equal(accountIn(file, 'a-visa').member_id, 'm-rohit', 'or by id')

  const before = readFileSync(file)
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-visa', set: { member: 'Nobody' } }), /No person is named "Nobody"\. People: "Rohit", "Diya"\./)
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-visa', set: { notes: 'Card name: Visa 4111 1111 1111 1111' } }), new RegExp(DATA_POLICY_REFUSAL.slice(0, 30)))
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-visa', set: { notes: 'pin: 4821' } }), new RegExp(DATA_POLICY_REFUSAL.slice(0, 30)))
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-visa', set: { notes: 7 } as never }), /notes is text/)
  assert.deepEqual(readFileSync(file), before)
})

// An account's card name and details are longbook's own, and so are a person's details: a write
// sending a non-empty one is refused by name, the local door in the hosted door's words.
const ACCOUNT_DETAILS = "card_name and details are longbook's own — write an account's details as lines of its notes"
const MEMBER_DETAILS = "details is longbook's own — a member carries a name, a tag, an email and linked accounts"
// How each door names an empty one it takes nothing from, with the key meant.
const CARD_NAME_IGNORED = "card_name — a card's name is a line of notes"
const ACCOUNT_DETAILS_IGNORED = "details — an account's details are lines of its notes"
const MEMBER_DETAILS_IGNORED = 'details — a member carries a name, a tag, an email and linked accounts'

test('update_account and update_person refuse card_name and details by name, both doors in one sentence', () => {
  const { dir, file } = seeded()
  const before = readFileSync(file)
  const refusals: [typeof updateAccount | typeof updateMember, string, Record<string, unknown>, string][] = [
    [updateAccount, 'update_account', { card_name: 'Platinum Reserve' }, ACCOUNT_DETAILS],
    [updateAccount, 'update_account', { notes: 'Lounge access', card_name: 'Platinum Reserve' }, ACCOUNT_DETAILS],
    [updateAccount, 'update_account', { details: { due_day: 5 } }, ACCOUNT_DETAILS],
    [updateAccount, 'update_account', { tag: 'credit card', details: { card_name: 'Coral' } }, ACCOUNT_DETAILS],
    [updateMember, 'update_person', { details: { relationship: 'sister' } }, MEMBER_DETAILS],
    [updateMember, 'update_person', { name: 'Diya S', details: { role: 'cook' } }, MEMBER_DETAILS],
    [updateMember, 'update_person', { card_name: 'Coral' }, MEMBER_DETAILS],
  ]
  for (const [write, kind, set, sentence] of refusals) {
    const id = kind === 'update_account' ? 'a-visa' : 'm-diya'
    let local = ''
    assert.throws(() => write(dir, 'claude', { id, set } as never), (error: Error) => {
      local = error.message
      return error.message === `Nothing was changed. Fix these — ${sentence}.`
    }, `${kind} ${JSON.stringify(set)}`)
    assert.throws(() => checkProposal(kind, { id, set }), (error: Error) => error.message === local, `${kind}: both doors word it alike`)
  }
  assert.deepEqual(readFileSync(file), before, 'nothing was written')

  // What says nothing refuses nothing: the rest of the write lands, and the answer names the
  // empty ones as ignored.
  const report = updateAccount(dir, 'claude', { id: 'a-visa', set: { notes: 'Lounge access', card_name: '', details: {} } } as never) as Record<string, any>
  assert.deepEqual(report.fields, ['notes'])
  assert.deepEqual(report.ignored, [CARD_NAME_IGNORED, ACCOUNT_DETAILS_IGNORED])
  assert.equal(accountIn(file, 'a-visa').notes, 'Lounge access')
  assert.equal(accountIn(file, 'a-visa').details, undefined)
  const person = updateMember(dir, 'claude', { id: 'm-diya', set: { tag: 'family', details: null } } as never) as Record<string, any>
  assert.deepEqual(person.fields, ['tag'])
  assert.deepEqual(person.ignored, [MEMBER_DETAILS_IGNORED])
})

test('update_account and update_person name each key they do not take, and write the rest', () => {
  const { dir, file } = seeded()
  const account = updateAccount(dir, 'claude', {
    id: 'a-visa', set: { notes: 'Shared card.', type: 'credit card', belongs_to: 'Diya', colour: 'red' },
  } as never) as Record<string, any>
  assert.deepEqual(account, {
    updated: { id: 'a-visa', name: 'HDFC Visa' },
    fields: ['notes'],
    ignored: ['type — the account type is tag', 'belongs_to — the person is member', 'colour'],
  })
  const visa = accountIn(file, 'a-visa')
  assert.deepEqual([visa.notes, visa.tag, visa.member_id], ['Shared card.', undefined, undefined], 'nothing is guessed from them')

  // The linked account under two of its names: the first the set gives is written, the other named.
  const linked = updateAccount(dir, 'claude', { id: 'a-visa', set: { linked_to: 'HDFC', parent: 'Amazon Pay' } }) as Record<string, any>
  assert.deepEqual([linked.fields, linked.ignored], [['linked_to'], ['parent — linked_to wins']])
  assert.equal(accountIn(file, 'a-visa').parent_account_id, 'a-hdfc')

  const person = updateMember(dir, 'claude', { id: 'm-diya', set: { tag: 'family', role: 'sister', notes: 'Role: cook' } } as never) as Record<string, any>
  assert.deepEqual(person, {
    updated: { id: 'm-diya', name: 'Diya' },
    fields: ['tag'],
    ignored: ['role — their role is tag', 'notes — what is said about a person goes in the notes of the commitment it is about'],
  })
  assert.equal(memberIn(file, 'm-diya').notes, undefined)
  const plain = updateMember(dir, 'claude', { id: 'm-diya', set: { email: 'diya@example.com' } }) as Record<string, any>
  assert.equal('ignored' in plain, false, 'a set the tool takes whole names nothing')
})

test('the two tools say what they refuse: a card_name or details that is not empty', () => {
  assert.match(UPDATE_ACCOUNT_SPEC.description, /card_name and details are longbook's own, and a set sending a non-empty one is refused\./)
  assert.match(UPDATE_MEMBER_SPEC.description, /details and card_name are longbook's own, and a set sending a non-empty one is refused\./)
})

test('a template a vault holds on any tag, of any shape, never stops a write', () => {
  const { dir, file } = seeded()
  const raw = fileJson(file)
  raw.tags = [
    { id: 't1', kind: 'account', name: 'credit card', name_key: 'credit card', template: 'not a list of fields' },
    { id: 't2', kind: 'member', name: 'family', name_key: 'family', template: [{ key: 'relationship' }] },
  ]
  writeFileSync(file, JSON.stringify(raw, null, 2))
  updateAccount(dir, 'claude', { id: 'a-visa', set: { tag: 'credit card' } })
  assert.equal(accountIn(file, 'a-visa').tag, 'credit card')
  assert.deepEqual(fileJson(file).tags, raw.tags, 'the file keeps what it holds')
})

test('update_account: a tag of only whitespace or newlines clears, and registers nothing', () => {
  const { dir, file } = seeded()
  updateAccount(dir, 'claude', { id: 'a-hdfc', set: { tag: 'bank account' } })
  assert.equal(accountIn(file, 'a-hdfc').tag, 'bank account')
  updateAccount(dir, 'claude', { id: 'a-hdfc', set: { tag: '\n' } })
  assert.equal(accountIn(file, 'a-hdfc').tag, null)
  updateAccount(dir, 'claude', { id: 'a-hdfc', set: { tag: ' \r\n ' } })
  assert.equal(accountIn(file, 'a-hdfc').tag, null)
  const registry = fileJson(file).tags as any[]
  assert.equal(registry.length, 1, 'only the real tag is registered')
  assert.ok(registry.every((t) => t.name_key), 'no entry with an empty name_key')
})

test('update_account: unknown, ambiguous and unnamed asks refuse, naming the candidates', () => {
  const { dir, file } = seeded()
  const before = readFileSync(file)
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-none', set: { tag: 'cash' } }), /No account has the id a-none/)
  assert.throws(() => updateAccount(dir, 'claude', { name: 'Nobody', set: { tag: 'cash' } }), /No account is named "Nobody"/)
  assert.throws(() => updateAccount(dir, 'claude', { name: 'CASH', set: { tag: 'cash' } }), /more than one account.*a-cash-1.*a-cash-2/s)
  assert.throws(() => updateAccount(dir, 'claude', { set: { tag: 'cash' } }), /Say which account/)
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-hdfc', set: {} }), /at least one field/)
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-hdfc', set: { colour: 'red' } as never }), /names none of/)
  assert.deepEqual(readFileSync(file), before)
})

test('update_person renames and reaches a person; email is kept as typed, cleared by null or ""', () => {
  const { dir, file } = seeded()
  const report = updateMember(dir, 'claude', { name: 'rohit', set: { name: 'Rohit S', email: ' Rohit@Example.com ' } }) as Record<string, any>
  assert.equal(memberIn(file, 'm-rohit').name, 'Rohit S')
  assert.equal(memberIn(file, 'm-rohit').name_key, 'rohit s')
  assert.equal(memberIn(file, 'm-rohit').email, ' Rohit@Example.com ')
  assert.equal(fileJson(file)._provenance['m-rohit'].edited_by, 'claude')
  assert.deepEqual(report, { updated: { id: 'm-rohit', name: 'Rohit S' }, fields: ['name', 'email'] })

  updateMember(dir, 'claude', { id: 'm-rohit', set: { email: null } })
  assert.equal(memberIn(file, 'm-rohit').email, null)
  updateMember(dir, 'claude', { id: 'm-diya', set: { email: '' } })
  assert.equal(memberIn(file, 'm-diya').email, null)

  // A tag is their role: the library's entry arrives whole, a new one is allowed, null clears.
  updateMember(dir, 'claude', { id: 'm-diya', set: { tag: ' Household Help ' } })
  assert.equal(memberIn(file, 'm-diya').tag, 'Household Help')
  const role = (fileJson(file).tags as any[]).find((t) => t.kind === 'member' && t.name_key === 'household help')
  assert.deepEqual([role.name, role.is_default, role.icon], ['household help', true, 'person.badge.clock'])
  assert.equal('template' in role, false, 'a member tag registers with no template')
  updateMember(dir, 'claude', { id: 'm-diya', set: { tag: 'tutor' } })
  assert.equal((fileJson(file).tags as any[]).find((t) => t.name_key === 'tutor').is_default, false)
  updateMember(dir, 'claude', { id: 'm-diya', set: { tag: null } })
  assert.equal(memberIn(file, 'm-diya').tag, null)
  assert.equal(memberIn(file, 'm-diya').email, null, 'a tag change touches nothing else')

  const before = readFileSync(file)
  assert.throws(() => updateMember(dir, 'claude', { id: 'm-rohit', set: { tag: 7 } as never }), /tag is their role/)
  assert.throws(() => updateMember(dir, 'claude', { id: 'm-rohit', set: { email: 'rohit.example.com' } }), /@ with something either side/)
  assert.throws(() => updateMember(dir, 'claude', { id: 'm-rohit', set: { email: '@example.com' } }), /@ with something either side/)
  assert.throws(() => updateMember(dir, 'claude', { id: 'm-rohit', set: { name: 'diya' } }), /There's already a person called diya\./)
  assert.throws(() => updateMember(dir, 'claude', { id: 'm-none', set: { email: 'a@b' } }), /No person has the id m-none/)
  assert.throws(() => updateMember(dir, 'claude', { name: 'Rohit S', set: {} }), /at least one field/)
  assert.deepEqual(readFileSync(file), before)
})

test('the hosted door holds both payloads to the same contract before filing', () => {
  const filed = checkProposal('update_account', { name: 'HDFC', set: { balance: 1200, tag: 'bank account' }, idempotency_key: 'k1' })
  assert.equal(filed.kind, 'update_account')
  assert.equal(filed.idempotency_key, 'k1')
  assert.deepEqual(filed.payload, { name: 'HDFC', set: { balance: 1200, tag: 'bank account' } })
  assert.equal(checkProposal('update_person', { id: 'm1', set: { email: null } }).kind, 'update_person')

  assert.throws(() => checkProposal('update_account', { set: { tag: 'cash' } }), /Say which account/)
  assert.throws(() => checkProposal('update_account', { name: 'HDFC', set: { balance: 1, balance_date: '2026-02-30' } }), /real YYYY-MM-DD/)
  assert.throws(() => checkProposal('update_account', { name: 'HDFC', set: { balance_date: null } }), /set balance to null to clear both/)
  assert.throws(() => checkProposal('update_account', { name: 'HDFC', set: { balance: 1, balance_date: null } }), /carries its day/)
  assert.throws(() => checkProposal('update_account', { name: 'HDFC', set: { parent_account: '  ' } }), /parent_account is an account name or id/)
  assert.throws(() => checkProposal('update_account', { name: 'HDFC', set: { linked_to: '' } }), /linked_to is an account name or id/)
  assert.throws(() => checkProposal('update_account', { name: 'HDFC', set: { card_name: 'Platinum Reserve' } }),
    (error: Error) => error.message === `Nothing was changed. Fix these — ${ACCOUNT_DETAILS}.`)
  assert.throws(() => checkProposal('update_account', { name: 'HDFC', set: { notes: 'Card name: 4111 1111 1111 1111' } }), new RegExp(DATA_POLICY_REFUSAL.slice(0, 30)))
  assert.throws(() => checkProposal('update_account', { name: 'HDFC', set: { member: 3 } }), /member is text/)
  const described = checkProposal('update_account', { name: 'HDFC Visa', set: { notes: 'Card name: Platinum Reserve', member: 'Diya', linked_to: 'HDFC' } })
  assert.deepEqual(Object.keys(described.payload.set as object), ['notes', 'member', 'linked_to'])
  assert.equal(checkProposal('update_person', { id: 'm1', set: { tag: 'landlord' } }).kind, 'update_person')
  assert.throws(() => checkProposal('update_person', { id: 'm1', set: { tag: 3 } }), /tag is their role/)
  assert.throws(() => checkProposal('update_account', { name: 'HDFC', set: { name: 'Visa 4111 1111 1111 1111' } }), new RegExp(DATA_POLICY_REFUSAL.slice(0, 30)))
  assert.throws(() => checkProposal('update_person', { set: { email: 'a@b' } }), /Say which person/)
  assert.throws(() => checkProposal('update_person', { id: 'm1', set: { email: 'nope' } }), /@ with something either side/)
  assert.throws(() => checkProposal('update_person', { id: 'm1', set: { nickname: 'R' } }), /none of name, email, tag/)
  assert.throws(() => checkProposal('update_person', { id: 'm1', set: { details: { role: 'cook' } } }),
    (error: Error) => error.message === `Nothing was changed. Fix these — ${MEMBER_DETAILS}.`)
})

// The rule: the hosted door scans a payload on what its values say, not on their type — nor
// on whether the tool takes the key. A number is rendered and scanned as a string is.
test('the hosted door refuses a card number in a payload whatever type or key carries it', () => {
  const refusal = new RegExp(DATA_POLICY_REFUSAL.slice(0, 30))
  const row = (memo: unknown) => ({
    rows: [{ name: 'Visa', amount: 100, currency: 'INR', billing_cycle: 'monthly', first_charge: '2026-09-10', memo }],
  })
  for (const value of [4111111111111111, '4111111111111111', [4111111111111111], ['ok', 4111111111111111]]) {
    const shown = JSON.stringify(value)
    assert.throws(() => checkProposal('add_commitments', row({ card_ref: value })), refusal, `add_commitments memo.card_ref = ${shown}`)
    assert.throws(
      () => checkProposal('update_commitment', { id: 'c1', set: { notes: 'Plan: Premium', memo: { card_ref: value } } }),
      refusal,
      `update_commitment memo.card_ref = ${shown}`,
    )
  }
  // And an ordinary figure still passes: a cover amount is not a secret.
  assert.equal(checkProposal('add_commitments', row({ cover: 10000000, auto_debit: true })).kind, 'add_commitments')
  assert.equal(checkProposal('update_commitment', { id: 'c1', set: { notes: 'Cover: 1 crore', memo: { cover: 10000000 } } }).kind, 'update_commitment')
})

test('both doors render a payload value into the same words before scanning it', () => {
  // One input, two renderings, one verdict — the asymmetry that matters is a secret
  // refused at one door and written at the other.
  assert.equal(payloadTexts({ details: { card_ref: 4111111111111111 } })['payload.details.card_ref'], '4111111111111111')
  assert.deepEqual(payloadTexts({ a: [1, 'b', true, null] }), {
    'payload.a.0': '1',
    'payload.a.1': 'b',
    'payload.a.2': 'yes',
  })
  assert.equal(payloadTexts({ big: 1e18 })['payload.big'], '1000000000000000000', 'never an exponent')
})

// ---- add_member, add_account -------------------------------------------------------------

test('add_member makes a person with what is known, registers their tag, and signs the row', () => {
  const { dir, file } = seeded()
  const report = addMember(dir, 'claude', { name: ' Meera ', tag: 'Household help', email: 'meera@example.com', source: 'gmail:18c2a' }) as Record<string, any>
  const meera = (fileJson(file).members as any[]).find((m) => m.name === 'Meera')
  assert.equal(meera.name_key, 'meera')
  assert.equal(meera.is_incomplete, false, 'described, so no longer only a name')
  assert.equal(meera.tag, 'Household help')
  assert.equal(meera.email, 'meera@example.com')
  assert.ok(meera.created_at)
  const registered = (fileJson(file).tags as any[]).find((t) => t.kind === 'member' && t.name_key === 'household help')
  assert.equal(registered.icon, 'person.badge.clock', 'the library entry, whole')
  assert.deepEqual(fileJson(file)._provenance[meera.id], { edited_by: 'claude', edited_at: fileJson(file)._provenance[meera.id].edited_at, source: 'gmail:18c2a' })
  assert.deepEqual(report, { added: { id: meera.id, name: 'Meera' }, fields: ['tag', 'email'] })

  // A name alone is a placeholder, as ensureEntity writes one.
  addMember(dir, 'claude', { name: 'Arjun' })
  assert.equal((fileJson(file).members as any[]).find((m) => m.name === 'Arjun').is_incomplete, true)
})

test('add_member refuses a twin, an empty name, a bad email and details, leaving the file as it was', () => {
  const { dir, file } = seeded()
  const before = readFileSync(file)
  assert.throws(() => addMember(dir, 'claude', { name: 'rohit ' }), (e: Error) => e.message === entityTwinRefusal('a person', 'rohit'))
  assert.throws(() => addMember(dir, 'claude', { name: '  ' }), (e: Error) => e.message === EMPTY_NAME_REFUSAL)
  assert.throws(() => addMember(dir, 'claude', { name: 'Meera', email: 'not-an-address' }), /@ with something either side/)
  assert.throws(() => addMember(dir, 'claude', { name: 'Meera', details: { role: 'cook' } }), new RegExp(MEMBER_DETAILS_REFUSAL))
  assert.throws(() => addMember(dir, 'claude', { name: 'Card 4111 1111 1111 1111' }), new RegExp(DATA_POLICY_REFUSAL))
  for (const [args, words] of [
    [{ name: '' }, EMPTY_NAME_REFUSAL],
    [{ name: 'Meera', details: { role: 'cook' } }, `Nothing was changed. Fix these — ${MEMBER_DETAILS_REFUSAL}.`],
  ] as [Record<string, unknown>, string][]) {
    assert.throws(() => checkProposal('add_person', args), (e: Error) => e.message === words, 'both doors word it alike')
  }
  assert.deepEqual(readFileSync(file), before)
})

test('add_account makes an account with its type, link, owner, notes and balance, as update_account would set them', () => {
  const { dir, file } = seeded()
  const report = addAccount(dir, 'claude', {
    name: 'Coral 9292', tag: 'credit card', linked_to: 'hdfc', member: 'Diya',
    notes: 'Card name: Coral\nBilling day: 20', balance: 18400.5,
  }) as Record<string, any>
  const coral = (fileJson(file).accounts as any[]).find((a) => a.name === 'Coral 9292')
  assert.equal(coral.name_key, 'coral 9292')
  assert.equal(coral.is_incomplete, false)
  assert.equal(coral.tag, 'credit card')
  assert.equal(coral.parent_account_id, 'a-hdfc', 'a name resolves to the id')
  assert.equal(coral.member_id, 'm-diya')
  assert.equal(coral.notes, 'Card name: Coral\nBilling day: 20')
  assert.equal(coral.balance, 18400.5)
  assert.equal(coral.balance_date, toISO(todayMid()), 'a bare balance is dated today')
  assert.ok((fileJson(file).tags as any[]).some((t) => t.kind === 'account' && t.name_key === 'credit card'))
  assert.equal(fileJson(file)._provenance[coral.id].edited_by, 'claude')
  assert.deepEqual(report, { added: { id: coral.id, name: 'Coral 9292' }, fields: ['tag', 'linked_to', 'member', 'notes', 'balance'] })

  addAccount(dir, 'claude', { name: 'Wallet' })
  assert.equal((fileJson(file).accounts as any[]).find((a) => a.name === 'Wallet').is_incomplete, true)
})

test('add_account takes the link under parent or parent_account as update_account does, linked_to winning', () => {
  const { dir, file } = seeded()
  const byParent = addAccount(dir, 'claude', { name: 'Coral', parent: 'HDFC' }) as Record<string, any>
  const coral = (fileJson(file).accounts as any[]).find((a) => a.name === 'Coral')
  assert.equal(coral.parent_account_id, 'a-hdfc', 'the older name links the account rather than leaving a placeholder')
  assert.equal(coral.is_incomplete, false)
  assert.deepEqual(byParent.fields, ['parent'])

  const both = addAccount(dir, 'claude', { name: 'Reef', linked_to: 'HDFC', parent_account: 'Amazon Pay' }) as Record<string, any>
  assert.equal((fileJson(file).accounts as any[]).find((a) => a.name === 'Reef').parent_account_id, 'a-hdfc')
  assert.deepEqual([both.fields, both.ignored], [['linked_to'], ['parent_account — linked_to wins']])

  assert.throws(() => addAccount(dir, 'claude', { name: 'Shoal', parent_account: 'Nobody' }), /That linked account isn't in the vault/)
  for (const key of ['parent', 'parent_account']) {
    assert.throws(() => addAccount(dir, 'claude', { name: 'Shoal', [key]: '  ' }), new RegExp(`${key} is an account name or id`))
    assert.throws(() => checkProposal('add_account', { name: 'Shoal', [key]: '  ' }), new RegExp(`${key} is an account name or id`), 'both doors word it alike')
  }
})

test('add_account refuses a twin, a link that is not one account, an owner the memory lacks, and a card name', () => {
  const { dir, file } = seeded()
  const before = readFileSync(file)
  assert.throws(() => addAccount(dir, 'claude', { name: 'HDFC ' }), (e: Error) => e.message === entityTwinRefusal('an account', 'HDFC'))
  assert.throws(() => addAccount(dir, 'claude', { name: 'Coral', linked_to: 'cash' }), /matches more than one account/)
  assert.throws(() => addAccount(dir, 'claude', { name: 'Coral', linked_to: 'Nobody' }), /That linked account isn't in the vault/)
  assert.throws(() => addAccount(dir, 'claude', { name: 'Coral', member: 'Nobody' }), /No person is named "Nobody"/)
  assert.throws(() => addAccount(dir, 'claude', { name: 'Coral', card_name: 'Platinum' }), new RegExp(ACCOUNT_DETAILS_REFUSAL))
  assert.throws(() => addAccount(dir, 'claude', { name: 'Coral', notes: 'pin: 4821' }), new RegExp(DATA_POLICY_REFUSAL))
  assert.throws(() => addAccount(dir, 'claude', { name: 'Coral', balance_date: '2026-09-01' }), /a balance carries its day; give balance with balance_date/)
  assert.throws(() => checkProposal('add_account', { name: 'Coral', card_name: 'Platinum' }), (e: Error) => e.message === `Nothing was changed. Fix these — ${ACCOUNT_DETAILS_REFUSAL}.`)
  assert.throws(() => checkProposal('add_account', { name: '' }), (e: Error) => e.message === EMPTY_NAME_REFUSAL)
  assert.deepEqual(readFileSync(file), before)
})

// ---- rename_tag, delete_tag --------------------------------------------------------------

const TAGGED = {
  app: 'longbook',
  version: 3,
  commitments: [
    { id: 'c-rent', name: 'Rent', amount: 42000, currency: 'INR', billing_cycle: 'monthly', status: 'active', tag: 'Home' },
    { id: 'c-gas', name: 'Gas', amount: 900, currency: 'INR', billing_cycle: 'monthly', status: 'active', tag: 'home ' },
    { id: 'c-claude', name: 'Claude', amount: 20, currency: 'USD', billing_cycle: 'monthly', status: 'active', tag: 'Work' },
  ],
  members: [{ id: 'm-ramesh', name: 'Ramesh', name_key: 'ramesh', tag: 'cook' }],
  accounts: [{ id: 'a-hdfc', name: 'HDFC', name_key: 'hdfc', tag: 'bank account' }],
  tags: [
    { id: 't-home', kind: 'commitment', name: 'Home', name_key: 'home', icon: 'house', is_default: true, sort: 0 },
    { id: 't-work', kind: 'commitment', name: 'Work', name_key: 'work', is_default: false, sort: 1 },
    { id: 't-bank', kind: 'account', name: 'bank account', name_key: 'bank account', is_default: true, sort: 0 },
  ],
  groups: [
    { id: 'g-house', kind: 'tag', name: 'House', name_key: 'house', tag_keys: ['home', 'work'] },
    { id: 'g-cards', kind: 'account', name: 'Cards', name_key: 'cards', account_ids: ['a-hdfc'] },
  ],
}

function tagged(): { dir: string; file: string } {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-mcp-tags-'))
  const file = join(dir, 'financial_memory.json')
  writeFileSync(file, JSON.stringify(TAGGED, null, 2))
  return { dir, file }
}

test('rename_tag renames the registry entry and carries every row wearing it, the owner\'s tag groups too', () => {
  const { dir, file } = tagged()
  const report = renameTag(dir, 'claude', { kind: 'commitment', from: 'HOME', to: ' Household ' })
  const vault = fileJson(file)
  const entry = (vault.tags as any[]).find((t) => t.id === 't-home')
  assert.deepEqual([entry.name, entry.name_key, entry.is_default, entry.icon], ['Household', 'household', false, 'house'], 'renamed is the owner\'s own word now')
  assert.deepEqual(vault.commitments.map((c: any) => c.tag), ['Household', 'Household', 'Work'])
  assert.deepEqual((vault.groups as any[])[0].tag_keys, ['household', 'work'], 'the group keeps its category')
  assert.deepEqual((vault.groups as any[])[1].account_ids, ['a-hdfc'])
  assert.deepEqual(Object.keys(vault._provenance).sort(), ['c-gas', 'c-rent'], 'carried rows are signed; tag rows never are')
  assert.equal(vault._provenance['c-rent'].edited_by, 'claude')
  assert.deepEqual(report, { renamed: { from: 'HOME', to: 'Household' }, kind: 'commitment', rows_moved: 2 })

  // A tag worn but never registered is renamed on its rows all the same.
  const worn = renameTag(dir, 'claude', { kind: 'member', from: 'cook', to: 'household help' })
  assert.equal(fileJson(file).members[0].tag, 'household help')
  assert.deepEqual(worn, { renamed: { from: 'cook', to: 'household help' }, kind: 'member', rows_moved: 1 })
  // Only the case changes: no twin, the rows follow.
  renameTag(dir, 'claude', { kind: 'commitment', from: 'work', to: 'WORK' })
  assert.equal(fileJson(file).commitments[2].tag, 'WORK')
})

test('rename_tag refuses a twin, an empty name, a tag nobody wears, and a secret, leaving the file as it was', () => {
  const { dir, file } = tagged()
  const before = readFileSync(file)
  assert.throws(() => renameTag(dir, 'claude', { kind: 'commitment', from: 'Home', to: 'work' }), (e: Error) => e.message === tagTwinRefusal('work'))
  assert.throws(() => renameTag(dir, 'claude', { kind: 'commitment', from: 'Home', to: '  ' }), (e: Error) => e.message === EMPTY_NAME_REFUSAL)
  assert.throws(() => renameTag(dir, 'claude', { kind: 'commitment', from: 'Travel', to: 'Trips' }), /No commitment tag is called "Travel"/)
  assert.throws(() => renameTag(dir, 'claude', { kind: 'account', from: 'Home', to: 'Household' }), /No account tag is called "Home"/)
  assert.throws(() => renameTag(dir, 'claude', { kind: 'commitment', from: 'Home', to: '4111 1111 1111 1111' }), new RegExp(DATA_POLICY_REFUSAL))
  assert.throws(() => renameTag(dir, 'claude', { kind: 'thing' as 'commitment', from: 'Home', to: 'X' }), /kind is commitment, member, account/)
  for (const [args, words] of [
    [{ kind: 'commitment', from: 'Home', to: '' }, EMPTY_NAME_REFUSAL],
    [{ kind: 'thing', from: 'Home', to: 'X' }, 'kind is commitment, member, account — which list the tag belongs to.'],
    [{ kind: 'commitment', from: '', to: 'X' }, 'from names the tag as the vault holds it.'],
  ] as [Record<string, unknown>, string][]) {
    assert.throws(() => checkProposal('rename_tag', args), (e: Error) => e.message === words, 'both doors word it alike')
  }
  assert.deepEqual(readFileSync(file), before)
})

test('delete_tag removes the registry entry and leaves the rows that wore it with no category', () => {
  const { dir, file } = tagged()
  const report = deleteTag(dir, 'claude', { kind: 'commitment', name: 'home' })
  const vault = fileJson(file)
  assert.deepEqual((vault.tags as any[]).map((t) => t.id), ['t-work', 't-bank'])
  assert.deepEqual(vault.commitments.map((c: any) => c.tag), [null, null, 'Work'])
  assert.deepEqual(Object.keys(vault._provenance).sort(), ['c-gas', 'c-rent'])
  assert.deepEqual(report, { deleted: 'home', kind: 'commitment', rows_cleared: 2 })
  assert.deepEqual((vault.groups as any[])[0].tag_keys, ['home', 'work'], 'a group is the owner\'s own label; it is left as it was')

  const bare = deleteTag(dir, 'claude', { kind: 'member', name: 'cook' })
  assert.equal(fileJson(file).members[0].tag, null)
  assert.deepEqual(bare, { deleted: 'cook', kind: 'member', rows_cleared: 1 })

  const before = readFileSync(file)
  assert.throws(() => deleteTag(dir, 'claude', { kind: 'commitment', name: 'Travel' }), /No commitment tag is called "Travel"/)
  assert.throws(() => deleteTag(dir, 'claude', { kind: 'commitment', name: ' ' }), /name names the tag as the vault holds it/)
  assert.throws(() => checkProposal('delete_tag', { kind: 'commitment', name: '' }), /name names the tag as the vault holds it\./)
  assert.deepEqual(readFileSync(file), before)
})

test('update_account and update_person star and unstar; the read tools say so; a star that is not a boolean is refused', async () => {
  const { dir, file } = seeded()
  const report = updateAccount(dir, 'claude', { id: 'a-hdfc', set: { starred: true } }) as Record<string, any>
  assert.equal(accountIn(file, 'a-hdfc').starred, true)
  assert.deepEqual(report.fields, ['starred'])
  updateMember(dir, 'claude', { id: 'm-diya', set: { starred: true } })
  assert.equal(memberIn(file, 'm-diya').starred, true)
  const { parseVault } = await import('../src/parse.js')
  const { accounts, members } = await import('../src/tools.js')
  const data = parseVault(readFileSync(file, 'utf8'))
  assert.equal((accounts(data).accounts.find((a) => a.id === 'a-hdfc') as Record<string, unknown>).starred, true)
  assert.equal('starred' in (accounts(data).accounts.find((a) => a.id === 'a-visa') as Record<string, unknown>), false)
  assert.equal((members(data).members.find((m) => m.id === 'm-diya') as Record<string, unknown>).starred, true)
  // Off leaves no key behind, as the app writes it.
  updateAccount(dir, 'claude', { id: 'a-hdfc', set: { starred: false } })
  assert.equal('starred' in accountIn(file, 'a-hdfc'), false)
  assert.throws(() => updateAccount(dir, 'claude', { id: 'a-hdfc', set: { starred: 'yes' as unknown as boolean } }), /starred is true or false/)
  assert.throws(() => updateMember(dir, 'claude', { id: 'm-diya', set: { starred: 1 as unknown as boolean } }), /starred is true or false/)
})
