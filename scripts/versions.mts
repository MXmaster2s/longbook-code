#!/usr/bin/env -S npx tsx
// Every piece of longbook and the number it carries, in one table, failing when any is behind.
// Offline it reads the repo (CI runs it); --live also asks the website, the hosted server, the
// plugin repo, npm, the MCP registry and the owner's devices. Run: npm run versions[:live].
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { APP_BUILD, APP_VERSION, MCP_NAME, NPM_NAME, RELEASE_VERSION, ROOT, RULEBOOK, appChangedSince, readLedger } from './release.mts'

const LIVE = process.argv.includes('--live')
type Row = { piece: string; want: string; have: string; ok: boolean | null; fix?: string }
const rows: Row[] = []
const json = (rel: string) => JSON.parse(readFileSync(join(ROOT, rel), 'utf8'))
const add = (piece: string, want: string | number, have: string | number | null | undefined, fix?: string, ok?: boolean | null) =>
  rows.push({ piece, want: String(want), have: have == null ? '—' : String(have), ok: ok !== undefined ? ok : have != null && String(have) === String(want), fix })
const git = (args: string[]): string => execFileSync('git', args, { cwd: ROOT, encoding: 'utf8' }).trim()

// ---- the rulebook, in every copy the repo carries ---------------------------------------------
const revisionIn = (rel: string): number | undefined => {
  if (rel.endsWith('.json')) return json(rel).contract_revision
  return Number(/CONTRACT_REVISION = (\d+)/.exec(readFileSync(join(ROOT, rel), 'utf8'))?.[1])
}
for (const [piece, rel] of [
  ['Rulebook in the servers', 'packages/core/src/contract.ts'],
  ['Rulebook files (core)', 'packages/core/contract/prompts.json'],
  ['Rulebook in the app', 'packages/swift-core/Sources/LongbookCore/Resources/prompts.json'],
  ['Rulebook on the website', 'apps/longbook-site/prompts.json'],
] as const) add(piece, RULEBOOK, revisionIn(rel), 'npm run vault:contract')

// ---- the shared release number --------------------------------------------------------------
const releaseTs = /RELEASE_VERSION = '([^']+)'/.exec(readFileSync(join(ROOT, 'packages/core/src/release.ts'), 'utf8'))?.[1]
add('Version both servers report', RELEASE_VERSION, releaseTs, 'npm run release')
add('npm package (repo)', RELEASE_VERSION, json('packages/mcp/package.json').version, 'npm run release')
add('MCP registry entry (repo)', RELEASE_VERSION, json('packages/mcp/server.json').version, 'npm run release')
add('Claude plugin (repo)', RELEASE_VERSION, json('apps/claude-plugin/plugins/longbook/.claude-plugin/plugin.json').version, 'npm run plugin:claude')

// ---- the app: devices reuse a number until it goes to TestFlight, then take the next --------
const ledger = readLedger()
const highest = Math.max(0, ...Object.keys(ledger).map(Number))
let appOk = APP_BUILD >= highest
let appNote = `${APP_VERSION} (${APP_BUILD})`
let appFix = `Raise CURRENT_PROJECT_VERSION in apps/longbook/project.yml above ${highest} and add its changelog entry.`
const built = ledger[String(APP_BUILD)]
if (appOk && built) {
  let known = true
  try { git(['cat-file', '-e', `${built.commit}^{commit}`]) } catch { known = false }
  if (!known) {
    appOk = false
    appNote += `, made from ${built.commit}, which this checkout does not have`
    appFix = 'Fetch the full history (git fetch --unshallow), or raise the build number.'
  } else if (appChangedSince(built.commit)) {
    if (built.testflight) {
      appOk = false
      appNote += `, on TestFlight since ${built.testflight} as ${built.commit}, and the app has changed since`
      appFix = `Raise CURRENT_PROJECT_VERSION in apps/longbook/project.yml to ${APP_BUILD + 1} and add its changelog entry.`
    } else {
      appNote += `, changed since ${built.commit} on the devices; reinstall before TestFlight`
    }
  }
}
rows.push({ piece: 'App build to make next', want: `${highest}, until it goes to TestFlight`, have: appNote, ok: appOk, fix: appOk ? undefined : appFix })

// ---- live -------------------------------------------------------------------------------------
async function fetchJson(url: string): Promise<any> {
  const response = await fetch(url, { headers: { accept: 'application/json' } })
  if (response.status === 404) return null
  if (!response.ok) throw new Error(`${url} answered ${response.status}`)
  return response.json()
}
const quiet = (cmd: string, args: string[], env: NodeJS.ProcessEnv = process.env): string | null => {
  try { return execFileSync(cmd, args, { cwd: ROOT, encoding: 'utf8', env, stdio: ['ignore', 'pipe', 'pipe'] }) } catch { return null }
}
/** A check that answers on stdout even when it exits 1 to say "these differ". */
const answer = (cmd: string, args: string[], env: NodeJS.ProcessEnv): string | null => {
  try {
    return execFileSync(cmd, args, { cwd: ROOT, encoding: 'utf8', env, stdio: ['ignore', 'pipe', 'pipe'] })
  } catch (error) {
    const out = (error as { stdout?: string }).stdout
    return out ? out : null
  }
}

if (LIVE) {
  const site = await fetchJson('https://longbook.app/prompts.json').catch(() => undefined)
  add('Website rulebook (live)', RULEBOOK, site?.contract_revision, 'npm run site:deploy')

  const token = quiet('security', ['find-generic-password', '-s', 'Supabase Personal-Access Token', '-w'])?.trim()
  const verify = token ? answer('npx', ['tsx', 'scripts/hosted-verify.mts'], { ...process.env, SUPABASE_ACCESS_TOKEN: token }) : null
  const hostedVersion = verify ? /deployed version (\d+)/.exec(verify)?.[1] : undefined
  const same = verify ? /byte for byte/.test(verify) && !/is not what|differs|missing/i.test(verify) : null
  const hostedHave = !token ? 'not checked (no Supabase token in the keychain)'
    : !verify ? 'not checked (the check could not run)'
    : `Supabase v${hostedVersion}${same ? ', same files' : ', different files'}`
  rows.push({ piece: 'Hosted server (live)', want: 'same files as main', have: hostedHave, ok: verify ? same : null, fix: 'npm run deploy:servers' })

  const plugin = await fetchJson('https://raw.githubusercontent.com/MXmaster2s/longbook-claude-plugin/main/plugins/longbook/.claude-plugin/plugin.json').catch(() => undefined)
  add('Claude plugin (live)', RELEASE_VERSION, plugin?.version, 'npm run plugin:claude:publish')

  const npm = await fetchJson(`https://registry.npmjs.org/${NPM_NAME.replace('/', '%2f')}`).catch(() => undefined)
  add('npm package (live)', RELEASE_VERSION, npm === null ? 'not published' : npm?.['dist-tags']?.latest, 'npm run npm:publish')

  const registry = await fetchJson(`https://registry.modelcontextprotocol.io/v0/servers?search=${encodeURIComponent(MCP_NAME)}`).catch(() => undefined)
  const entries = ((registry?.servers ?? []) as { server?: { name?: string; version?: string }; _meta?: Record<string, { isLatest?: boolean }> }[])
    .filter((s) => s.server?.name === MCP_NAME)
  const latest = entries.find((s) => Object.values(s._meta ?? {}).some((m) => m?.isLatest)) ?? entries.at(-1)
  add('MCP registry (live)', RELEASE_VERSION, latest?.server?.version ?? 'not listed', 'npm run registry:publish')

  const devices = quiet('xcrun', ['devicectl', 'list', 'devices'])
  const udid = devices ? /([0-9A-F]{8}-[0-9A-F]{16}) \(UDID\)\s+available \(paired\)/.exec(devices)?.[1] : undefined
  let phoneBuild: string | null | undefined
  if (udid) {
    const out = join(process.env.TMPDIR ?? '/tmp', `longbook-versions-${process.pid}.json`)
    if (quiet('xcrun', ['devicectl', 'device', 'info', 'apps', '--device', udid, '--json-output', out]) !== null) {
      phoneBuild = (JSON.parse(readFileSync(out, 'utf8')).result?.apps ?? []).find((a: { bundleIdentifier?: string }) => a.bundleIdentifier === 'app.longbook.longbook')?.bundleVersion
    }
  }
  const phoneOk = phoneBuild ? Number(phoneBuild) === highest : null
  rows.push({ piece: 'App on the iPhone (live)', want: `build ${highest}`, have: phoneBuild ? `build ${phoneBuild}` : 'not connected', ok: phoneOk })
  const macPlist = '/Applications/longbook.app/Contents/Info.plist'
  const macBuild = existsSync(macPlist) ? quiet('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleVersion', macPlist])?.trim() : undefined
  rows.push({ piece: 'App on the Mac (live)', want: `build ${highest}`, have: macBuild ? `build ${macBuild}` : 'not installed', ok: macBuild ? Number(macBuild) === highest : null })
}

// ---- the table ----------------------------------------------------------------------------------
const width = (k: keyof Row) => Math.max(...rows.map((r) => String(r[k]).length), k.length)
const [w1, w2, w3] = [width('piece'), width('want'), width('have')]
console.log(`longbook ${RELEASE_VERSION} · rulebook ${RULEBOOK} · app ${APP_VERSION} (${APP_BUILD})\n`)
console.log(`   ${'Piece'.padEnd(w1)}  ${'Should be'.padEnd(w2)}  ${'Is'.padEnd(w3)}`)
for (const r of rows) console.log(`${r.ok === null ? ' ·' : r.ok ? ' ✓' : ' ✗'} ${r.piece.padEnd(w1)}  ${r.want.padEnd(w2)}  ${r.have.padEnd(w3)}`)
const behind = rows.filter((r) => r.ok === false)
if (behind.length) {
  console.log('\nBehind:')
  for (const r of behind) console.log(`  ${r.piece}: ${r.fix ?? 'see above'}`)
  process.exit(1)
}
console.log('\nEverything matches.')
