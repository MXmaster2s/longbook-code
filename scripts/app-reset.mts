#!/usr/bin/env -S npx tsx
// Puts longbook back to its first run on this Mac and on booted simulators, for testing. A dry run
// unless --apply; --apply asks for a typed "reset" unless --yes. Settings only: no vault is touched.
// Run: npm run app:reset [-- --mac | --simulator | --device <udid>] [--apply [--yes]].
import { execFileSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { createInterface } from 'node:readline/promises'
import {
  alreadyGone, notPermitted, BUNDLE_ID, APP_GROUP, bootedSimulators, CONFIRM_WORD, confirmed, macPlan, renderPlan,
  simulatorPlan, VAULT_FILE, type Plan,
} from './app-reset-plan.mts'
import { topLevelKeys } from './plist.mts'

const args = process.argv.slice(2)
const APPLY = args.includes('--apply')
const YES = args.includes('--yes')
const device = args.includes('--device') ? args[args.indexOf('--device') + 1] : undefined
const onlyMac = args.includes('--mac')
const onlySims = args.includes('--simulator') || device !== undefined
const wantMac = !onlySims || onlyMac
const wantSims = !onlyMac || onlySims

const run = (cmd: string, argv: string[]): string =>
  execFileSync(cmd, argv, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
const attempt = (cmd: string, argv: string[]): string | null => {
  try {
    return run(cmd, argv)
  } catch {
    return null
  }
}

const plans: Plan[] = []

if (wantMac && process.platform === 'darwin') {
  const home = homedir()
  // Key names only, through cfprefsd; values are never printed.
  const exported = attempt('defaults', ['export', BUNDLE_ID, '-'])
  plans.push(macPlan({
    home,
    running: attempt('pgrep', ['-x', 'longbook']) !== null,
    userDomainKeys: exported ? topLevelKeys(exported) : [],
    iCloudVault: existsSync(join(home, 'Library/Mobile Documents/iCloud~app~longbook/Documents', VAULT_FILE)),
  }))
}

if (wantSims) {
  const listed = attempt('xcrun', ['simctl', 'list', 'devices', 'booted', '-j'])
  const sims = listed ? bootedSimulators(listed).filter((s) => !device || s.udid === device) : []
  if (device && !sims.length) {
    console.error(`No booted simulator has the id ${device}.`)
    process.exit(1)
  }
  for (const sim of sims) {
    const data = attempt('xcrun', ['simctl', 'get_app_container', sim.udid, BUNDLE_ID, 'data'])?.trim() || null
    const group = attempt('xcrun', ['simctl', 'get_app_container', sim.udid, BUNDLE_ID, APP_GROUP])?.trim()
    const prefs = data ? join(data, 'Library/Preferences', `${BUNDLE_ID}.plist`) : ''
    const xml = prefs && existsSync(prefs) ? attempt('plutil', ['-convert', 'xml1', '-o', '-', prefs]) : null
    const vault = data ? [join(data, 'Documents/longbook'), join(data, 'Documents')].find((d) => existsSync(join(d, VAULT_FILE))) ?? null : null
    plans.push(simulatorPlan({ ...sim, dataContainer: data, groupContainers: group ? [group] : [], keys: xml ? topLevelKeys(xml) : [], localVault: vault }))
  }
  if (!sims.length && onlySims) console.log('No booted simulator. Boot one, then run this again.\n')
}

console.log(`longbook reset to first run — ${APPLY ? 'about to apply' : 'dry run, nothing changes'}\n`)
console.log(renderPlan(plans))

const work = plans.filter((p) => p.steps.length)
if (!APPLY) {
  console.log(work.length ? 'Dry run. Add --apply to do the steps above.' : 'Nothing to reset.')
  process.exit(0)
}
const blocked = work.filter((p) => p.blocked)
if (blocked.length) {
  console.error('Stopped: ' + blocked.map((p) => `${p.target}: ${p.blocked}`).join(' '))
  process.exit(1)
}
if (!work.length) process.exit(0)

if (!YES) {
  if (!process.stdin.isTTY) {
    console.error('Not a terminal, so no answer can be typed. Pass --yes to go ahead.')
    process.exit(1)
  }
  const rl = createInterface({ input: process.stdin, output: process.stdout })
  const answer = await rl.question(`Type "${CONFIRM_WORD}" to do the steps above: `)
  rl.close()
  if (!confirmed(answer)) {
    console.log('Nothing changed.')
    process.exit(1)
  }
}

let problems = 0
for (const plan of work) {
  for (const step of plan.steps) {
    try {
      execFileSync(step.command[0], step.command.slice(1), { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
      console.log(`✓ ${plan.target}: ${step.command.slice(-2).join(' ')}`)
    } catch (error) {
      const stderr = String((error as { stderr?: string }).stderr ?? error)
      if (step.optional || alreadyGone(stderr)) {
        console.log(`– ${plan.target}: ${step.command.slice(-2).join(' ')} (nothing there)`)
      } else {
        problems++
        console.error(`✗ ${plan.target}: ${stderr.trim().split('\n').pop()}`)
        if (notPermitted(stderr)) console.error('  macOS guards the app\'s container. Give this terminal Full Disk Access in Privacy & Security, then run this again.')
      }
    }
  }
}
console.log(problems ? `\n${problems} step(s) failed.` : '\nDone. Open longbook to see its first run.')
process.exit(problems ? 1 : 0)
