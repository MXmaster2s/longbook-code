// The reorganisation's pure part: the digest names every row by id, and the sieve keeps
// only proposals the book can take — nothing that moves money, nothing already so.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  MAX_PART_PROPOSALS, PART_SIZE, carryOf, digest, emptyCarry, groupKey, partCount, partition, readCarry, reorganiseInstructions, takeProposals,
} from '../src/reorganise.js'
import { fixture, inMonths, mkRow, mkSub } from './fixtures.js'

test('digest: every commitment, person and account by id, with the library beside the book', () => {
  const text = digest(fixture())
  for (const id of ['s-netflix', 's-rent', 'm-rohit', 'pm-hdfc']) assert.ok(text.includes(id), id)
  assert.ok(text.includes('streaming'), 'library tag named')
  assert.ok(text.includes('## Commitments'))
})

test('digest: lists paid charges two commitments share by day and amount', () => {
  const data = fixture()
  const day = inMonths(-1)
  data.charges!.push({ commitment_id: 's-rent', date: day, amount: 299, paid: true, basis: 'statement' })
  const text = digest(data)
  assert.ok(text.includes('share a day and an amount'))
  assert.ok(text.includes(`${day} 299 | s-old, s-rent`) || text.includes(`${day} 299 | s-rent, s-old`))
})

test('instructions carry the chapter, the tool schemas and the day', () => {
  const text = reorganiseInstructions('## Reorganise my longbook\nThe method.', '2026-10-15')
  assert.ok(text.includes('The method.'))
  assert.ok(text.includes('update_commitment: {'))
  assert.ok(text.includes('rename_tag: {'))
  assert.ok(text.includes('2026-10-15'))
})

test('sieve: keeps names, tags and links; drops money, unknown rows and no-ops', () => {
  const data = fixture()
  const answer = {
    summary: 'Renamed one, categorised two.',
    proposals: [
      { kind: 'update_commitment', arguments: JSON.stringify({ id: 's-icloud', set: { tag: 'software', amount: 999 } }), why: 'software' },
      { kind: 'update_commitment', arguments: JSON.stringify({ id: 's-netflix', set: { tag: 'Entertainment' } }), why: 'same tag' },
      { kind: 'update_commitment', arguments: JSON.stringify({ id: 's-nobody', set: { tag: 'software' } }), why: 'missing' },
      { kind: 'update_commitment', arguments: JSON.stringify({ id: 's-water', set: { status: 'cancelled' } }), why: 'money' },
      { kind: 'rename_tag', arguments: JSON.stringify({ kind: 'commitment', from: 'Entertainment', to: 'streaming' }), why: 'library word' },
      { kind: 'add_person', arguments: JSON.stringify({ name: 'Sunita', tag: 'household help' }), why: 'paid monthly' },
      { kind: 'delete_commitment', arguments: JSON.stringify({ id: 's-old' }), why: 'not allowed' },
      { kind: 'update_commitment', arguments: '{not json', why: 'broken' },
      { kind: 'update_commitment', arguments: JSON.stringify({ id: 's-icloud', set: { tag: 'software' } }), why: 'twin' },
    ],
  }
  const out = takeProposals(answer, data)
  assert.equal(out.summary, 'Renamed one, categorised two.')
  assert.deepEqual(out.proposals.map((p) => p.kind), ['update_commitment', 'rename_tag', 'add_person'])
  assert.deepEqual(out.proposals[0]!.payload, { id: 's-icloud', set: { tag: 'software' } })
  assert.equal(out.dropped, 5)
})

test('sieve: a charge goes only when another commitment holds the same paid day and amount', () => {
  const data = fixture()
  const day = inMonths(-1)
  data.charges!.push({ commitment_id: 's-rent', date: day, amount: 299, paid: true, basis: 'statement' })
  const out = takeProposals({
    summary: '',
    proposals: [
      { kind: 'remove_charges', arguments: JSON.stringify({ id: 's-rent', dates: [day, inMonths(-2)] }), why: 'double' },
      { kind: 'remove_charges', arguments: JSON.stringify({ id: 's-netflix', dates: [inMonths(-1, new Date().getDate() + 3)] }), why: 'not a double' },
    ],
  }, data)
  assert.equal(out.proposals.length, 1)
  assert.deepEqual(out.proposals[0]!.payload, { id: 's-rent', dates: [day] })
  assert.equal(out.dropped, 1)
})

/** A book shaped like a long-kept one: 320 commitments, bank-style twins, two years of charges. */
function bigBook() {
  const data = fixture()
  const payees = ['Netflix', 'Spotify', 'HDFC Ergo', 'Airtel', 'Swiggy', 'Zomato', 'Uber', 'Amazon', 'Jio', 'Tata Power']
  for (let i = 0; i < 312; i++) {
    const payee = payees[i % payees.length]!
    const bank = i % 3 === 0
    const id = `s-big-${String(i).padStart(3, '0')}`
    data.subs.push(mkSub({ id, name: bank ? `ACH DEBIT ${payee.toUpperCase()} ${4400 + i}` : `${payee} ${i}`, amount: 100 + i }))
    for (let m = 0; m < 24; m++) data.charges!.push(mkRow(id, inMonths(m - 12, 1 + (i % 27)), 100 + i, { paid: m < 12, basis: m < 12 ? 'statement' : 'plan' }))
  }
  return data
}

test('groupKey: a bank-style name and the plain one point at one payee', () => {
  assert.equal(groupKey('ACH DEBIT NETFLIX.COM 4402'), 'netflix')
  assert.equal(groupKey('Netflix'), 'netflix')
  assert.equal(groupKey('UPI-SWIGGY-PAYMENT'), 'swiggy')
  assert.equal(groupKey('1234'), '')
})

test('partition: a 320-row book in parts of about forty, every row once, each payee in one part', () => {
  const data = bigBook()
  const parts = partition(data)
  assert.equal(parts.length, partCount(data.subs.length))
  assert.equal(parts.length, Math.ceil(320 / PART_SIZE))
  const all = parts.flat()
  assert.equal(all.length, data.subs.length)
  assert.equal(new Set(all).size, data.subs.length)
  for (const p of parts) assert.ok(p.length >= PART_SIZE / 2 && p.length <= PART_SIZE * 1.5, `part of ${p.length}`)
  // Ten payees of 31 or so rows each: no payee's group is split more than its size needs.
  const where = new Map(parts.flatMap((p, i) => p.map((id) => [id, i] as const)))
  const netflix = data.subs.filter((s) => groupKey(s.name) === 'netflix').map((s) => where.get(s.id))
  assert.equal(new Set(netflix).size, 1, 'every Netflix row in one part')
  assert.deepEqual(partition(data), parts, 'the same book gives the same parts')
})

test('partition: commitments sharing a paid day and amount sit in one part', () => {
  const data = bigBook()
  const day = inMonths(-3, 9)
  // Two names that sort far apart: "Cult" and "Yoga studio", the one class paid twice.
  data.subs.push(mkSub({ id: 's-cult', name: 'Cult membership', amount: 777 }), mkSub({ id: 's-yoga', name: 'Yoga studio', amount: 777 }))
  data.charges!.push(mkRow('s-cult', day, 777, { paid: true, basis: 'statement' }))
  data.charges!.push(mkRow('s-yoga', day, 777, { paid: true, basis: 'statement' }))
  const parts = partition(data)
  const holder = parts.find((p) => p.includes('s-cult'))!
  assert.ok(holder.includes('s-yoga'))
})

test('partition: a small book is one part, an empty one too', () => {
  assert.equal(partition(fixture()).length, 1)
  assert.deepEqual(partition({ ...fixture(), subs: [], charges: [] }), [[]])
})

test('digest of a part: its rows in full, the rest by name, earlier choices listed', () => {
  const data = bigBook()
  const parts = partition(data)
  const carry = { ...emptyCarry(), tags_renamed: [{ kind: 'commitment', from: 'OTT', to: 'Streaming' }], people: ['Sunita'] }
  const scope = { index: 2, count: parts.length, ids: new Set(parts[2]), carry }
  const text = digest(data, 160_000, scope)
  const commitments = text.split('## Commitments')[1]!.split('\n## ')[0]!
  for (const id of parts[2]!) assert.ok(commitments.includes(id), id)
  for (const id of parts[0]!) assert.ok(!commitments.includes(`${id} |`), id)
  assert.ok(text.includes("other commitments, read in other parts"))
  assert.ok(text.includes('commitment OTT → Streaming'))
  assert.ok(text.includes('people added: Sunita'))
  assert.ok(text.length < 40_000, `digest of ${text.length}`)
  const words = reorganiseInstructions('The method.', '2026-10-27', scope)
  assert.ok(words.includes(`${parts.length} parts; this is part 3`))
  assert.ok(words.includes(`at most ${MAX_PART_PROPOSALS} proposals`))
})

test('sieve of a part: its own rows only, book-wide kinds in the first part, earlier choices kept', () => {
  const data = bigBook()
  const parts = partition(data)
  const inPart = parts[1]![0]!
  const elsewhere = parts[0]![0]!
  const carry = { ...emptyCarry(), tags_renamed: [{ kind: 'commitment', from: 'OTT', to: 'Streaming' }], people: ['Sunita'] }
  const answer = {
    summary: 'Part two.',
    proposals: [
      { kind: 'update_commitment', arguments: JSON.stringify({ id: inPart, set: { tag: 'ott' } }), why: 'renamed tag' },
      { kind: 'update_commitment', arguments: JSON.stringify({ id: elsewhere, set: { tag: 'software' } }), why: 'other part' },
      { kind: 'rename_tag', arguments: JSON.stringify({ kind: 'commitment', from: 'Entertainment', to: 'streaming' }), why: 'first part only' },
      { kind: 'add_person', arguments: JSON.stringify({ name: 'sunita' }), why: 'added before' },
      { kind: 'add_person', arguments: JSON.stringify({ name: 'Ravi' }), why: 'new' },
    ],
  }
  const scope = { index: 1, count: parts.length, ids: new Set(parts[1]), carry }
  const out = takeProposals(answer, data, scope)
  assert.deepEqual(out.proposals.map((p) => p.kind), ['update_commitment', 'add_person'])
  assert.deepEqual(out.proposals[0]!.payload, { id: inPart, set: { tag: 'Streaming' } })
  assert.equal(out.dropped, 2)
  const next = carryOf(carry, out.proposals)
  assert.deepEqual(next.people, ['Sunita', 'Ravi'])
  assert.deepEqual(next.tags, ['Streaming'])
  // The first part may merge tags.
  const first = takeProposals(answer, data, { index: 0, count: parts.length, ids: new Set(parts[0]), carry: emptyCarry() })
  assert.ok(first.proposals.some((p) => p.kind === 'rename_tag'))
})

test('readCarry: holds what the app sends back to its shape', () => {
  const carry = readCarry({ people: ['A', 'a', 7, 'x'.repeat(200)], tags_renamed: [{ kind: 'commitment', from: 'X' }], names: 'no' })
  assert.deepEqual(carry.people, ['A', 'x'.repeat(80)])
  assert.deepEqual(carry.tags_renamed, [])
  assert.deepEqual(carry.names, [])
  assert.deepEqual(readCarry(null), emptyCarry())
})
