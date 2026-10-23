// longbook Cloud on the server: what a subscription transaction and each App Store
// notification do to the row, and that the migration, the guard and the functions carry
// the one rule. Run: npm run cloud:test.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import {
  CLOUD_NOTICES,
  CLOUD_PRODUCT_ID,
  accountToken,
  isCloudTransaction,
  isStale,
  noticeChange,
  snapshot,
  statusFromDates,
  subscriptionRow,
  type SubscriptionTransaction,
} from '../supabase/functions/_shared/cloud-subscription.ts'
import { hasCloud } from '../supabase/functions/_shared/has-cloud.ts'
import { licenceCloudUntil, nextGrant } from '../supabase/functions/_shared/licence-cloud.ts'

const read = (rel: string): string => readFileSync(new URL(`../${rel}`, import.meta.url), 'utf8')
const NOW = new Date('2026-10-06T12:00:00Z')
const USER = '4f3c2b1a-0000-4000-8000-00000000abcd'
const tx: SubscriptionTransaction = {
  productId: CLOUD_PRODUCT_ID,
  type: 'Auto-Renewable Subscription',
  environment: 'Production',
  originalTransactionId: '2000000987654321',
  appAccountToken: USER.toUpperCase(),
  expiresDate: Date.parse('2026-11-06T12:00:00Z'),
  signedDate: Date.parse('2026-10-06T11:59:00Z'),
}

test('only this app\'s subscription product, as a subscription, is Cloud', () => {
  assert.ok(isCloudTransaction(tx))
  assert.ok(!isCloudTransaction({ ...tx, type: 'Non-Consumable' }))
  assert.ok(!isCloudTransaction({ ...tx, productId: 'app.longbook.licence' }))
  assert.ok(!isCloudTransaction({}))
})

test('the dates say active, expired or revoked, in that order of precedence', () => {
  assert.equal(statusFromDates(tx, NOW), 'active')
  assert.equal(statusFromDates({ ...tx, expiresDate: NOW.getTime() }, NOW), 'expired')
  assert.equal(statusFromDates({ ...tx, expiresDate: NOW.getTime() - 1, revocationDate: NOW.getTime() - 5 }, NOW), 'revoked')
  assert.equal(statusFromDates({ ...tx, expiresDate: undefined }, NOW), 'active', 'a period without an end is running')
})

test('a transaction becomes the row, with the token as a lowercase uuid and ISO dates', () => {
  assert.deepEqual(subscriptionRow(tx, NOW), {
    product_id: CLOUD_PRODUCT_ID,
    apple_original_transaction_id: '2000000987654321',
    apple_environment: 'Production',
    app_account_token: USER,
    status: 'active',
    expires_at: '2026-11-06T12:00:00.000Z',
    last_signed_at: '2026-10-06T11:59:00.000Z',
  })
  assert.equal(subscriptionRow({ ...tx, appAccountToken: 'not-a-uuid' }, NOW).app_account_token, null)
  assert.equal(subscriptionRow({ ...tx, signedDate: undefined }, NOW).last_signed_at, null)
})

test('the app account token is kept only as a uuid', () => {
  assert.equal(accountToken(USER.toUpperCase()), USER)
  assert.equal(accountToken('4f3c2b1a'), null)
  assert.equal(accountToken(42), null)
  assert.equal(accountToken(undefined), null)
})

test('a signature older than what the row holds is stale; a missing side is not', () => {
  assert.ok(isStale(Date.parse('2026-10-01T00:00:00Z'), '2026-10-05T00:00:00Z'))
  assert.ok(!isStale(Date.parse('2026-10-05T00:00:00Z'), '2026-10-05T00:00:00Z'), 'the same instant is not older')
  assert.ok(!isStale(Date.parse('2026-10-06T00:00:00Z'), '2026-10-05T00:00:00Z'))
  assert.ok(!isStale(undefined, '2026-10-05T00:00:00Z'))
  assert.ok(!isStale(Date.parse('2026-10-01T00:00:00Z'), null))
  assert.ok(!isStale(Date.parse('2026-10-01T00:00:00Z'), 'not a date'))
})

test('the notifications handled are exactly the ten the subscription needs', () => {
  assert.deepEqual([...CLOUD_NOTICES].sort(), [
    'DID_CHANGE_RENEWAL_STATUS', 'DID_FAIL_TO_RENEW', 'DID_RENEW', 'EXPIRED', 'GRACE_PERIOD_EXPIRED',
    'REFUND', 'REFUND_REVERSED', 'RENEWAL_EXTENDED', 'REVOKE', 'SUBSCRIBED',
  ])
  assert.equal(noticeChange('OFFER_REDEEMED', undefined, tx, null, NOW), null)
  assert.equal(noticeChange('', undefined, tx, null, NOW), null)
})

test('a purchase, a renewal, an extension and a reversed refund follow the dates', () => {
  const renewal = { autoRenewStatus: 1 }
  for (const type of ['SUBSCRIBED', 'DID_RENEW', 'RENEWAL_EXTENDED', 'REFUND_REVERSED']) {
    assert.deepEqual(noticeChange(type, undefined, tx, renewal, NOW), {
      status: 'active', expires_at: '2026-11-06T12:00:00.000Z', auto_renew: true,
    }, type)
  }
  const lapsed = { ...tx, expiresDate: NOW.getTime() - 1 }
  assert.equal(noticeChange('REFUND_REVERSED', undefined, lapsed, null, NOW)?.status, 'expired')
  assert.ok(!('auto_renew' in noticeChange('DID_RENEW', 'BILLING_RECOVERY', tx, null, NOW)!), 'no renewal info, no auto_renew')
})

test('a renewal-status change carries the whole standing, so it may overtake a delayed renewal', () => {
  assert.deepEqual(noticeChange('DID_CHANGE_RENEWAL_STATUS', 'AUTO_RENEW_DISABLED', tx, { autoRenewStatus: 0 }, NOW), {
    status: 'active', expires_at: '2026-11-06T12:00:00.000Z', auto_renew: false,
  })
  assert.deepEqual(noticeChange('DID_CHANGE_RENEWAL_STATUS', 'AUTO_RENEW_ENABLED', tx, { autoRenewStatus: 1 }, NOW), {
    status: 'active', expires_at: '2026-11-06T12:00:00.000Z', auto_renew: true,
  })
  assert.deepEqual(noticeChange('DID_CHANGE_RENEWAL_STATUS', undefined, tx, null, NOW), {
    status: 'active', expires_at: '2026-11-06T12:00:00.000Z',
  }, 'without renewal info the dates still land')
  // The renewal signed first but arrives last: the status change already wrote its period.
  const renewed = { ...tx, expiresDate: Date.parse('2026-12-06T12:00:00Z') }
  const first = noticeChange('DID_CHANGE_RENEWAL_STATUS', 'AUTO_RENEW_DISABLED', renewed, { autoRenewStatus: 0 }, NOW)
  assert.equal(first?.expires_at, '2026-12-06T12:00:00.000Z')
  assert.equal(noticeChange('DID_RENEW', undefined, renewed, { autoRenewStatus: 0 }, NOW)?.expires_at, first?.expires_at)
})

test('the snapshot reads grace, billing retry and expiry from the dates and renewal info', () => {
  const lapsed = { ...tx, expiresDate: Date.parse('2026-10-05T12:00:00Z') }
  const graceEnd = Date.parse('2026-10-21T12:00:00Z')
  assert.deepEqual(snapshot(lapsed, { gracePeriodExpiresDate: graceEnd, isInBillingRetryPeriod: true }, NOW),
    { status: 'grace', expires_at: '2026-10-21T12:00:00.000Z' })
  assert.deepEqual(snapshot(lapsed, { isInBillingRetryPeriod: true }, NOW),
    { status: 'billing_retry', expires_at: '2026-10-05T12:00:00.000Z' })
  assert.deepEqual(snapshot(lapsed, { isInBillingRetryPeriod: false }, NOW),
    { status: 'expired', expires_at: '2026-10-05T12:00:00.000Z' })
  assert.deepEqual(snapshot(lapsed, null, NOW), { status: 'expired', expires_at: '2026-10-05T12:00:00.000Z' })
  assert.equal(snapshot(lapsed, { gracePeriodExpiresDate: Date.parse('2026-10-06T11:00:00Z') }, NOW).status, 'expired',
    'a grace period already over does not serve')
  assert.deepEqual(snapshot(tx, { gracePeriodExpiresDate: graceEnd }, NOW), { status: 'active', expires_at: '2026-11-06T12:00:00.000Z' },
    'a paid period outlasting the grace end is active to its own end')
  assert.equal(snapshot({ ...tx, revocationDate: NOW.getTime() - 1 }, { gracePeriodExpiresDate: graceEnd }, NOW).status, 'revoked')
  assert.equal(snapshot({ ...tx, expiresDate: undefined }, null, NOW).status, 'active', 'a period without an end is running')
  // Auto-renew turned off during grace keeps grace, as the renewal info still says.
  assert.deepEqual(noticeChange('DID_CHANGE_RENEWAL_STATUS', 'AUTO_RENEW_DISABLED', lapsed,
    { autoRenewStatus: 0, gracePeriodExpiresDate: graceEnd, isInBillingRetryPeriod: true }, NOW),
    { status: 'grace', expires_at: '2026-10-21T12:00:00.000Z', auto_renew: false })
})

test('a failed renewal is grace with the grace period\'s end, or billing retry', () => {
  const grace = { autoRenewStatus: 1, gracePeriodExpiresDate: Date.parse('2026-11-22T12:00:00Z') }
  assert.deepEqual(noticeChange('DID_FAIL_TO_RENEW', 'GRACE_PERIOD', tx, grace, NOW), {
    status: 'grace', expires_at: '2026-11-22T12:00:00.000Z', auto_renew: true,
  })
  assert.equal(noticeChange('DID_FAIL_TO_RENEW', 'GRACE_PERIOD', tx, { autoRenewStatus: 1 }, NOW)?.expires_at,
    '2026-11-06T12:00:00.000Z', 'without a grace end, the period\'s own end')
  assert.deepEqual(noticeChange('DID_FAIL_TO_RENEW', undefined, tx, { autoRenewStatus: 1, isInBillingRetryPeriod: true }, NOW), {
    status: 'billing_retry', expires_at: '2026-11-06T12:00:00.000Z', auto_renew: true,
  })
})

test('a grace period that ends is billing retry while Apple still retries, else expired', () => {
  assert.equal(noticeChange('GRACE_PERIOD_EXPIRED', undefined, tx, { isInBillingRetryPeriod: true }, NOW)?.status, 'billing_retry')
  assert.equal(noticeChange('GRACE_PERIOD_EXPIRED', undefined, tx, { isInBillingRetryPeriod: false }, NOW)?.status, 'expired')
  assert.equal(noticeChange('GRACE_PERIOD_EXPIRED', undefined, tx, null, NOW)?.status, 'expired')
})

test('an expiry, a refund and a revocation end access whatever the dates say', () => {
  assert.equal(noticeChange('EXPIRED', 'VOLUNTARY', tx, { autoRenewStatus: 0 }, NOW)?.status, 'expired')
  assert.equal(noticeChange('REFUND', undefined, tx, null, NOW)?.status, 'revoked')
  assert.equal(noticeChange('REVOKE', undefined, tx, null, NOW)?.status, 'revoked')
  assert.equal(noticeChange('EXPIRED', 'VOLUNTARY', tx, { autoRenewStatus: 0 }, NOW)?.auto_renew, false)
})

test('hasCloud answers the database, yes while the rule is not installed, no on any other failure', async () => {
  const client = (reply: { data: unknown; error: { code?: string } | null }) => ({
    calls: [] as unknown[],
    rpc(fn: string, args: Record<string, unknown>) { this.calls.push([fn, args]); return Promise.resolve(reply) },
  })
  const yes = client({ data: true, error: null })
  assert.equal(await hasCloud(yes, USER), true)
  assert.deepEqual(yes.calls, [['has_cloud', { uid: USER }]])
  assert.equal(await hasCloud(client({ data: false, error: null }), USER), false)
  assert.equal(await hasCloud(client({ data: null, error: null }), USER), false)
  assert.equal(await hasCloud(client({ data: null, error: { code: 'PGRST202' } }), USER), true)
  assert.equal(await hasCloud(client({ data: null, error: { code: '42501' } }), USER), false)
})

test('the migration, the guard and the functions carry the one rule', () => {
  const sql = read('supabase/migrations/20261006130000_cloud_subscriptions.sql')
  for (const piece of [
    'create table if not exists public.cloud_subscriptions',
    'create table if not exists public.cloud_grants',
    "status text not null check (status in ('active', 'grace', 'billing_retry', 'expired', 'revoked'))",
    'grant select (user_id, status, expires_at, auto_renew) on table public.cloud_subscriptions to authenticated',
    'revoke all on table public.cloud_grants from public, anon, authenticated',
    'create or replace function public.has_cloud(uid uuid)',
    "interval '14 days'",
    'with check (auth.uid() = user_id and public.has_cloud(user_id))',
    "return query select null::uuid, false, 0, 'entitlement_required'",
    "cloud_until(hm.user_id) < now() - interval '30 days'",
  ]) assert.ok(sql.includes(piece), `migration lacks: ${piece}`)
  assert.equal(sql.match(/with check \(auth\.uid\(\) = user_id and public\.has_cloud\(user_id\)\)/g)?.length, 2, 'the push and the refresh')
  const trial = read('supabase/migrations/20261007100000_trial_three_days.sql')
  assert.ok(trial.includes("interval '3 days'") && !trial.includes("interval '14 days'"), 'the trial is three days')

  const guard = read('scripts/guard-rls.mts')
  assert.ok(guard.includes("'has_cloud',"))
  assert.ok(guard.includes("{ t: 'cloud_subscriptions', p: 'SELECT', c: ['auto_renew', 'expires_at', 'status', 'user_id'] }"))
  assert.ok(guard.includes("table_name='cloud_grants'"))

  const purchase = read('supabase/functions/apple-purchase/index.ts')
  assert.ok(purchase.includes('if (isCloudTransaction(tx)) return recordCloud(tx, user.id)'))
  assert.ok(purchase.includes("refuse('this subscription belongs to another account', 409)"))
  const cloudBranch = purchase.slice(purchase.indexOf('async function recordCloud'), purchase.indexOf('Deno.serve'))
  assert.ok(!cloudBranch.includes('confirmPurchase'), 'no purchase email for Cloud')

  const notices = read('supabase/functions/apple-notifications/index.ts')
  assert.ok(notices.includes('if (isCloudTransaction(tx)) return recordCloudNotice(notice, tx)'))
  assert.ok(notices.includes('ENVIRONMENTS.includes(environment)'))
  assert.ok(notices.includes('isStale(notice.signedDate, row.last_signed_at)'))

  assert.ok(read('supabase/functions/mcp/index.ts').includes("failureBody('entitlement_required'"))
  for (const fn of ['statement-extract', 'share-report']) {
    assert.ok(read(`supabase/functions/${fn}/index.ts`).includes('await hasCloud(service, user.id)'), fn)
  }
})

test('a licence brings twelve months of Cloud, never shortening a longer grant', () => {
  const bought = new Date('2026-10-20T09:30:00Z')
  assert.equal(licenceCloudUntil(bought).toISOString(), '2027-10-20T09:30:00.000Z')
  assert.deepEqual(nextGrant(null, bought), { until: '2027-10-20T09:30:00.000Z', note: 'licence' })
  assert.equal(nextGrant({ until: '2099-01-01T00:00:00Z', note: 'owner' }, bought), null)
  assert.deepEqual(nextGrant({ until: '2026-11-01T00:00:00Z', note: 'support' }, bought), { until: '2027-10-20T09:30:00.000Z', note: 'licence' })
})

test('the purchase and notice functions grant and take back the licence Cloud', () => {
  assert.match(read('supabase/functions/apple-purchase/index.ts'), /grantLicenceCloud\(service, user\.id, purchasedAt\)/)
  assert.match(read('supabase/functions/apple-notifications/index.ts'), /revokeLicenceCloud\(service, row\.user_id\)/)
})
