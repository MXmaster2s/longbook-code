// The app's changelog, read the way the app reads it: apps/longbook/Resources/changelog.json,
// one entry per version, newest build first. TestFlight's notes and the check below use it.
export interface Release {
  version: string
  build: number
  date: string
  changes: string[]
}

export function releases(json: string): Release[] {
  const rows = JSON.parse(json) as unknown
  if (!Array.isArray(rows)) throw new Error('changelog.json is not a list')
  return rows
    .map((row: Record<string, unknown>) => ({
      version: String(row.version ?? ''), build: Number(row.build), date: String(row.date ?? ''),
      changes: Array.isArray(row.changes) ? row.changes.map(String) : [],
    }))
    .filter((r) => r.version && Number.isInteger(r.build) && r.changes.length)
    .sort((a, b) => b.build - a.build)
}

export function newestRelease(json: string): Release {
  const [newest] = releases(json)
  if (!newest) throw new Error('changelog.json names no release')
  return newest
}
