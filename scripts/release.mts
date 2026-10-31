// longbook's release numbers, read from their one home each: the rulebook revision from the
// contract generator, the patch from release.json, the app's version and build from project.yml.
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { releases } from './changelog.mts'

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel: string): string => readFileSync(join(ROOT, rel), 'utf8')

const revision = /const CONTRACT_REVISION = (\d+)/.exec(read('scripts/gen-vault-contract.mts'))?.[1]
if (!revision) throw new Error('scripts/gen-vault-contract.mts names no CONTRACT_REVISION')
export const RULEBOOK = Number(revision)

const release = JSON.parse(read('release.json')) as { patch?: unknown }
if (!Number.isInteger(release.patch) || (release.patch as number) < 0) throw new Error('release.json needs a whole-number patch')
export const PATCH = release.patch as number

/** The npm package, the plugin, the registry entry and both servers' reported version. */
export const RELEASE_VERSION = `1.${RULEBOOK}.${PATCH}`

const project = read('apps/longbook/project.yml')
export const APP_VERSION = /MARKETING_VERSION: "([^"]+)"/.exec(project)?.[1] ?? '?'
export const APP_BUILD = Number(/CURRENT_PROJECT_VERSION: "(\d+)"/.exec(project)?.[1] ?? NaN)

export const MCP_NAME = 'app.longbook/mcp'
export const NPM_NAME = '@longbook/mcp'

// ---- one build number per device build: the owner's devices, then TestFlight, then the App Store
// Every device build of a changed app takes the next number; the marketing version stays for the
// sprint. TestFlight ships the highest device build, and the App Store a number TestFlight had.
export const LEDGER = join(ROOT, 'apps/longbook/device-builds.json')
export const PROJECT_YML = 'apps/longbook/project.yml'
export const CHANGELOG = 'apps/longbook/Resources/changelog.json'
export type LedgerEntry = { version: string; commit: string; installed: string; testflight?: string; direct?: string }
export type Ledger = Record<string, LedgerEntry>
export const readLedger = (): Ledger =>
  existsSync(LEDGER) ? JSON.parse(readFileSync(LEDGER, 'utf8')) as Ledger : {}
export const writeLedger = (ledger: Ledger): void =>
  writeFileSync(LEDGER, JSON.stringify(ledger, null, 2) + '\n')

/** The highest build the devices have had, 0 for an empty ledger. */
export const highestBuild = (ledger: Ledger): number => Math.max(0, ...Object.keys(ledger).map(Number))

/** What makes the app; the ledger itself is bookkeeping, not app. */
export const APP_PATHS = ['apps/longbook', 'packages/swift-core', 'packages/swift-design', ':(exclude)apps/longbook/device-builds.json']

/** project.yml without its build number: a new number alone makes the same app. */
export const projectSansBuild = (yml: string): string => yml.replace(/CURRENT_PROJECT_VERSION: "\d+"/, 'CURRENT_PROJECT_VERSION: ""')

/** The changelog as the app shows it: version and lines, an entry repeating the one before it folded in. */
export function changelogAsShown(json: string): string {
  const shown: { version: string; changes: string[] }[] = []
  for (const r of releases(json).reverse()) {
    const last = shown.at(-1)
    if (last && last.version === r.version && JSON.stringify(last.changes) === JSON.stringify(r.changes)) continue
    shown.push({ version: r.version, changes: r.changes })
  }
  return JSON.stringify(shown)
}

/** Whether two copies of one app file make the same app, the build-number bookkeeping aside. */
export function sameApp(rel: string, before: string | null, after: string | null): boolean {
  if (before === null || after === null) return before === after
  if (rel === PROJECT_YML) return projectSansBuild(before) === projectSansBuild(after)
  if (rel === CHANGELOG) {
    try { return changelogAsShown(before) === changelogAsShown(after) } catch { return false }
  }
  return before === after
}

const fileAt = (rev: string, rel: string): string | null => {
  try {
    return execFileSync('git', ['show', `${rev}:${rel}`], { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 << 20 })
  } catch {
    return null
  }
}

/** Whether this checkout makes a different app from the one built at `commit`. */
export function appChangedSince(commit: string): boolean {
  const changed = execFileSync('git', ['diff', '--name-only', commit, 'HEAD', '--', ...APP_PATHS], { cwd: ROOT, encoding: 'utf8' }).trim()
  if (!changed) return false
  return changed.split('\n').some((rel) => !sameApp(rel, fileAt(commit, rel), fileAt('HEAD', rel)))
}

/**
 * The number the next device build carries. The same app as the highest recorded build keeps
 * that number; a changed app takes one more than the highest of the ledger and project.yml.
 */
export function nextDeviceBuild(ledger: Ledger, projectBuild: number, changedSince: (commit: string) => boolean): { build: number; reuse: boolean } {
  const highest = highestBuild(ledger)
  const last = ledger[String(highest)]
  if (last && projectBuild <= highest && !changedSince(last.commit)) return { build: highest, reuse: true }
  return { build: Math.max(highest, Number.isFinite(projectBuild) ? projectBuild : 0) + 1, reuse: false }
}

/** project.yml with `build` as its build number. */
export const withBuild = (yml: string, build: number): string =>
  yml.replace(/CURRENT_PROJECT_VERSION: "\d+"/, `CURRENT_PROJECT_VERSION: "${build}"`)

/**
 * changelog.json with an entry for `build`, repeating the newest entry's lines, which must be
 * this version's. An entry already there for the build is kept. Throws when the newest is another version.
 */
export function withChangelogEntry(json: string, version: string, build: number, date: string): string {
  const rows = JSON.parse(json) as Record<string, unknown>[]
  if (rows.some((r) => Number(r.build) === build && r.version === version)) return json
  const newest = releases(json)[0]
  if (!newest || newest.version !== version) {
    throw new Error(`The newest entry in ${CHANGELOG} is ${newest?.version ?? 'missing'}, not ${version}. Add the ${version} entry first.`)
  }
  const entry = { version, build, date, changes: newest.changes }
  return JSON.stringify([entry, ...rows], null, 2) + '\n'
}

/** Why this checkout may not go to TestFlight, or null: it must be the highest build on the devices. */
export function untestedOnDevices(): string | null {
  const ledger = readLedger()
  const highest = highestBuild(ledger)
  const entry = ledger[String(highest)]
  if (!entry) return 'No build has been on your devices. Run npm run device:install first.'
  if (APP_BUILD !== highest) {
    return `project.yml builds ${APP_BUILD}, but the latest device build is ${highest}. Commit the files npm run device:install wrote.`
  }
  if (appChangedSince(entry.commit)) return `The app has changed since build ${highest} went on your devices (${entry.commit}). Run npm run device:install first.`
  return null
}

/** Marks the highest device build as on TestFlight. */
export function markOnTestFlight(): void {
  const ledger = readLedger()
  const entry = ledger[String(highestBuild(ledger))]
  if (!entry) return
  entry.testflight = new Date().toISOString().slice(0, 10)
  writeLedger(ledger)
}

/** Marks the highest device build as released from longbook.app, the direct Mac channel. */
export function markDirect(): void {
  const ledger = readLedger()
  const entry = ledger[String(highestBuild(ledger))]
  if (!entry) return
  entry.direct = new Date().toISOString().slice(0, 10)
  writeLedger(ledger)
}
