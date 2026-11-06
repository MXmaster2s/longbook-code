#!/usr/bin/env -S npx tsx
// The App Store captures that store:images frames: each screen of the US demo household from a
// Debug build of current code, written to images/screenshots/<platform>/appstore/source.
// macOS only. Nothing shows on screen. Run: npm run store:captures [-- --only ios|mac]

// Mac: a Debug build signed ad hoc, under its own bundle id, with a copy of the Mac entitlements
// that drops the sandbox, the files.* keys and the developer keys. LONGBOOK_SNAPSHOT draws each
// screen offscreen at 1440 x 900 points, twice the pixels: 2880 x 1800.

// iPhone: a simulator build installed on its own iPhone 17 Pro Max simulator, booted with simctl
// and never shown. The demo folder goes in the app's Documents/longbook, the status bar reads
// 9:41 with a full battery, and simctl io screenshot takes 1320 x 2868.

// Every screen is dark; store:images sets it on white. Proposals is taken last, from its own
// copy of the folder, because LONGBOOK_SNAPSHOT_REVIEW writes Claude's proposal into the folder it
// reads. Reports reads a folder dated the last day of last month, so a whole month leads the list.
import { execFileSync } from 'node:child_process'
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const APP_DIR = join(ROOT, 'apps/longbook')
const SHOTS = join(ROOT, 'images/screenshots')
// The harness's own bundle id, so its defaults never mix with an installed longbook's.
const HARNESS_ID = 'app.longbook.storecaptures'
const IOS_ID = 'app.longbook.longbook'
const SIMULATOR = 'iPhone 17 Pro Max (store captures)'
const SIM_TYPE = 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max'

const argv = process.argv.slice(2)
const onlyAt = argv.indexOf('--only')
const only = onlyAt >= 0 ? argv[onlyAt + 1] : undefined
if (only !== undefined && only !== 'ios' && only !== 'mac') {
  console.error('Usage: npm run store:captures [-- --only ios|mac]')
  process.exit(2)
}
if (process.platform !== 'darwin') {
  console.error('store:captures builds the app with Xcode, so it runs on a Mac.')
  process.exit(1)
}

// One capture: its name in the source folder, the harness screen, and what else it needs.
interface Shot { source: string; screen: string; vault?: 'review' | 'month'; env?: Record<string, string> }

// Proposals on its Charges tab, which holds the most of Claude's proposal. AI Connections, iPhone
// only, with the server on, as the harness stages it without a session.
const PROPOSALS: Shot = { source: 'proposals', screen: 'changes', vault: 'review',
  env: { LONGBOOK_SNAPSHOT_REVIEW: 'usd', LONGBOOK_SNAPSHOT_LINE: 'charges' } }
const AI: Shot = { source: 'ai-connections', screen: 'connectai', env: { LONGBOOK_SNAPSHOT_MCP: 'on' } }

// The Mac dashboard is the harness's default, in its shell; naming it would host it alone.
const MAC_SHOTS: Shot[] = [
  { source: 'dashboard', screen: '' },
  { source: 'charges', screen: 'charges' },
  { source: 'reports', screen: 'reports', vault: 'month' },
  { source: 'commitments', screen: 'commitments' },
  { source: 'people', screen: 'members' },
  PROPOSALS,
]
// Calendar and AI Connections are for store:header's product page images.
const IOS_SHOTS: Shot[] = [
  { source: 'dashboard', screen: 'dashboard' },
  { source: 'charges', screen: 'charges' },
  { source: 'reports', screen: 'reports', vault: 'month' },
  { source: 'commitments', screen: 'commitments' },
  { source: 'people', screen: 'members' },
  { source: 'calendar', screen: 'calendar' },
  AI,
  PROPOSALS,
]

const work = mkdtempSync(join(tmpdir(), 'store-captures-'))
const log = join(work, 'build.log')

const run = (cmd: string, args: string[], opts: { cwd?: string; env?: NodeJS.ProcessEnv } = {}): string =>
  execFileSync(cmd, args, { encoding: 'utf8', cwd: opts.cwd, env: opts.env, stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 << 20 })

/** xcodebuild into the work folder, its output in the log; the log's tail on a failure. */
function build(label: string, args: string[]): void {
  console.log(`building ${label}…`)
  try {
    const out = run('xcodebuild', ['-project', join(APP_DIR, 'longbook.xcodeproj'), '-scheme', 'longbook',
      '-configuration', 'Debug', ...args, 'build'])
    writeFileSync(log, out, { flag: 'a' })
  } catch (e) {
    const out = String((e as { stdout?: string }).stdout ?? '')
    writeFileSync(log, out, { flag: 'a' })
    console.error(out.split('\n').filter((l) => l.includes('error:')).slice(0, 10).join('\n') || out.slice(-3000))
    throw new Error(`the ${label} build failed; the whole log is ${log}`)
  }
}

function appIn(folder: string): string {
  const app = readdirSync(folder).find((f) => f.endsWith('.app'))
  if (!app) throw new Error(`no .app in ${folder}`)
  return join(folder, app)
}

/** A fresh demo folder. `today` moves the household's dates, as demo:vault's flag does. */
function demoVault(name: string, today?: string): string {
  const folder = join(work, name)
  run('npx', ['tsx', join(ROOT, 'scripts/demo-vault.mts'), folder, '--household', 'us', ...(today ? ['--today', today] : [])], { cwd: ROOT })
  if (!existsSync(join(folder, '.demo-vault'))) throw new Error(`${folder} is not a demo folder`)
  return folder
}

/** The last day of last month, as YYYY-MM-DD. */
function endOfLastMonth(): string {
  const now = new Date()
  return new Date(Date.UTC(now.getFullYear(), now.getMonth(), 0)).toISOString().slice(0, 10)
}

function pixels(png: string): string {
  const out = run('sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', png])
  const [w, h] = [/pixelWidth: (\d+)/, /pixelHeight: (\d+)/].map((re) => re.exec(out)?.[1])
  return `${w}x${h}`
}

function sourceFolder(platform: 'ios' | 'mac'): string {
  const folder = join(SHOTS, platform, 'appstore/source')
  mkdirSync(folder, { recursive: true })
  return folder
}

// ---- Mac ----------------------------------------------------------------------------------

/** The Mac entitlements less the sandbox, files.* and developer keys an ad hoc signature cannot carry. */
function harnessEntitlements(): string {
  const json = JSON.parse(run('plutil', ['-convert', 'json', '-o', '-', join(APP_DIR, 'LongbookMac.entitlements')])) as Record<string, unknown>
  const kept = Object.fromEntries(Object.entries(json).filter(([key]) =>
    key !== 'com.apple.security.app-sandbox' && !key.startsWith('com.apple.security.files.') && !key.startsWith('com.apple.developer.')))
  const out = join(work, 'harness.entitlements')
  writeFileSync(join(work, 'harness.json'), JSON.stringify(kept))
  run('plutil', ['-convert', 'xml1', '-o', out, join(work, 'harness.json')])
  return out
}

function captureMac(): void {
  const derived = join(work, 'mac')
  build('the Mac harness', ['-destination', 'platform=macOS', '-derivedDataPath', derived,
    'CODE_SIGN_IDENTITY=-', 'CODE_SIGN_STYLE=Manual', 'DEVELOPMENT_TEAM=', 'PROVISIONING_PROFILE_SPECIFIER=',
    `CODE_SIGN_ENTITLEMENTS=${harnessEntitlements()}`, `PRODUCT_BUNDLE_IDENTIFIER=${HARNESS_ID}`])
  const app = appIn(join(derived, 'Build/Products/Debug'))
  // A sandboxed build cannot read the demo folder and silently opens the real vault instead.
  const signed = execFileSync('codesign', ['-d', '--entitlements', '-', '--xml', app], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })
  if (signed.includes('app-sandbox')) throw new Error('the Mac harness came out sandboxed; refusing to run it')
  const binary = join(app, 'Contents/MacOS/longbook')
  const vaults = { main: demoVault('vault-mac'), review: demoVault('vault-mac-review'), month: demoVault('vault-mac-month', endOfLastMonth()) }
  const out = sourceFolder('mac')
  try {
    for (const shot of MAC_SHOTS) {
      const png = join(out, `${shot.source}.png`)
      rmSync(png, { force: true })
      run(binary, ['-appearance', 'dark'], { env: {
        ...process.env, ...shot.env,
        LONGBOOK_VAULT_PATH: vaults[shot.vault ?? 'main'], LONGBOOK_SNAPSHOT: png, ...(shot.screen ? { LONGBOOK_SNAPSHOT_SCREEN: shot.screen } : {}),
        LONGBOOK_SNAPSHOT_WIDTH: '1440', LONGBOOK_SNAPSHOT_HEIGHT: '900', LONGBOOK_SNAPSHOT_SCALE: '2', LONGBOOK_SNAPSHOT_WAIT: '5',
      } })
      if (!existsSync(png)) throw new Error(`the harness wrote no ${shot.source}.png`)
      console.log(`mac/appstore/source/${shot.source}.png ${pixels(png)}`)
    }
  } finally {
    // The harness's defaults, written under its own id, go with it.
    try { run('defaults', ['delete', HARNESS_ID]) } catch { /* none were written */ }
    rmSync(join(homedir(), 'Library/Preferences', `${HARNESS_ID}.plist`), { force: true })
  }
}

// ---- iPhone -------------------------------------------------------------------------------

/** This script's own simulator, made on the newest iOS runtime the first time. */
function simulator(): string {
  const list = JSON.parse(run('xcrun', ['simctl', 'list', '-j', 'devices'])) as { devices: Record<string, { name: string; udid: string }[]> }
  const found = Object.values(list.devices).flat().find((d) => d.name === SIMULATOR)
  if (found) return found.udid
  const runtimes = (JSON.parse(run('xcrun', ['simctl', 'list', '-j', 'runtimes'])) as { runtimes: { identifier: string; platform: string; isAvailable: boolean }[] })
    .runtimes.filter((r) => r.platform === 'iOS' && r.isAvailable)
  const runtime = runtimes.at(-1)
  if (!runtime) throw new Error('no iOS simulator runtime is installed')
  return run('xcrun', ['simctl', 'create', SIMULATOR, SIM_TYPE, runtime.identifier]).trim()
}

function captureIOS(): void {
  const derived = join(work, 'ios')
  build('the iPhone app', ['-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', derived, 'CODE_SIGNING_ALLOWED=NO'])
  const app = appIn(join(derived, 'Build/Products/Debug-iphonesimulator'))
  const udid = simulator()
  const sim = (...args: string[]): string => run('xcrun', ['simctl', ...args])
  // Booted by simctl alone, so no Simulator window opens.
  try { sim('boot', udid) } catch { /* already booted */ }
  sim('bootstatus', udid, '-b')
  sim('ui', udid, 'appearance', 'dark')
  sim('status_bar', udid, 'override', '--time', '9:41', '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3',
    '--cellularMode', 'active', '--cellularBars', '4', '--batteryState', 'discharging', '--batteryLevel', '100')
  const vaults = { main: demoVault('vault-ios'), month: demoVault('vault-ios-month', endOfLastMonth()) }
  // A fresh install each time: a folder swapped under an app that remembers the last one reads as
  // an outside edit, and Proposals' banner would cover the next screen.
  const place = (which: 'main' | 'month'): void => {
    try { sim('uninstall', udid, IOS_ID) } catch { /* not installed */ }
    sim('install', udid, app)
    const documents = join(sim('get_app_container', udid, IOS_ID, 'data').trim(), 'Documents')
    mkdirSync(documents, { recursive: true })
    cpSync(vaults[which], join(documents, 'longbook'), { recursive: true })
  }
  const out = sourceFolder('ios')
  try {
    for (const shot of IOS_SHOTS) {
      try { sim('terminate', udid, IOS_ID) } catch { /* not running */ }
      place(shot.vault === 'month' ? 'month' : 'main')
      const env: NodeJS.ProcessEnv = { ...process.env, SIMCTL_CHILD_LONGBOOK_SKIP_AUTH: '1', SIMCTL_CHILD_LONGBOOK_SNAPSHOT_SCREEN: shot.screen }
      for (const [key, value] of Object.entries(shot.env ?? {})) env[`SIMCTL_CHILD_${key}`] = value
      run('xcrun', ['simctl', 'launch', udid, IOS_ID], { env })
      run('sleep', ['8'])
      const png = join(out, `${shot.source}.png`)
      sim('io', udid, 'screenshot', png)
      const size = pixels(png)
      if (size !== '1320x2868') throw new Error(`${shot.source}.png is ${size}; the 6.9-inch size is 1320x2868`)
      console.log(`ios/appstore/source/${shot.source}.png ${size}`)
    }
  } finally {
    try { sim('uninstall', udid, IOS_ID) } catch { /* not installed */ }
    sim('status_bar', udid, 'clear')
    sim('shutdown', udid)
  }
}

// A build may re-resolve the Swift packages; a pin file that was clean before is put back after.
const PINS = 'packages/swift-core/Package.resolved'
const pinsClean = run('git', ['status', '--porcelain', '--', PINS], { cwd: ROOT }).trim() === ''
try {
  console.log('generating the Xcode project…')
  run('xcodegen', ['generate'], { cwd: APP_DIR })
  if (only !== 'ios') captureMac()
  if (only !== 'mac') captureIOS()
  console.log('Check each capture shows the demo household, then run npm run store:images.')
} finally {
  if (pinsClean) run('git', ['checkout', '--', PINS], { cwd: ROOT })
  rmSync(work, { recursive: true, force: true })
}
