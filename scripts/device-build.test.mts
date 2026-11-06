// The device build number: devices stay one above the highest build on TestFlight, and the
// bookkeeping that records a number is not an app change. Run: npm run device-build:test.
import assert from 'node:assert/strict'
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { carriesFirstUseReset, DEVICE_BUILD_SETTING, RESET_MARKER } from './device-build-flag.mts'
import { nextDeviceBuild, ROOT, sameApp, withBuild, withChangelogEntry, type Ledger } from './release.mts'

const ledger: Ledger = {
  51: { version: '1.4.1', commit: 'aaa', installed: '2026-10-23', testflight: '2026-10-23' },
  52: { version: '1.5.0', commit: 'bbb', installed: '2026-10-26' },
}

const shipped: Ledger = { ...ledger, 52: { ...ledger[52], testflight: '2026-10-27' } }

test('devices stay one above the highest build on TestFlight', () => {
  assert.deepEqual(nextDeviceBuild(shipped, 53), { build: 53, reuse: true })
})

test('a project above that number comes back down to it', () => {
  assert.deepEqual(nextDeviceBuild(shipped, 60), { build: 53, reuse: false })
})

test('the first build after a TestFlight mark takes the next number', () => {
  assert.deepEqual(nextDeviceBuild(shipped, 52), { build: 53, reuse: false })
})

test('with no TestFlight mark the highest known number stays', () => {
  assert.deepEqual(nextDeviceBuild(ledger, 52), { build: 52, reuse: true })
  assert.deepEqual(nextDeviceBuild({}, 52), { build: 52, reuse: true })
})

const yml = 'settings:\n  base:\n    MARKETING_VERSION: "1.5.0"\n    CURRENT_PROJECT_VERSION: "52"\n'
const log = JSON.stringify([{ version: '1.5.0', build: 52, date: '2026-10-23', changes: ['a', 'b'] }], null, 2)

test('the recorded number goes into project.yml and the changelog repeats the lines before it', () => {
  assert.match(withBuild(yml, 53), /CURRENT_PROJECT_VERSION: "53"/)
  const next = JSON.parse(withChangelogEntry(log, '1.5.0', 53, '2026-10-27'))
  assert.deepEqual(next[0], { version: '1.5.0', build: 53, date: '2026-10-27', changes: ['a', 'b'] })
  assert.equal(next.length, 2)
  assert.equal(withChangelogEntry(log, '1.5.0', 52, '2026-10-27'), log, 'an entry already there is kept')
  assert.throws(() => withChangelogEntry(log, '1.6.0', 53, '2026-10-27'), /not 1\.6\.0/)
})

test('the bookkeeping is the same app; a new line or a new setting is not', () => {
  const project = 'apps/longbook/project.yml'
  const changelog = 'apps/longbook/Resources/changelog.json'
  assert.ok(sameApp(project, yml, withBuild(yml, 53)))
  assert.ok(!sameApp(project, yml, yml.replace('1.5.0', '1.6.0')))
  assert.ok(sameApp(changelog, log, withChangelogEntry(log, '1.5.0', 53, '2026-10-27')))
  const edited = JSON.stringify([{ version: '1.5.0', build: 53, date: '2026-10-27', changes: ['a', 'b', 'c'] }, ...JSON.parse(log)])
  assert.ok(!sameApp(changelog, log, edited))
  assert.ok(!sameApp('apps/longbook/Sources/App.swift', 'x', 'y'))
  assert.ok(!sameApp('apps/longbook/Sources/New.swift', null, 'y'))
})

const read = (rel: string): string => readFileSync(join(ROOT, rel), 'utf8')

test('only device:install compiles in the first-use reset; archives and CI never do', () => {
  assert.match(read('scripts/device-install.mts'), /`LONGBOOK_COMMIT=\$\{commit\}`, DEVICE_BUILD_SETTING, 'build'/)
  const own = new Set(['device-install.mts', 'device-build-flag.mts', 'device-build.test.mts', 'release-doctor-checks.mts', 'release-doctor.test.mts'])
  const files = [
    ...readdirSync(join(ROOT, 'scripts')).filter((n) => n.endsWith('.mts') && !own.has(n)).map((n) => `scripts/${n}`),
    ...readdirSync(join(ROOT, '.github/workflows')).map((n) => `.github/workflows/${n}`),
  ]
  for (const file of files) {
    const text = read(file)
    for (const needle of ['DEVICE_BUILD', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS', 'OTHER_SWIFT_FLAGS']) {
      assert.ok(!text.includes(needle), `${file} names ${needle}`)
    }
  }
  assert.ok(files.includes('scripts/release-ios.mts') && files.includes('scripts/release-mas.mts'))
  for (const file of ['scripts/release-ios.mts', 'scripts/release-mas.mts']) {
    assert.match(read(file), /if \(carriesFirstUseReset\(join\(archive, 'Products\/Applications\/longbook\.app'\)\)\)/, `${file} checks its archive`)
  }
})

test('project.yml leaves the flag empty and gives it to the app target alone', () => {
  const yml = read('apps/longbook/project.yml')
  assert.match(yml, /^ {4}LONGBOOK_DEVICE_BUILD: ""$/m)
  assert.equal(yml.match(/\$\(LONGBOOK_DEVICE_BUILD\)/g)?.length, 1)
  const app = yml.slice(yml.indexOf('\n  longbook:\n'), yml.indexOf('\n  LongbookWidget:\n'))
  assert.match(app, /SWIFT_ACTIVE_COMPILATION_CONDITIONS: "\$\(inherited\) \$\(LONGBOOK_DEVICE_BUILD\)"/)
  assert.equal(DEVICE_BUILD_SETTING, 'LONGBOOK_DEVICE_BUILD=DEVICE_BUILD')
})

test('the reset is compiled only under DEVICE_BUILD, and its marker is the one searched for', () => {
  const swift = read('apps/longbook/Sources/FirstUseReset.swift').trim()
  assert.ok(swift.startsWith('#if DEVICE_BUILD\n') && swift.endsWith('\n#endif'))
  assert.ok(swift.includes(`static let marker = "${RESET_MARKER}"`))
  const root = read('apps/longbook/Sources/RootView.swift')
  assert.match(root, /#if DEVICE_BUILD\n\s+if FirstUseReset\.handles\(url\) \{ FirstUseReset\.run\(\) \}\n\s+#endif/)
  const uses = readdirSync(join(ROOT, 'apps/longbook/Sources'), { recursive: true }).map(String)
    .filter((n) => n.endsWith('.swift') && read(`apps/longbook/Sources/${n}`).includes('FirstUseReset'))
  const app = read('apps/longbook/Sources/LongbookApp.swift')
  assert.equal(app.match(/#if DEVICE_BUILD\n\s+FirstUseReset\.runIfAsked\(\)\n\s+#endif/g)?.length, 2, 'asked at launch on both apps')
  assert.deepEqual(uses.sort(), ['FirstUseReset.swift', 'LongbookApp.swift', 'RootView.swift'])
})

test('a built app is checked for the reset by its executable', () => {
  const dir = mkdtempSync(join(tmpdir(), 'device-flag-'))
  const mac = join(dir, 'Mac/longbook.app')
  const phone = join(dir, 'iPhone/longbook.app')
  mkdirSync(join(mac, 'Contents/MacOS'), { recursive: true })
  mkdirSync(phone, { recursive: true })
  writeFileSync(join(mac, 'Contents/MacOS/longbook'), Buffer.concat([Buffer.from([0, 1]), Buffer.from(RESET_MARKER), Buffer.from([0])]))
  writeFileSync(join(phone, 'longbook'), 'longbook device build')
  assert.ok(carriesFirstUseReset(mac))
  assert.ok(!carriesFirstUseReset(phone))
  assert.ok(!carriesFirstUseReset(join(dir, 'missing.app')))
  rmSync(dir, { recursive: true, force: true })
})
