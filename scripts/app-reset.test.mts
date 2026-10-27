// The reset-to-first-run plan: which keys it names, what it leaves alone, and when it stops.
// Run: npm run dev-tools:test.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  alreadyGone, bootedSimulators, compactKeys, confirmed, groupKeys, macPlan, renderPlan, simulatorPlan,
  type SimulatorState,
} from './app-reset-plan.mts'
import { topLevelKeys } from './plist.mts'

const sim = (over: Partial<SimulatorState> = {}): SimulatorState => ({
  udid: 'U-1', name: 'iPhone 16', runtime: 'iOS-26-5', dataContainer: '/sim/data', groupContainers: [],
  keys: ['longbook.vaultBookmark', 'onboarding.finished.step1', 'tutorial.seen.dashboard', 'appearance'], localVault: null, ...over,
})

test('top-level keys are read without nested ones or comments', () => {
  const xml = `<?xml version="1.0"?><plist version="1.0"><dict>
    <!-- <key>commented</key> -->
    <key>a</key><true/>
    <key>b</key><dict><key>inner</key><string>x</string></dict>
    <key>c</key><array><dict><key>deep</key><false/></dict></array>
    <key>d</key><data>AAAA</data>
  </dict></plist>`
  assert.deepEqual(topLevelKeys(xml), ['a', 'b', 'c', 'd'])
  assert.deepEqual(topLevelKeys('<plist version="1.0"><dict/></plist>'), [])
})

test('booted simulators are found across runtimes', () => {
  const json = JSON.stringify({ devices: {
    'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [{ udid: 'A', name: 'iPhone 17 Pro', state: 'Booted' }, { udid: 'B', name: 'Off', state: 'Shutdown' }],
    'com.apple.CoreSimulator.SimRuntime.iOS-27-0': [],
  } })
  assert.deepEqual(bootedSimulators(json), [{ udid: 'A', name: 'iPhone 17 Pro', runtime: 'iOS-26-5' }])
})

test('keys sort into folder, onboarding, tutorials and the rest', () => {
  const g = groupKeys(['tutorial.seen.reports', 'vaultBookmark', 'onboarding.finished.step2', 'longbook.installId', 'longbook.vaultBookmark'])
  assert.deepEqual(g, {
    folder: ['longbook.vaultBookmark', 'vaultBookmark'], onboarding: ['onboarding.finished.step2'],
    tutorials: ['tutorial.seen.reports'], other: ['longbook.installId'],
  })
  assert.deepEqual(compactKeys(['a', 'longbook.lastSeenHash.0123456789abcdef01', 'longbook.lastSeenHash.fedcba9876543210ff']), ['a', 'longbook.lastSeenHash.* (2)'])
})

test('no plan step names a vault, the Documents folder or iCloud', () => {
  const plans = [
    macPlan({ home: '/Users/me', running: false, userDomainKeys: ['x'], iCloudVault: true }),
    simulatorPlan(sim({ groupContainers: ['/sim/group'], localVault: '/sim/data/Documents/longbook' })),
  ]
  for (const step of plans.flatMap((p) => p.steps)) {
    const cmd = step.command.join(' ')
    assert.match(cmd, /^(defaults delete|xcrun simctl (spawn \S+ defaults delete|terminate))/)
    assert.doesNotMatch(cmd, /Documents|Mobile Documents|financial_memory|\brm\b|uninstall/)
  }
})

test('the Mac plan stops while the app runs and says the iCloud vault reopens', () => {
  const plan = macPlan({ home: '/Users/me', running: true, userDomainKeys: [], iCloudVault: true })
  assert.ok(plan.blocked)
  assert.equal(plan.steps.length, 2)
  assert.match(plan.kept[0], /iCloud vault/)
  assert.equal(macPlan({ home: '/Users/me', running: false, userDomainKeys: ['k'], iCloudVault: false }).steps.length, 3)
})

test('the simulator plan lists the keys it deletes and keeps the local vault', () => {
  const plan = simulatorPlan(sim({ localVault: '/sim/data/Documents/longbook' }))
  const text = renderPlan([plan])
  assert.match(text, /Folder: longbook\.vaultBookmark/)
  assert.match(text, /Onboarding: onboarding\.finished\.step1/)
  assert.match(text, /Tutorials: tutorial\.seen\.dashboard/)
  assert.match(text, /vault in the app's Documents/)
  assert.equal(simulatorPlan(sim({ dataContainer: null })).steps.length, 0)
  assert.equal(simulatorPlan(sim({ keys: [] })).steps.length, 0)
})

test('only the typed word goes ahead, and a missing domain is not a failure', () => {
  assert.ok(confirmed(' reset\n'))
  assert.ok(!confirmed('y'))
  assert.ok(!confirmed(''))
  assert.ok(alreadyGone('Domain app.longbook.longbook does not exist'))
  assert.ok(!alreadyGone('Operation not permitted'))
})
