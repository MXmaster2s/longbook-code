// longbook's release numbers, read from their one home each: the rulebook revision from the
// contract generator, the patch from release.json, the app's version and build from project.yml.
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

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

// ---- one build number, three stops: the owner's devices, then TestFlight, then the App Store --
// Devices reuse a number until it goes to TestFlight; the next device build takes the next one.
// TestFlight ships the number tested on the devices, and the App Store a number TestFlight had.
export const LEDGER = join(ROOT, 'apps/longbook/device-builds.json')
export type LedgerEntry = { version: string; commit: string; installed: string; testflight?: string }
export const readLedger = (): Record<string, LedgerEntry> =>
  existsSync(LEDGER) ? JSON.parse(readFileSync(LEDGER, 'utf8')) as Record<string, LedgerEntry> : {}
export const writeLedger = (ledger: Record<string, LedgerEntry>): void =>
  writeFileSync(LEDGER, JSON.stringify(ledger, null, 2) + '\n')

/** What makes the app; the ledger itself is bookkeeping, not app. */
export const APP_PATHS = ['apps/longbook', 'packages/swift-core', 'packages/swift-design', ':(exclude)apps/longbook/device-builds.json']

/** Whether this checkout makes a different app from the one built at `commit`. */
export const appChangedSince = (commit: string): boolean =>
  execFileSync('git', ['diff', '--name-only', commit, 'HEAD', '--', ...APP_PATHS], { cwd: ROOT, encoding: 'utf8' }).trim() !== ''

/** Why this checkout may not go to TestFlight, or null: it must be the app on the devices. */
export function untestedOnDevices(): string | null {
  const entry = readLedger()[String(APP_BUILD)]
  if (!entry) return `Build ${APP_BUILD} has not been on your devices. Run npm run device:install first.`
  if (appChangedSince(entry.commit)) return `The app has changed since build ${APP_BUILD} went on your devices (${entry.commit}). Run npm run device:install first.`
  return null
}

/** Marks the build as on TestFlight, so the next device build takes the next number. */
export function markOnTestFlight(): void {
  const ledger = readLedger()
  const entry = ledger[String(APP_BUILD)]
  if (!entry) return
  entry.testflight = new Date().toISOString().slice(0, 10)
  writeLedger(ledger)
}
