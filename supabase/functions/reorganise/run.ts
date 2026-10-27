// One pass is read in parts under one run id. A run starts at its first part, lives a few
// hours at most, and takes a bounded number of calls, so one share buys one pass. Pure, so
// the rule is testable away from the function.

/** How long one run's parts may keep arriving. */
export const RUN_MS = 3 * 60 * 60 * 1000

export interface RunRow {
  outcome: string
  calls: number
  started_at: string
}

/** "new" checks the share and counts the run; "continue" is a later part of a counted run. */
export type RunVerdict = 'new' | 'continue' | 'stale'

export function runVerdict(row: RunRow | null, part: number, parts: number, now = Date.now()): RunVerdict {
  // A run that gave nothing back was not counted; asking again counts it afresh.
  if (row?.outcome === 'refused') return 'new'
  if (!row) return part === 0 ? 'new' : 'stale'
  const started = Date.parse(row.started_at)
  if (!Number.isFinite(started) || now - started > RUN_MS) return 'stale'
  // Each part once, each retried once, and the first asked again.
  if (row.calls >= parts * 2 + 2) return 'stale'
  return 'continue'
}

/** The part the request asks for: absent is the whole book, which only a one-part book is. */
export function partAsked(raw: unknown, parts: number): number | 'whole_too_large' | null {
  if (raw === undefined || raw === null) return parts === 1 ? 0 : 'whole_too_large'
  if (typeof raw !== 'number' || !Number.isInteger(raw) || raw < 0 || raw >= parts) return null
  return raw
}
