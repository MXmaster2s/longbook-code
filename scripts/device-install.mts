#!/usr/bin/env -S npx tsx
// Builds this checkout onto the owner's iPhone and Mac, the first step of every release. It
// refuses uncommitted changes, a device holding a newer build, and a number TestFlight already
// has for a different app, and records the commit. Run: npm run device:install [-- --ios-only | --mac-only] [--device <udid>]
import { execFileSync } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { join } from 'node:path'
import { APP_BUILD, APP_VERSION, ROOT, appChangedSince, readLedger, writeLedger } from './release.mts'

const argv = process.argv.slice(2)
const iosOnly = argv.includes('--ios-only')
const macOnly = argv.includes('--mac-only')
const deviceAt = argv.indexOf('--device')
const APP_DIR = join(ROOT, 'apps/longbook')
const MAC_APP = '/Applications/longbook.app'

const run = (cmd: string, args: string[], cwd = ROOT): string => execFileSync(cmd, args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
const stop = (message: string): never => {
  console.error(message)
  process.exit(1)
}

if (run('git', ['status', '--porcelain']).trim()) {
  stop('This checkout has uncommitted changes. Commit them first, so the build is one exact commit.')
}
const commit = run('git', ['rev-parse', '--short=10', 'HEAD']).trim()

type Device = { identifier: string; name: string; build: number | null }
function iphone(): Device {
  const out = join(mkdtempSync(join(tmpdir(), 'longbook-devices-')), 'list.json')
  run('xcrun', ['devicectl', 'list', 'devices', '--json-output', out])
  const devices = (JSON.parse(readFileSync(out, 'utf8')).result?.devices ?? []) as {
    identifier: string
    deviceProperties?: { name?: string }
    hardwareProperties?: { platform?: string; reality?: string; udid?: string }
    connectionProperties?: { pairingState?: string }
  }[]
  const wanted = deviceAt >= 0 ? argv[deviceAt + 1] : undefined
  const phone = devices.find((d) =>
    wanted ? d.hardwareProperties?.udid === wanted || d.identifier === wanted
      : d.hardwareProperties?.platform === 'iOS' && d.hardwareProperties?.reality === 'physical' && d.connectionProperties?.pairingState === 'paired')
  if (!phone) stop('No paired iPhone found. Connect and unlock it, or name it with --device <udid>.')
  const udid = phone!.hardwareProperties?.udid ?? phone!.identifier
  const apps = join(mkdtempSync(join(tmpdir(), 'longbook-apps-')), 'apps.json')
  run('xcrun', ['devicectl', 'device', 'info', 'apps', '--device', udid, '--json-output', apps])
  const installed = (JSON.parse(readFileSync(apps, 'utf8')).result?.apps ?? []) as { bundleIdentifier?: string; bundleVersion?: string }[]
  const ours = installed.find((a) => a.bundleIdentifier === 'app.longbook.longbook')
  return { identifier: udid, name: phone!.deviceProperties?.name ?? 'iPhone', build: ours?.bundleVersion ? Number(ours.bundleVersion) : null }
}

const macBuild = (): number | null => {
  if (!existsSync(MAC_APP)) return null
  return Number(run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleVersion', join(MAC_APP, 'Contents/Info.plist')]).trim())
}

// TestFlight installs the Mac app as root and updates it on its own, so the swap below
// cannot move it. Said before the build, with the one command that clears the way.
if (!iosOnly && existsSync(MAC_APP) && statSync(MAC_APP).uid !== process.getuid?.()) {
  stop('/Applications/longbook.app was installed by TestFlight and only your password can move it. In TestFlight on ' +
    'this Mac, turn off Automatic Updates for longbook (or Stop Testing), then run:\n' +
    '  sudo mv /Applications/longbook.app ~/.Trash/longbook-testflight.app\nand install again.')
}
const phone = macOnly ? null : iphone()
const onMac = iosOnly ? null : macBuild()
// The devices reuse a number until it goes to TestFlight; after that a changed app takes the next.
const shipped = readLedger()[String(APP_BUILD)]
if (shipped?.testflight && appChangedSince(shipped.commit)) {
  stop(`Build ${APP_BUILD} went to TestFlight on ${shipped.testflight}, and the app has changed since. Raise ` +
    `CURRENT_PROJECT_VERSION in apps/longbook/project.yml to ${APP_BUILD + 1} and add its changelog entry.`)
}
for (const [where, build] of [['your iPhone', phone?.build], ['your Mac', onMac]] as const) {
  if (build != null && build > APP_BUILD) {
    stop(`Build ${build} is already on ${where}, newer than the ${APP_BUILD} project.yml builds. Raise CURRENT_PROJECT_VERSION ` +
      'in apps/longbook/project.yml and add its changelog entry.')
  }
}

const keychain = (service: string): string => run('security', ['find-generic-password', '-s', service, '-w']).trim()
const keyId = keychain('App Store Connect Key ID')
const issuer = keychain('Apple App Store Connect Issuer ID')
const keyPath = join(homedir(), '.appstoreconnect/private_keys', `AuthKey_${keyId}.p8`)
const derived = mkdtempSync(join(tmpdir(), 'longbook-device-build-'))

function build(destination: string): void {
  execFileSync('xcodebuild', [
    '-project', join(APP_DIR, 'longbook.xcodeproj'), '-scheme', 'longbook', '-configuration', 'Release',
    '-destination', destination, '-derivedDataPath', derived, '-allowProvisioningUpdates',
    '-authenticationKeyPath', keyPath, '-authenticationKeyID', keyId, '-authenticationKeyIssuerID', issuer,
    `LONGBOOK_COMMIT=${commit}`, 'build',
  ], { cwd: APP_DIR, stdio: ['ignore', 'ignore', 'inherit'] })
}

try {
  console.log(`Building ${APP_VERSION} (${APP_BUILD}) from ${commit}…`)
  run('xcodegen', ['generate'], APP_DIR)
  if (phone) {
    build(`id=${phone.identifier}`)
    run('xcrun', ['devicectl', 'device', 'install', 'app', '--device', phone.identifier,
      join(derived, 'Build/Products/Release-iphoneos/longbook.app')])
    const now = iphone().build
    if (now !== APP_BUILD) stop(`${phone.name} reports build ${now} after the install, not ${APP_BUILD}.`)
    console.log(`${phone.name}: ${APP_VERSION} (${APP_BUILD}) installed.`)
  }
  if (!iosOnly) {
    build('platform=macOS')
    // Never opened here: the owner opens the new build himself.
    try { run('osascript', ['-e', 'tell application "longbook" to quit']) } catch { /* not running */ }
    if (onMac != null) {
      // Stamped, so a --same-build swap never lands on the folder an earlier swap left.
      const trash = join(homedir(), '.Trash', `longbook-old-build${onMac}-${Date.now()}`)
      run('mkdir', ['-p', trash])
      run('mv', [MAC_APP, trash])
    }
    run('ditto', [join(derived, 'Build/Products/Release/longbook.app'), MAC_APP])
    if (macBuild() !== APP_BUILD) stop(`/Applications/longbook.app is not build ${APP_BUILD} after the swap.`)
    console.log(`Mac: ${APP_VERSION} (${APP_BUILD}) in Applications${onMac != null ? `, build ${onMac} in the Trash` : ''}.`)
  }
} finally {
  rmSync(derived, { recursive: true, force: true })
}

const ledger = readLedger()
// A reinstall of the same app keeps its TestFlight mark; a changed app never reaches here with one.
const kept = ledger[String(APP_BUILD)]?.testflight
ledger[String(APP_BUILD)] = { version: APP_VERSION, commit, installed: new Date().toISOString().slice(0, 10), ...(kept ? { testflight: kept } : {}) }
writeLedger(ledger)
console.log(`Recorded build ${APP_BUILD} = ${commit} in apps/longbook/device-builds.json. Commit that file.`)
