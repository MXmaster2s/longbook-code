// longbook Cloud as the App Store describes it: what a signed subscription transaction, or
// a server notification about one, means for the account's cloud_subscriptions row. Pure,
// so a test runs every case; apple-purchase and apple-notifications verify and write.

export const CLOUD_PRODUCT_ID = 'app.longbook.cloud.monthly'
export const SUBSCRIPTION_TYPE = 'Auto-Renewable Subscription'

export type CloudStatus = 'active' | 'grace' | 'billing_retry' | 'expired' | 'revoked'

/** What this module reads of a signed transaction; Apple's names, milliseconds since 1970. */
export interface SubscriptionTransaction {
  productId?: string
  type?: string
  environment?: string
  originalTransactionId?: string
  appAccountToken?: string
  expiresDate?: number
  revocationDate?: number
  signedDate?: number
}

/** What this module reads of signed renewal info. */
export interface RenewalInfo {
  autoRenewStatus?: number
  gracePeriodExpiresDate?: number
  isInBillingRetryPeriod?: boolean
}

/** The columns a transaction fills; user_id, auto_renew and updated_at are the caller's. */
export interface CloudRow {
  product_id: string
  apple_original_transaction_id: string
  apple_environment: string
  app_account_token: string | null
  status: CloudStatus
  expires_at: string | null
  last_signed_at: string | null
}

/** What a notification changes on the row; absent fields stay as they are. */
export interface CloudChange {
  status?: CloudStatus
  expires_at?: string | null
  auto_renew?: boolean
}

/** The notifications that move a subscription; every other type is acknowledged and ignored. */
export const CLOUD_NOTICES = new Set([
  'SUBSCRIBED',
  'DID_RENEW',
  'DID_CHANGE_RENEWAL_STATUS',
  'DID_FAIL_TO_RENEW',
  'GRACE_PERIOD_EXPIRED',
  'EXPIRED',
  'REFUND',
  'REVOKE',
  'REFUND_REVERSED',
  'RENEWAL_EXTENDED',
])

export const isCloudTransaction = (tx: SubscriptionTransaction): boolean =>
  tx.type === SUBSCRIPTION_TYPE && tx.productId === CLOUD_PRODUCT_ID

const iso = (ms: number | undefined): string | null => (typeof ms === 'number' && Number.isFinite(ms) ? new Date(ms).toISOString() : null)

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** The app account token as the app sets it, a uuid, or null for anything else. */
export const accountToken = (raw: unknown): string | null =>
  typeof raw === 'string' && UUID.test(raw) ? raw.toLowerCase() : null

/** What the dates alone say: a revocation beats everything, then a run-out period, then running. */
export function statusFromDates(tx: SubscriptionTransaction, now: Date): CloudStatus {
  if (tx.revocationDate) return 'revoked'
  if (typeof tx.expiresDate === 'number' && tx.expiresDate <= now.getTime()) return 'expired'
  return 'active'
}

/**
 * The whole standing a transaction and its renewal info describe, so a notice applied
 * alone leaves the row right: revoked on a revocation; grace to the grace period's end
 * while that outlasts the paid period; active while the paid period runs; billing retry
 * while Apple still tries; else expired.
 */
export function snapshot(tx: SubscriptionTransaction, renewal: RenewalInfo | null, now: Date): Pick<CloudChange, 'status' | 'expires_at'> {
  const paidEnd = tx.expiresDate
  const graceEnd = renewal?.gracePeriodExpiresDate
  if (tx.revocationDate) return { status: 'revoked', expires_at: iso(paidEnd) }
  if (typeof graceEnd === 'number' && graceEnd > now.getTime() && graceEnd > (paidEnd ?? -Infinity)) {
    return { status: 'grace', expires_at: iso(graceEnd) }
  }
  if (typeof paidEnd !== 'number' || paidEnd > now.getTime()) return { status: 'active', expires_at: iso(paidEnd) }
  return { status: renewal?.isInBillingRetryPeriod ? 'billing_retry' : 'expired', expires_at: iso(paidEnd) }
}

/** The row a verified subscription transaction writes. The caller has checked the ids. */
export function subscriptionRow(tx: SubscriptionTransaction, now: Date): CloudRow {
  return {
    product_id: tx.productId ?? CLOUD_PRODUCT_ID,
    apple_original_transaction_id: tx.originalTransactionId ?? '',
    apple_environment: tx.environment ?? '',
    app_account_token: accountToken(tx.appAccountToken),
    status: statusFromDates(tx, now),
    expires_at: iso(tx.expiresDate),
    last_signed_at: iso(tx.signedDate),
  }
}

/** True when Apple signed this before what the row already holds, so it must not overwrite it. */
export function isStale(signedDate: number | undefined, lastSignedAt: string | null | undefined): boolean {
  if (typeof signedDate !== 'number' || !lastSignedAt) return false
  const last = Date.parse(lastSignedAt)
  return Number.isFinite(last) && signedDate < last
}

/**
 * The change a notice makes, or null for one that changes nothing. Every change carries
 * status and expires_at, so notices may land in any order: the latest-signed holds the
 * whole standing and an earlier one is dropped. In grace, expires_at is the grace period's end.
 */
export function noticeChange(
  type: string,
  subtype: string | undefined,
  tx: SubscriptionTransaction,
  renewal: RenewalInfo | null,
  now: Date,
): CloudChange | null {
  if (!CLOUD_NOTICES.has(type)) return null
  const autoRenew: CloudChange =
    typeof renewal?.autoRenewStatus === 'number' ? { auto_renew: renewal.autoRenewStatus === 1 } : {}
  switch (type) {
    case 'DID_FAIL_TO_RENEW':
      return subtype === 'GRACE_PERIOD'
        ? { status: 'grace', expires_at: iso(renewal?.gracePeriodExpiresDate) ?? iso(tx.expiresDate), ...autoRenew }
        : { status: 'billing_retry', expires_at: iso(tx.expiresDate), ...autoRenew }
    case 'GRACE_PERIOD_EXPIRED':
      return { status: renewal?.isInBillingRetryPeriod ? 'billing_retry' : 'expired', expires_at: iso(tx.expiresDate), ...autoRenew }
    case 'EXPIRED':
      return { status: 'expired', expires_at: iso(tx.expiresDate), ...autoRenew }
    case 'REFUND':
    case 'REVOKE':
      return { status: 'revoked', expires_at: iso(tx.expiresDate), ...autoRenew }
    default:
      // SUBSCRIBED, DID_RENEW, RENEWAL_EXTENDED, REFUND_REVERSED and DID_CHANGE_RENEWAL_STATUS,
      // whose transaction carries the latest period too: the dates say it all.
      return { ...snapshot(tx, renewal, now), ...autoRenew }
  }
}
