#!/usr/bin/env -S npx tsx
// Writes both platforms' App Store listing through App Store Connect's API — version
// string, words, URLs, category, age rating, the attached build — and stops. Nothing is
// submitted. `--check` reports without writing. Run: npm run asc:listing -- [--build 11]
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { createSign } from 'node:crypto'
import { homedir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const BUNDLE_ID = 'app.longbook.longbook'
const CHECK = process.argv.includes('--check')
const buildAt = process.argv.indexOf('--build')
const BUILD = buildAt >= 0 ? process.argv[buildAt + 1] : undefined
// --platform MAC_OS writes one platform's version and leaves the app-level record alone,
// for when the other platform is already in review.
const platformAt = process.argv.indexOf('--platform')
const ONLY = platformAt >= 0 ? process.argv[platformAt + 1] : undefined
if (ONLY && !['IOS', 'MAC_OS'].includes(ONLY)) {
  console.error('--platform takes IOS or MAC_OS.')
  process.exit(1)
}

// The listing, from the App Store launch plan of 2026-10-12. Lowercase is the wordmark's rule;
// the rest is sentence case. Limits: name 30, subtitle 30, keywords 100, promotional 170.
const WORDS = {
  name: 'longbook: subscription tracker',
  subtitle: 'Track your money, with your AI',
  keywords: 'recurring,expense,manager,insurance,premium,EMI,reminder,calendar,budget,MCP,family,private,bill',
  promotionalText:
    'Your longbook is a private memory of your money. Remember what you pay, to whom & from which account - without connecting your bank. Lifetime license & family sharing.',
  description: `longbook remembers every subscription, bill, insurance premium, EMI, rent and school fee, and reminds you before it charges you. On iPhone and Mac, with your data in your own iCloud.

Connect Claude or ChatGPT and your AI keeps it current: it reads your mail and bank statements, adds every charge it finds, and nothing lands until you keep it in the Changes screen.

WHAT LONGBOOK DOES
• Shows your next commitment, the 30 days ahead, and a calendar of every day money leaves
• Tracks subscriptions, renewals, premiums, EMIs, rent, fees, domains and memberships in any currency
• Draws a report for every month: spending by category, by account and by person
• Knows who each payment is for (Members) and which card or account pays it (Accounts)
• No notifications: glance at the iPhone widget or the Mac menu bar
• Marks charges paid, bookmarks the ones you watch, and keeps the full history

LET YOUR AI DO THE DATA ENTRY
• Works with Claude and ChatGPT through longbook's MCP server; on a Mac, Claude Desktop and Claude Code can read your folder directly, at no charge
• Import a bank statement and your AI writes every line as a charge, then plans the ones that repeat
• Set a daily email round: your AI checks your inbox each morning and adds what it finds
• Ask it anything: "What do I pay next?", "What renews this year?", "What did I spend in May?"

NOTHING CHANGES WITHOUT YOU
• Every edit your AI makes waits in Changes for you to keep or undo
• Full history of what was proposed, kept and undone

PRIVATE BY DESIGN
• Your longbook is a folder of plain files in your own iCloud Drive or on your device
• No bank login and no account linking; nothing in your longbook reaches our servers unless you turn on longbook Cloud or import a statement
• Back up any time; the files are yours

ONE PURCHASE, BOTH PLATFORMS
One lifetime purchase unlocks longbook on iPhone and Mac, for everyone in your Apple family through Family Sharing. Changed your mind? Request a refund within 7 days from Account; Apple makes the refund. No subscription for your subscription tracker.

LONGBOOK CLOUD, OPTIONAL
Online AI access, shared reports and more statement reading run on longbook's server, as a longbook Cloud subscription: $4 a month in the US App Store, with the first 12 months included in your purchase and shared with your Apple family through Family Sharing; cancel any time in your Apple ID settings. Everything else works without it, and every account can have a few statements a month read on the server.

Terms of Use: https://longbook.app/terms/
Privacy Policy: https://longbook.app/privacy-policy/
Questions or ideas: contact@longbook.app`,
  supportUrl: 'https://longbook.app/contact/',
  marketingUrl: 'https://longbook.app',
  privacyPolicyUrl: 'https://longbook.app/privacy-policy/',
  copyright: '2026 Rohit Kundliwal',
}
// The Mac App Store is searched apart: its keywords trade "family" for "menu bar", and its
// description names the Mac first.
const MAC_WORDS = {
  keywords: 'recurring,expense,manager,insurance,premium,EMI,rent,reminder,calendar,budget,money,MCP,menu bar',
  description: `longbook remembers every subscription, bill, insurance premium, EMI, rent and school fee, and reminds you before it charges you. On Mac and iPhone, with your data in your own iCloud.

Connect Claude or ChatGPT and your AI keeps it current: it reads your mail and bank statements, adds every charge it finds, and nothing lands until you keep it in the Changes screen.

WHAT LONGBOOK DOES
• Shows your next commitment, the 30 days ahead, and a calendar of every day money leaves
• Tracks subscriptions, renewals, premiums, EMIs, rent, fees, domains and memberships in any currency
• Draws a report for every month: spending by category, by account and by person
• Knows who each payment is for (Members) and which card or account pays it (Accounts)
• No notifications: glance at the Mac menu bar or the iPhone widget
• Marks charges paid, bookmarks the ones you watch, and keeps the full history

LET YOUR AI DO THE DATA ENTRY
• Works with Claude and ChatGPT through longbook's MCP server; on a Mac, Claude Desktop and Claude Code can read your folder directly, at no charge
• Import a bank statement and your AI writes every line as a charge, then plans the ones that repeat
• Set a daily email round: your AI checks your inbox each morning and adds what it finds
• Ask it anything: "What do I pay next?", "What renews this year?", "What did I spend in May?"

NOTHING CHANGES WITHOUT YOU
• Every edit your AI makes waits in Changes for you to keep or undo
• Full history of what was proposed, kept and undone

PRIVATE BY DESIGN
• Your longbook is a folder of plain files in your own iCloud Drive or on your device
• No bank login and no account linking; nothing in your longbook reaches our servers unless you turn on longbook Cloud or import a statement
• Back up any time; the files are yours

ONE PURCHASE, BOTH PLATFORMS
One lifetime purchase unlocks longbook on iPhone and Mac, for everyone in your Apple family through Family Sharing. Changed your mind? Request a refund within 7 days from Account; Apple makes the refund. No subscription for your subscription tracker.

LONGBOOK CLOUD, OPTIONAL
Online AI access, shared reports and more statement reading run on longbook's server, as a longbook Cloud subscription: $4 a month in the US App Store, with the first 12 months included in your purchase and shared with your Apple family through Family Sharing; cancel any time in your Apple ID settings. Everything else works without it, and every account can have a few statements a month read on the server.

Terms of Use: https://longbook.app/terms/
Privacy Policy: https://longbook.app/privacy-policy/
Questions or ideas: contact@longbook.app`,
}
const ABOUT = `longbook is a private memory for recurring payments: subscriptions, insurance, EMIs, rent. It does not connect to bank accounts, move money or give financial advice. The user's data lives in a folder of plain files in their own iCloud Drive (or on the device). Our server keeps only the account email, the licence and the Cloud subscription status.`
// What the reviewer reads before opening the app. The demo account's code comes from the
// keychain (npm run review:account). The contact phone is not here: an existing record keeps
// its own, and a new one reads it from the keychain.
const REVIEW = {
  contactFirstName: 'Rohit', contactLastName: 'Kundliwal', contactEmail: 'contact@longbook.app',
  demoAccountRequired: true,
  notes: `The attached PDF pictures every screen of this walk; with the demo account the purchase screen (its last pages) comes straight after sign-in.

${ABOUT}

A. WITH THE DEMO ACCOUNT (it holds no purchase, so both In-App Purchases come up in order)
1. On the welcome screen, tap "Continue with Email".
2. Enter appreview@longbook.app, tap "Send me a code", type the eight-digit code given as the password above and tap "Verify and continue". The screen says a code was sent; for this account none is, there is no second factor, and the code does not expire.
3. The first screen is "Activate your longbook". The In-App Purchase "longbook" is the button "Buy longbook" with its price ($38.00 in the US store) at the foot; buy it in the sandbox. ("See Demo" shows a made-up household without buying.)
4. longbook creates its folder in iCloud Drive. If iCloud Drive is off, tap "Keep It on this iPhone".
5. "Import a statement" follows, the last of three steps. "Securely Upload Statement" reads a bank statement and "Use My Own AI" connects the user's AI; the demo account can tap "Skip" to open the dashboard without one. The setup questions are in Settings > Optimize your data.
6. On the dashboard, the + tab adds a commitment.
7. Settings > Account and plan: "Subscribe to longbook Cloud" is the second In-App Purchase, also bought in the sandbox. The same screen has "Request a Refund", Sign out and "Delete Account...".

IN-APP PURCHASES (both in this submission)
1. "longbook": one-time, non-consumable, Family Sharing on. Unlocks the app on iPhone and Mac and includes 12 months of longbook Cloud. Purchases have a 7-day refund policy; there is no free trial. After a purchase, Settings > Account and plan shows "Request a Refund" for 7 days, which passes the request to Apple.
2. "longbook Cloud": auto-renewable, one month, app.longbook.cloud.monthly, Family Sharing on. It covers the features that use our server: the hosted copy for the user's own AI, shared reports and extra statement reading. The licence brings 12 months of Cloud, except to this demo account, so after the purchase "Subscribe to longbook Cloud" (Settings > Account and plan) and "Let AI Read My longbook" (Settings > AI Connections) open the Cloud sheet: price, term, renewal terms, Subscribe, Restore Purchases, Terms and Privacy. It can be bought in the sandbox.
Everything else works without Cloud. All payments go through in-app purchase.

STATEMENTS AND AI
- "Securely Upload Statement" (the Import a statement step, or Settings > Import a statement): the first time, a sheet names Anthropic's AI and asks the user to accept the privacy policy. Before a file is chosen, the screen says it is read once by an AI model and not kept. The file is sent to our server for analysis, the suggested charges come back, and the server does not store the file. Only the charges the user keeps are saved, in their own folder.
- "Reorganise my longbook" (Settings > AI Connections) asks first, then sends the folder to our server for one pass; the result arrives as a change to keep or undo.
- "Let AI Read My longbook" is off until the user turns it on.
- Settings > Help & about lists what leaves the device and has the "Share usage and crash data" switch. Privacy policy: https://longbook.app/privacy-policy/

ACCOUNT
"Delete Account..." (type DELETE) removes the account, and for an account opened with Apple ends its Sign in with Apple link. Sign in with Apple is offered alongside Google on iPhone.

No hardware is required and the app works the same in every region (prices use Apple's local tiers).
Questions: contact@longbook.app`,
}
// The Mac reviewer's walk: the same account and purchases, in the Mac's places.
const MAC_REVIEW = {
  ...REVIEW,
  notes: `The attached PDF pictures every screen.

${ABOUT}

A. WITH THE DEMO ACCOUNT (it holds no purchase, so both In-App Purchases come up in order)
1. On the welcome screen, click "Continue with Email".
2. Enter appreview@longbook.app, click "Send me a code", type the eight-digit code given as the password above and click "Verify and continue". The screen says a code was sent; for this account none is, there is no second factor, and the code does not expire.
3. The first screen is "Activate your longbook". The In-App Purchase "longbook" is the button "Buy longbook" with its price ($38.00 in the US store) at the foot; buy it in the sandbox. ("See Demo" shows a made-up household without buying.)
4. longbook creates its folder in iCloud Drive. If iCloud Drive is off, click "Keep It on this Mac".
5. "Import a statement" follows, the last of three steps. "Securely Upload Statement" reads a bank statement and "Use My Own AI" connects the user's AI; the demo account can click "Skip" to open the dashboard without one. The setup questions are in Settings > Data > Optimize your data.
6. The dashboard has a sidebar. "Add commitment" (File > New Commitment, Command-N) adds one; Settings is at the foot of the sidebar and under longbook > Settings (Command-comma).
7. Settings > Account: "Subscribe to longbook Cloud" is the second In-App Purchase, also bought in the sandbox. The same screen has "Request a Refund", Sign Out and "Delete Account...".
8. The menu bar shows the next payment beside the clock; its menu has "Open longbook".

IN-APP PURCHASES
1. "longbook": one-time, non-consumable, Family Sharing on. One purchase unlocks the app on Mac and iPhone and includes 12 months of longbook Cloud. Purchases have a 7-day refund policy; there is no free trial. After a purchase, Settings > Account shows "Request a Refund" for 7 days, which passes the request to Apple.
2. "longbook Cloud": auto-renewable, one month, app.longbook.cloud.monthly, Family Sharing on. It covers the features that use our server: the hosted copy for the user's own AI, shared reports and extra statement reading. The licence brings 12 months of Cloud, except to this demo account, so after the purchase "Subscribe to longbook Cloud" (Settings > Account) and "Let AI Read My longbook" (Settings > AI) open the Cloud sheet: price, term, renewal terms, Subscribe, Restore Purchases, Terms and Privacy. It can be bought in the sandbox.
Everything else works without Cloud. All payments go through in-app purchase.

STATEMENTS AND AI
- "Securely Upload Statement" (the Import a statement step, or File > Import Statement, Command-I): a first-time sheet names Anthropic's AI and asks to accept the privacy policy. Before a file is chosen, the window says it is read once by an AI model and not kept. The file is sent to our server for analysis, the suggested charges come back, and the server does not store the file. Only the charges the user keeps are saved, in their own folder.
- "Reorganise my longbook" (Settings > AI) asks first, then sends the folder to our server for one pass; the result arrives as a change to keep or undo.
- "Let AI Read My longbook" is off until the user turns it on.
- Help > longbook Help lists what leaves the device; the Help menu has the "Share Usage and Crash Data" switch. Privacy policy: https://longbook.app/privacy-policy/

ACCOUNT
"Delete Account..." (type DELETE) removes the account, and for an account opened with Apple ends its Sign in with Apple link. Sign in with Apple is offered alongside Google.

No hardware is required and the app works the same in every region (prices use Apple's local tiers).
Questions: contact@longbook.app`,
}
// A single check on the caps, so a word too long fails here and not at Apple.
const caps: [string, string, number][] = [
  ['name', WORDS.name, 30], ['subtitle', WORDS.subtitle, 30], ['keywords', WORDS.keywords, 100],
  ['Mac keywords', MAC_WORDS.keywords, 100], ['promotionalText', WORDS.promotionalText, 170],
  ['description', WORDS.description, 4000], ['Mac description', MAC_WORDS.description, 4000],
  ['review notes', REVIEW.notes, 4000], ['Mac review notes', MAC_REVIEW.notes, 4000],
]
for (const [key, text, max] of caps) {
  if (text.length > max) {
    console.error(`${key} is ${text.length} characters; the limit is ${max}.`)
    process.exit(1)
  }
}

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
const keychainOrNone = (service: string): string | undefined => {
  try {
    return sh('security', ['find-generic-password', '-s', service, '-w']).trim() || undefined
  } catch {
    return undefined
  }
}
// The demo sign-in, from the keychain item npm run review:account writes. Never printed.
const DEMO = { demoAccountName: 'appreview@longbook.app', demoAccountPassword: keychainOrNone('longbook App Review sign-in code') }
if (!DEMO.demoAccountPassword && !CHECK) {
  console.error('No keychain item "longbook App Review sign-in code". Run: npm run review:account')
  process.exit(1)
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
const call = async (path: string, method = 'GET', body?: unknown): Promise<any> => {
  const res = await fetch(path.startsWith('http') ? path : `${API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await res.text()
  if (!res.ok) {
    console.error(`App Store Connect refused ${method} ${path}: ${res.status}`)
    console.error(text.slice(0, 800))
    process.exit(1)
  }
  return text ? JSON.parse(text) : {}
}
const write = async (label: string, path: string, method: string, body: unknown) => {
  if (CHECK) {
    console.log(`· ${label} — would be written`)
    return
  }
  await call(path, method, body)
  console.log(`✓ ${label}`)
}

const app = (await call(`/v1/apps?filter[bundleId]=${BUNDLE_ID}`)).data?.[0]
if (!app) {
  console.error(`No App Store Connect record for ${BUNDLE_ID}.`)
  process.exit(1)
}
console.log(`✓ app ${app.attributes.name} (${app.id})`)
const marketing = /MARKETING_VERSION:\s*"([^"]+)"/.exec(readFileSync(join(ROOT, 'apps/longbook/project.yml'), 'utf8'))?.[1] ?? '1.0'

// ---- app-level words: name, subtitle, privacy URL, category, age rating ------------------

const infos = (await call(`/v1/apps/${app.id}/appInfos?fields[appInfos]=appStoreState,state`)).data ?? []
const info = ONLY ? undefined : infos.find((i: any) => ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED', 'WAITING_FOR_REVIEW'].includes(i.attributes.appStoreState ?? i.attributes.state)) ?? infos[0]
if (info) {
  const locs = (await call(`/v1/appInfos/${info.id}/appInfoLocalizations`)).data ?? []
  const en = locs.find((l: any) => l.attributes.locale === 'en-US')
  const attributes = { name: WORDS.name, subtitle: WORDS.subtitle, privacyPolicyUrl: WORDS.privacyPolicyUrl }
  if (en) {
    await write('name, subtitle, privacy URL', `/v1/appInfoLocalizations/${en.id}`, 'PATCH', { data: { type: 'appInfoLocalizations', id: en.id, attributes } })
  } else {
    await write('name, subtitle, privacy URL', '/v1/appInfoLocalizations', 'POST', {
      data: { type: 'appInfoLocalizations', attributes: { ...attributes, locale: 'en-US' }, relationships: { appInfo: { data: { type: 'appInfos', id: info.id } } } },
    })
  }
  // The app carries no third-party content: its own words, its own pictures.
  await write('content rights: no third-party content', `/v1/apps/${app.id}`, 'PATCH', {
    data: { type: 'apps', id: app.id, attributes: { contentRightsDeclaration: 'DOES_NOT_USE_THIRD_PARTY_CONTENT' } },
  })
  await write('category Finance', `/v1/appInfos/${info.id}`, 'PATCH', {
    data: { type: 'appInfos', id: info.id, relationships: { primaryCategory: { data: { type: 'appCategories', id: 'FINANCE' } } } },
  })
  const rating = (await call(`/v1/appInfos/${info.id}/ageRatingDeclaration`)).data
  if (rating) {
    await write('age rating: nothing to declare (4+)', `/v1/ageRatingDeclarations/${rating.id}`, 'PATCH', {
      data: {
        type: 'ageRatingDeclarations', id: rating.id,
        attributes: {
          alcoholTobaccoOrDrugUseOrReferences: 'NONE', contests: 'NONE', gamblingSimulated: 'NONE', horrorOrFearThemes: 'NONE',
          matureOrSuggestiveThemes: 'NONE', medicalOrTreatmentInformation: 'NONE', profanityOrCrudeHumor: 'NONE',
          sexualContentGraphicAndNudity: 'NONE', sexualContentOrNudity: 'NONE', violenceCartoonOrFantasy: 'NONE',
          violenceRealistic: 'NONE', violenceRealisticProlongedGraphicOrSadistic: 'NONE',
          gambling: false, unrestrictedWebAccess: false, kidsAgeBand: null, lootBox: false,
          advertising: false, messagingAndChat: false, userGeneratedContent: false,
        },
      },
    })
  }
}

// ---- each platform's version: string, words, build --------------------------------------

const versions = (await call(`/v1/apps/${app.id}/appStoreVersions?fields[appStoreVersions]=platform,versionString,appStoreState&limit=10`)).data ?? []
for (const platform of ONLY ? [ONLY] : ['IOS', 'MAC_OS']) {
  // A version Apple sent back is edited in place, as a fresh one is: a new version beside it
  // would leave the rejected one waiting.
  const editable = ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY']
  let version = versions.find((v: any) => v.attributes.platform === platform && editable.includes(v.attributes.appStoreState))
  // A version in review is locked; a second one would stand beside it, unasked.
  const reviewing = versions.find((v: any) => v.attributes.platform === platform && ['WAITING_FOR_REVIEW', 'IN_REVIEW'].includes(v.attributes.appStoreState))
  if (!version && reviewing) {
    console.log(`· ${platform} version ${reviewing.attributes.versionString} is in review — left alone`)
    continue
  }
  if (!version) {
    if (CHECK) {
      console.log(`· ${platform} version ${marketing} — would be created`)
      continue
    }
    version = (await call('/v1/appStoreVersions', 'POST', {
      data: { type: 'appStoreVersions', attributes: { platform, versionString: marketing }, relationships: { app: { data: { type: 'apps', id: app.id } } } },
    })).data
    console.log(`✓ ${platform} version ${marketing} created`)
  } else if (version.attributes.versionString !== marketing) {
    await write(`${platform} version string ${version.attributes.versionString} → ${marketing}`, `/v1/appStoreVersions/${version.id}`, 'PATCH', {
      data: { type: 'appStoreVersions', id: version.id, attributes: { versionString: marketing } },
    })
  } else {
    console.log(`✓ ${platform} version ${marketing} — on file`)
  }
  // Manual release: approval never publishes on its own; the maintainer presses Release.
  await write(`${platform} copyright and manual release`, `/v1/appStoreVersions/${version.id}`, 'PATCH', {
    data: { type: 'appStoreVersions', id: version.id, attributes: { copyright: WORDS.copyright, releaseType: 'MANUAL' } },
  })
  const detail = (await call(`/v1/appStoreVersions/${version.id}/appStoreReviewDetail`)).data
  if (detail) {
    if (!detail.attributes?.contactPhone) console.log(`! ${platform}: the review record has no contact phone. Add it in App Store Connect.`)
    await write(`${platform} review contact and notes`, `/v1/appStoreReviewDetails/${detail.id}`, 'PATCH', {
      data: { type: 'appStoreReviewDetails', id: detail.id, attributes: { ...(platform === 'MAC_OS' ? MAC_REVIEW : REVIEW), ...DEMO } },
    })
  } else {
    const phone = keychainOrNone('App Review Contact Phone')
    if (!phone) console.log(`! ${platform}: no keychain item "App Review Contact Phone", so the new review record has no phone. Add it in App Store Connect.`)
    await write(`${platform} review contact and notes`, '/v1/appStoreReviewDetails', 'POST', {
      data: { type: 'appStoreReviewDetails', attributes: { ...(platform === 'MAC_OS' ? MAC_REVIEW : REVIEW), ...DEMO, ...(phone ? { contactPhone: phone } : {}) }, relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } } },
    })
  }
  const locs = (await call(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations`)).data ?? []
  const en = locs.find((l: any) => l.attributes.locale === 'en-US')
  // No "what's new": a first release has nothing before it, and Apple refuses the field.
  const attributes = {
    description: platform === 'MAC_OS' ? MAC_WORDS.description : WORDS.description,
    keywords: platform === 'MAC_OS' ? MAC_WORDS.keywords : WORDS.keywords, promotionalText: WORDS.promotionalText,
    supportUrl: WORDS.supportUrl, marketingUrl: WORDS.marketingUrl,
  }
  if (en) {
    await write(`${platform} words`, `/v1/appStoreVersionLocalizations/${en.id}`, 'PATCH', { data: { type: 'appStoreVersionLocalizations', id: en.id, attributes } })
  } else {
    await write(`${platform} words`, '/v1/appStoreVersionLocalizations', 'POST', {
      data: { type: 'appStoreVersionLocalizations', attributes: { ...attributes, locale: 'en-US' }, relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } } },
    })
  }
  if (BUILD) {
    const builds = (await call(`/v1/builds?filter[app]=${app.id}&filter[version]=${BUILD}&filter[preReleaseVersion.platform]=${platform}&limit=5`)).data ?? []
    const build = builds.find((b: any) => !b.attributes.expired)
    if (!build) {
      console.log(`· ${platform} build ${BUILD} — not on App Store Connect yet`)
      continue
    }
    await write(`${platform} build ${BUILD} attached to ${marketing}`, `/v1/appStoreVersions/${version.id}/relationships/build`, 'PATCH', {
      data: { type: 'builds', id: build.id },
    })
  }
}

console.log('\nNothing was submitted. Review it at appstoreconnect.apple.com → Apps → longbook → the iOS and macOS versions.')
