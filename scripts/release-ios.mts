#!/usr/bin/env -S npx tsx
// The iOS release, one command: archive → export → upload, where the build becomes a
// TestFlight build. Prerequisites are checked up front and each refusal says what to run.
//
// `--check` reports without building; `--no-upload` stops after the export.
import { markOnTestFlight, untestedOnDevices } from './release.mts'
import { carriesFirstUseReset } from './device-build-flag.mts'
import { execFileSync, execSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, readdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

/** The commit this build is made from, marked when the checkout has uncommitted changes. */
const commitStamp = (): string => {
  const sha = execFileSync('git', ['rev-parse', '--short=10', 'HEAD'], { cwd: ROOT, encoding: 'utf8' }).trim()
  const dirty = execFileSync('git', ['status', '--porcelain'], { cwd: ROOT, encoding: 'utf8' }).trim() !== ''
  return dirty ? `${sha}+changes` : sha
}
const APP_DIR = join(ROOT, 'apps/longbook')
const BUILD = join(APP_DIR, 'build/ios')
// Beside the build it belongs to, never in /tmp: the system empties that folder after a
// few days, and a half-emptied package checkout fails the archive with a missing manifest.
const DERIVED = process.env.LONGBOOK_IOS_DERIVED_DATA ?? join(APP_DIR, 'build/derived-ios')
const EXPORT_OPTIONS = join(ROOT, 'scripts/ios-export-options.plist')

const sh = (cmd: string, args: string[], opts: { cwd?: string } = {}): string =>
  execFileSync(cmd, args, { encoding: 'utf8', cwd: opts.cwd, stdio: ['ignore', 'pipe', 'pipe'] })

const version = (): { marketing: string; build: string } => {
  const yml = readFileSync(join(APP_DIR, 'project.yml'), 'utf8')
  const marketing = yml.match(/MARKETING_VERSION: "([^"]+)"/)?.[1]
  const build = yml.match(/CURRENT_PROJECT_VERSION: "([^"]+)"/)?.[1]
  if (!marketing || !build) throw new Error('project.yml carries no version')
  return { marketing, build }
}

// The App Store Connect key, by the three parts Apple asks for. The private half is a file
// on this machine; the two ids sit in the keychain. Nothing is read into a variable that
// could be printed — the paths and ids are handed to xcodebuild and altool directly.
const keychain = (service: string): string | null => {
  try {
    return sh('security', ['find-generic-password', '-s', service, '-w']).trim() || null
  } catch {
    return null
  }
}

const ascKey = (): { path: string; id: string; issuer: string } | null => {
  const id = process.env.ASC_KEY_ID ?? keychain('App Store Connect Key ID')
  const issuer = process.env.ASC_ISSUER_ID ?? keychain('Apple App Store Connect Issuer ID')
  if (!id || !issuer) return null
  // Only where xcodebuild will actually read it. It refuses a key under /private with
  // "must be an absolute path to an existing file" even when the file is there and
  // readable, so a key kept anywhere else has to move rather than be pointed at.
  const home = join(homedir(), `.appstoreconnect/private_keys/AuthKey_${id}.p8`)
  const path = process.env.ASC_KEY_PATH ?? home
  return existsSync(path) ? { path, id, issuer } : null
}

/// Somewhere a key was found that the toolchain will not read — worth saying, because the
/// alternative is looking for a file that is plainly sitting there.
const strandedKey = (id: string): string | null =>
  [`/private/AuthKey_${id}.p8`, join(homedir(), `private/AuthKey_${id}.p8`), join(homedir(), `Downloads/AuthKey_${id}.p8`)]
    .find((p) => existsSync(p)) ?? null

type Check = { name: string; ok: boolean; fix: string }

const preflight = (): Check[] => {
  const checks: Check[] = []

  const key = ascKey()
  const stranded = !key ? strandedKey(process.env.ASC_KEY_ID ?? keychain('App Store Connect Key ID') ?? '') : null

  let identities = ''
  try {
    identities = sh('security', ['find-identity', '-v', '-p', 'codesigning'])
  } catch {
    identities = ''
  }
  // Automatic signing mints this from the key on the first run, so a missing certificate is
  // only a problem when there is no key to mint it with. Reported either way: knowing whether
  // the run will pause to create one is worth a line.
  const hasCert = identities.includes('Apple Distribution')
  checks.push({
    name: 'Apple Distribution certificate',
    ok: hasCert,
    fix: 'Run: npm run asc:provision — it creates the certificate and both profiles, once a year.',
  })

  const profiles = join(homedir(), 'Library/Developer/Xcode/UserData/Provisioning Profiles')
  let storeProfiles = 0
  try {
    storeProfiles = readdirSync(profiles).filter((f) => f.endsWith('.mobileprovision')).length
  } catch {
    storeProfiles = 0
  }
  checks.push({
    name: 'App Store provisioning profiles installed',
    ok: storeProfiles > 0,
    fix: 'Run: npm run asc:provision — it installs them where xcodebuild looks.',
  })
  checks.push({
    name: 'App Store Connect key (both ids and the .p8)',
    ok: key !== null,
    fix: stranded
      ? `The key is at ${stranded}, where xcodebuild will not read it. Move it: mv ${stranded} ~/.appstoreconnect/private_keys/`
      : `Store the key id as "App Store Connect Key ID" and the issuer id as "Apple App Store Connect Issuer ID" in the keychain, and put its AuthKey_<id>.p8 at ~/.appstoreconnect/private_keys/. The id and the file name must be the same key.`,
  })

  let xcodegen = false
  try {
    sh('xcodegen', ['--version'])
    xcodegen = true
  } catch {
    xcodegen = false
  }
  checks.push({
    name: 'xcodegen (the project is generated from project.yml)',
    ok: xcodegen,
    fix: 'brew install xcodegen',
  })

  const manifests = ['Resources/PrivacyInfo.xcprivacy', 'Widget/PrivacyInfo.xcprivacy']
  checks.push({
    name: 'A privacy manifest in the app and in the widget',
    ok: manifests.every((m) => existsSync(join(APP_DIR, m))),
    fix: 'Apple refuses an upload that uses a required-reason API without declaring it. Both bundles need their own manifest.',
  })

  const yml = readFileSync(join(APP_DIR, 'project.yml'), 'utf8')
  checks.push({
    name: 'Export compliance answered in the bundle',
    ok: yml.includes('ITSAppUsesNonExemptEncryption'),
    fix: 'Add ITSAppUsesNonExemptEncryption to the app target\'s info properties, or every build waits on a manual answer.',
  })

  const untested = untestedOnDevices()
  checks.push({
    name: 'The latest device build, unchanged since',
    ok: untested === null,
    fix: untested ?? '',
  })

  return checks
}

const report = (checks: Check[]): boolean => {
  let allOk = true
  for (const c of checks) {
    console.log(`${c.ok ? '✓' : '✗'} ${c.name}`)
    if (!c.ok) {
      console.log(`    → ${c.fix}`)
      allOk = false
    }
  }
  return allOk
}

// The same gate the Mac release keeps: the version that ships must be the version the
// project names. App Store Connect rejects a build whose number it has already seen, and a
// mislabelled one costs an upload and a wait to find out.
const assertExportedVersion = (app: string, marketing: string, build: string): void => {
  const plistValue = (key: string): string => {
    try {
      return sh('/usr/libexec/PlistBuddy', ['-c', `Print :${key}`, join(app, 'Info.plist')]).trim()
    } catch {
      return ''
    }
  }
  const builtMarketing = plistValue('CFBundleShortVersionString')
  const builtBuild = plistValue('CFBundleVersion')
  if (builtMarketing !== marketing || builtBuild !== build) {
    console.error(`The archived app reports version "${builtMarketing}" build "${builtBuild}", but project.yml says "${marketing}" build "${build}".`)
    console.error(`Delete the derived data (rm -rf "${DERIVED}") and release again.`)
    process.exit(1)
  }
  console.log(`  it reports ${builtMarketing} (${builtBuild}), matching project.yml.`)
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
  console.log(`longbook iOS release — ${marketing} (${build})\n`)

  const checks = preflight()
  const ready = report(checks)
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
  console.log('2/4 archiving for a device…')
  execFileSync('xcodebuild', [
    '-project', join(APP_DIR, 'longbook.xcodeproj'),
    '-scheme', 'longbook',
    '-destination', 'generic/platform=iOS',
    '-archivePath', archive,
    '-derivedDataPath', DERIVED,
    '-allowProvisioningUpdates',
    '-authenticationKeyPath', key.path,
    '-authenticationKeyID', key.id,
    '-authenticationKeyIssuerID', key.issuer,
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
  // No -allowProvisioningUpdates here, deliberately: it routes the export through Apple's
  // cloud signing, which refuses this key and then reports it as missing profiles. The export
  // options name the profiles instead, and npm run asc:provision is what puts them there.
  console.log('3/4 exporting for App Store Connect…')
  execFileSync('xcodebuild', [
    '-exportArchive',
    '-archivePath', archive,
    '-exportOptionsPlist', EXPORT_OPTIONS,
    '-exportPath', exported,
  ], { stdio: 'inherit' })

  const ipa = join(exported, 'longbook.ipa')
  if (!existsSync(ipa)) {
    console.error(`The export produced no package at ${ipa}.`)
    process.exit(1)
  }

  if (process.argv.includes('--no-upload')) {
    console.log(`\n4/4 skipped. The package is at:\n  ${ipa}`)
    return
  }

  console.log('4/4 uploading to App Store Connect (this waits on Apple)…')
  execFileSync('xcrun', [
    'altool', '--upload-app', '-f', ipa, '-t', 'ios',
    '--apiKey', key.id, '--apiIssuer', key.issuer,
  ], { stdio: 'inherit' })

  console.log(`\nUploaded ${marketing} (${build}). App Store Connect processes it before it appears in TestFlight — minutes, sometimes longer.`)
  markOnTestFlight()
  console.log(`Recorded build ${build} as on TestFlight in apps/longbook/device-builds.json. Commit that file.`)
  console.log('Internal testers get it without review. A public link needs an external group, which goes through Beta App Review.')
}

main()
