// The device build number: the same app keeps its number, a changed one takes the next, and the
// bookkeeping that records a number is not an app change. Run: npm run device-build:test.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { nextDeviceBuild, sameApp, withBuild, withChangelogEntry, type Ledger } from './release.mts'

const ledger: Ledger = {
  51: { version: '1.4.1', commit: 'aaa', installed: '2026-10-23', testflight: '2026-10-23' },
  52: { version: '1.5.0', commit: 'bbb', installed: '2026-10-26' },
}
const changed = () => true
const unchanged = () => false

test('a changed app takes one more than the highest device build', () => {
  assert.deepEqual(nextDeviceBuild(ledger, 52, changed), { build: 53, reuse: false })
})

test('the same app as the highest device build keeps its number, on TestFlight or not', () => {
  assert.deepEqual(nextDeviceBuild(ledger, 52, unchanged), { build: 52, reuse: true })
  const shipped = { ...ledger, 52: { ...ledger[52], testflight: '2026-10-27' } }
  assert.deepEqual(nextDeviceBuild(shipped, 52, unchanged), { build: 52, reuse: true })
})

test('project.yml above the ledger counts from project.yml', () => {
  assert.deepEqual(nextDeviceBuild(ledger, 60, changed), { build: 61, reuse: false })
  assert.deepEqual(nextDeviceBuild(ledger, 60, unchanged), { build: 61, reuse: false })
})

test('an empty ledger counts from project.yml', () => {
  assert.deepEqual(nextDeviceBuild({}, 52, unchanged), { build: 53, reuse: false })
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
