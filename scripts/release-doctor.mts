#!/usr/bin/env -S npx tsx
// Says what this Mac lacks for release:mas and release:ios, before either starts. Reads only:
// it never prints a secret and never opens a keychain item's contents. Run: npm run release:doctor.
// `--quick` skips xcodegen and xcodebuild. Under CI, checks needing this Mac's keychain are skipped.
import { execFileSync } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs'
import { homedir, platform, tmpdir } from 'node:os'
import { join } from 'node:path'
import { ROOT, untestedOnDevices } from './release.mts'
import {
  assetChecks, buildSettingChecks, entitlementChecks, failed, fail, parseBuildSettings, pass, render,
  signingChecks, skip, versionChecks, type Check,
} from './release-doctor-checks.mts'

const APP_DIR = join(ROOT, 'apps/longbook')
const QUICK = process.argv.includes('--quick')
const ci = process.env.CI ? 'CI has no signing keychain' : platform() !== 'darwin' ? 'not a Mac' : null

const readOrNull = (path: string): string | null => (existsSync(path) ? readFileSync(path, 'utf8') : null)
const run = (cmd: string, args: string[], timeout = 60_000): string =>
  execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout, maxBuffer: 64 << 20 })
const succeeds = (cmd: string, args: string[]): boolean => {
  try {
    run(cmd, args)
    return true
  } catch {
    return false
  }
}

const yml = readFileSync(join(APP_DIR, 'project.yml'), 'utf8')
const checks: Check[] = [
  ...versionChecks(yml, readFileSync(join(APP_DIR, 'Resources/changelog.json'), 'utf8'), readFileSync(join(ROOT, 'release.json'), 'utf8')),
  ...entitlementChecks(Object.fromEntries(['Longbook.entitlements', 'LongbookMac.entitlements', 'Widget.entitlements']
    .map((f) => [f, readOrNull(join(APP_DIR, f))])), yml),
  ...assetChecks(yml, (rel) => existsSync(join(APP_DIR, rel)), (rel) => readOrNull(join(APP_DIR, rel))),
]

const local = (names: string[], body: () => Check[]): Check[] => (ci ? names.map((n) => skip(n, ci)) : body())

checks.push(...local(['Signing certificates'], () => {
  const identities = (args: string[]): string => {
    try {
      return run('security', ['find-identity', '-v', ...args])
    } catch {
      return ''
    }
  }
  return signingChecks(yml, identities(['-p', 'codesigning']), identities([]))
}))

checks.push(...local(['Provisioning profiles'], () => {
  const dirs = [join(homedir(), 'Library/Developer/Xcode/UserData/Provisioning Profiles'), join(homedir(), 'Library/MobileDevice/Provisioning Profiles')]
  const files = dirs.flatMap((d) => (existsSync(d) ? readdirSync(d) : []))
  const mac = files.filter((f) => f.endsWith('.provisionprofile')).length
  const ios = files.filter((f) => f.endsWith('.mobileprovision')).length
  return [
    mac ? pass('Mac App Store provisioning profile', `${mac} installed`) : fail('Mac App Store provisioning profile', 'None installed. Run: npm run asc:provision'),
    ios ? pass('App Store provisioning profiles', `${ios} installed`) : fail('App Store provisioning profiles', 'None installed. Run: npm run asc:provision'),
  ]
}))

// Presence only: without -w the keychain hands back the item's label, never its secret.
checks.push(...local(['App Store Connect key'], () => {
  const items = ['App Store Connect Key ID', 'Apple App Store Connect Issuer ID']
  const absent = items.filter((s) => !succeeds('security', ['find-generic-password', '-s', s]))
  const keys = join(homedir(), '.appstoreconnect/private_keys')
  const p8 = existsSync(keys) && readdirSync(keys).some((f) => /^AuthKey_.+\.p8$/.test(f))
  const problems = [
    absent.length ? `no keychain item "${absent.join('", "')}"` : '',
    p8 ? '' : 'no AuthKey_<id>.p8 in ~/.appstoreconnect/private_keys',
  ].filter(Boolean)
  return [problems.length ? fail('App Store Connect key', `${problems.join('; ')}. See docs/releasing-ios.md`) : pass('App Store Connect key', 'both keychain items and a .p8')]
}))

checks.push(...local(['The build on your devices'], () => {
  const untested = untestedOnDevices()
  return [untested ? fail('The build on your devices, unchanged since', untested) : pass('The build on your devices, unchanged since')]
}))

checks.push(...local(['xcodegen', 'The project generates', 'The Mac build settings'], () => {
  let version = ''
  try {
    version = run('xcodegen', ['--version']).trim()
  } catch {
    return [fail('xcodegen', 'Not installed. Run: brew install xcodegen'), skip('The project generates', 'no xcodegen'), skip('The Mac build settings', 'no xcodegen')]
  }
  const out: Check[] = [pass('xcodegen', version.replace(/^Version:\s*/, ''))]
  if (QUICK) return [...out, skip('The project generates', '--quick'), skip('The Mac build settings', '--quick')]
  // Generated into a scratch folder, so the checkout's own project is left as it was.
  const scratch = mkdtempSync(join(tmpdir(), 'longbook-doctor-'))
  try {
    try {
      run('xcodegen', ['generate', '--quiet', '--spec', join(APP_DIR, 'project.yml'), '--project', scratch], 120_000)
      out.push(pass('The project generates'))
    } catch (error) {
      out.push(fail('The project generates', String((error as { stderr?: string }).stderr || error).trim().split('\n').slice(-3).join(' ')))
      return [...out, skip('The Mac build settings', 'the project did not generate')]
    }
    try {
      const settings = run('xcodebuild', [
        '-project', join(scratch, 'longbook.xcodeproj'), '-scheme', 'longbook', '-configuration', 'Release',
        '-destination', 'generic/platform=macOS', '-derivedDataPath', join(APP_DIR, 'build/derived-mas'),
        '-showBuildSettings',
      ], 300_000)
      out.push(...buildSettingChecks(parseBuildSettings(settings), yml))
    } catch (error) {
      out.push(fail('The Mac build settings', String((error as { stderr?: string }).stderr || error).trim().split('\n').slice(-3).join(' ')))
    }
  } finally {
    rmSync(scratch, { recursive: true, force: true })
  }
  return out
}))

console.log(`longbook release doctor — what the Mac App Store and iOS releases need\n`)
console.log(render(checks))
process.exit(failed(checks) ? 1 : 0)
