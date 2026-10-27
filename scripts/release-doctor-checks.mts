// The release doctor's judgements, kept apart from the commands that gather their input, so
// each can be tested on text alone. Run the doctor: npm run release:doctor.
import { changelogProblems } from './changelog.mts'
import { topLevelKinds } from './plist.mts'

export type Status = 'pass' | 'fail' | 'skip'
export interface Check { name: string; status: Status; detail: string }

export const pass = (name: string, detail = ''): Check => ({ name, status: 'pass', detail })
export const fail = (name: string, detail: string): Check => ({ name, status: 'fail', detail })
export const skip = (name: string, detail: string): Check => ({ name, status: 'skip', detail })

// ---- version and build ----------------------------------------------------------------------

export function versionChecks(projectYml: string, changelogJson: string, releaseJson: string): Check[] {
  const checks: Check[] = []
  const version = /MARKETING_VERSION: "([^"]+)"/.exec(projectYml)?.[1]
  const build = /CURRENT_PROJECT_VERSION: "(\d+)"/.exec(projectYml)?.[1]
  const name = 'Version and build in project.yml'
  checks.push(version && build ? pass(name, `${version} (${build})`) : fail(name, 'project.yml names no MARKETING_VERSION or CURRENT_PROJECT_VERSION.'))

  // App Store Connect refuses an app and widget whose numbers differ; one setting serves both.
  const copies = (projectYml.match(/MARKETING_VERSION:/g) ?? []).length + (projectYml.match(/CURRENT_PROJECT_VERSION:/g) ?? []).length
  const once = 'Every target reads the one version'
  checks.push(copies === 2 ? pass(once) : fail(once, `project.yml sets the version or build ${copies} times; keep one pair under settings.base.`))

  let problems: string[]
  try {
    problems = changelogProblems(projectYml, changelogJson)
  } catch (error) {
    problems = [(error as Error).message]
  }
  const log = 'changelog.json describes this build'
  checks.push(problems.length ? fail(log, problems.join('; ')) : pass(log))

  const rel = 'release.json carries a whole-number patch'
  try {
    const patch = (JSON.parse(releaseJson) as { patch?: unknown }).patch
    checks.push(Number.isInteger(patch) && (patch as number) >= 0 ? pass(rel, `patch ${patch}`) : fail(rel, 'Set "patch" to a whole number.'))
  } catch {
    checks.push(fail(rel, 'release.json is not JSON.'))
  }
  return checks
}

// ---- signing ---------------------------------------------------------------------------------

/** The kind and team of each valid identity, read from `security find-identity -v`. Never names or hashes. */
export function identityKinds(output: string): { kind: string; team: string }[] {
  const found: { kind: string; team: string }[] = []
  for (const line of output.split('\n')) {
    const m = /^\s*\d+\)\s+[0-9A-F]{40}\s+"([^:"]+):[^"]*\(([A-Z0-9]{10})\)"/.exec(line)
    if (m) found.push({ kind: m[1].trim(), team: m[2] })
  }
  return found
}

export const teamOf = (projectYml: string): string[] =>
  [...new Set([...projectYml.matchAll(/DEVELOPMENT_TEAM:\s*"?([A-Z0-9]{10})"?/g)].map((m) => m[1]))]

export function signingChecks(projectYml: string, codesigning: string, allIdentities: string): Check[] {
  const teams = teamOf(projectYml)
  const checks: Check[] = [
    teams.length === 1 ? pass('One signing team for every target', teams[0]) : fail('One signing team for every target', `project.yml names ${teams.length ? teams.join(', ') : 'no'} team.`),
  ]
  const team = teams[0] ?? ''
  const signing = identityKinds(codesigning)
  const any = identityKinds(allIdentities)
  // A development certificate's brackets hold the person's id, not the team's, so only its kind counts.
  const need: [string, { kind: string; team: string }[], boolean, string][] = [
    ['Apple Distribution', signing, true, 'both releases sign with it'],
    ['3rd Party Mac Developer Installer', any, true, 'the Mac package is signed with it'],
    ['Apple Development', signing, false, 'device builds sign with it'],
  ]
  for (const [kind, list, byTeam, why] of need) {
    const ok = list.some((i) => i.kind === kind && (!byTeam || i.team === team))
    const name = byTeam ? `${kind} certificate for team ${team}` : `${kind} certificate`
    checks.push(ok ? pass(name) : fail(name, `None in the keychain; ${why}. Run: npm run asc:provision`))
  }
  return checks
}

// ---- entitlements ------------------------------------------------------------------------------

const ICLOUD = ['com.apple.developer.icloud-container-identifiers', 'com.apple.developer.icloud-services', 'com.apple.developer.ubiquity-container-identifiers']

/** Each entitlements file and the keys it must hold, no more and no fewer. */
export const EXPECTED_ENTITLEMENTS: Record<string, string[]> = {
  'Longbook.entitlements': ['com.apple.developer.applesignin', 'com.apple.security.application-groups', ...ICLOUD],
  'LongbookMac.entitlements': [
    'com.apple.security.app-sandbox', 'com.apple.security.files.user-selected.read-write',
    'com.apple.security.files.bookmarks.app-scope', 'com.apple.security.network.client',
    'com.apple.developer.applesignin', ...ICLOUD,
  ],
  'Widget.entitlements': ['com.apple.security.application-groups', ...ICLOUD],
}

export function entitlementChecks(files: Record<string, string | null>, projectYml: string): Check[] {
  const checks: Check[] = []
  for (const [file, expected] of Object.entries(EXPECTED_ENTITLEMENTS)) {
    const name = `${file} holds the expected keys`
    const xml = files[file]
    if (xml == null) {
      checks.push(fail(name, `apps/longbook/${file} is missing.`))
      continue
    }
    const kinds = topLevelKinds(xml)
    const missing = expected.filter((k) => !(k in kinds))
    const extra = Object.keys(kinds).filter((k) => !expected.includes(k))
    const problems = [
      missing.length ? `missing ${missing.join(', ')}` : '',
      extra.length ? `unexpected ${extra.join(', ')}` : '',
      file === 'LongbookMac.entitlements' && 'com.apple.security.app-sandbox' in kinds && kinds['com.apple.security.app-sandbox'] !== 'true'
        ? 'the sandbox is off; the Mac App Store refuses that' : '',
      projectYml.includes(file) ? '' : 'project.yml does not name it',
    ].filter(Boolean)
    checks.push(problems.length ? fail(name, problems.join('; ')) : pass(name))
  }
  return checks
}

// ---- icons and assets ------------------------------------------------------------------------

/** Files an asset catalog's Contents.json, or a layered .icon's icon.json, names. */
export const appIconFiles = (contentsJson: string): string[] =>
  [...new Set(((JSON.parse(contentsJson) as { images?: { filename?: string }[] }).images ?? []).map((i) => i.filename).filter((f): f is string => !!f))]

export const layeredIconImages = (iconJson: string): string[] =>
  [...new Set([...iconJson.matchAll(/"image-name"\s*:\s*"([^"]+)"/g)].map((m) => m[1]))]

/** `exists` answers for a path relative to apps/longbook; `read` returns a file there, or null. */
export function assetChecks(projectYml: string, exists: (rel: string) => boolean, read: (rel: string) => string | null): Check[] {
  const checks: Check[] = []
  const iconName = /ASSETCATALOG_COMPILER_APPICON_NAME:\s*(\S+)/.exec(projectYml)?.[1] ?? 'AppIcon'
  const macIconName = /"ASSETCATALOG_COMPILER_APPICON_NAME\[sdk=macosx\*\]":\s*(\S+)/.exec(projectYml)?.[1]
  const accent = /ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME:\s*(\S+)/.exec(projectYml)?.[1]

  const set = `Resources/Assets.xcassets/${iconName}.appiconset`
  const contents = read(`${set}/Contents.json`)
  if (contents == null) {
    checks.push(fail(`App icon ${iconName}`, `${set}/Contents.json is missing.`))
  } else {
    const files = appIconFiles(contents)
    const missing = files.filter((f) => !exists(`${set}/${f}`))
    const images = (JSON.parse(contents) as { images?: { idiom?: string; platform?: string }[] }).images ?? []
    const sizes = images.some((i) => i.idiom === 'mac') && images.some((i) => i.platform === 'ios' || i.idiom === 'iphone')
    checks.push(missing.length ? fail(`App icon ${iconName}`, `missing ${missing.join(', ')}`)
      : !sizes ? fail(`App icon ${iconName}`, 'it lacks the iPhone or the Mac sizes.')
      : pass(`App icon ${iconName}`, `${files.length} images`))
  }

  if (macIconName) {
    const icon = `Resources/${macIconName}.icon`
    const json = read(`${icon}/icon.json`)
    const missing = json == null ? ['icon.json'] : layeredIconImages(json).filter((f) => !exists(`${icon}/Assets/${f}`))
    checks.push(missing.length ? fail(`Mac icon ${macIconName}`, `${icon}: missing ${missing.join(', ')}`) : pass(`Mac icon ${macIconName}`))
  }
  if (accent) {
    const at = `Resources/Assets.xcassets/${accent}.colorset/Contents.json`
    checks.push(exists(at) ? pass(`Accent colour ${accent}`) : fail(`Accent colour ${accent}`, `${at} is missing.`))
  }
  const manifests = ['Resources/PrivacyInfo.xcprivacy', 'Widget/PrivacyInfo.xcprivacy'].filter((m) => !exists(m))
  checks.push(manifests.length ? fail('Privacy manifests in the app and the widget', `missing ${manifests.join(', ')}`) : pass('Privacy manifests in the app and the widget'))
  checks.push(projectYml.includes('ITSAppUsesNonExemptEncryption') ? pass('Export compliance answered in the bundle')
    : fail('Export compliance answered in the bundle', 'Add ITSAppUsesNonExemptEncryption to the app target\'s info properties.'))
  return checks
}

// ---- build settings ----------------------------------------------------------------------------

/** `xcodebuild -showBuildSettings` output as one map; the first target's block wins. */
export function parseBuildSettings(output: string): Record<string, string> {
  const out: Record<string, string> = {}
  for (const line of output.split('\n')) {
    const m = /^\s{4}([A-Z0-9_]+(?:\[[^\]]+\])?) = (.*)$/.exec(line)
    if (m && !(m[1] in out)) out[m[1]] = m[2]
  }
  return out
}

export function buildSettingChecks(settings: Record<string, string>, projectYml: string): Check[] {
  const version = /MARKETING_VERSION: "([^"]+)"/.exec(projectYml)?.[1]
  const build = /CURRENT_PROJECT_VERSION: "(\d+)"/.exec(projectYml)?.[1]
  const want: [string, string | undefined][] = [
    ['PRODUCT_BUNDLE_IDENTIFIER', 'app.longbook.longbook'],
    ['MARKETING_VERSION', version],
    ['CURRENT_PROJECT_VERSION', build],
    ['CODE_SIGN_ENTITLEMENTS', 'LongbookMac.entitlements'],
    ['DEVELOPMENT_TEAM', teamOf(projectYml)[0]],
    ['ENABLE_HARDENED_RUNTIME', 'YES'],
  ]
  const wrong = want.filter(([k, v]) => settings[k] !== v).map(([k, v]) => `${k} is "${settings[k] ?? ''}", expected "${v}"`)
  const name = 'The Mac build settings'
  return [wrong.length ? fail(name, wrong.join('; ')) : pass(name, `${settings.PRODUCT_BUNDLE_IDENTIFIER} ${settings.MARKETING_VERSION} (${settings.CURRENT_PROJECT_VERSION})`)]
}

// ---- the report --------------------------------------------------------------------------------

export function render(checks: Check[]): string {
  const mark = { pass: '✓', fail: '✗', skip: '–' }
  const lines = checks.map((c) => `${mark[c.status]} ${c.name}${c.detail ? ` — ${c.status === 'skip' ? `skipped: ${c.detail}` : c.detail}` : ''}`)
  const failed = checks.filter((c) => c.status === 'fail').length
  const skipped = checks.filter((c) => c.status === 'skip').length
  lines.push('', failed
    ? `${failed} of ${checks.length} checks failed${skipped ? `, ${skipped} skipped` : ''}. The list above is the whole of it.`
    : `All ${checks.length - skipped} checks passed${skipped ? `, ${skipped} skipped` : ''}.`)
  return lines.join('\n')
}

export const failed = (checks: Check[]): boolean => checks.some((c) => c.status === 'fail')
