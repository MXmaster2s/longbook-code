// A commitment's standing: whether it is active, and what its cancelling date means today.
// Every occurrence is a row in charges[]; nothing here computes one.
import type { Commitment, SubStatus } from '../model'
import { parseDate, todayMid, daysBetween } from './dates'

export interface CancelInfo {
  /** A future cancellation is scheduled. */
  scheduled: boolean
  /** The scheduled cancel date, if any. */
  date: Date | null
  /** Days from today until cancellation (negative once past). */
  days: number | null
  /** The scheduled date has passed — the sub should be treated as cancelled. */
  lapsed: boolean
}

/** Interpret a subscription's optional ends_on. */
export function cancelInfo(
  sub: Pick<Commitment, 'ends_on'>,
  today: Date = todayMid(),
): CancelInfo {
  if (!sub.ends_on) return { scheduled: false, date: null, days: null, lapsed: false }
  const date = parseDate(sub.ends_on)
  const days = daysBetween(today, date)
  return { scheduled: true, date, days, lapsed: days < 0 }
}

/**
 * Effective status shown to the user. A stored `active` sub whose scheduled cancel date has
 * passed reads as `cancelled` (checked-on-open, mirroring how renewals roll forward without a write).
 */
export function displayStatus(
  sub: Pick<Commitment, 'status' | 'ends_on'>,
  today: Date = todayMid(),
): SubStatus {
  const stored = sub.status as SubStatus
  if (stored === 'active' && cancelInfo(sub, today).lapsed) return 'cancelled'
  return stored
}

/** Is this sub actively billing right now (not paused/cancelled/lapsed)? */
export function isEffectivelyActive(
  sub: Pick<Commitment, 'status' | 'ends_on'>,
  today: Date = todayMid(),
): boolean {
  return displayStatus(sub, today) === 'active'
}
