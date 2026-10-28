#!/usr/bin/env -S npx tsx
// Puts longbook back to a brand-new user: app state, the vault moved to iCloud Drive › longbook
// backups, the account deleted, Claude Code's longbook plugin removed. Dry run unless --apply.
// Run: npm run clean:slate [-- --mac] [--device <udid> [--reinstall <app>]] [--account [<email>]] [--apply [--yes]]
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { basename, join } from 'node:path'
import { createInterface } from 'node:readline/promises'
import {
  alreadyGone, APP_GROUP, bootedSimulators, BUNDLE_ID, macAppPids, macPlan, notPermitted, quote, simulatorPlan, VAULT_FILE,
} from './app-reset-plan.mts'
import {
  backupDir, cascadeCountQuery, chooseAccount, confirmedPhrase, CONFIRM_PHRASE, copyVerified, folderSummary, ICLOUD_VAULT,
  longbookMcpServers, longbookPlugins, maskEmail, normaliseEmail, parseArgs, restoreCommand, size, sqlText, WORKSPACE_FILE,
} from './clean-slate-plan.mts'
import { topLevelKeys } from './plist.mts'

const PROJECT_REF = 'xbrnijgctmovoqbbmgmb'
const MANAGE = `https://api.supabase.com/v1/projects/${PROJECT_REF}`
const AUTH = `https://${PROJECT_REF}.supabase.co/auth/v1`
const TOKEN_SERVICE = 'Supabase Personal-Access Token'
const ACCESS_KEY_SERVICE = 'longbook access key'

const args = parseArgs(process.argv.slice(2))
if (args.problems.length) {
  console.error(args.problems.join('\n'))
  process.exit(1)
}
const home = homedir()
const now = new Date()
const BACKUP = backupDir(home, now)
/** Copies that are not the iCloud vault sit beside it, so a restore of the vault stays one line. */
const MORE = `${BACKUP} app copies`
const ICLOUD = join(home, ICLOUD_VAULT)
const MAC_DATA = join(home, 'Library/Containers', BUNDLE_ID, 'Data')
const MAC_GROUP = join(home, 'Library/Group Containers', APP_GROUP)
const wantMac = args.mac || !args.device
const wantAutoPhone = !args.mac && !args.device

interface Action { what: string; shown: string; run: () => void | Promise<void>; optional?: boolean }
interface Section { target: string; actions: Action[]; kept: string[]; blocked?: string }
const sections: Section[] = []

const run = (cmd: string, argv: string[], cwd?: string, timeout = 120_000): string =>
  execFileSync(cmd, argv, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], cwd, timeout })
const attempt = (cmd: string, argv: string[], timeout?: number): string | null => {
  try {
    return run(cmd, argv, undefined, timeout)
  } catch {
    return null
  }
}
const command = (what: string, argv: string[], extra: { optional?: boolean; cwd?: string } = {}): Action => ({
  what,
  shown: `$ ${extra.cwd ? `cd ${quote(extra.cwd)} && ` : ''}${argv.map(quote).join(' ')}`,
  run: () => void run(argv[0], argv.slice(1), extra.cwd),
  optional: extra.optional,
})
const removeAction = (what: string, path: string): Action => ({
  what, shown: `$ rm -rf ${quote(path)}`, run: () => rmSync(path, { recursive: true, force: true }),
})
const readable = (dir: string): boolean => {
  try {
    readdirSync(dir)
    return true
  } catch {
    return false
  }
}
const isVault = (dir: string): boolean => readable(dir) && readdirSync(dir).some((n) => n === VAULT_FILE || n === `.${VAULT_FILE}.icloud`)
const pause = (ms: number): void => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms) as unknown as void
const macPids = (): number[] => macAppPids(attempt('ps', ['-axo', 'pid=,comm=']) ?? '')
const counted = (s: { files: number; bytes: number }): string => `${s.files} file(s), ${size(s.bytes)}`

/** Moves a folder's contents: copied, every file's SHA-256 matched, and only then the originals removed. */
function moveAction(what: string, source: string, destination: string, guard?: () => void): Action {
  return {
    what,
    shown: `copy to ${quote(destination)}, match every file's SHA-256, then remove the originals`,
    run: () => {
      guard?.()
      if (existsSync(destination)) throw new Error(`${destination} already exists. Wait a minute and run this again.`)
      mkdirSync(join(destination, '..'), { recursive: true })
      const copied = copyVerified(source, destination)
      for (const name of readdirSync(source)) rmSync(join(source, name), { recursive: true, force: true })
      const left = readdirSync(source).length
      if (left) throw new Error(`${left} item(s) could not be removed from ${source}; the copy is complete.`)
      console.log(`  moved ${counted(copied)}, every file matched`)
    },
  }
}

/** The folder a stored bookmark points at, read from the bookmark's own bytes. Nothing is opened. */
function bookmarkPath(base64: string): string | null {
  const script = "function run(a){ObjC.import('Foundation');var d=$.NSData.alloc.initWithBase64EncodedStringOptions(a[0],1);" +
    "var v=$.NSURL.resourceValuesForKeysFromBookmarkData($([$.NSURLPathKey]),d);if(!v||v.isNil())return '';" +
    "var p=v.objectForKey($.NSURLPathKey);return (p&&!p.isNil())?p.js:''}"
  return attempt('osascript', ['-l', 'JavaScript', '-e', script, base64])?.trim() || null
}
const bookmarksIn = (domain: string, keys: string[]): string[] => {
  const xml = attempt('defaults', ['export', domain, '-']) ?? ''
  return keys.flatMap((key) => {
    const data = new RegExp(`<key>${key.replace(/\./g, '\\.')}</key>\\s*<data>([\\s\\S]*?)</data>`).exec(xml)?.[1]
    const path = data ? bookmarkPath(data.replace(/\s+/g, '')) : null
    return path ? [path] : []
  })
}

// The address that last opened the vault, which the app writes from its signed-in session.
const accountIn = (folder: string): string | null => {
  try {
    const email = JSON.parse(readFileSync(join(folder, WORKSPACE_FILE), 'utf8')).accountEmail
    return typeof email === 'string' && email.trim() ? email.trim() : null
  } catch {
    return null
  }
}
let signedIn = accountIn(ICLOUD)

// ── This Mac: the app ────────────────────────────────────────────────────────────────────────
if (wantMac && process.platform === 'darwin') {
  const containerOpen = readable(MAC_DATA)
  const exported = attempt('defaults', ['export', BUNDLE_ID, '-'])
  const reset = macPlan({ home, running: false, userDomainKeys: exported ? topLevelKeys(exported) : [], iCloudVault: isVault(ICLOUD) })
  const actions: Action[] = [{
    what: 'Quit longbook, and wait until it has gone: it writes its settings back as it closes.',
    shown: `$ osascript -e 'quit app "longbook"'`,
    run: () => {
      if (!macPids().length) return
      run('osascript', ['-e', 'quit app "longbook"'])
      for (let i = 0; i < 40 && macPids().length; i++) pause(500)
      if (macPids().length) throw new Error('longbook is still running. Quit it, then run this again.')
    },
  }]
  // Everything app:reset does, with the app group's whole domain in place of its one key.
  for (const step of reset.steps.filter((s) => s.command.at(-1) !== 'vaultBookmark')) {
    actions.push(command(step.what.replace(/ macOS keeps.*$/, ''), step.command))
  }
  actions.push(command('Delete the app group\'s settings domain: the folder bookmark and what the widget and menu bar keep.',
    ['defaults', 'delete', join(MAC_GROUP, 'Library/Preferences', APP_GROUP)]))
  if (containerOpen) {
    const history = join(MAC_DATA, 'Library/Application Support/longbook')
    if (readable(history)) {
      actions.push(moveAction(`Move the app's own copy of the vault's history (${counted(folderSummary(history))}) to the backup.`,
        history, join(MORE, 'Mac app history')))
    }
    for (const [what, rel] of [
      ['the app\'s caches', 'Library/Caches/app.longbook.longbook'], ['its web storage', 'Library/HTTPStorages/app.longbook.longbook'],
      ['its saved window state', 'Library/Saved Application State/app.longbook.longbook.savedState'],
      ['Support attachments waiting to send', 'tmp/longbook-support'], ['the demo longbook', 'tmp/demo-longbook'],
    ] as const) {
      if (existsSync(join(MAC_DATA, rel))) actions.push(removeAction(`Delete ${what}.`, join(MAC_DATA, rel)))
    }
  }
  if (readable(MAC_GROUP) && existsSync(join(MAC_GROUP, 'widget-copy.json'))) {
    actions.push(removeAction('Delete the widget\'s copy of the vault, a derived file.', join(MAC_GROUP, 'widget-copy.json')))
  }
  if (attempt('security', ['find-generic-password', '-s', ACCESS_KEY_SERVICE]) !== null) {
    actions.push({
      what: 'Delete the saved longbook access key from the login keychain.',
      shown: `$ security delete-generic-password -s ${quote(ACCESS_KEY_SERVICE)}`,
      run: () => {
        while (attempt('security', ['delete-generic-password', '-s', ACCESS_KEY_SERVICE]) !== null) { /* one item per account */ }
      },
    })
  }
  sections.push({
    target: `This Mac${macPids().length ? ' (longbook is open; the first step quits it)' : ''}`,
    actions,
    blocked: containerOpen ? undefined
      : 'macOS guards the app\'s container from this terminal, so its own folder and any picked vault cannot be checked. ' +
        'Give this terminal Full Disk Access in Privacy & Security, then run this again.',
    kept: [
      'The signed-in session and the trial stamp (app.longbook.session, app.longbook.trial). They live in the data-protection ' +
        'keychain, which only the app can reach. Deleting the account ends the session on the server; the app signs out ' +
        'the next time it refreshes its token (the project\'s tokens live an hour). The trial stamp keeps this Mac\'s earliest trial start.',
      'Purchases, which StoreKit keeps. Clear test purchases in Xcode\'s StoreKit transaction manager.',
    ],
  })

  // ── The vault ──────────────────────────────────────────────────────────────────────────────
  const vault: Action[] = []
  const kept: string[] = []
  let blocked: string | undefined
  const notRunning = () => {
    if (macPids().length) throw new Error('longbook is running. Nothing in the vault was moved.')
  }
  if (!readable(join(home, 'Library/Mobile Documents/com~apple~CloudDocs'))) {
    blocked = 'iCloud Drive is not on this Mac, so there is nowhere to move the vault.'
  }
  if (existsSync(BACKUP) || existsSync(MORE)) blocked = `${BACKUP} already exists. Wait a minute and run this again.`
  if (readable(ICLOUD) && readdirSync(ICLOUD).length) {
    const dataless = attempt('find', [ICLOUD, '-flags', '+dataless'])?.split('\n').filter(Boolean).length ?? 0
    const placeholders = attempt('find', [ICLOUD, '-name', '.*.icloud'])?.split('\n').filter(Boolean).length ?? 0
    if (dataless + placeholders) {
      blocked = `${dataless + placeholders} file(s) in the vault are still in iCloud only. Download them first: brctl download ${quote(ICLOUD)}`
    }
    vault.push(moveAction(`Move everything in the iCloud longbook folder (${counted(folderSummary(ICLOUD))}) to iCloud Drive › longbook backups › ${basename(BACKUP)}. ` +
      'The folder itself stays, empty, and the iPhone sees it empty once iCloud syncs.', ICLOUD, BACKUP, notRunning))
    kept.push(`Restore with: ${restoreCommand(BACKUP, ICLOUD)}`)
  } else kept.push('The iCloud longbook folder is already empty.')
  if (readable(MAC_DATA)) {
    const docs = join(MAC_DATA, 'Documents')
    if (isVault(docs) || isVault(join(docs, 'longbook'))) {
      signedIn ??= accountIn(docs) ?? accountIn(join(docs, 'longbook'))
      vault.push(moveAction(`Move the vault kept in the app's own Documents (${counted(folderSummary(docs))}).`, docs, join(MORE, 'Mac app Documents'), notRunning))
      kept.push(`Restore with: ${restoreCommand(join(MORE, 'Mac app Documents'), docs)}`)
    }
    const picked = [
      ...bookmarksIn(join(MAC_DATA, 'Library/Preferences', BUNDLE_ID), ['longbook.vaultBookmark', 'vaultBookmark']),
      ...bookmarksIn(join(MAC_GROUP, 'Library/Preferences', APP_GROUP), ['vaultBookmark']),
    ]
    for (const folder of new Set(picked)) {
      if (folder.startsWith(ICLOUD) || folder.startsWith(MAC_DATA) || !isVault(folder)) continue
      signedIn ??= accountIn(folder)
      const to = join(MORE, `Picked folder ${basename(folder)}`)
      vault.push(moveAction(`Move the vault in the folder picked in the app, ${folder} (${counted(folderSummary(folder))}).`, folder, to, notRunning))
      kept.push(`Restore with: ${restoreCommand(to, folder)}`)
    }
  } else kept.push('A vault in the app\'s own Documents or a picked folder: not checked, see above.')
  sections.push({ target: 'The vault (moved, never deleted)', actions: vault, kept, blocked })
}

// ── The account ──────────────────────────────────────────────────────────────────────────────
const choice = chooseAccount(args.account, signedIn)
if (choice.kind === 'refuse') {
  console.error(`Stopped: ${choice.reason}`)
  process.exit(1)
}
// Read once, never printed.
let cachedToken: string | null | undefined
const token = (): string | null => {
  cachedToken ??= process.env.SUPABASE_ACCESS_TOKEN?.trim() || attempt('security', ['find-generic-password', '-s', TOKEN_SERVICE, '-w'])?.trim() || null
  return cachedToken
}
async function manage(path: string, init: RequestInit = {}): Promise<any> {
  const res = await fetch(`${MANAGE}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    signal: AbortSignal.timeout(20_000),
  })
  if (!res.ok) throw new Error(`Supabase ${path.split('?')[0]} answered ${res.status}: ${(await res.text()).slice(0, 200)}`)
  return res.json()
}
const sql = (query: string): Promise<any[]> => manage('/database/query', { method: 'POST', body: JSON.stringify({ query }) })
type Found = { id: string; created: string; providers: string[] }
const lookUp = async (email: string): Promise<Found[]> => sql(
  `select u.id, to_char(u.created_at, 'YYYY-MM-DD') as created, coalesce((select array_agg(distinct i.provider) from auth.identities i ` +
  `where i.user_id = u.id), '{}') as providers from auth.users u where lower(u.email) = lower(${sqlText(email)})`)
async function rowsHeld(id: string): Promise<{ table: string; rows: number; onDelete: string }[]> {
  const keys = (await sql(
    `select c.conrelid::regclass::text as "table", quote_ident(a.attname) as "column", c.confdeltype as "onDelete" from pg_constraint c ` +
    `join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1] where c.contype = 'f' ` +
    `and c.confrelid = 'auth.users'::regclass and c.connamespace <> 'auth'::regnamespace`)) as { table: string; column: string; onDelete: string }[]
  const counts = (await sql(cascadeCountQuery(keys, id))) as { table: string; rows: number }[]
  return counts.map((c) => ({ ...c, onDelete: keys.find((k) => k.table === c.table)?.onDelete ?? 'c' }))
}

let appleLinked = false
if (choice.kind === 'delete') {
  const masked = maskEmail(choice.email)
  const actions: Action[] = []
  const kept: string[] = []
  let blocked: string | undefined
  const intro = signedIn ? `the vault was opened by ${maskEmail(signedIn)}` : 'no signed-in address was found in the vault'
  if (!token()) {
    blocked = `No Supabase access token: set SUPABASE_ACCESS_TOKEN, or keep it in the keychain as "${TOKEN_SERVICE}".`
  } else {
    try {
      const found = await lookUp(choice.email)
      if (found.length !== 1) {
        kept.push(found.length ? `${found.length} accounts match ${masked}; none is deleted.` : `No account on the server has the address ${masked}. Nothing to delete.`)
        if (found.length > 1) blocked = 'More than one account matches.'
      } else {
        const user = found[0]
        appleLinked = user.providers.includes('apple')
        const held = await rowsHeld(user.id)
        const holding = held.filter((h) => h.rows > 0)
        const stuck = holding.filter((h) => h.onDelete !== 'c')
        if (stuck.length) blocked = `Rows in ${stuck.map((s) => s.table).join(', ')} do not go with the account; the delete would fail or leave them.`
        let storage = 'unknown'
        try {
          storage = String((await sql(`select count(*)::int as n from storage.objects where owner_id = ${sqlText(user.id)}`))[0]?.n ?? 0)
        } catch { /* no storage schema on this project */ }
        actions.push({
          what: `Delete ${masked} (made ${user.created}, signs in with ${user.providers.join(', ') || 'email'}): the same admin delete the ` +
            `delete-account function makes, which takes every row keyed to the account with it — ` +
            `${holding.map((h) => `${h.table.replace(/^public\./, '')} ${h.rows}`).join(', ') || 'no rows'}; storage objects ${storage}.`,
          shown: `$ DELETE ${AUTH}/admin/users/${user.id.slice(0, 8)}… (service role key, fetched from the Management API)`,
          run: async () => {
            const keys = (await manage('/api-keys?reveal=true')) as { name: string; api_key: string }[]
            const service = keys.find((k) => k.name === 'service_role')?.api_key
            if (!service) throw new Error('The project has no service_role key.')
            const res = await fetch(`${AUTH}/admin/users/${user.id}`, {
              method: 'DELETE', headers: { Authorization: `Bearer ${service}`, apikey: service }, signal: AbortSignal.timeout(20_000),
            })
            if (!res.ok) throw new Error(`The delete answered ${res.status}: ${(await res.text()).slice(0, 200)}`)
            const after = await rowsHeld(user.id)
            const left = after.filter((h) => h.rows > 0)
            if ((await lookUp(choice.email)).length || left.length) throw new Error(`The account or ${left.length} table(s) of its rows are still there.`)
            console.log(`  ${masked} deleted; no rows left in ${after.length} table(s)`)
          },
        })
      }
    } catch (error) {
      blocked = (error as Error).message
    }
  }
  kept.push(`--account ${choice.typeToConfirm ? 'alone' : 'named the address'}; ${intro}.`)
  sections.push({ target: `The account ${masked}`, actions, kept, blocked })
} else {
  sections.push({ target: 'The account', actions: [], kept: [`Kept. Add --account to delete it (${signedIn ? `the vault was opened by ${maskEmail(signedIn)}` : 'no signed-in address found'}).`] })
}

// ── Claude Code and Claude Desktop on this Mac ───────────────────────────────────────────────
if (wantMac && process.platform === 'darwin') {
  const actions: Action[] = []
  const kept: string[] = []
  const json = (path: string): unknown => {
    try {
      return JSON.parse(readFileSync(path, 'utf8'))
    } catch {
      return null
    }
  }
  const hasClaude = attempt('which', ['claude']) !== null
  const plugins = longbookPlugins(json(join(home, '.claude/plugins/installed_plugins.json')))
  const markets = Object.keys((json(join(home, '.claude/plugins/known_marketplaces.json')) ?? {}) as object).filter((m) => /^longbook/i.test(m))
  const servers = longbookMcpServers(json(join(home, '.claude.json')))
  if (!hasClaude && plugins.length + markets.length + servers.length) kept.push('The claude command is not on this PATH, so nothing here can be removed.')
  if (hasClaude) {
    for (const p of plugins) {
      actions.push(command(`Uninstall the ${p.id} plugin (${p.scope} scope).`, ['claude', 'plugin', 'uninstall', p.id, '--scope', p.scope], { cwd: p.project }))
    }
    for (const m of markets) actions.push(command(`Remove the ${m} plugin marketplace.`, ['claude', 'plugin', 'marketplace', 'remove', m]))
    for (const s of servers) {
      actions.push(command(`Remove the ${s.name} MCP server (${s.scope} scope).`, ['claude', 'mcp', 'remove', s.name, '-s', s.scope], { cwd: s.project }))
    }
  }
  const desktop = join(home, 'Library/Application Support/Claude/claude_desktop_config.json')
  const desktopConfig = json(desktop) as { mcpServers?: Record<string, unknown> } | null
  const desktopNames = longbookMcpServers({ mcpServers: desktopConfig?.mcpServers }).map((s) => s.name)
  if (desktopNames.length) {
    actions.push({
      what: `Remove ${desktopNames.join(', ')} from Claude Desktop's config; a copy of the file goes to the backup first.`,
      shown: `edit ${quote(desktop)}`,
      run: () => {
        mkdirSync(MORE, { recursive: true })
        writeFileSync(join(MORE, 'claude_desktop_config.json'), readFileSync(desktop))
        for (const n of desktopNames) delete desktopConfig!.mcpServers![n]
        writeFileSync(desktop, `${JSON.stringify(desktopConfig, null, 2)}\n`)
      },
    })
  }
  if (!actions.length && !kept.length) kept.push('No longbook plugin or MCP server is set up here.')
  sections.push({ target: 'Claude Code and Claude Desktop on this Mac', actions, kept })
}

// ── A device ─────────────────────────────────────────────────────────────────────────────────
const NO_IN_PLACE = 'devicectl can copy files into the app\'s container but cannot delete them, and the keychain (session, ' +
  'trial stamp) outlives even an uninstall, so the app cannot be reset in place. Run again with --reinstall <path-to-.app>, an ' +
  'iphoneos build from xcodebuild (device:install deletes its own once installed): the uninstall clears settings, caches and app group.'

function simulatorSection(sim: { udid: string; name: string; runtime: string }): Section {
  const data = attempt('xcrun', ['simctl', 'get_app_container', sim.udid, BUNDLE_ID, 'data'])?.trim() || null
  const group = attempt('xcrun', ['simctl', 'get_app_container', sim.udid, BUNDLE_ID, APP_GROUP])?.trim() || null
  const prefs = data ? join(data, 'Library/Preferences', `${BUNDLE_ID}.plist`) : ''
  const xml = prefs && existsSync(prefs) ? attempt('plutil', ['-convert', 'xml1', '-o', '-', prefs]) : null
  const local = data ? [join(data, 'Documents/longbook'), join(data, 'Documents')].find(isVault) ?? null : null
  const plan = simulatorPlan({ ...sim, dataContainer: data, groupContainers: [], keys: xml ? topLevelKeys(xml) : [], localVault: local })
  if (!data) return { target: plan.target, actions: [], kept: plan.kept }
  const actions: Action[] = [command('Quit longbook on the simulator.', ['xcrun', 'simctl', 'terminate', sim.udid, BUNDLE_ID], { optional: true })]
  if (local) {
    const docs = join(data, 'Documents')
    actions.push(moveAction(`Move the vault in the app's Documents (${counted(folderSummary(docs))}).`, docs, join(MORE, `Simulator ${sim.name} Documents`)))
  }
  const history = join(data, 'Library/Application Support/longbook')
  if (readable(history)) actions.push(moveAction('Move the app\'s own copy of the vault\'s history.', history, join(MORE, `Simulator ${sim.name} history`)))
  for (const step of plan.steps.slice(1)) actions.push(command(step.what, step.command))
  if (group) {
    actions.push(command('Delete the app group\'s settings domain.', ['xcrun', 'simctl', 'spawn', sim.udid, 'defaults', 'delete', join(group, 'Library/Preferences', APP_GROUP)], { optional: true }))
    if (existsSync(join(group, 'widget-copy.json'))) actions.push(removeAction('Delete the widget\'s copy of the vault.', join(group, 'widget-copy.json')))
  }
  for (const rel of ['Library/Caches', 'tmp']) {
    const dir = join(data, rel)
    if (!readable(dir) || !readdirSync(dir).length) continue
    actions.push({ what: `Empty ${rel}.`, shown: `$ rm -rf ${quote(dir)}/*`, run: () => readdirSync(dir).forEach((n) => rmSync(join(dir, n), { recursive: true, force: true })) })
  }
  actions.push(command('Reset the simulator\'s keychain: the session and trial stamp, and every other app\'s items on this simulator.', ['xcrun', 'simctl', 'keychain', sim.udid, 'reset']))
  return { target: plan.target, actions, kept: ['Purchases, which StoreKit keeps.'] }
}

type Phone = { udid: string; name: string }
function pairedPhones(): Phone[] {
  const out = join(mkdtempSync(join(tmpdir(), 'clean-slate-')), 'devices.json')
  if (attempt('xcrun', ['devicectl', 'list', 'devices', '--json-output', out], 30_000) === null) return []
  const devices = (JSON.parse(readFileSync(out, 'utf8')).result?.devices ?? []) as {
    identifier: string; deviceProperties?: { name?: string }; hardwareProperties?: { platform?: string; reality?: string; udid?: string }
    connectionProperties?: { pairingState?: string }
  }[]
  return devices
    .filter((d) => d.hardwareProperties?.platform === 'iOS' && d.hardwareProperties?.reality === 'physical' && d.connectionProperties?.pairingState === 'paired')
    .map((d) => ({ udid: d.hardwareProperties?.udid ?? d.identifier, name: d.deviceProperties?.name ?? 'iPhone' }))
}
function installedBuild(udid: string): string | null | undefined {
  const out = join(mkdtempSync(join(tmpdir(), 'clean-slate-')), 'apps.json')
  if (attempt('xcrun', ['devicectl', 'device', 'info', 'apps', '--device', udid, '--timeout', '30', '--json-output', out], 60_000) === null) return undefined
  const apps = (JSON.parse(readFileSync(out, 'utf8')).result?.apps ?? []) as { bundleIdentifier?: string; bundleVersion?: string }[]
  return apps.find((a) => a.bundleIdentifier === BUNDLE_ID)?.bundleVersion ?? null
}
const plistValue = (plist: string, key: string): string | null => attempt('plutil', ['-extract', key, 'raw', '-o', '-', plist])?.trim() ?? null

function phoneSection(phone: Phone): Section {
  const target = `iPhone ${phone.name} (${phone.udid})`
  const build = installedBuild(phone.udid)
  const reach = build === undefined ? 'It does not answer now; connect and unlock it.' : build === null ? 'longbook is not installed on it.' : `longbook build ${build} is installed.`
  if (!args.reinstall) return { target, actions: [], kept: [reach, NO_IN_PLACE, 'The vault in iCloud: the Mac\'s part of this run moves it, and the iPhone follows once iCloud syncs.'] }
  const app = args.reinstall
  const info = join(app, 'Info.plist')
  const id = existsSync(info) ? plistValue(info, 'CFBundleIdentifier') : null
  const platforms = existsSync(info) ? attempt('plutil', ['-extract', 'CFBundleSupportedPlatforms', 'json', '-o', '-', info]) ?? '' : ''
  const version = existsSync(info) ? plistValue(info, 'CFBundleVersion') : null
  const blocked = build === undefined ? reach
    : id !== BUNDLE_ID || !platforms.includes('iPhoneOS') ? `${app} is not an iPhone build of ${BUNDLE_ID}.` : undefined
  const copyTo = join(MORE, 'iPhone app Documents')
  const devicectl = ['xcrun', 'devicectl', 'device']
  const actions: Action[] = []
  if (build !== null) {
    actions.push(command('Copy the app\'s Documents off the iPhone first: a vault kept "on this iPhone" lives there, and the uninstall would take it.',
      [...devicectl, 'copy', 'from', '--device', phone.udid, '--domain-type', 'appDataContainer', '--domain-identifier', BUNDLE_ID, '--source', 'Documents', '--destination', copyTo]))
    actions.push({ what: 'Count what came off, before anything is removed.', shown: `count files in ${quote(copyTo)}`, run: () => {
      if (!existsSync(copyTo)) throw new Error('Nothing arrived from the iPhone; the app stays installed.')
      console.log(`  ${counted(folderSummary(copyTo))} copied`)
    } })
    actions.push(command('Uninstall longbook: its settings, caches, app group and Documents go.', [...devicectl, 'uninstall', 'app', '--device', phone.udid, BUNDLE_ID]))
  }
  actions.push(command(`Install ${basename(app)} (build ${version ?? '?'}).`, [...devicectl, 'install', 'app', '--device', phone.udid, app]))
  actions.push({ what: 'Check the iPhone reports that build.', shown: `$ xcrun devicectl device info apps --device ${phone.udid}`, run: () => {
    const now = installedBuild(phone.udid)
    if (now !== version) throw new Error(`The iPhone reports build ${now ?? 'none'}, not ${version}.`)
  } })
  return {
    target, actions, blocked,
    kept: [reach, 'The keychain items (session, trial stamp): iOS keeps them through an uninstall. The session ends with the account; the trial stamp stays.',
      'The vault in iCloud: the Mac\'s part of this run moves it, and the iPhone follows once iCloud syncs.'],
  }
}

if (args.device) {
  const sims = bootedSimulators(attempt('xcrun', ['simctl', 'list', 'devices', 'booted', '-j']) ?? '{"devices":{}}')
  const sim = sims.find((s) => s.udid === args.device)
  const phone = sim ? undefined : pairedPhones().find((p) => p.udid === args.device)
  if (sim) sections.push(simulatorSection(sim))
  else if (phone) sections.push(phoneSection(phone))
  else {
    console.error(`No booted simulator or paired iPhone has the id ${args.device}.`)
    process.exit(1)
  }
} else if (wantAutoPhone) {
  const phones = pairedPhones()
  if (phones.length === 1) sections.push(phoneSection(phones[0]))
  else sections.push({ target: 'iPhone', actions: [], kept: [phones.length ? `${phones.length} paired iPhones; name one with --device <udid>.` : 'No paired iPhone. Name one with --device <udid>.'] })
}

// ── The plan ─────────────────────────────────────────────────────────────────────────────────
const browser = [
  'claude.ai › Settings › Connectors: remove longbook.',
  'chatgpt.com › Settings › Apps & Connectors: remove longbook.',
  // The app ends the Apple link with a fresh code from Apple, which only the device can get.
  ...(appleLinked ? ['iPhone Settings › Apple Account › Sign in with Apple › longbook: Stop Using Apple Account.'] : []),
]
console.log(`longbook clean slate — ${args.apply ? 'about to apply' : 'dry run, nothing changes'}\n`)
let n = 0
for (const s of sections) {
  console.log(s.target)
  if (s.blocked) console.log(`  ✗ ${s.blocked}`)
  if (!s.actions.length) console.log('  Nothing to do.')
  for (const a of s.actions) console.log(`  ${++n}. ${a.what}\n     ${a.shown}`)
  if (s.kept.length) console.log(['  Stays, or note:', ...s.kept.map((k) => `  · ${k}`)].join('\n'))
  console.log('')
}
console.log([`Done by hand, by the person running this:`, ...browser.map((b) => `  · ${b}`)].join('\n') + '\n')

const work = sections.filter((s) => s.actions.length)
if (!args.apply) {
  console.log(work.length ? 'Dry run. Add --apply to do the steps above.' : 'Nothing to do.')
  process.exit(0)
}
const blocked = sections.filter((s) => s.blocked)
if (blocked.length) {
  console.error(`Stopped, nothing changed: ${blocked.map((s) => `${s.target}: ${s.blocked}`).join(' ')}`)
  process.exit(1)
}
if (!work.length) process.exit(0)

const typeToConfirm = choice.kind === 'delete' && choice.typeToConfirm
if ((!args.yes || typeToConfirm) && !process.stdin.isTTY) {
  console.error(typeToConfirm ? '--account alone needs its address typed in a terminal. Pass --account <email> instead.'
    : 'Not a terminal, so no answer can be typed. Pass --yes to go ahead.')
  process.exit(1)
}
const rl = createInterface({ input: process.stdin, output: process.stdout })
if (!args.yes && !confirmedPhrase(await rl.question(`Type "${CONFIRM_PHRASE}" to do the steps above: `))) {
  rl.close()
  console.log('Nothing changed.')
  process.exit(1)
}
if (choice.kind === 'delete' && typeToConfirm) {
  const typed = await rl.question(`Type the full address of ${maskEmail(choice.email)} to delete that account: `)
  if (normaliseEmail(typed) !== normaliseEmail(choice.email)) {
    rl.close()
    console.log('That is not the address. Nothing changed.')
    process.exit(1)
  }
}
rl.close()

n = 0
for (const s of work) {
  for (const a of s.actions) {
    n++
    try {
      await a.run()
      console.log(`✓ ${n}. ${s.target}: ${a.what.split(/[.:(]/)[0]}`)
    } catch (error) {
      const stderr = String((error as { stderr?: string }).stderr || (error as Error).message || error)
      if (a.optional || alreadyGone(stderr)) {
        console.log(`– ${n}. ${s.target}: nothing there`)
        continue
      }
      console.error(`✗ ${n}. ${s.target}: ${stderr.trim().split('\n').pop()}`)
      if (notPermitted(stderr)) console.error('  Give this terminal Full Disk Access in Privacy & Security, then run this again.')
      console.error('Stopped here; the steps after this one did not run.')
      process.exit(1)
    }
  }
}
console.log(`\nDone. Then, by hand: ${browser.join(' ')}`)
if (existsSync(BACKUP)) console.log(`Restore the vault with: ${restoreCommand(BACKUP, ICLOUD)}`)
