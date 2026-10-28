// The clean-slate decisions: where the backup goes, which account may go, what is longbook's in
// Claude Code's config, and that a vault copy is proved before anything is removed.
// Run: npm run dev-tools:test.
import assert from 'node:assert/strict'
import { mkdirSync, mkdtempSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { macAppPids } from './app-reset-plan.mts'
import {
  appRunning, backupDir, backupStamp, cascadeCountQuery, chooseAccount, compareManifests, confirmedPhrase, copyVerified, inStageOrder,
  isProtectedAccount, longbookMcpServers, longbookPlugins, macResetCommand, manifest, maskEmail, normaliseEmail, parseArgs,
  phoneResetCommand, resetLogCommand, restoreCommand, sqlText, type Stage,
} from './clean-slate-plan.mts'

test('the backup folder is iCloud Drive › longbook backups › date and minute', () => {
  const at = new Date(2026, 9, 8, 7, 5)
  assert.equal(backupStamp(at), '2026-10-08 0705')
  assert.equal(backupDir('/h/me', at), '/h/me/Library/Mobile Documents/com~apple~CloudDocs/longbook backups/2026-10-08 0705')
  assert.equal(
    restoreCommand('/h/me/b/2026-10-08 0705', '/h/me/Library/Mobile Documents/iCloud~app~longbook/Documents'),
    "ditto '/h/me/b/2026-10-08 0705' '/h/me/Library/Mobile Documents/iCloud~app~longbook/Documents/'",
  )
})

test('emails are masked to a first letter and the domain', () => {
  assert.equal(maskEmail('rohit@example.com'), 'r…@example.com')
  assert.equal(maskEmail(' Ann@x.io '), 'A…@x.io')
  assert.equal(maskEmail('nope'), '…')
  assert.equal(sqlText("o'neil"), "'o''neil'")
})

test('the App Review accounts are refused, however they are written', () => {
  for (const email of ['appreview@longbook.app', 'AppReview@Longbook.app', ' review@longbook.app', 'review+1@longbook.app']) {
    assert.ok(isProtectedAccount(email), email)
    const choice = chooseAccount(email, null)
    assert.equal(choice.kind, 'refuse')
    assert.equal(chooseAccount(true, email).kind, 'refuse')
  }
  assert.ok(!isProtectedAccount('someone@longbook.app'))
  assert.equal(normaliseEmail(' A.B+tag@X.com '), 'a.b@x.com')
})

test('the account named must be the one the vault was opened by', () => {
  assert.deepEqual(chooseAccount(undefined, 'me@x.com'), { kind: 'skip' })
  assert.deepEqual(chooseAccount('Me@X.com', 'me@x.com'), { kind: 'delete', email: 'Me@X.com', typeToConfirm: false })
  assert.equal(chooseAccount('other@x.com', 'me@x.com').kind, 'refuse')
  assert.deepEqual(chooseAccount(true, 'me@x.com'), { kind: 'delete', email: 'me@x.com', typeToConfirm: true })
  assert.equal(chooseAccount(true, null).kind, 'refuse')
  assert.equal(chooseAccount("x'@y.com", null).kind, 'refuse')
  assert.deepEqual(chooseAccount('named@x.com', null), { kind: 'delete', email: 'named@x.com', typeToConfirm: false })
})

test('arguments: --account alone, values, and strays', () => {
  assert.equal(parseArgs(['--account']).account, true)
  assert.equal(parseArgs(['--account', '--apply']).account, true)
  assert.equal(parseArgs(['--account', 'a@b.co', '--mac']).account, 'a@b.co')
  const a = parseArgs(['--device', 'U1', '--reinstall', '/x/longbook.app', '--apply', '--yes'])
  assert.deepEqual([a.device, a.reinstall, a.apply, a.yes, a.problems], ['U1', '/x/longbook.app', true, true, []])
  assert.deepEqual(parseArgs(['--reinstall', '/x.app']).problems, ['--reinstall needs --device <udid>.'])
  assert.deepEqual(parseArgs(['--mac', 'oops']).problems, ['Unknown argument: oops'])
  assert.ok(confirmedPhrase(' Clean Slate\n'))
  assert.ok(!confirmedPhrase('yes'))
})

test('longbook is found in Claude Code\'s config and nothing else is', () => {
  const claude = {
    mcpServers: { jean: { command: 'jean' }, longbook: { url: 'https://longbook.app/mcp' }, money: { url: 'https://longbook.app/mcp' } },
    projects: { '/p': { mcpServers: { 'longbook-local': { command: 'node' }, other: {} } }, '/q': {} },
  }
  assert.deepEqual(longbookMcpServers(claude), [
    { name: 'longbook', scope: 'user' }, { name: 'money', scope: 'user' }, { name: 'longbook-local', scope: 'local', project: '/p' },
  ])
  assert.deepEqual(longbookMcpServers(null), [])
  const installed = { version: 2, plugins: { 'longbook@longbook': [{ scope: 'user' }, { scope: 'local', projectPath: '/p' }], 'x@y': [{ scope: 'user' }] } }
  assert.deepEqual(longbookPlugins(installed), [{ id: 'longbook@longbook', scope: 'user' }, { id: 'longbook@longbook', scope: 'local', project: '/p' }])
})

test('only the Mac app counts as running, never a simulator\'s copy', () => {
  const ps = [
    '  101 /h/me/Library/Developer/CoreSimulator/Devices/A/data/Containers/Bundle/Application/B/longbook.app/longbook',
    '  202 /Applications/longbook.app/Contents/MacOS/longbook',
    '  303 /Applications/longbook.app/Contents/PlugIns/Widget.appex/Contents/MacOS/Widget',
    '  404 /h/me/DerivedData/Build/Products/Debug/longbook.app/Contents/MacOS/longbook',
  ].join('\n')
  assert.deepEqual(macAppPids(ps), [202, 404])
  assert.deepEqual(macAppPids(''), [])
})

test('row counts are one query over the keyed tables', () => {
  const q = cascadeCountQuery([{ table: 'entitlements', column: 'user_id' }, { table: 'profiles', column: 'id' }], 'u-1')
  assert.match(q, /from entitlements where user_id = 'u-1'\nunion all\nselect 'profiles'/)
  assert.equal(cascadeCountQuery([], 'u'), 'select 1 where false')
})

test('a vault copy is proved byte for byte, and a changed byte is caught', () => {
  const root = mkdtempSync(join(tmpdir(), 'clean-slate-test-'))
  const vault = join(root, 'vault')
  mkdirSync(join(vault, '.longbook/history'), { recursive: true })
  writeFileSync(join(vault, 'financial_memory.json'), '{"rows":[]}')
  writeFileSync(join(vault, '.longbook/history/1.json'), 'one')
  symlinkSync('financial_memory.json', join(vault, 'link.json'))
  const copied = copyVerified(vault, join(root, 'backup'))
  assert.deepEqual(copied, { files: 2, bytes: 14 })
  assert.deepEqual(readdirSync(vault).sort(), ['.longbook', 'financial_memory.json', 'link.json'], 'the originals stay until the caller removes them')
  assert.throws(() => copyVerified(vault, join(root, 'backup')), 'an existing backup is never written over')

  writeFileSync(join(root, 'backup/.longbook/history/1.json'), 'One')
  writeFileSync(join(root, 'backup/extra.txt'), '')
  assert.deepEqual(compareManifests(manifest(vault), manifest(join(root, 'backup'))), [
    'differs in the copy: .longbook/history/1.json', 'extra in the copy: extra.txt',
  ])
  rmSync(root, { recursive: true, force: true })
})

test('apps reset themselves first, then the vault moves, then the account and Claude Code go', () => {
  const at = (stage: Stage, target: string) => ({ stage, target })
  const order = inStageOrder([at('vault', 'vault'), at('account', 'account'), at('claude', 'claude'), at('app', 'Mac'), at('app', 'iPhone')])
  assert.deepEqual(order.map((s) => s.target), ['Mac', 'iPhone', 'vault', 'account', 'claude'])
})

test('the reset link goes to the installed Mac app and to a fresh iPhone launch', () => {
  assert.deepEqual(macResetCommand('/Applications/longbook.app'), ['open', '-W', '-a', '/Applications/longbook.app', 'longbook://dev/first-use'])
  assert.deepEqual(phoneResetCommand('U1'), [
    'xcrun', 'devicectl', 'device', 'process', 'launch', '--device', 'U1', '--terminate-existing',
    '--payload-url', 'longbook://dev/first-use', 'app.longbook.longbook',
  ])
  const log = resetLogCommand(new Date(2026, 9, 8, 7, 5, 9))
  assert.deepEqual(log.slice(0, 3), ['/usr/bin/log', 'show', '--start'])
  assert.equal(log[3], '2026-10-08 07:05:09')
  assert.match(log.at(-1)!, /category == "first-use"/)
})

test('the iPhone app counts as running, its widget does not', () => {
  const app = 'file:///private/var/containers/Bundle/Application/A1/longbook.app/longbook'
  const widget = 'file:///private/var/containers/Bundle/Application/A1/longbook.app/PlugIns/LongbookWidget.appex/LongbookWidget'
  assert.ok(appRunning({ result: { runningProcesses: [{ executable: '/usr/libexec/x' }, { executable: app }] } }))
  assert.ok(!appRunning({ result: { runningProcesses: [{ executable: widget }, {}] } }))
  assert.ok(!appRunning(null))
})
