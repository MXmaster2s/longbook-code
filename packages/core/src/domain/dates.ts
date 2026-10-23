// Pure date math — ported verbatim in behaviour from the original app.js.
// All dates are handled as local calendar days (no timezone drift) via y/m/d construction.

/** Parse an ISO `YYYY-MM-DD` string into a local Date at midnight. */
export function parseDate(s: string): Date {
  const [y, m, d] = String(s).split('-').map(Number)
  return new Date(y ?? 1970, (m ?? 1) - 1, d ?? 1)
}

/** Format a Date back to ISO `YYYY-MM-DD` (local). */
export function toISO(dt: Date): string {
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`
}

/** Today at local midnight. */
export function todayMid(): Date {
  const n = new Date()
  return new Date(n.getFullYear(), n.getMonth(), n.getDate())
}

/** Whole days from a to b (b - a). */
export function daysBetween(a: Date, b: Date): number {
  return Math.round((b.getTime() - a.getTime()) / 86400000)
}

/** Whole calendar months from a to b (b - a). */
export function monthsBetween(a: Date, b: Date): number {
  return (b.getFullYear() - a.getFullYear()) * 12 + (b.getMonth() - a.getMonth())
}

/**
 * Add `months` to an anchor date, clamping the day to the target month's length
 * so e.g. Jan 31 + 1 month = Feb 28/29 rather than overflowing into March.
 */
export function addMonthsClamped(anchor: Date, months: number): Date {
  const y = anchor.getFullYear()
  const m = anchor.getMonth()
  const d = anchor.getDate()
  const total = m + months
  const ny = y + Math.floor(total / 12)
  const nm = ((total % 12) + 12) % 12
  const last = new Date(ny, nm + 1, 0).getDate()
  return new Date(ny, nm, Math.min(d, last))
}

/**
 * Human label for a signed day delta — e.g. "in 5 days", "3d overdue". Differs from
 * `relativeDayLabel` in one branch: past is *overdue* here (a due-date badge), *ago*
 * there (elapsed time). That branch is the whole distinction — don't merge them.
 */
export function dueLabel(days: number): string {
  if (days < 0) return `${Math.abs(days)}d overdue`
  if (days === 0) return 'today'
  if (days === 1) return 'tomorrow'
  return `in ${days} days`
}

/** e.g. "in 5 days", "today", "tomorrow", "3 days ago" — softer phrasing used in lists. */
export function relativeDayLabel(days: number): string {
  if (days < 0) return `${Math.abs(days)} days ago`
  if (days === 0) return 'today'
  if (days === 1) return 'tomorrow'
  return `in ${days} days`
}

/** Locale-aware short date, e.g. "5 Aug 2026". */
export function fmtDate(dt: Date, locale?: string): string {
  return dt.toLocaleDateString(locale, { day: 'numeric', month: 'short', year: 'numeric' })
}
