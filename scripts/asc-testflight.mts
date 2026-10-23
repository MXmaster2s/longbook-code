#!/usr/bin/env -S npx tsx
// TestFlight through App Store Connect's API: the external group with its public link,
// testers and team members, the review contact, and a build submitted for Beta App Review.
// Every step reads first. `--check` reports without writing.
//
// npm run asc:testflight -- [--build 11] [--internal 11] [--tester a@b.c]... [--invite a@b.c]...
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { createSign } from 'node:crypto'
import { homedir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { newestRelease } from './changelog.mts'

const BUNDLE_ID = 'app.longbook.longbook'
const GROUP = 'Early access'
const CONTACT = { first: 'Rohit', last: 'Kundliwal', email: 'contact@longbook.app' }
const REVIEW_NOTES =
  'longbook keeps recurring money as a file in the tester\'s own iCloud Drive. Sign in with Google or an email address (longbook sends a code to the inbox), or with Apple on iPhone; no demo account is needed. A new account opens on the purchase screen: the one-time licence, which TestFlight buys with sandbox money, so testers pay nothing. See a Demo First opens a made-up household without buying.'
// What to test comes from the app's own changelog, so the notes and the app's Check for
// updates screen say the same thing.
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
// Testers start knowing nothing: the standing guide first, then what this build changed.
const WHATS_NEW = `${readFileSync(join(ROOT, 'scripts/testflight-guide.txt'), 'utf8').trim()}\n\nNEW IN THIS BUILD\n${newestRelease(readFileSync(join(ROOT, 'apps/longbook/Resources/changelog.json'), 'utf8')).changes.map((c) => `- ${c}`).join('\n')}`.slice(0, 4000)

const argv = process.argv.slice(2)
// A build number can recur across versions; the one meant is the project's version's.
const MARKETING = /MARKETING_VERSION: "([^"]+)"/.exec(readFileSync(join(ROOT, 'apps/longbook/project.yml'), 'utf8'))?.[1] ?? ''
const CHECK = argv.includes('--check')
const flag = (name: string): string[] => argv.flatMap((a, i) => (a === name && argv[i + 1] ? [argv[i + 1]] : []))
const TESTERS = flag('--tester')
const INVITES = flag('--invite')
const BUILD = flag('--build')[0]
const PHONE = process.env.LONGBOOK_REVIEW_PHONE

const sh = (cmd: string, args: string[]): string =>
  execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
const keychain = (service: string): string => {
  try {
    return sh('security', ['find-generic-password', '-s', service, '-w']).trim()
  } catch {
    console.error(`No keychain item "${service}". See docs/releasing-ios.md.`)
    process.exit(1)
  }
}
const KEY_ID = keychain('App Store Connect Key ID')
const ISSUER = keychain('Apple App Store Connect Issuer ID')
const KEY_PATH = join(homedir(), `.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`)
if (!existsSync(KEY_PATH)) {
  console.error(`No key at ${KEY_PATH}.`)
  process.exit(1)
}
const b64u = (b: Buffer): string => b.toString('base64url')
const token = (): string => {
  const now = Math.floor(Date.now() / 1000)
  const header = b64u(Buffer.from(JSON.stringify({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' })))
  const payload = b64u(Buffer.from(JSON.stringify({ iss: ISSUER, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' })))
  const signer = createSign('SHA256')
  signer.update(`${header}.${payload}`)
  const sig = signer.sign({ key: readFileSync(KEY_PATH), dsaEncoding: 'ieee-p1363' })
  return `${header}.${payload}.${b64u(sig)}`
}
const API = 'https://api.appstoreconnect.apple.com'
const call = async (path: string, method = 'GET', body?: unknown, allow: string[] = []): Promise<any> => {
  const res = await fetch(path.startsWith('http') ? path : `${API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await res.text()
  // An error code the caller expects comes back as its answer, not as the end of the run.
  const code = res.ok ? undefined : (() => { try { return JSON.parse(text).errors?.[0]?.code } catch { return undefined } })()
  if (code && allow.includes(code)) return { refused: code }
  if (!res.ok) {
    console.error(`App Store Connect refused ${method} ${path}: ${res.status}`)
    console.error(text.slice(0, 800))
    process.exit(1)
  }
  return text ? JSON.parse(text) : {}
}

const app = (await call(`/v1/apps?filter[bundleId]=${BUNDLE_ID}`)).data?.[0]
if (!app) {
  console.error(`No App Store Connect record for ${BUNDLE_ID}.`)
  process.exit(1)
}
console.log(`✓ app ${app.attributes.name} (${app.id})`)

// ---- the external group, with its public link ------------------------------------------

const groups = (await call(`/v1/apps/${app.id}/betaGroups?limit=50`)).data ?? []
let group = groups.find((g: any) => g.attributes.name === GROUP)
if (group) {
  console.log(`✓ group "${GROUP}" — already there${group.attributes.publicLink ? `, public link ${group.attributes.publicLink}` : ''}`)
} else if (CHECK) {
  console.log(`· group "${GROUP}" — would be created with a public link`)
} else {
  group = (await call('/v1/betaGroups', 'POST', {
    data: {
      type: 'betaGroups',
      attributes: { name: GROUP, isInternalGroup: false, publicLinkEnabled: true, publicLinkLimitEnabled: false, feedbackEnabled: true },
      relationships: { app: { data: { type: 'apps', id: app.id } } },
    },
  })).data
  console.log(`✓ group "${GROUP}" created — public link ${group.attributes.publicLink ?? '(appears once a build is approved)'}`)
}

// ---- the review contact ----------------------------------------------------------------

const detail = (await call(`/v1/apps/${app.id}/betaAppReviewDetail`)).data
if (detail?.attributes?.contactEmail && detail.attributes.contactPhone) {
  console.log(`✓ review contact — ${detail.attributes.contactFirstName} ${detail.attributes.contactLastName}, on file`)
  // The notes are written with the contact, so once it is on file they would never change again.
  if (detail.attributes.notes === REVIEW_NOTES) {
    console.log('✓ review notes — current')
  } else if (CHECK) {
    console.log('· review notes — differ from the ones in this script; they would be rewritten')
  } else {
    await call(`/v1/betaAppReviewDetails/${detail.id}`, 'PATCH', {
      data: { type: 'betaAppReviewDetails', id: detail.id, attributes: { notes: REVIEW_NOTES } },
    })
    console.log('✓ review notes rewritten')
  }
} else if (!PHONE) {
  console.log('· review contact — needs a phone: LONGBOOK_REVIEW_PHONE="+91…" in the environment')
} else if (CHECK) {
  console.log('· review contact — would be written')
} else {
  await call(`/v1/betaAppReviewDetails/${detail.id}`, 'PATCH', {
    data: {
      type: 'betaAppReviewDetails',
      id: detail.id,
      attributes: {
        contactFirstName: CONTACT.first, contactLastName: CONTACT.last, contactEmail: CONTACT.email,
        contactPhone: PHONE, demoAccountRequired: false, notes: REVIEW_NOTES,
      },
    },
  })
  console.log('✓ review contact written')
}

// ---- the beta app description ----------------------------------------------------------
// External testing refuses a build until the app carries a description and a feedback
// address; the same words for every build, so they are written once.

const BETA_DESCRIPTION =
  'longbook keeps your recurring money — subscriptions, insurance, EMIs, rent, fees — as a file in your own iCloud Drive that the AI you already use can read and fill in. Import a statement through your AI, review every change in the app, and see what is due next. Early version: expect rough edges, and tell us about them.'
const betaLocs = (await call(`/v1/apps/${app.id}/betaAppLocalizations`)).data ?? []
if (betaLocs.some((l: any) => l.attributes.locale === 'en-US' && l.attributes.description)) {
  console.log('✓ beta app description — on file')
} else if (CHECK) {
  console.log('· beta app description — would be written')
} else {
  const existing = betaLocs.find((l: any) => l.attributes.locale === 'en-US')
  const attributes = {
    description: BETA_DESCRIPTION, feedbackEmail: CONTACT.email,
    marketingUrl: 'https://longbook.app', privacyPolicyUrl: 'https://longbook.app/privacy-policy/',
  }
  if (existing) {
    await call(`/v1/betaAppLocalizations/${existing.id}`, 'PATCH', { data: { type: 'betaAppLocalizations', id: existing.id, attributes } })
  } else {
    await call('/v1/betaAppLocalizations', 'POST', {
      data: { type: 'betaAppLocalizations', attributes: { ...attributes, locale: 'en-US' }, relationships: { app: { data: { type: 'apps', id: app.id } } } },
    })
  }
  console.log('✓ beta app description written')
}

// ---- the internal group sees every build -----------------------------------------------
// Team members test without review; a build not added to their group is invisible to them.

const internal = groups.find((g: any) => g.attributes.isInternalGroup)
const INTERNAL_BUILDS = flag('--internal')

// ---- testers ---------------------------------------------------------------------------

for (const email of TESTERS) {
  const have = (await call(`/v1/betaTesters?filter[email]=${encodeURIComponent(email)}&filter[apps]=${app.id}`)).data ?? []
  if (have.length) {
    console.log(`✓ tester ${email} — already invited (${have[0].attributes.state})`)
    continue
  }
  if (CHECK || !group) {
    console.log(`· tester ${email} — would be invited to "${GROUP}"`)
    continue
  }
  await call('/v1/betaTesters', 'POST', {
    data: {
      type: 'betaTesters',
      attributes: { email },
      relationships: { betaGroups: { data: [{ type: 'betaGroups', id: group.id }] } },
    },
  })
  console.log(`✓ tester ${email} — invited to "${GROUP}"`)
}

for (const email of INVITES) {
  const users = (await call(`/v1/users?filter[username]=${encodeURIComponent(email)}`)).data ?? []
  const pending = (await call(`/v1/userInvitations?filter[email]=${encodeURIComponent(email)}`)).data ?? []
  if (users.length || pending.length) {
    console.log(`✓ team member ${email} — ${users.length ? 'on the team' : 'invitation pending'}`)
    continue
  }
  if (CHECK) {
    console.log(`· team member ${email} — would be invited (Marketing role, this app)`)
    continue
  }
  const [first, ...rest] = email.split('@')[0].split(/[._-]/)
  await call('/v1/userInvitations', 'POST', {
    data: {
      type: 'userInvitations',
      attributes: {
        email, firstName: first ? first[0].toUpperCase() + first.slice(1) : 'Tester',
        lastName: rest.length ? rest.join(' ') : 'longbook', roles: ['MARKETING'],
        allAppsVisible: false, provisioningAllowed: false,
      },
      relationships: { visibleApps: { data: [{ type: 'apps', id: app.id }] } },
    },
  })
  console.log(`✓ team member ${email} — invited (Marketing role, this app); Apple emails the invitation`)
}

// ---- the build -------------------------------------------------------------------------

// One build number is two builds — iPhone and Mac — and each needs its own submission.
const numbered = BUILD
  ? ((await call(`/v1/builds?filter[app]=${app.id}&filter[version]=${BUILD}&filter[preReleaseVersion.version]=${MARKETING}&limit=10`)).data ?? []).filter((b: any) => !b.attributes.expired)
  : []
if (BUILD && !numbered.length) {
  console.error(`No build ${BUILD} on App Store Connect yet — it appears once Apple has processed the upload.`)
  process.exit(1)
}
// One build of a version on TestFlight at a time: the older ones of this version expire,
// which also ends a beta review still waiting. Other versions are never touched.
if (BUILD && !CHECK) {
  const older = ((await call(`/v1/builds?filter[app]=${app.id}&filter[preReleaseVersion.version]=${MARKETING}&limit=50`)).data ?? [])
    .filter((b: any) => !b.attributes.expired && Number(b.attributes.version) < Number(BUILD))
  for (const old of older) {
    await call(`/v1/builds/${old.id}`, 'PATCH', { data: { type: 'builds', id: old.id, attributes: { expired: true } } })
    console.log(`✓ build ${old.attributes.version} (${old.id.slice(0, 8)}) of ${MARKETING} — expired, so only ${BUILD} is on TestFlight`)
  }
}
for (const build of numbered) {
  if (build.attributes.processingState !== 'VALID') {
    console.error(`Build ${BUILD} (${build.id.slice(0, 8)}) is ${build.attributes.processingState}; wait for VALID.`)
    continue
  }
  const what = `build ${BUILD} (${build.id.slice(0, 8)})`
  // Apple may open an empty en-US entry itself; an empty one is written like a missing one.
  const locs = (await call(`/v1/builds/${build.id}/betaBuildLocalizations`)).data ?? []
  const english = locs.find((l: any) => l.attributes.locale === 'en-US')
  if (english?.attributes.whatsNew?.trim() !== WHATS_NEW && !CHECK) {
    if (english) {
      await call(`/v1/betaBuildLocalizations/${english.id}`, 'PATCH', {
        data: { type: 'betaBuildLocalizations', id: english.id, attributes: { whatsNew: WHATS_NEW } },
      })
    } else {
      await call('/v1/betaBuildLocalizations', 'POST', {
        data: {
          type: 'betaBuildLocalizations',
          attributes: { locale: 'en-US', whatsNew: WHATS_NEW },
          relationships: { build: { data: { type: 'builds', id: build.id } } },
        },
      })
    }
    console.log(`✓ ${what} — "what to test" written`)
  }
  if (group && !CHECK) {
    const inGroup = ((await call(`/v1/betaGroups/${group.id}/builds?limit=50`)).data ?? []).some((b: any) => b.id === build.id)
    if (!inGroup) await call(`/v1/betaGroups/${group.id}/relationships/builds`, 'POST', { data: [{ type: 'builds', id: build.id }] })
    console.log(`✓ ${what} — ${inGroup ? 'already in' : 'added to'} "${GROUP}"`)
    const submission = await call(`/v1/builds/${build.id}/betaAppReviewSubmission`)
    if (submission?.data) {
      console.log(`✓ ${what} — Beta App Review ${submission.data.attributes.betaReviewState}`)
    } else {
      // Apple reviews one build per version at a time; a newer one waits its turn in the group.
      const made = await call('/v1/betaAppReviewSubmissions', 'POST', {
        data: { type: 'betaAppReviewSubmissions', relationships: { build: { data: { type: 'builds', id: build.id } } } },
      }, ['ENTITY_UNPROCESSABLE.ANOTHER_BUILD_IN_REVIEW'])
      if (made.refused) console.log(`· ${what} — waits: an earlier build of this version is still in Beta App Review; run this again once it clears`)
      else console.log(`✓ ${what} — submitted for Beta App Review (${made.data.attributes.betaReviewState})`)
    }
  } else {
    console.log(`· ${what} — would be added to "${GROUP}" and submitted for Beta App Review`)
  }
}

for (const number of INTERNAL_BUILDS) {
  if (!internal) break
  const builds = (await call(`/v1/builds?filter[app]=${app.id}&filter[version]=${number}&filter[preReleaseVersion.version]=${MARKETING}&limit=5`)).data ?? []
  for (const build of builds.filter((b: any) => !b.attributes.expired)) {
    if (CHECK) {
      console.log(`· build ${number} (${build.id.slice(0, 8)}) — would be added to "${internal.attributes.name}"`)
      continue
    }
    await call(`/v1/betaGroups/${internal.id}/relationships/builds`, 'POST', { data: [{ type: 'builds', id: build.id }] })
    console.log(`✓ build ${number} (${build.id.slice(0, 8)}) — added to "${internal.attributes.name}"`)
  }
}

if (group?.attributes?.publicLink) console.log(`\nPublic link: ${group.attributes.publicLink}`)
