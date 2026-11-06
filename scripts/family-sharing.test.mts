// Family Sharing on the server: which account a licence or a Cloud transaction lands on, when
// a record is refused or moves, and what a revocation touches. Run: npm run cloud:test.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { CLOUD_PRODUCT_ID, subscriptionRow } from '../supabase/functions/_shared/cloud-subscription.ts'
import {
  FAMILY_SHARED,
  HELD_ELSEWHERE,
  TOKEN_ELSEWHERE,
  appleLicenceKind,
  cloudStep,
  holdsLicence,
  inGoodStanding,
  licenceStep,
  noticeAccount,
  type CloudHeld,
  type LicenceHeld,
  type SharedTransaction,
} from '../supabase/functions/_shared/family-sharing.ts'

const read = (rel: string): string => readFileSync(new URL(`../${rel}`, import.meta.url), 'utf8')
const NOW = new Date('2026-11-03T12:00:00Z')
const ME = '11111111-1111-4111-8111-111111111111'
const OTHER = '22222222-2222-4222-8222-222222222222'

const bought: SharedTransaction = { originalTransactionId: '2000000000000001', inAppOwnershipType: 'PURCHASED', environment: 'Production' }
const shared: SharedTransaction = { originalTransactionId: '2000000000000077', inAppOwnershipType: FAMILY_SHARED, environment: 'Production' }
const licence = (over: Partial<LicenceHeld> = {}): LicenceHeld => ({
  user_id: ME, status: 'active', apple_original_transaction_id: null, apple_family_transaction_id: null, ...over,
})

test('a family member\'s first copy of the licence is theirs, with no Restore and no sale counted', () => {
  const step = licenceStep({ tx: shared, mine: null, holder: null, auto: true })
  assert.deepEqual(step, { kind: 'write', status: 'active', licence: 'real', family: true, moveFrom: null, first: true })
})

test('a family copy is found by its own column, a purchase by the purchase\'s', () => {
  assert.ok(holdsLicence(licence({ apple_family_transaction_id: shared.originalTransactionId! }), shared))
  assert.ok(!holdsLicence(licence({ apple_original_transaction_id: shared.originalTransactionId! }), shared))
  assert.ok(holdsLicence(licence({ apple_original_transaction_id: bought.originalTransactionId! }), bought))
  assert.ok(!holdsLicence(null, bought))
})

test('a family copy never replaces a licence the account already holds', () => {
  const mine = licence({ apple_original_transaction_id: '2000000000000555' })
  assert.deepEqual(licenceStep({ tx: shared, mine, holder: null, auto: false }), { kind: 'keep', status: 'active' })
})

test('an automatic record never takes a licence from another account; Restore moves it', () => {
  const holder = licence({ user_id: OTHER, apple_family_transaction_id: shared.originalTransactionId! })
  assert.deepEqual(licenceStep({ tx: shared, mine: null, holder, auto: true }), { kind: 'refuse', error: HELD_ELSEWHERE })
  assert.deepEqual(licenceStep({ tx: shared, mine: null, holder, auto: false }),
    { kind: 'write', status: 'active', licence: 'real', family: true, moveFrom: OTHER, first: false })
  const buyer = licence({ user_id: OTHER, apple_original_transaction_id: bought.originalTransactionId! })
  assert.equal(licenceStep({ tx: bought, mine: null, holder: buyer, auto: true }).kind, 'refuse')
  const moved = licenceStep({ tx: bought, mine: null, holder: buyer, auto: false })
  assert.ok(moved.kind === 'write' && moved.moveFrom === OTHER && !moved.first, 'a moved purchase is not a new sale')
})

test('a re-recorded purchase is not a new sale', () => {
  const mine = licence({ apple_original_transaction_id: bought.originalTransactionId! })
  const step = licenceStep({ tx: bought, mine, holder: null, auto: true })
  assert.ok(step.kind === 'write' && !step.first)
})

test('sharing stopped ends the family copy that names it, and nothing else', () => {
  const stopped = { ...shared, revocationDate: Date.parse('2026-11-02T00:00:00Z') }
  const copy = licence({ apple_family_transaction_id: shared.originalTransactionId! })
  assert.deepEqual(licenceStep({ tx: stopped, mine: copy, holder: null, auto: true }),
    { kind: 'write', status: 'revoked', licence: 'real', family: true, moveFrom: null, first: false })
  const own = licence({ apple_original_transaction_id: '2000000000000555' })
  assert.deepEqual(licenceStep({ tx: stopped, mine: own, holder: null, auto: true }), { kind: 'keep', status: 'active' })
  assert.deepEqual(licenceStep({ tx: stopped, mine: null, holder: null, auto: true }), { kind: 'keep', status: null },
    'a revoked transaction never makes a row')
})

test('a refunded purchase ends the buyer\'s licence only where it is recorded', () => {
  const refunded = { ...bought, revocationDate: Date.parse('2026-11-02T00:00:00Z') }
  const mine = licence({ apple_original_transaction_id: bought.originalTransactionId! })
  assert.equal(licenceStep({ tx: refunded, mine, holder: null, auto: true }).kind, 'write')
  const fromAnotherAppleAccount = licence({ apple_original_transaction_id: '2000000000000555' })
  assert.equal(licenceStep({ tx: refunded, mine: fromAnotherAppleAccount, holder: null, auto: true }).kind, 'keep')
})

// MARK: real and test licences

const sandbox: SharedTransaction = { ...bought, originalTransactionId: '2000000000000300', environment: 'Sandbox' }

test('a sandbox purchase writes an active test licence; a production one a real licence', () => {
  assert.equal(appleLicenceKind('Sandbox'), 'test')
  assert.equal(appleLicenceKind('Production'), 'real')
  assert.equal(appleLicenceKind(undefined), 'test', 'an environment that is not production sells nothing')
  assert.deepEqual(licenceStep({ tx: sandbox, mine: null, holder: null, auto: false }),
    { kind: 'write', status: 'active', licence: 'test', family: false, moveFrom: null, first: true })
  assert.deepEqual(licenceStep({ tx: bought, mine: null, holder: null, auto: false }),
    { kind: 'write', status: 'active', licence: 'real', family: false, moveFrom: null, first: true })
  const familySandbox = { ...shared, environment: 'Sandbox' }
  const copy = licenceStep({ tx: familySandbox, mine: null, holder: null, auto: true })
  assert.ok(copy.kind === 'write' && copy.status === 'active' && copy.licence === 'test' && copy.family)
})

test('a test purchase never replaces, downgrades or moves a real licence', () => {
  const real = licence({ kind: 'real', apple_original_transaction_id: '2000000000000555' })
  assert.deepEqual(licenceStep({ tx: sandbox, mine: real, holder: null, auto: false }), { kind: 'keep', status: 'active' })
  const legacy = licence({ apple_original_transaction_id: sandbox.originalTransactionId! })
  assert.deepEqual(licenceStep({ tx: sandbox, mine: legacy, holder: null, auto: true }), { kind: 'keep', status: 'active' },
    'a row from before kinds is real, and its own sandbox transaction never downgrades it')
  const grant = licence({ kind: 'real' })
  assert.deepEqual(licenceStep({ tx: { ...shared, environment: 'Sandbox' }, mine: grant, holder: null, auto: false }), { kind: 'keep', status: 'active' })
  const elsewhere = licence({ user_id: OTHER, apple_original_transaction_id: sandbox.originalTransactionId! })
  assert.deepEqual(licenceStep({ tx: sandbox, mine: null, holder: elsewhere, auto: false }), { kind: 'keep', status: null },
    'Restore leaves another account\'s real licence where it is')
  assert.equal(licenceStep({ tx: sandbox, mine: null, holder: elsewhere, auto: true }).kind, 'refuse')
})

test('a real purchase replaces a test licence, a family copy included', () => {
  const testRow = licence({ kind: 'test', apple_original_transaction_id: sandbox.originalTransactionId! })
  assert.deepEqual(licenceStep({ tx: bought, mine: testRow, holder: null, auto: true }),
    { kind: 'write', status: 'active', licence: 'real', family: false, moveFrom: null, first: true })
  assert.deepEqual(licenceStep({ tx: shared, mine: testRow, holder: null, auto: true }),
    { kind: 'write', status: 'active', licence: 'real', family: true, moveFrom: null, first: true })
})

test('test licences move between accounts as before, and a refund keeps the row\'s kind', () => {
  const testElsewhere = licence({ user_id: OTHER, kind: 'test', apple_original_transaction_id: sandbox.originalTransactionId! })
  assert.deepEqual(licenceStep({ tx: sandbox, mine: null, holder: testElsewhere, auto: false }),
    { kind: 'write', status: 'active', licence: 'test', family: false, moveFrom: OTHER, first: false })
  const anotherTest = licence({ kind: 'test', apple_original_transaction_id: '2000000000000301' })
  assert.equal(licenceStep({ tx: sandbox, mine: anotherTest, holder: null, auto: false }).kind, 'write', 'a test purchase replaces a test licence')
  const refunded = { ...sandbox, revocationDate: Date.parse('2026-11-02T00:00:00Z') }
  const legacy = licence({ apple_original_transaction_id: sandbox.originalTransactionId! })
  assert.deepEqual(licenceStep({ tx: refunded, mine: legacy, holder: null, auto: true }),
    { kind: 'write', status: 'revoked', licence: 'real', family: false, moveFrom: null, first: false })
})

test('apple-purchase writes the kind, keeps status active for a sandbox purchase, and emails only a real one', () => {
  const fn = read('supabase/functions/apple-purchase/index.ts')
  assert.match(fn, /const LICENCE_COLUMNS = 'user_id, status, kind, /)
  assert.match(fn, /\n      status,\n      kind: licence,\n/)
  assert.match(fn, /if \(status === 'active' && licence === 'real'\) \{\n    const confirming = confirmPurchase\(/)
  assert.match(fn, /step\.first && status === 'active' && tx\.environment === 'Production'/, 'the price step counts production only')
  const sql = read('supabase/migrations/20261104120000_licence_kind.sql')
  assert.match(sql, /add column kind text not null default 'real' check \(kind in \('real', 'test'\)\)/)
  assert.match(sql, /grant select \(kind\) on table public\.entitlements to authenticated;/)
  assert.ok(read('scripts/guard-rls.mts').includes("c: ['kind', 'major_version', 'polar_order_id', 'purchased_at', 'status', 'user_id']"))
})

const cloudTx: SharedTransaction = {
  productId: CLOUD_PRODUCT_ID,
  type: 'Auto-Renewable Subscription',
  environment: 'Production',
  originalTransactionId: '2000000000000900',
  inAppOwnershipType: FAMILY_SHARED,
  appAccountToken: OTHER,
  expiresDate: Date.parse('2026-12-03T12:00:00Z'),
  signedDate: Date.parse('2026-11-03T11:00:00Z'),
}
const cloudRow = (over: Partial<CloudHeld> = {}): CloudHeld => ({
  user_id: ME, status: 'active', expires_at: '2026-12-01T00:00:00Z', apple_original_transaction_id: '2000000000000111',
  apple_ownership: 'PURCHASED', last_signed_at: null, ...over,
})

test('a family member\'s Cloud is recorded on their own account, without the buyer\'s token', () => {
  assert.deepEqual(cloudStep({ userId: ME, tx: cloudTx, mine: null, holder: null, auto: true, now: NOW }), { kind: 'write', moveFrom: null })
  const row = subscriptionRow(cloudTx, NOW)
  assert.equal(row.apple_ownership, FAMILY_SHARED)
  assert.equal(row.app_account_token, null, 'the token a family copy carries is the buyer\'s')
})

test('a family copy of Cloud never replaces the account\'s own running subscription', () => {
  assert.deepEqual(cloudStep({ userId: ME, tx: cloudTx, mine: cloudRow(), holder: null, auto: false, now: NOW }), { kind: 'keep' })
  const lapsed = cloudRow({ status: 'expired', expires_at: '2026-10-01T00:00:00Z' })
  assert.equal(cloudStep({ userId: ME, tx: cloudTx, mine: lapsed, holder: null, auto: true, now: NOW }).kind, 'write')
  const ownTx = { ...cloudTx, inAppOwnershipType: 'PURCHASED', appAccountToken: ME }
  const familyRow = cloudRow({ apple_ownership: FAMILY_SHARED })
  assert.equal(cloudStep({ userId: ME, tx: ownTx, mine: familyRow, holder: null, auto: true, now: NOW }).kind, 'write',
    'subscribing yourself replaces a family copy')
  assert.equal(cloudStep({ userId: ME, tx: cloudTx, mine: cloudRow({ apple_ownership: null }), holder: null, auto: true, now: NOW }).kind, 'keep',
    'a row from before ownership was kept reads as the subscriber\'s own')
})

test('a lapsed subscription never replaces a running one', () => {
  const lapsedTx = { ...cloudTx, inAppOwnershipType: 'PURCHASED', appAccountToken: ME, expiresDate: Date.parse('2026-10-01T00:00:00Z') }
  assert.deepEqual(cloudStep({ userId: ME, tx: lapsedTx, mine: cloudRow({ apple_ownership: FAMILY_SHARED }), holder: null, auto: true, now: NOW }), { kind: 'keep' })
})

test('Cloud held by another account: a purchase is refused, a family copy moves on Restore only', () => {
  const holder = cloudRow({ user_id: OTHER, apple_original_transaction_id: cloudTx.originalTransactionId! })
  assert.deepEqual(cloudStep({ userId: ME, tx: cloudTx, mine: null, holder, auto: true, now: NOW }), { kind: 'refuse', error: HELD_ELSEWHERE })
  assert.deepEqual(cloudStep({ userId: ME, tx: cloudTx, mine: null, holder, auto: false, now: NOW }), { kind: 'write', moveFrom: OTHER })
  const own = { ...cloudTx, inAppOwnershipType: 'PURCHASED', appAccountToken: undefined }
  assert.equal(cloudStep({ userId: ME, tx: own, mine: null, holder, auto: false, now: NOW }).kind, 'refuse')
})

test('sharing stopped ends the family Cloud that names it, and never another subscription', () => {
  const stopped = { ...cloudTx, revocationDate: Date.parse('2026-11-02T00:00:00Z') }
  const mine = cloudRow({ apple_original_transaction_id: cloudTx.originalTransactionId!, apple_ownership: FAMILY_SHARED })
  assert.equal(cloudStep({ userId: ME, tx: stopped, mine, holder: null, auto: true, now: NOW }).kind, 'write')
  assert.equal(subscriptionRow(stopped, NOW).status, 'revoked')
  assert.deepEqual(cloudStep({ userId: ME, tx: stopped, mine: cloudRow(), holder: null, auto: true, now: NOW }), { kind: 'keep' })
  assert.deepEqual(cloudStep({ userId: ME, tx: stopped, mine: null, holder: null, auto: true, now: NOW }), { kind: 'keep' })
})

test('a Cloud purchase belongs to the account its token names; without a token, to the first that records it', () => {
  const bought = { ...cloudTx, inAppOwnershipType: 'PURCHASED', appAccountToken: OTHER.toUpperCase() }
  for (const auto of [true, false]) {
    assert.deepEqual(cloudStep({ userId: ME, tx: bought, mine: null, holder: null, auto, now: NOW }), { kind: 'refuse', error: TOKEN_ELSEWHERE })
  }
  assert.deepEqual(cloudStep({ userId: OTHER, tx: bought, mine: null, holder: null, auto: true, now: NOW }), { kind: 'write', moveFrom: null },
    'the token compares without case')
  const untokened = { ...bought, appAccountToken: undefined }
  assert.equal(cloudStep({ userId: ME, tx: untokened, mine: null, holder: null, auto: true, now: NOW }).kind, 'write')
  const heldUntokened = cloudRow({ user_id: OTHER, apple_original_transaction_id: untokened.originalTransactionId! })
  assert.equal(cloudStep({ userId: ME, tx: untokened, mine: null, holder: heldUntokened, auto: false, now: NOW }).kind, 'refuse')
  assert.equal(cloudStep({ userId: ME, tx: { ...bought, appAccountToken: 'not-a-uuid' }, mine: null, holder: null, auto: true, now: NOW }).kind, 'write',
    'a token that is not a uuid is no token')
  assert.equal(cloudStep({ userId: ME, tx: cloudTx, mine: null, holder: null, auto: true, now: NOW }).kind, 'write',
    'a family copy carrying the buyer\'s token is still the member\'s')
})

test('good standing is active or grace with time left', () => {
  assert.ok(inGoodStanding({ status: 'grace', expires_at: '2026-11-04T00:00:00Z' }, NOW))
  assert.ok(!inGoodStanding({ status: 'active', expires_at: '2026-11-01T00:00:00Z' }, NOW))
  assert.ok(!inGoodStanding({ status: 'revoked', expires_at: '2026-12-01T00:00:00Z' }, NOW))
})

test('a server notice makes a Cloud row from the token for a purchase, never for a family copy', () => {
  assert.equal(noticeAccount(cloudTx, OTHER), null)
  assert.equal(noticeAccount({ ...cloudTx, inAppOwnershipType: 'PURCHASED' }, OTHER), OTHER)
})

test('apple-purchase decides with family-sharing.ts and tells an automatic record apart', () => {
  const fn = read('supabase/functions/apple-purchase/index.ts')
  assert.match(fn, /licenceStep\(\{ tx, mine, holder, auto \}\)/)
  assert.match(fn, /cloudStep\(\{ tx, userId, mine, holder, auto, now \}\)/)
  assert.match(fn, /const auto = body\.auto === true/)
  assert.match(read('supabase/functions/apple-notifications/index.ts'), /noticeAccount\(tx, accountToken\(tx\.appAccountToken\)\)/)
  assert.match(read('supabase/migrations/20261103120000_cloud_family_sharing.sql'), /add column if not exists apple_ownership/)
})

test('the local StoreKit file shares both products, as App Store Connect does', () => {
  const kit = JSON.parse(read('apps/longbook/longbook.storekit'))
  const products = [...kit.products, ...kit.subscriptionGroups.flatMap((g: { subscriptions: unknown[] }) => g.subscriptions)]
  assert.equal(products.length, 2)
  for (const p of products as { productID: string; familyShareable: boolean }[]) assert.equal(p.familyShareable, true, p.productID)
})
