// The pieces of `npm run clean:slate` that decide rather than do: where the backup goes, which
// account may be deleted, what in Claude Code's config is longbook's, and whether a copy is exact.
import { createHash } from 'node:crypto'
import { cpSync, lstatSync, readdirSync, readFileSync, readlinkSync } from 'node:fs'
import { join } from 'node:path'
import { BUNDLE_ID, quote } from './app-reset-plan.mts'
import { FIRST_USE_URL } from './device-build-flag.mts'

/** Typed to go ahead with --apply. */
export const CONFIRM_PHRASE = 'clean slate'
export const confirmedPhrase = (answer: string): boolean => answer.trim().toLowerCase() === CONFIRM_PHRASE

/** The app's iCloud container folder, relative to the home folder. */
export const ICLOUD_VAULT = 'Library/Mobile Documents/iCloud~app~longbook/Documents'
/** iCloud Drive › longbook backups. */
export const BACKUPS = 'Library/Mobile Documents/com~apple~CloudDocs/longbook backups'
/** The file in the vault that names the account that last opened it. */
export const WORKSPACE_FILE = 'longbook.workspace.json'

/** The App Review accounts. No flag deletes them. */
export const PROTECTED_ACCOUNTS = ['appreview@longbook.app', 'review@longbook.app']

const pad = (n: number): string => String(n).padStart(2, '0')

/** Local time, minute precision: `2026-10-28 1642`. */
export function backupStamp(at: Date): string {
  return `${at.getFullYear()}-${pad(at.getMonth() + 1)}-${pad(at.getDate())} ${pad(at.getHours())}${pad(at.getMinutes())}`
}

export const backupDir = (home: string, at: Date): string => join(home, BACKUPS, backupStamp(at))

/** One line that copies a backup back into place, quit app first. */
export const restoreCommand = (backup: string, target: string): string =>
  `ditto ${quote(backup)} ${quote(target.endsWith('/') ? target : `${target}/`)}`

/** Lowercased and trimmed, with any +tag dropped, so the review accounts cannot hide behind one. */
export function normaliseEmail(email: string): string {
  const [local, domain] = email.trim().toLowerCase().split('@')
  return domain === undefined ? local : `${local.replace(/\+.*$/, '')}@${domain}`
}

export const isProtectedAccount = (email: string): boolean => PROTECTED_ACCOUNTS.includes(normaliseEmail(email))

/** No quotes, backslashes or spaces, so it can sit inside a SQL literal. */
export const validEmail = (email: string): boolean => /^[^\s'"\\@]+@[^\s'"\\@]+\.[^\s'"\\@]+$/.test(email.trim())

/** First letter and domain only: `r…@example.com`. */
export function maskEmail(email: string): string {
  const [local, domain] = email.trim().split('@')
  return domain === undefined ? '…' : `${local.slice(0, 1)}…@${domain}`
}

export const sqlText = (text: string): string => `'${text.replace(/'/g, "''")}'`

/** `true` is --account with no address after it. */
export type AccountFlag = string | true | undefined
export type AccountChoice =
  | { kind: 'skip' }
  | { kind: 'refuse'; reason: string }
  | { kind: 'delete'; email: string; typeToConfirm: boolean }

/** Which account goes, from the flag and the address the vault says opened it. */
export function chooseAccount(flag: AccountFlag, signedIn: string | null): AccountChoice {
  if (flag === undefined) return { kind: 'skip' }
  const email = flag === true ? signedIn : flag
  if (!email) {
    return { kind: 'refuse', reason: 'No signed-in address was found in the vault. Name the account: --account <email>.' }
  }
  if (!validEmail(email)) return { kind: 'refuse', reason: `${maskEmail(email)} is not an email address.` }
  if (isProtectedAccount(email)) return { kind: 'refuse', reason: `${maskEmail(email)} is an App Review account. clean:slate never deletes it.` }
  if (flag !== true && signedIn && normaliseEmail(signedIn) !== normaliseEmail(email)) {
    return {
      kind: 'refuse',
      reason: `--account names ${maskEmail(email)}, but the vault was opened by ${maskEmail(signedIn)}. Pass that address, or --account alone.`,
    }
  }
  return { kind: 'delete', email: email.trim(), typeToConfirm: flag === true }
}

export interface Args {
  apply: boolean
  yes: boolean
  mac: boolean
  device?: string
  account: AccountFlag
  reinstall?: string
  problems: string[]
}

export function parseArgs(argv: string[]): Args {
  const problems: string[] = []
  const value = (flag: string): string | undefined => {
    const at = argv.indexOf(flag)
    if (at < 0) return undefined
    const next = argv[at + 1]
    if (next === undefined || next.startsWith('--')) {
      problems.push(`${flag} needs a value.`)
      return undefined
    }
    return next
  }
  const accountAt = argv.indexOf('--account')
  const afterAccount = argv[accountAt + 1]
  const account: AccountFlag = accountAt < 0 ? undefined : afterAccount === undefined || afterAccount.startsWith('--') ? true : afterAccount
  const known = new Set(['--apply', '--yes', '--mac', '--device', '--account', '--reinstall'])
  const after = (flag: string): string | undefined => (argv.includes(flag) ? argv[argv.indexOf(flag) + 1] : undefined)
  const values = new Set([after('--device'), after('--reinstall'), account === true ? undefined : account])
  for (const arg of argv) if (!known.has(arg) && !values.has(arg)) problems.push(`Unknown argument: ${arg}`)
  const device = value('--device')
  const reinstall = value('--reinstall')
  if (reinstall && argv.indexOf('--device') < 0) problems.push('--reinstall needs --device <udid>.')
  return { apply: argv.includes('--apply'), yes: argv.includes('--yes'), mac: argv.includes('--mac'), device, account, reinstall, problems }
}

export interface McpEntry { name: string; scope: 'user' | 'local'; project?: string }

const isLongbook = (name: string, server: unknown): boolean =>
  /longbook/i.test(name) || /longbook\.app/i.test(JSON.stringify(server ?? ''))

/** longbook's MCP servers in ~/.claude.json: user scope, and local scope per project. */
export function longbookMcpServers(claudeJson: unknown): McpEntry[] {
  const root = (claudeJson ?? {}) as { mcpServers?: Record<string, unknown>; projects?: Record<string, { mcpServers?: Record<string, unknown> }> }
  const out: McpEntry[] = []
  for (const [name, server] of Object.entries(root.mcpServers ?? {})) if (isLongbook(name, server)) out.push({ name, scope: 'user' })
  for (const [project, config] of Object.entries(root.projects ?? {})) {
    for (const [name, server] of Object.entries(config?.mcpServers ?? {})) {
      if (isLongbook(name, server)) out.push({ name, scope: 'local', project })
    }
  }
  return out
}

export interface PluginEntry { id: string; scope: string; project?: string }

/** Installs of a longbook plugin in ~/.claude/plugins/installed_plugins.json. */
export function longbookPlugins(installed: unknown): PluginEntry[] {
  const root = (installed ?? {}) as { plugins?: Record<string, unknown> }
  const plugins = (root.plugins ?? root) as Record<string, unknown>
  const out: PluginEntry[] = []
  for (const [id, entries] of Object.entries(plugins)) {
    if (!/^longbook@/i.test(id) || !Array.isArray(entries)) continue
    for (const e of entries as { scope?: string; projectPath?: string }[]) {
      out.push({ id, scope: e.scope ?? 'user', ...(e.projectPath ? { project: e.projectPath } : {}) })
    }
  }
  return out
}

/** Counts the rows each table keyed to auth.users holds for one user, in one query. */
export function cascadeCountQuery(keys: { table: string; column: string }[], userId: string): string {
  if (!keys.length) return 'select 1 where false'
  return keys.map((k) => `select ${sqlText(k.table)} as "table", count(*)::int as rows from ${k.table} where ${k.column} = ${sqlText(userId)}`).join('\nunion all\n')
}

/** Every file, folder and link under a folder, with each file's size and, unless asked not to, SHA-256. */
export function manifest(dir: string, hash = true): Map<string, string> {
  const out = new Map<string, string>()
  const walk = (rel: string): void => {
    for (const name of readdirSync(join(dir, rel))) {
      const path = rel ? `${rel}/${name}` : name
      const stat = lstatSync(join(dir, path))
      if (stat.isSymbolicLink()) out.set(path, `link:${readlinkSync(join(dir, path))}`)
      else if (stat.isDirectory()) {
        out.set(path, 'dir')
        walk(path)
      } else out.set(path, hash ? `${stat.size}:${createHash('sha256').update(readFileSync(join(dir, path))).digest('hex')}` : `${stat.size}`)
    }
  }
  walk('')
  return out
}

/** What differs between an original and its copy, by path. Empty means byte for byte. */
export function compareManifests(original: Map<string, string>, copy: Map<string, string>): string[] {
  const problems: string[] = []
  for (const [path, sum] of original) {
    if (!copy.has(path)) problems.push(`missing in the copy: ${path}`)
    else if (copy.get(path) !== sum) problems.push(`differs in the copy: ${path}`)
  }
  for (const path of copy.keys()) if (!original.has(path)) problems.push(`extra in the copy: ${path}`)
  return problems
}

/** Copies a folder's contents into a new folder and proves the copy, without removing anything. */
export function copyVerified(source: string, destination: string): { files: number; bytes: number } {
  const before = manifest(source)
  cpSync(source, destination, { recursive: true, preserveTimestamps: true, errorOnExist: true, force: false, verbatimSymlinks: true })
  const problems = compareManifests(before, manifest(destination))
  if (problems.length) throw new Error(`The copy is not exact (${problems.length} difference(s)), first: ${problems[0]}`)
  const files = [...before.values()].filter((v) => v !== 'dir' && !v.startsWith('link:'))
  return { files: files.length, bytes: files.reduce((n, v) => n + Number(v.split(':')[0]), 0) }
}

/** How many files a folder holds and their total size, from sizes alone: nothing is read. */
export function folderSummary(dir: string): { files: number; bytes: number } {
  const files = [...manifest(dir, false).values()].filter((v) => v !== 'dir' && !v.startsWith('link:'))
  return { files: files.length, bytes: files.reduce((n, v) => n + Number(v.split(':')[0]), 0) }
}

export const size = (bytes: number): string =>
  bytes < 1024 ? `${bytes} B` : bytes < 1024 ** 2 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / 1024 ** 2).toFixed(1)} MB`

/** The order the tool works in: each app resets itself, then the vault moves, then the account and Claude Code go. */
export const STAGES = ['app', 'vault', 'account', 'claude'] as const
export type Stage = (typeof STAGES)[number]

/** Sections sorted into the working order, keeping their order within a stage. */
export const inStageOrder = <T extends { stage: Stage }>(sections: T[]): T[] =>
  STAGES.flatMap((stage) => sections.filter((s) => s.stage === stage))

/** Opens the reset link in the Mac app and waits for it to quit, which it does once reset. */
export const macResetCommand = (app: string): string[] => ['open', '-W', '-a', app, FIRST_USE_URL]

/** A fresh launch with the reset link, so a running copy cannot swallow it unseen. */
export const phoneResetCommand = (udid: string): string[] => [
  'xcrun', 'devicectl', 'device', 'process', 'launch', '--device', udid, '--terminate-existing', '--payload-url', FIRST_USE_URL, BUNDLE_ID,
]

/** The one line the app logs as it resets, read back from the Mac's log since a local time. */
export const resetLogCommand = (since: Date): string[] => [
  '/usr/bin/log', 'show', '--start', `${backupStamp(since).slice(0, 10)} ${pad(since.getHours())}:${pad(since.getMinutes())}:${pad(since.getSeconds())}`,
  '--style', 'compact', '--predicate', 'subsystem == "app.longbook.longbook" AND category == "first-use"',
]

/** Whether `devicectl device info processes` lists the app itself; its widget does not count. */
export function appRunning(processes: unknown): boolean {
  const list = ((processes as { result?: { runningProcesses?: { executable?: unknown }[] } })?.result?.runningProcesses ?? [])
  return list.some((p) => /\/longbook\.app\/longbook$/.test(String(p?.executable ?? '')))
}
