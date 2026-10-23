// The reorganisation's pure part: the digest names every row by id, and the sieve keeps
// only proposals the book can take — nothing that moves money, nothing already so.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { digest, reorganiseInstructions, takeProposals } from '../src/reorganise.js'
import { fixture, inMonths } from './fixtures.js'

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
