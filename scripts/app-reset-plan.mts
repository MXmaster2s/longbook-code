// What `npm run app:reset` clears to bring the app back to its first run, worked out from what
// is on the machine. Only settings: the vault folder is never in a plan, only the bookmark to it.
export const BUNDLE_ID = 'app.longbook.longbook'
export const APP_GROUP = 'group.app.longbook'
export const VAULT_FILE = 'financial_memory.json'

/** `optional`: a failure means there was nothing to do, as with quitting an app that is not open. */
export interface Step { what: string; command: string[]; optional?: boolean }
export interface Plan { target: string; steps: Step[]; kept: string[]; blocked?: string }

export interface Simulator { udid: string; name: string; runtime: string }

/** The booted simulators in `xcrun simctl list devices booted -j`. */
export function bootedSimulators(json: string): Simulator[] {
  const devices = (JSON.parse(json) as { devices?: Record<string, { udid: string; name: string; state: string }[]> }).devices ?? {}
  return Object.entries(devices).flatMap(([runtime, list]) =>
    list.filter((d) => d.state === 'Booted').map((d) => ({ udid: d.udid, name: d.name, runtime: runtime.replace(/^.*SimRuntime\./, '') })))
}

/** The app's stored keys, sorted into what each one remembers. */
export function groupKeys(keys: string[]): Record<'folder' | 'onboarding' | 'tutorials' | 'other', string[]> {
  const out = { folder: [] as string[], onboarding: [] as string[], tutorials: [] as string[], other: [] as string[] }
  for (const key of [...keys].sort()) {
    if (key === 'longbook.vaultBookmark' || key === 'vaultBookmark') out.folder.push(key)
    else if (key.startsWith('onboarding.')) out.onboarding.push(key)
    else if (key.startsWith('tutorial.seen.')) out.tutorials.push(key)
    else out.other.push(key)
  }
  return out
}

/** Keys ending in a hash or an id, folded into one entry per prefix: `longbook.lastSeenHash.* (5)`. */
export function compactKeys(keys: string[]): string[] {
  const counts = new Map<string, number>()
  const out: string[] = []
  for (const key of keys) {
    const prefix = /^(.*\.)[0-9a-f-]{16,}$/i.exec(key)?.[1]
    if (!prefix) out.push(key)
    else counts.set(prefix, (counts.get(prefix) ?? 0) + 1)
  }
  for (const [prefix, n] of counts) out.push(`${prefix}* (${n})`)
  return out
}

const STAYS = [
  'Your sign-in, kept in the keychain. Sign out in the app to see the signed-out screens.',
  'Purchases, which StoreKit keeps. Clear test purchases in Xcode\'s StoreKit transaction manager.',
  'Setup progress saved inside a vault and on your account, which a reopened vault resumes from.',
]

export interface MacState {
  home: string
  running: boolean
  /** Keys in the unsandboxed domain, which a Debug build outside the sandbox writes. */
  userDomainKeys: string[]
  /** Whether the iCloud container holds a vault; checked by its file's presence alone. */
  iCloudVault: boolean
}

export function macPlan(state: MacState): Plan {
  const container = `${state.home}/Library/Containers/${BUNDLE_ID}/Data/Library/Preferences/${BUNDLE_ID}`
  const group = `${state.home}/Library/Group Containers/${APP_GROUP}/Library/Preferences/${APP_GROUP}`
  const steps: Step[] = [
    {
      what: 'Delete the app\'s settings domain: the folder bookmark, onboarding.finished.step*, tutorial.seen.*, consents, appearance and the other @AppStorage keys. macOS keeps this domain behind the container\'s privacy guard, so its keys are listed from the source, not read.',
      command: ['defaults', 'delete', container],
    },
    { what: 'Forget the folder bookmark the app group keeps.', command: ['defaults', 'delete', group, 'vaultBookmark'] },
  ]
  if (state.userDomainKeys.length) {
    steps.unshift({ what: `Delete the unsandboxed domain: ${state.userDomainKeys.join(', ')}.`, command: ['defaults', 'delete', BUNDLE_ID] })
  }
  const kept = [
    state.iCloudVault
      ? 'The iCloud vault (iCloud~app~longbook). The app finds it without a bookmark and opens it again; to see first run with it in place, run a Debug build with LONGBOOK_SNAPSHOT_VAULT=new.'
      : 'Any vault folder. With none in iCloud and the bookmark gone, the app opens on its first run.',
    ...STAYS,
  ]
  return { target: 'This Mac', steps, kept, blocked: state.running ? 'longbook is running. Quit it first, or it writes its settings back as it closes.' : undefined }
}

export interface SimulatorState extends Simulator {
  /** The app's data container, or null when the app is not installed there. */
  dataContainer: string | null
  groupContainers: string[]
  keys: string[]
  /** A vault kept in the app's Documents folder, or null. */
  localVault: string | null
}

export function simulatorPlan(sim: SimulatorState): Plan {
  const target = `Simulator ${sim.name} (${sim.runtime}, ${sim.udid})`
  if (!sim.dataContainer) return { target, steps: [], kept: ['longbook is not installed here; nothing to reset.'] }
  const spawn = ['xcrun', 'simctl', 'spawn', sim.udid, 'defaults', 'delete']
  const groups = groupKeys(sim.keys)
  const listed = (label: string, keys: string[]) => (keys.length ? `${label}: ${compactKeys(keys).join(', ')}` : '')
  const steps: Step[] = [{ what: 'Quit longbook on the simulator.', command: ['xcrun', 'simctl', 'terminate', sim.udid, BUNDLE_ID], optional: true }]
  if (sim.keys.length) {
    steps.push({
      what: `Delete the app's settings domain. ${[
        listed('Folder', groups.folder), listed('Onboarding', groups.onboarding),
        listed('Tutorials', groups.tutorials), listed('Other settings', groups.other),
      ].filter(Boolean).join('. ')}.`,
      command: [...spawn, `${sim.dataContainer}/Library/Preferences/${BUNDLE_ID}`],
    })
  }
  for (const group of sim.groupContainers) {
    steps.push({ what: 'Forget the folder bookmark the app group keeps.', command: [...spawn, `${group}/Library/Preferences/${APP_GROUP}`, 'vaultBookmark'] })
  }
  const kept = [
    sim.localVault
      ? `The vault in the app's Documents (${sim.localVault}). The app finds it there and opens it again; delete the app from the simulator yourself if you want it gone.`
      : 'Any vault folder. With none in the app\'s Documents and the bookmark gone, the app opens on its first run.',
    ...STAYS,
  ]
  return { target, steps: steps.length > 1 ? steps : [], kept: steps.length > 1 ? kept : ['No settings stored yet; already at first run.', ...kept] }
}

export const quote = (arg: string): string => (/^[\w@%+=:,./-]+$/.test(arg) ? arg : `'${arg.replace(/'/g, `'\\''`)}'`)

export function renderPlan(plans: Plan[]): string {
  const lines: string[] = []
  for (const plan of plans) {
    lines.push(plan.target)
    if (plan.blocked) lines.push(`  ✗ ${plan.blocked}`)
    if (!plan.steps.length) lines.push('  Nothing to reset.')
    plan.steps.forEach((s, i) => lines.push(`  ${i + 1}. ${s.what}`, `     $ ${s.command.map(quote).join(' ')}`))
    lines.push('  Stays as it is:', ...plan.kept.map((k) => `  · ${k}`), '')
  }
  return lines.join('\n')
}

/** The Mac's longbook app, by bundle path; a simulator's copy runs under CoreSimulator. */
export function macAppPids(ps: string): number[] {
  return ps.split('\n').flatMap((line) => {
    const m = /^\s*(\d+)\s+(.+)$/.exec(line)
    return m && /\/longbook\.app\/Contents\/MacOS\/longbook$/.test(m[2]) && !m[2].includes('/CoreSimulator/') ? [Number(m[1])] : []
  })
}

/** The word typed to go ahead; anything else stops the reset. */
export const CONFIRM_WORD = 'reset'
export const confirmed = (answer: string): boolean => answer.trim().toLowerCase() === CONFIRM_WORD

/** `defaults delete` on a domain or key that is already gone has nothing to do, which is fine. */
export const alreadyGone = (stderr: string): boolean => /does not exist|not found/i.test(stderr)

/** macOS refuses a terminal the app's container unless it has Full Disk Access. */
export const notPermitted = (stderr: string): boolean => /not permitted|permission/i.test(stderr)
