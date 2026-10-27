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

/** What stops the newest entry describing the build project.yml makes; empty when it does. */
export function changelogProblems(projectYml: string, changelogJson: string): string[] {
  const version = /MARKETING_VERSION: "([^"]+)"/.exec(projectYml)?.[1]
  const build = /CURRENT_PROJECT_VERSION: "(\d+)"/.exec(projectYml)?.[1]
  const newest = newestRelease(changelogJson)
  const problems: string[] = []
  if (newest.version !== version) problems.push(`changelog names ${newest.version}, project.yml builds ${version}`)
  if (String(newest.build) !== build) problems.push(`changelog names build ${newest.build}, project.yml builds ${build}`)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(newest.date)) problems.push(`the newest entry's date "${newest.date}" is not a day`)
  const long = newest.changes.filter((c) => c.length > 300)
  if (long.length) problems.push(`${long.length} change(s) run past 300 characters`)
  if (newest.changes.join(' ').length > 4000) problems.push('the notes run past TestFlight\'s 4000 characters')
  return problems
}
