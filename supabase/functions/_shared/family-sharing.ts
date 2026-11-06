// Which longbook account an App Store transaction lands on: the buyer's own purchase or a
// family member's copy through Family Sharing, of the licence or of longbook Cloud. Pure, so
// a test runs every case; apple-purchase reads the rows and writes what this decides.

// The rules: a copy goes to the first account that records it. An automatic record (the app
// at launch, or the App Store's updates) never takes a purchase from another account; only
// Restore Purchase or a purchase moves it. A revocation touches only the row holding it.
import { accountToken, statusFromDates, type SubscriptionTransaction } from './cloud-subscription.ts'

export const FAMILY_SHARED = 'FAMILY_SHARED'
export const PURCHASED = 'PURCHASED'

/** What a decision reads of a signed transaction, licence or subscription. */
export interface SharedTransaction extends SubscriptionTransaction {
  /** PURCHASED for the buyer; FAMILY_SHARED for a family member's copy. */
  inAppOwnershipType?: string
}

export const isFamilyShared = (tx: SharedTransaction): boolean => tx.inAppOwnershipType === FAMILY_SHARED

/** The words an automatic record is refused with, for the app's log, never a screen. */
export const TOKEN_ELSEWHERE = 'this subscription was bought by another longbook account'
export const HELD_ELSEWHERE = 'this purchase is recorded on another longbook account; Restore Purchase moves it here'

// MARK: licence

/** An entitlements row, as the decision reads it. A row without a kind reads as real. */
export interface LicenceHeld {
  user_id: string
  status: string
  kind?: string | null
  apple_original_transaction_id: string | null
  apple_family_transaction_id: string | null
}

/** real: a purchase that was paid for, or a grant. test: one from a sandbox, which cost nothing. */
export type LicenceKind = 'real' | 'test'

/** Only Apple's production environment sells; TestFlight, App Review and Xcode buy in the sandbox. */
export const appleLicenceKind = (environment: string | undefined): LicenceKind =>
  environment === 'Production' ? 'real' : 'test'

export const kindOf = (row: Pick<LicenceHeld, 'kind'> | null | undefined): LicenceKind =>
  row?.kind === 'test' ? 'test' : 'real'

const activeReal = (row: LicenceHeld | null): boolean => row?.status === 'active' && kindOf(row) === 'real'

export type LicenceStep =
  | { kind: 'write'; status: 'active' | 'revoked'; licence: LicenceKind; family: boolean; moveFrom: string | null; first: boolean }
  | { kind: 'keep'; status: string | null }
  | { kind: 'refuse'; error: string }

/** Whether a row holds this very transaction, in the column its ownership uses. */
export function holdsLicence(row: LicenceHeld | null, tx: SharedTransaction): boolean {
  if (!row || !tx.originalTransactionId) return false
  return isFamilyShared(tx)
    ? row.apple_family_transaction_id === tx.originalTransactionId
    : row.apple_original_transaction_id === tx.originalTransactionId
}

/**
 * What a verified licence transaction does to the signed-in account. `mine` is its row;
 * `holder` the row of another account holding the same transaction. `first` is true when no
 * account held it before, so a sale is counted once. `licence` is the kind the row is written with.
 */
export function licenceStep(input: { tx: SharedTransaction; mine: LicenceHeld | null; holder: LicenceHeld | null; auto: boolean }): LicenceStep {
  const { tx, mine, holder, auto } = input
  const family = isFamilyShared(tx)
  const licence = appleLicenceKind(tx.environment)
  if (tx.revocationDate) {
    // A refund, or a family organiser who stopped sharing: only the licence it names ends.
    return holdsLicence(mine, tx)
      ? { kind: 'write', status: 'revoked', licence: kindOf(mine), family, moveFrom: null, first: false }
      : { kind: 'keep', status: mine?.status ?? null }
  }
  // A test purchase never replaces or downgrades a real licence, the same transaction's included.
  if (licence === 'test' && activeReal(mine)) return { kind: 'keep', status: 'active' }
  // A family copy never takes the place of a licence the account already holds, unless it is
  // real and the one held is a test.
  const upgrades = licence === 'real' && kindOf(mine) === 'test'
  if (family && mine?.status === 'active' && !holdsLicence(mine, tx) && !upgrades) return { kind: 'keep', status: 'active' }
  if (holder && auto) return { kind: 'refuse', error: HELD_ELSEWHERE }
  // Nor does Restore move a real licence off another account for a test purchase.
  if (licence === 'test' && activeReal(holder)) return { kind: 'keep', status: mine?.status ?? null }
  return { kind: 'write', status: 'active', licence, family, moveFrom: holder?.user_id ?? null, first: !holder && !holdsLicence(mine, tx) }
}

// MARK: longbook Cloud

/** A cloud_subscriptions row, as the decision reads it. Ownership is null on rows from before it was kept. */
export interface CloudHeld {
  user_id: string
  status: string
  expires_at: string | null
  apple_original_transaction_id: string
  apple_ownership?: string | null
  last_signed_at: string | null
}

export type CloudStep =
  | { kind: 'write'; moveFrom: string | null }
  | { kind: 'keep' }
  | { kind: 'refuse'; error: string }

/** Active or in grace with time left: the standing has_cloud serves. */
export function inGoodStanding(row: Pick<CloudHeld, 'status' | 'expires_at'>, now: Date): boolean {
  if (row.status !== 'active' && row.status !== 'grace') return false
  return !row.expires_at || Date.parse(row.expires_at) > now.getTime()
}

/**
 * What a Cloud transaction does to the account's row (`mine`); `holder` is another account's
 * row holding it. A purchase never moves, a family copy only by Restore. Another subscription
 * replaces the row only when it runs or the row does not; a family copy never replaces its own.
 */
export function cloudStep(input: { tx: SharedTransaction; userId: string; mine: CloudHeld | null; holder: CloudHeld | null; auto: boolean; now: Date }): CloudStep {
  const { tx, userId, mine, holder, auto, now } = input
  const family = isFamilyShared(tx)
  const holdsThis = !!mine && mine.apple_original_transaction_id === tx.originalTransactionId
  if (tx.revocationDate && !holdsThis) return { kind: 'keep' }
  // A purchase carrying a token belongs to the account it names; one without (older, or bought
  // outside the app) keeps the first-recorder rule below.
  const token = family ? null : accountToken(tx.appAccountToken)
  if (token && token !== userId.toLowerCase()) return { kind: 'refuse', error: TOKEN_ELSEWHERE }
  if (holder) {
    if (!family) return { kind: 'refuse', error: 'this subscription belongs to another account' }
    if (auto) return { kind: 'refuse', error: HELD_ELSEWHERE }
  }
  if (mine && !holdsThis && inGoodStanding(mine, now)) {
    const mineIsOwn = (mine.apple_ownership ?? PURCHASED) === PURCHASED
    if (family && mineIsOwn) return { kind: 'keep' }
    if (statusFromDates(tx, now) !== 'active') return { kind: 'keep' }
  }
  return { kind: 'write', moveFrom: holder?.user_id ?? null }
}

/**
 * The account a server notice may make a Cloud row for when the app has not: the token a
 * purchase in the app carries. A family copy's token, if any, is the buyer's, so its row
 * waits for the family member's app.
 */
export function noticeAccount(tx: SharedTransaction, token: string | null): string | null {
  return isFamilyShared(tx) ? null : token
}
