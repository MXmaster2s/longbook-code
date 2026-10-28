#!/usr/bin/env -S npx tsx
// Builds the Mac app for the Mac App Store and uploads it to App Store Connect, where it
// reaches TestFlight for Mac and, on submission, the store. Run: npm run release:mas.
// `--check` reports without building; `--no-upload` stops after the export.
import { execFileSync, execSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, readdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { markOnTestFlight, untestedOnDevices } from './release.mts'
import { carriesFirstUseReset } from './device-build-flag.mts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

/** The commit this build is made from, marked when the checkout has uncommitted changes. */
const commitStamp = (): string => {
  const sha = execFileSync('git', ['rev-parse', '--short=10', 'HEAD'], { cwd: ROOT, encoding: 'utf8' }).trim()
  const dirty = execFileSync('git', ['status', '--porcelain'], { cwd: ROOT, encoding: 'utf8' }).trim() !== ''
  return dirty ? `${sha}+changes` : sha
}
const APP_DIR = join(ROOT, 'apps/longbook')
const BUILD = join(APP_DIR, 'build/mas')
// Beside the build, never in /tmp — see release-ios.mts.
const DERIVED = join(APP_DIR, 'build/derived-mas')
const EXPORT_OPTIONS = join(ROOT, 'scripts/mas-export-options.plist')

const sh = (cmd: string, args: string[]): string =>
  execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })

const version = (): { marketing: string; build: string } => {
  const yml = readFileSync(join(APP_DIR, 'project.yml'), 'utf8')
  const marketing = /MARKETING_VERSION:\s*"([^"]+)"/.exec(yml)?.[1]
  const build = /CURRENT_PROJECT_VERSION:\s*"([^"]+)"/.exec(yml)?.[1]
  if (!marketing || !build) {
    console.error('project.yml carries no MARKETING_VERSION / CURRENT_PROJECT_VERSION.')
    process.exit(1)
  }
  return { marketing, build }
}

const keychain = (service: string): string | null => {
  try {
    return sh('security', ['find-generic-password', '-s', service, '-w']).trim()
  } catch {
    return null
  }
}

const ascKey = (): { id: string; issuer: string; path: string } | null => {
  const id = keychain('App Store Connect Key ID')
  const issuer = keychain('Apple App Store Connect Issuer ID')
  if (!id || !issuer) return null
  const path = join(homedir(), `.appstoreconnect/private_keys/AuthKey_${id}.p8`)
  return existsSync(path) ? { id, issuer, path } : null
}

type Check = { ok: boolean; what: string; fix?: string }

const preflight = (): Check[] => {
  const identities = (() => {
    try {
      return sh('security', ['find-identity', '-v', '-p', 'codesigning'])
    } catch {
      return ''
    }
  })()
  const installer = (() => {
    try {
      return sh('security', ['find-identity', '-v'])
    } catch {
      return ''
    }
  })()
  const untested = untestedOnDevices()
  const profiles = join(homedir(), 'Library/Developer/Xcode/UserData/Provisioning Profiles')
  const hasMacProfile = existsSync(profiles) && sh('ls', [profiles]).split('\n').some((f) => f.endsWith('.provisionprofile'))
  return [
    { ok: identities.includes('Apple Distribution'), what: 'Apple Distribution certificate', fix: 'npm run asc:provision' },
    { ok: installer.includes('3rd Party Mac Developer Installer'), what: 'Mac Installer Distribution certificate', fix: 'npm run asc:provision' },
    { ok: hasMacProfile, what: 'Mac App Store provisioning profile installed', fix: 'npm run asc:provision' },
    { ok: ascKey() !== null, what: 'App Store Connect key (both ids and the .p8)', fix: 'see docs/releasing-ios.md' },
    { ok: (() => { try { sh('xcodegen', ['--version']); return true } catch { return false } })(), what: 'xcodegen', fix: 'brew install xcodegen' },
    { ok: readFileSync(join(APP_DIR, 'LongbookMac.entitlements'), 'utf8').includes('com.apple.security.app-sandbox'), what: 'The Mac entitlements carry the sandbox', fix: 'edit apps/longbook/LongbookMac.entitlements' },
    // TestFlight ships what was tested: the latest build on the owner's devices, unchanged since.
    { ok: untested === null, what: 'The latest device build, unchanged since', fix: untested ?? '' },
  ]
}

const report = (checks: Check[]): boolean => {
  for (const c of checks) console.log(`${c.ok ? '✓' : '✗'} ${c.what}${c.ok || !c.fix ? '' : ` — ${c.fix}`}`)
  return checks.every((c) => c.ok)
}

const assertExportedVersion = (app: string, marketing: string, build: string) => {
  const plistValue = (key: string): string => {
    try {
      return sh('/usr/libexec/PlistBuddy', ['-c', `Print :${key}`, join(app, 'Contents/Info.plist')]).trim()
    } catch {
      return ''
    }
  }
  const builtMarketing = plistValue('CFBundleShortVersionString')
  const builtBuild = plistValue('CFBundleVersion')
  if (builtMarketing !== marketing || builtBuild !== build) {
    console.error(`The archived app reports "${builtMarketing}" (${builtBuild}); project.yml says "${marketing}" (${build}). Delete ${DERIVED} and release again.`)
    process.exit(1)
  }
  console.log(`  it reports ${builtMarketing} (${builtBuild}), matching project.yml.`)
  const entitlements = sh('codesign', ['-d', '--entitlements', '-', '--xml', app])
  if (!entitlements.includes('com.apple.security.app-sandbox')) {
    console.error('The archived app is not sandboxed; the Mac App Store refuses it.')
    process.exit(1)
  }
  console.log('  it is sandboxed.')
}

/// A package checkout missing its manifest stops the archive with a puzzle. Dropping the
/// fetched packages costs one download and clears it.
const healPackages = (): void => {
  const packages = join(DERIVED, 'SourcePackages')
  const checkouts = join(packages, 'checkouts')
  if (!existsSync(checkouts)) return
  if (!readdirSync(checkouts).some((name) => !existsSync(join(checkouts, name, 'Package.swift')))) return
  console.log('  a fetched package is incomplete — fetching them again.')
  execSync(`rm -rf "${packages}"`)
}

const main = () => {
  const { marketing, build } = version()
  console.log(`longbook Mac App Store release — ${marketing} (${build})\n`)
  const ready = report(preflight())
  if (process.argv.includes('--check')) {
    console.log(ready ? '\nEverything is in place. Run without --check to release.' : '\nNot ready yet — the fixes above are the whole list.')
    process.exit(ready ? 0 : 1)
  }
  if (!ready) {
    console.error('\nNot ready. The list above is the whole of it.')
    process.exit(1)
  }
  const key = ascKey()!

  console.log('\n1/4 generating the project…')
  execFileSync('xcodegen', ['generate'], { cwd: APP_DIR, stdio: 'inherit' })

  mkdirSync(BUILD, { recursive: true })
  healPackages()
  const archive = join(BUILD, 'longbook.xcarchive')
  console.log('2/4 archiving for the Mac…')
  execFileSync('xcodebuild', [
    '-project', join(APP_DIR, 'longbook.xcodeproj'), '-scheme', 'longbook',
    '-destination', 'generic/platform=macOS', '-configuration', 'Release',
    '-archivePath', archive, '-derivedDataPath', DERIVED,
    '-allowProvisioningUpdates',
    '-authenticationKeyPath', key.path, '-authenticationKeyID', key.id, '-authenticationKeyIssuerID', key.issuer,
    `LONGBOOK_COMMIT=${commitStamp()}`,
    'archive',
  ], { stdio: 'inherit' })
  assertExportedVersion(join(archive, 'Products/Applications/longbook.app'), marketing, build)
  // A device build's reset must never reach TestFlight or the App Store.
  if (carriesFirstUseReset(join(archive, 'Products/Applications/longbook.app'))) {
    console.error('The archived app carries the device-build reset, which only device:install builds may. Archive again from a clean derived data folder.')
    process.exit(1)
  }

  const exported = join(BUILD, 'export')
  execSync(`rm -rf "${exported}"`)
  console.log('3/4 exporting for App Store Connect…')
  execFileSync('xcodebuild', [
    '-exportArchive', '-archivePath', archive, '-exportOptionsPlist', EXPORT_OPTIONS, '-exportPath', exported,
  ], { stdio: 'inherit' })
  const pkg = join(exported, 'longbook.pkg')
  if (!existsSync(pkg)) {
    console.error(`The export produced no package at ${pkg}.`)
    process.exit(1)
  }
  if (process.argv.includes('--no-upload')) {
    console.log(`\n4/4 skipped. The package is at:\n  ${pkg}`)
    return
  }
  console.log('4/4 uploading to App Store Connect (this waits on Apple)…')
  execFileSync('xcrun', ['altool', '--upload-app', '-f', pkg, '-t', 'macos', '--apiKey', key.id, '--apiIssuer', key.issuer], { stdio: 'inherit' })
  console.log(`\nUploaded ${marketing} (${build}) for the Mac. It appears in TestFlight for Mac once Apple has processed it.`)
  markOnTestFlight()
  console.log(`Recorded build ${build} as on TestFlight in apps/longbook/device-builds.json. Commit that file.`)
}

main()
