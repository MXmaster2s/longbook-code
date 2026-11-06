// The release doctor's checks on sample text: versions, signing, entitlements, icons and build
// settings. Run: npm run dev-tools:test.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { test } from 'node:test'
import { ROOT } from './release.mts'
import {
  assetChecks, buildSettingChecks, entitlementChecks, EXPECTED_ENTITLEMENTS, failed, identityKinds, parseBuildSettings,
  render, signingChecks, versionChecks,
} from './release-doctor-checks.mts'

const APP = join(ROOT, 'apps/longbook')
const yml = readFileSync(join(APP, 'project.yml'), 'utf8')
const statuses = (checks: { status: string }[]) => checks.map((c) => c.status)

const projectYml = (version = '1.5.0', build = '52') =>
  `settings:\n  base:\n    MARKETING_VERSION: "${version}"\n    CURRENT_PROJECT_VERSION: "${build}"\n    DEVELOPMENT_TEAM: ABCDE12345\n`
const changelog = (version = '1.5.0', build = 52) => JSON.stringify([{ version, build, date: '2026-10-27', changes: ['A change.'] }])

test('versions agree, or the doctor says which differs', () => {
  assert.deepEqual(statuses(versionChecks(projectYml(), changelog(), '{"patch":0}')), ['pass', 'pass', 'pass', 'pass'])
  const off = versionChecks(projectYml('1.5.0', '53'), changelog(), '{"patch":"x"}')
  assert.equal(off[2].status, 'fail')
  assert.match(off[2].detail, /build 52, project.yml builds 53/)
  assert.equal(off[3].status, 'fail')
  const twice = versionChecks(projectYml() + '    MARKETING_VERSION: "1.4.0"\n', changelog(), '{"patch":0}')
  assert.equal(twice[1].status, 'fail')
})

test('the checkout as it stands passes the file checks', () => {
  const files = Object.fromEntries(Object.keys(EXPECTED_ENTITLEMENTS).map((f) => [f, readFileSync(join(APP, f), 'utf8')]))
  const checks = [
    ...versionChecks(yml, readFileSync(join(APP, 'Resources/changelog.json'), 'utf8'), readFileSync(join(ROOT, 'release.json'), 'utf8')),
    ...entitlementChecks(files, yml),
  ]
  assert.ok(!failed(checks), render(checks))
})

const IDS = `  1) ${'A'.repeat(40)} "Apple Distribution: Someone (ABCDE12345)"
  2) ${'B'.repeat(40)} "Apple Development: someone@example.com (ZZZZZ99999)"
  3) ${'C'.repeat(40)} "3rd Party Mac Developer Installer: Someone (ABCDE12345)"
     3 valid identities found`

test('identities are read as kind and team, and matched to the project team', () => {
  assert.deepEqual(identityKinds(IDS).map((i) => i.kind), ['Apple Distribution', 'Apple Development', '3rd Party Mac Developer Installer'])
  const ok = signingChecks(projectYml(), IDS, IDS)
  assert.ok(!failed(ok), render(ok))
  assert.doesNotMatch(render(ok), /Someone|example\.com|AAAA/)
  const otherTeam = signingChecks(projectYml().replace('ABCDE12345', 'QQQQQ00000'), IDS, IDS)
  assert.deepEqual(statuses(otherTeam), ['pass', 'fail', 'fail', 'pass'])
  assert.ok(failed(signingChecks(projectYml(), '', '')))
})

test('an entitlements file with a key missing, an extra key or the sandbox off fails', () => {
  const plist = (body: string) => `<plist version="1.0"><dict>${body}</dict></plist>`
  const keys = (list: string[], sandbox = '<true/>') => list.map((k) => `<key>${k}</key>${k.endsWith('app-sandbox') ? sandbox : '<array/>'}`).join('')
  const good = Object.fromEntries(Object.entries(EXPECTED_ENTITLEMENTS).map(([f, k]) => [f, plist(keys(k))]))
  const names = Object.keys(EXPECTED_ENTITLEMENTS).join(' ')
  assert.ok(!failed(entitlementChecks(good, names)))
  const mac = EXPECTED_ENTITLEMENTS['LongbookMac.entitlements']
  const bad = entitlementChecks({
    ...good,
    'Longbook.entitlements': plist(keys(EXPECTED_ENTITLEMENTS['Longbook.entitlements'].slice(1))),
    'Widget.entitlements': plist(keys([...EXPECTED_ENTITLEMENTS['Widget.entitlements'], 'com.apple.security.get-task-allow'])),
    'LongbookMac.entitlements': plist(keys(mac, '<false/>')),
  }, names)
  assert.deepEqual(statuses(bad), ['fail', 'fail', 'fail'])
  assert.match(bad[0].detail, /missing com\.apple\.developer\.applesignin/)
  assert.match(bad[1].detail, /sandbox is off/)
  assert.match(bad[2].detail, /unexpected com\.apple\.security\.get-task-allow/)
  assert.equal(entitlementChecks({ ...good, 'Widget.entitlements': null }, names)[2].status, 'fail')
})

test('a missing icon image is named', () => {
  const contents = JSON.stringify({ images: [
    { filename: 'icon_1024.png', idiom: 'universal', platform: 'ios' }, { filename: 'icon_16.png', idiom: 'mac' },
  ] })
  const files: Record<string, string> = {
    'Resources/Assets.xcassets/AppIcon.appiconset/Contents.json': contents,
    'Resources/AppIconMac.icon/icon.json': '{"groups":[{"layers":[{"image-name" : "book.png"}]}]}',
  }
  const present = new Set(['Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png', 'Resources/AppIconMac.icon/Assets/book.png',
    'Resources/Assets.xcassets/AccentColor.colorset/Contents.json', 'Resources/PrivacyInfo.xcprivacy', 'Widget/PrivacyInfo.xcprivacy'])
  const checks = assetChecks(yml, (rel) => present.has(rel) || rel in files, (rel) => files[rel] ?? null)
  assert.equal(checks[0].status, 'fail')
  assert.match(checks[0].detail, /icon_16\.png/)
  assert.deepEqual(statuses(checks.slice(1)), ['pass', 'pass', 'pass', 'pass'])
})

test('build settings are parsed and compared with project.yml', () => {
  const out = `Build settings for action build and target longbook:
    CODE_SIGN_ENTITLEMENTS = LongbookMac.entitlements
    CURRENT_PROJECT_VERSION = 52
    DEVELOPMENT_TEAM = ABCDE12345
    ENABLE_HARDENED_RUNTIME = YES
    MARKETING_VERSION = 1.5.0
    PRODUCT_BUNDLE_IDENTIFIER = app.longbook.longbook

Build settings for action build and target LongbookWidget:
    PRODUCT_BUNDLE_IDENTIFIER = app.longbook.longbook.widget
`
  const settings = parseBuildSettings(out)
  assert.equal(settings.PRODUCT_BUNDLE_IDENTIFIER, 'app.longbook.longbook')
  assert.equal(buildSettingChecks(settings, projectYml())[0].status, 'pass')
  const wrong = buildSettingChecks({ ...settings, CURRENT_PROJECT_VERSION: '51' }, projectYml())[0]
  assert.equal(wrong.status, 'fail')
  assert.match(wrong.detail, /CURRENT_PROJECT_VERSION is "51", expected "52"/)
  const device = buildSettingChecks({ ...settings, SWIFT_ACTIVE_COMPILATION_CONDITIONS: ' DEVICE_BUILD' }, projectYml())[0]
  assert.equal(device.status, 'fail')
  assert.match(device.detail, /carries DEVICE_BUILD/)
})

test('the report counts failures and skips', () => {
  const text = render([{ name: 'a', status: 'pass', detail: '' }, { name: 'b', status: 'fail', detail: 'why' }, { name: 'c', status: 'skip', detail: 'CI' }])
  assert.match(text, /✗ b — why/)
  assert.match(text, /– c — skipped: CI/)
  assert.match(text, /1 of 3 checks failed, 1 skipped/)
})
