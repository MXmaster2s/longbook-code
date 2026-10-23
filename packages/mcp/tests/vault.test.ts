import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, utimesSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { VaultReadError, VaultReader, parseVault, resolveVaultDir } from '../src/vault.js'

const MINIMAL = {
  app: 'longbook',
  version: 3,
  commitments: [
    { id: 's1', name: 'Netflix', amount: 649, currency: 'INR', billing_cycle: 'monthly', status: 'active' },
  ],
  charges: [
    { commitment_id: 's1', date: '2026-09-01', amount: 649, paid: false, basis: 'plan' },
    { commitment_id: 's1', date: 'soon', amount: 649, paid: false },
    { commitment_id: 's1', date: '2026-10-01', amount: 'lots', paid: false },
  ],
  members: [{ id: 'm1', name: 'Rohit', name_key: 'rohit' }],
  accounts: [{ id: 'p1', name: 'HDFC', name_key: 'hdfc' }],
}

test('parseVault fills the fields the schema leaves optional', () => {
  const data = parseVault(JSON.stringify(MINIMAL))
  const sub = data.subs[0]!
  assert.equal(sub.name, 'Netflix')
  assert.equal(sub.custom_cycle_days, null)
  assert.equal(sub.notes, null)
  assert.equal(data.members[0]!.is_incomplete, false)
  // A malformed row drops alone; the charges around it survive.
  assert.equal(data.charges!.length, 1)
  assert.equal(data.charges![0]!.date, '2026-09-01')
})

test('parseVault carries fields it does not know straight through', () => {
  const vault = { ...MINIMAL, commitments: [{ ...MINIMAL.commitments[0], future_field: 'kept' }] }
  const data = parseVault(JSON.stringify(vault))
  assert.equal((data.subs[0] as unknown as Record<string, unknown>).future_field, 'kept')
})

test('a template a vault holds reads as none on every kind of tag, whatever shape it has', () => {
  const data = parseVault(JSON.stringify({
    ...MINIMAL,
    tags: [
      { id: 't1', kind: 'commitment', name: 'insurance', name_key: 'insurance', template: [{ key: 'insurer', label: 'Insurer', hint: 'text' }] },
      { id: 't2', kind: 'account', name: 'credit card', name_key: 'credit card', icon: 'creditcard.fill', template: [{ key: 'card_name', label: 'Card name', hint: 'text' }] },
      { id: 't3', kind: 'member', name: 'family', name_key: 'family', template: 'not a list of fields' },
    ],
  }))
  assert.equal(data.tags!.length, 3)
  for (const tag of data.tags!) assert.equal('template' in tag, false, `${tag.kind}: no template`)
  const card = data.tags!.find((t) => t.kind === 'account')!
  assert.deepEqual([card.name, card.icon], ['credit card', 'creditcard.fill'], 'the rest of the entry reads as before')

  // The shared fixture an older writer left, templates and all; the Swift suite reads it too.
  const older = parseVault(readFileSync(join(import.meta.dirname, '../../core/tests/fixtures/mcp-written-vault.json'), 'utf8'))
  assert.ok(older.tags!.some((t) => t.name_key === 'insurance'))
  for (const t of older.tags!) assert.equal('template' in t, false, `${t.name} reads with no template`)
})

test('parseVault refuses files that are not a financial memory, and any other format', () => {
  assert.throws(() => parseVault('{"app":"other"}'), VaultReadError)
  assert.throws(() => parseVault('not json'), VaultReadError)
  assert.throws(() => parseVault(JSON.stringify({ ...MINIMAL, version: 2 })), /format 2/)
})

test('parseVault refuses values core would silently turn into wrong charges', () => {
  const withSub = (over: Record<string, unknown>) =>
    JSON.stringify({ ...MINIMAL, commitments: [{ ...MINIMAL.commitments[0], ...over }] })
  assert.throws(() => parseVault(withSub({ billing_cycle: 'weekly' })), /billing_cycle/)
  assert.throws(() => parseVault(withSub({ status: 'archived' })), /status/)
  assert.throws(() => parseVault(withSub({ amount: 'lots' })), /amount/)
  assert.throws(() => parseVault(withSub({ ends_on: '17-08-2026' })), /ends_on/)
  // The refusal names the row so the owner knows where to look.
  assert.throws(() => parseVault(withSub({ amount: null })), /Netflix/)
})

test('VaultReader re-reads only when the file actually changed', () => {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-mcp-'))
  const file = join(dir, 'financial_memory.json')
  writeFileSync(file, JSON.stringify(MINIMAL))
  const reader = new VaultReader(dir)
  const first = reader.load()
  assert.equal(reader.load(), first)

  const edited = { ...MINIMAL, commitments: [{ ...MINIMAL.commitments[0], name: 'Netflix Premium' }] }
  writeFileSync(file, JSON.stringify(edited))
  utimesSync(file, new Date(), new Date(Date.now() + 5000))
  assert.equal(reader.load().subs[0]!.name, 'Netflix Premium')
})

test('VaultReader names the missing file and the fix in its error', () => {
  const reader = new VaultReader(join(tmpdir(), 'longbook-nowhere'))
  assert.throws(() => reader.load(), /LONGBOOK_VAULT_PATH/)
})

test('resolveVaultDir prefers the flag, then the environment', () => {
  assert.equal(resolveVaultDir(['node', 'server.ts', '--vault', '/a'], { LONGBOOK_VAULT_PATH: '/b' }), '/a')
  assert.equal(resolveVaultDir(['node', 'server.ts', '--vault=/a'], { LONGBOOK_VAULT_PATH: '/b' }), '/a')
  assert.equal(resolveVaultDir(['node', 'server.ts'], { LONGBOOK_VAULT_PATH: '/b' }), '/b')
  assert.match(resolveVaultDir(['node', 'server.ts'], {}), /iCloud~app~longbook/)
})

test('a bare --vault refuses instead of quietly answering from the default folder', () => {
  assert.throws(() => resolveVaultDir(['node', 'server.ts', '--vault'], {}), VaultReadError)
  assert.throws(() => resolveVaultDir(['node', 'server.ts', '--vault', '--verbose'], {}), VaultReadError)
})
