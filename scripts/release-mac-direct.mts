#!/usr/bin/env -S npx tsx
// The direct Mac release: Developer ID export, notarised DMG, Sparkle appcast, GitHub release.
// Run: SPARKLE_PUBLIC_KEY=… <print the Sparkle private key> | npm run release:mac-direct
// `--check` reports without building; `--no-publish` stops before the GitHub release.
import { execFileSync, execSync, spawn, spawnSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, symlinkSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { basename, dirname, join } from 'node:path'
import { isatty } from 'node:tty'
import { fileURLToPath } from 'node:url'
import { markDirect, untestedOnDevices } from './release.mts'
import { carriesFirstUseReset } from './device-build-flag.mts'
import { releases } from './changelog.mts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const APP_DIR = join(ROOT, 'apps/longbook')
const BUILD = join(APP_DIR, 'build/direct')
// Beside the build, never in /tmp — see release-ios.mts.
const DERIVED = join(APP_DIR, 'build/derived-direct')
const EXPORT_OPTIONS = join(ROOT, 'scripts/direct-export-options.plist')
const ENTITLEMENTS = join(APP_DIR, 'LongbookDirect.entitlements')
const INFO_PLIST = join(APP_DIR, 'InfoDirect.plist')
const APPCAST = join(ROOT, 'apps/longbook-site/appcast.xml')
const REPO = 'MXmaster2s/longbook-code'
const TEAM = '27F9SH746V'
const KEY_PLACEHOLDER = 'LONGBOOK_SPARKLE_PUBLIC_KEY'
const CHECK = process.argv.includes('--check')
const NO_PUBLISH = process.argv.includes('--no-publish')

/** The commit this build is made from, marked when the checkout has uncommitted changes. */
const commitStamp = (): string => {
  const sha = execFileSync('git', ['rev-parse', '--short=10', 'HEAD'], { cwd: ROOT, encoding: 'utf8' }).trim()
  const dirty = execFileSync('git', ['status', '--porcelain'], { cwd: ROOT, encoding: 'utf8' }).trim() !== ''
  return dirty ? `${sha}+changes` : sha
}

const sh = (cmd: string, args: string[]): string =>
  execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 << 20 })
const succeeds = (cmd: string, args: string[]): boolean => {
  try {
    sh(cmd, args)
    return true
  } catch {
    return false
  }
}
// Never stdin: it carries the Sparkle private key, for generate_appcast alone.
const run = (cmd: string, args: string[], cwd?: string): void => {
  execFileSync(cmd, args, { cwd, stdio: ['ignore', 'inherit', 'inherit'] })
}

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

// ---- the App Store Connect key, for notarytool and the archive's provisioning --------------
// The key id is the .p8's file name; the issuer id sits in the keychain, as release-mas reads it.
const KEYS = join(homedir(), '.appstoreconnect/private_keys')
const ISSUER_ITEM = 'Apple App Store Connect Issuer ID'

const keyFile = (): { id: string; path: string } | null => {
  const wanted = process.env.ASC_KEY_ID
  const files = existsSync(KEYS) ? readdirSync(KEYS).filter((f) => /^AuthKey_[A-Z0-9]+\.p8$/.test(f)) : []
  const file = wanted ? files.find((f) => f === `AuthKey_${wanted}.p8`) : files.length === 1 ? files[0] : undefined
  return file ? { id: /^AuthKey_([A-Z0-9]+)\.p8$/.exec(file)![1], path: join(KEYS, file) } : null
}

const issuer = (): string | null => {
  if (process.env.ASC_ISSUER_ID) return process.env.ASC_ISSUER_ID
  try {
    return sh('security', ['find-generic-password', '-s', ISSUER_ITEM, '-w']).trim() || null
  } catch {
    return null
  }
}

// ---- signing -----------------------------------------------------------------------------------

/** The full name of this team's Developer ID Application identity, or null. Names only, never hashes. */
const developerId = (): string | null => {
  let out = ''
  try {
    out = sh('security', ['find-identity', '-v', '-p', 'codesigning'])
  } catch {
    return null
  }
  const name = out.split('\n').map((l) => /"(Developer ID Application: [^"]+)"/.exec(l)?.[1]).find((n) => n?.endsWith(`(${TEAM})`))
  return name ?? null
}

const plistString = (file: string, key: string): string => {
  try {
    return sh('/usr/libexec/PlistBuddy', ['-c', `Print :${key}`, file]).trim()
  } catch {
    return ''
  }
}

/** The profile the export options name, whether it is installed, and the developer entitlements it lacks. */
const profile = (): { name: string; installed: boolean; lacks: string[] } => {
  const name = plistString(EXPORT_OPTIONS, 'provisioningProfiles:app.longbook.longbook')
  const dirs = [join(homedir(), 'Library/Developer/Xcode/UserData/Provisioning Profiles'), join(homedir(), 'Library/MobileDevice/Provisioning Profiles')]
  const decoded = dirs.flatMap((d) => (existsSync(d) ? readdirSync(d).filter((f) => f.endsWith('.provisionprofile')).map((f) => join(d, f)) : []))
    .map((file) => {
      try {
        return sh('security', ['cms', '-D', '-i', file])
      } catch {
        return ''
      }
    })
    .find((text) => !!name && text.includes(`<string>${name}</string>`))
  // Signing with an entitlement the profile does not grant fails the export, or the launch.
  const wanted = [...(existsSync(ENTITLEMENTS) ? readFileSync(ENTITLEMENTS, 'utf8') : '').matchAll(/<key>(com\.apple\.developer\.[^<]+)<\/key>/g)].map((m) => m[1])
  return { name, installed: decoded !== undefined, lacks: decoded === undefined ? [] : wanted.filter((k) => !decoded.includes(`<key>${k}</key>`)) }
}

/** An Ed25519 public key as Sparkle prints it: 32 bytes, base64. */
const sparkleKey = (): string | null => {
  const key = process.env.SPARKLE_PUBLIC_KEY?.trim() ?? ''
  return /^[A-Za-z0-9+/]{43}=$/.test(key) ? key : null
}

type Check = { name: string; ok: boolean; fix: string }

const preflight = (): Check[] => {
  const untested = untestedOnDevices()
  const prof = profile()
  const entitlements = existsSync(ENTITLEMENTS) ? readFileSync(ENTITLEMENTS, 'utf8') : ''
  const checks: Check[] = [
    { name: `Developer ID Application certificate for team ${TEAM}`, ok: developerId() !== null, fix: 'Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application.' },
    { name: `Developer ID provisioning profile "${prof.name}"`, ok: prof.installed, fix: 'Xcode makes it: archive longbook-direct once and export with Developer ID, or download it from the developer site. Its name must match scripts/direct-export-options.plist.' },
    { name: 'The profile grants every developer entitlement the app asks for', ok: prof.installed && prof.lacks.length === 0, fix: prof.lacks.length ? `It lacks ${prof.lacks.join(', ')}. Developer ID may not offer it: remove it from LongbookDirect.entitlements, or regenerate the profile if the capability applies.` : 'Install the profile first.' },
    { name: 'App Store Connect key (.p8 and issuer id), for notarytool', ok: keyFile() !== null && (!!process.env.ASC_ISSUER_ID || succeeds('security', ['find-generic-password', '-s', ISSUER_ITEM])), fix: `Put one AuthKey_<id>.p8 in ~/.appstoreconnect/private_keys (or set ASC_KEY_ID) and the issuer id in the keychain as "${ISSUER_ITEM}". See docs/releasing-ios.md.` },
    { name: 'xcodegen', ok: succeeds('xcodegen', ['--version']), fix: 'brew install xcodegen' },
    { name: 'The direct entitlements carry the sandbox and Sparkle\'s installer lookups', ok: entitlements.includes('com.apple.security.app-sandbox') && entitlements.includes('-spki') && entitlements.includes('-spks'), fix: 'edit apps/longbook/LongbookDirect.entitlements' },
    // Developer ID cannot hold it: Apple sign-in on this build goes through the browser.
    { name: 'The direct entitlements leave out Sign in with Apple', ok: !entitlements.includes('com.apple.developer.applesignin'), fix: 'Remove com.apple.developer.applesignin from apps/longbook/LongbookDirect.entitlements.' },
    { name: 'project.yml leaves the Sparkle key placeholder for this script', ok: readFileSync(join(APP_DIR, 'project.yml'), 'utf8').includes(`SUPublicEDKey: ${KEY_PLACEHOLDER}`), fix: `Set the longbook-direct target's SUPublicEDKey to ${KEY_PLACEHOLDER}.` },
    { name: 'SPARKLE_PUBLIC_KEY, the base64 public half of the Sparkle key', ok: sparkleKey() !== null, fix: 'Run Sparkle\'s generate_keys -p (in the Sparkle artifact bundle) and pass what it prints as SPARKLE_PUBLIC_KEY=….' },
    { name: 'The latest device build, unchanged since', ok: untested === null, fix: untested ?? '' },
  ]
  if (!NO_PUBLISH) {
    checks.push({ name: 'gh, signed in', ok: succeeds('gh', ['auth', 'status']), fix: 'brew install gh && gh auth login' })
  }
  if (!CHECK) {
    checks.push({
      name: 'The Sparkle private key on stdin',
      // isatty, not process.stdin: touching that stream can start reading the key.
      ok: !isatty(0),
      fix: "Pipe it in: security find-generic-password -s 'https://sparkle-project.org' -a ed25519 -w | SPARKLE_PUBLIC_KEY=… npm run release:mac-direct",
    })
  }
  return checks
}

const report = (checks: Check[]): boolean => {
  for (const c of checks) {
    console.log(`${c.ok ? '✓' : '✗'} ${c.name}`)
    if (!c.ok && c.fix) console.log(`    → ${c.fix}`)
  }
  return checks.every((c) => c.ok)
}

// ---- gates on what was built -------------------------------------------------------------------

const assertArchived = (app: string, marketing: string, build: string, key: string): void => {
  const info = join(app, 'Contents/Info.plist')
  const builtMarketing = plistString(info, 'CFBundleShortVersionString')
  const builtBuild = plistString(info, 'CFBundleVersion')
  if (builtMarketing !== marketing || builtBuild !== build) {
    console.error(`The archived app reports "${builtMarketing}" (${builtBuild}); project.yml says "${marketing}" (${build}). Delete ${DERIVED} and release again.`)
    process.exit(1)
  }
  console.log(`  it reports ${builtMarketing} (${builtBuild}), matching project.yml.`)
  if (plistString(info, 'SUPublicEDKey') !== key) {
    console.error('The archived app does not carry SPARKLE_PUBLIC_KEY as SUPublicEDKey; Sparkle would refuse every update.')
    process.exit(1)
  }
  if (plistString(info, 'SUFeedURL') !== 'https://longbook.app/appcast.xml') {
    console.error('The archived app has no SUFeedURL; was the longbook-direct scheme archived?')
    process.exit(1)
  }
  console.log('  it carries the Sparkle feed and public key.')
}

const assertSigned = (app: string): void => {
  try {
    sh('codesign', ['--verify', '--strict', '--deep', app])
  } catch (error) {
    console.error(`codesign does not verify the exported app: ${String((error as { stderr?: string }).stderr ?? error).trim()}`)
    process.exit(1)
  }
  // codesign writes its description to stderr.
  const described = spawnSync('codesign', ['-dvv', app], { encoding: 'utf8' })
  const all = `${described.stdout}${described.stderr}`
  if (!/Authority=Developer ID Application: .*\(27F9SH746V\)/.test(all)) {
    console.error('The exported app is not signed with this team\'s Developer ID Application certificate.')
    process.exit(1)
  }
  if (!/flags=0x[0-9a-f]*\(runtime\)/.test(all)) {
    console.error('The exported app is not signed with the hardened runtime; notarisation would refuse it.')
    process.exit(1)
  }
  const entitlements = sh('codesign', ['-d', '--entitlements', '-', '--xml', app])
  if (!entitlements.includes('com.apple.security.app-sandbox') || entitlements.includes('get-task-allow')) {
    console.error('The exported app is not sandboxed, or still allows a debugger to attach.')
    process.exit(1)
  }
  // The export adds this from iCloudContainerEnvironment; without it iCloud Drive fails quietly.
  if (!/icloud-container-environment<\/key>\s*<string>Production<\/string>/.test(entitlements)) {
    console.error('The exported app does not name the production iCloud environment; check scripts/direct-export-options.plist.')
    process.exit(1)
  }
  console.log('  it is signed with Developer ID, the hardened runtime, the sandbox and production iCloud.')
}

/// Signing proves who built it, never that it runs: the exported app must still be running
/// after ten seconds before Apple is asked to notarise it.
const assertRuns = async (app: string): Promise<void> => {
  const child = spawn(join(app, 'Contents/MacOS/longbook'), [], { stdio: 'ignore' })
  let exited: number | null | undefined
  child.on('exit', (code) => { exited = code })
  await new Promise((done) => setTimeout(done, 10_000))
  if (exited !== undefined) {
    console.error(`The exported app quit within ten seconds (exit ${exited}). Open it from ${app} to see why.`)
    process.exit(1)
  }
  child.kill('SIGTERM')
  console.log('  it launched and was still running after ten seconds.')
}

/** Submits a file to Apple's notary service and waits; refuses anything but Accepted. */
const notarise = (file: string, key: { id: string; path: string }, issuerId: string): void => {
  const out = execFileSync('xcrun', [
    'notarytool', 'submit', file, '--key', key.path, '--key-id', key.id, '--issuer', issuerId,
    '--wait', '--output-format', 'json',
  ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] })
  const result = JSON.parse(out) as { id?: string; status?: string }
  if (result.status !== 'Accepted') {
    console.error(`Apple's notary service answered "${result.status ?? 'nothing'}" for ${basename(file)}.`)
    if (result.id) console.error(`Its log: xcrun notarytool log ${result.id} --key <the .p8> --key-id <id> --issuer <issuer id>`)
    process.exit(1)
  }
  console.log(`  accepted (${result.id}).`)
}

/** generate_appcast from the Sparkle package the archive fetched. */
const findGenerateAppcast = (): string | null => {
  const root = join(DERIVED, 'SourcePackages/artifacts')
  if (!existsSync(root)) return null
  const walk = (dir: string, depth: number): string | null => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name)
      if (name === 'generate_appcast' && statSync(path).isFile()) return path
      if (depth < 6 && statSync(path).isDirectory()) {
        const found = walk(path, depth + 1)
        if (found) return found
      }
    }
    return null
  }
  return walk(root, 0)
}

const escape = (text: string): string => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

/** Sparkle shows this beside the update: the version's changes, as changelog.json lists them. */
const releaseNotes = (marketing: string): string => {
  const changes = [...new Set(releases(readFileSync(join(APP_DIR, 'Resources/changelog.json'), 'utf8'))
    .filter((r) => r.version === marketing).flatMap((r) => r.changes))]
    .filter((c) => !c.startsWith('Nothing you will see'))
  return `<h2>longbook ${escape(marketing)}</h2>\n<ul>\n${changes.map((c) => `  <li>${escape(c)}</li>`).join('\n')}\n</ul>\n`
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

const main = async () => {
  const { marketing, build } = version()
  const tag = `mac-${marketing}-${build}`
  const dmgName = `longbook-${marketing}-${build}.dmg`
  console.log(`longbook direct Mac release — ${marketing} (${build})\n`)
  const ready = report(preflight())
  if (CHECK) {
    console.log(ready ? '\nEverything is in place. Run without --check to release.' : '\nNot ready yet — the fixes above are the whole list.')
    process.exit(ready ? 0 : 1)
  }
  if (!ready) {
    console.error('\nNot ready. The list above is the whole of it.')
    process.exit(1)
  }
  const key = keyFile()!
  const issuerId = issuer()
  if (!issuerId) {
    console.error(`The keychain item "${ISSUER_ITEM}" could not be read.`)
    process.exit(1)
  }
  const publicKey = sparkleKey()!
  const identity = developerId()!

  console.log('\n1/9 generating the project and writing the Sparkle public key…')
  run('xcodegen', ['generate'], APP_DIR)
  // The generated plist only; project.yml keeps the placeholder.
  run('/usr/libexec/PlistBuddy', ['-c', `Set :SUPublicEDKey ${publicKey}`, INFO_PLIST])

  mkdirSync(BUILD, { recursive: true })
  healPackages()
  const archive = join(BUILD, 'longbook.xcarchive')
  console.log('2/9 archiving longbook-direct…')
  run('xcodebuild', [
    '-project', join(APP_DIR, 'longbook.xcodeproj'), '-scheme', 'longbook-direct',
    '-destination', 'generic/platform=macOS', '-configuration', 'Release',
    '-archivePath', archive, '-derivedDataPath', DERIVED,
    '-allowProvisioningUpdates',
    '-authenticationKeyPath', key.path, '-authenticationKeyID', key.id, '-authenticationKeyIssuerID', issuerId,
    `LONGBOOK_COMMIT=${commitStamp()}`,
    'archive',
  ])
  assertArchived(join(archive, 'Products/Applications/longbook.app'), marketing, build, publicKey)
  // A device build's reset must never reach anyone else's Mac.
  if (carriesFirstUseReset(join(archive, 'Products/Applications/longbook.app'))) {
    console.error('The archived app carries the device-build reset, which only device:install builds may. Archive again from a clean derived data folder.')
    process.exit(1)
  }

  const exported = join(BUILD, 'export')
  execSync(`rm -rf "${exported}"`)
  // No -allowProvisioningUpdates here: the export options name the Developer ID profile.
  console.log('3/9 exporting with Developer ID…')
  run('xcodebuild', ['-exportArchive', '-archivePath', archive, '-exportOptionsPlist', EXPORT_OPTIONS, '-exportPath', exported])
  const app = join(exported, 'longbook.app')
  if (!existsSync(app)) {
    console.error(`The export produced no app at ${app}.`)
    process.exit(1)
  }
  assertSigned(app)

  console.log('4/9 opening the exported app…')
  await assertRuns(app)

  console.log('5/9 notarising the app (this waits on Apple)…')
  const zip = join(BUILD, 'longbook.zip')
  execSync(`rm -f "${zip}"`)
  run('ditto', ['-c', '-k', '--keepParent', app, zip])
  notarise(zip, key, issuerId)
  run('xcrun', ['stapler', 'staple', app])
  run('xcrun', ['stapler', 'validate', app])

  console.log('6/9 building the DMG…')
  const staging = join(BUILD, 'dmg')
  execSync(`rm -rf "${staging}"`)
  mkdirSync(staging, { recursive: true })
  run('ditto', [app, join(staging, 'longbook.app')])
  symlinkSync('/Applications', join(staging, 'Applications'))
  const feed = join(BUILD, 'appcast')
  execSync(`rm -rf "${feed}"`)
  mkdirSync(feed, { recursive: true })
  const dmg = join(feed, dmgName)
  run('hdiutil', ['create', '-volname', 'longbook', '-srcfolder', staging, '-fs', 'HFS+', '-format', 'UDZO', '-ov', dmg])
  run('codesign', ['--sign', identity, '--timestamp', dmg])

  console.log('7/9 notarising the DMG…')
  notarise(dmg, key, issuerId)
  run('xcrun', ['stapler', 'staple', dmg])
  try {
    sh('spctl', ['--assess', '--type', 'open', '--context', 'context:primary-signature', '-v', dmg])
  } catch (error) {
    console.error(`Gatekeeper refuses the DMG: ${String((error as { stderr?: string }).stderr ?? error).trim()}`)
    process.exit(1)
  }
  console.log('  Gatekeeper accepts it.')

  console.log('8/9 adding it to the appcast…')
  const generate = findGenerateAppcast()
  if (!generate) {
    console.error(`No generate_appcast under ${join(DERIVED, 'SourcePackages/artifacts')}; the archive should have fetched Sparkle there.`)
    process.exit(1)
  }
  writeFileSync(join(feed, dmgName.replace(/\.dmg$/, '.html')), releaseNotes(marketing))
  // generate_appcast updates a feed it finds beside the archives, keeping its earlier entries.
  if (existsSync(APPCAST)) copyFileSync(APPCAST, join(feed, 'appcast.xml'))
  execFileSync(generate, [
    '--ed-key-file', '-',
    '--download-url-prefix', `https://github.com/${REPO}/releases/download/${tag}/`,
    '--embed-release-notes',
    '-o', APPCAST,
    feed,
  ], { stdio: ['inherit', 'inherit', 'inherit'] })
  const appcast = readFileSync(APPCAST, 'utf8')
  if (!appcast.includes(`${tag}/${dmgName}`) || !appcast.includes('sparkle:edSignature')) {
    console.error(`${APPCAST} does not list ${dmgName} with an EdDSA signature.`)
    process.exit(1)
  }
  copyFileSync(dmg, join(BUILD, dmgName))
  console.log(`  ${APPCAST} lists ${dmgName}.`)

  if (NO_PUBLISH) {
    console.log(`\n9/9 skipped. The DMG is at:\n  ${join(BUILD, dmgName)}`)
    return
  }
  console.log(`9/9 creating the GitHub release ${tag}…`)
  const notes = join(BUILD, 'release-notes.md')
  writeFileSync(notes, `longbook for Mac ${marketing} (${build}), notarised by Apple. Updates arrive through the app.\n`)
  run('gh', ['release', 'create', tag, join(BUILD, dmgName), '--repo', REPO, '--title', `longbook for Mac ${marketing} (${build})`, '--notes-file', notes])

  markDirect()
  console.log(`\nReleased ${marketing} (${build}) at https://github.com/${REPO}/releases/tag/${tag}.`)
  console.log('Recorded it in apps/longbook/device-builds.json. Commit that file and apps/longbook-site/appcast.xml;')
  console.log('Sparkle offers the update once the site is deployed with the new appcast (npm run site:deploy).')
}

await main()
