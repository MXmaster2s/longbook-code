// How many statements an account may have read on the server in a rolling month, and
// whether this one is within it. Pure, so the rule is testable away from the function.

export const MONTH_MS = 30 * 24 * 60 * 60 * 1000

export interface ShareRule {
  /** Files a month for an account without longbook Cloud. */
  free: number
  /** Files a month with Cloud. */
  cloud: number
}

export interface ShareAnswer {
  allowed: number
  used: number
  /** When the oldest counted file falls out of the month, ISO date; absent while within the share. */
  resetsOn?: string
}

/** The account's share: its own grant when one exists, else by Cloud. */
export function shareFor(rule: ShareRule, cloud: boolean, grant: number | null | undefined): number {
  if (typeof grant === 'number' && Number.isFinite(grant)) return Math.max(0, Math.floor(grant))
  return cloud ? rule.cloud : rule.free
}

/** Whether another file may start now, given the start times of the files read in the month. */
export function withinShare(allowed: number, startedAt: string[], now: number = Date.now()): ShareAnswer {
  const since = now - MONTH_MS
  const counted = startedAt.map((t) => new Date(t).getTime()).filter((t) => Number.isFinite(t) && t >= since).sort((a, b) => a - b)
  if (counted.length < allowed) return { allowed, used: counted.length }
  // The share opens again when the file that fills it is a month old. A share of none
  // has no such file, so the wait is a whole month.
  const gate = counted[Math.max(0, counted.length - Math.max(1, allowed))] ?? now
  return { allowed, used: counted.length, resetsOn: new Date(gate + MONTH_MS).toISOString().slice(0, 10) }
}
