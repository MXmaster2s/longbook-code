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
// Marketing words name no price and never call longbook a tracker.
const description = (first: 'iPhone' | 'Mac') => {
  const both = first === 'Mac' ? 'On Mac and iPhone' : 'On iPhone and Mac'
  const glance = first === 'Mac' ? 'the Mac menu bar or the iPhone widget' : 'the iPhone widget or the Mac menu bar'
  return `longbook remembers every subscription, bill, insurance premium, EMI, rent and school fee, and shows you what is due before it charges you. ${both}, with your data in your own iCloud.

Connect Claude or ChatGPT and your AI keeps it current: it reads your mail and bank statements, adds every charge it finds, and nothing lands until you keep it in the Proposals screen.

WHAT LONGBOOK DOES
• Shows your next commitment, the 30 days ahead, and a calendar of every day money leaves
• Remembers renewals, premiums, EMIs, rent, fees, subscriptions, domains and memberships in any currency
• Keeps what already happened in Charges, Earnings and Transfers
• Draws a report for every month: spending by category, by account and by person
• Knows who each payment is for (People) and which card or account pays it (Accounts)
• No notifications: glance at ${glance}
• Marks charges paid, bookmarks the ones you watch, and keeps the full history

LET YOUR AI DO THE DATA ENTRY
• Works with Claude and ChatGPT through longbook's MCP server; on a Mac, Claude Desktop and Claude Code can read your folder directly, at no charge
• Import a bank statement and your AI writes every line as a charge, then plans the ones that repeat
• Set a daily email round: your AI checks your inbox each morning and adds what it finds
• Ask it anything: "What do I pay next?", "What renews this year?", "What did I spend in May?"

NOTHING CHANGES WITHOUT YOU
• Every edit your AI makes waits in Proposals for you to keep or undo
• Full history of what was proposed, kept and undone

PRIVATE BY DESIGN
• Your longbook is a folder of plain files in your own iCloud Drive or on your device
• No bank login and no account linking; nothing in your longbook reaches our servers unless you turn on longbook Cloud, import a statement or choose Reorganise my longbook
• Back up any time; the files are yours

ONE PURCHASE, BOTH PLATFORMS
One lifetime purchase unlocks longbook on iPhone and Mac, for everyone in your Apple family through Family Sharing. Within 7 days of buying, Request a Refund in Account sends your request to Apple. longbook supports every request made in those 7 days, and Apple decides each one.

LONGBOOK CLOUD, OPTIONAL
Online AI access, shared reports and more statement reading run on longbook's server as longbook Cloud: a monthly subscription priced in your App Store, with the first 12 months included in your purchase and shared with your Apple family through Family Sharing; cancel any time in your Apple Account settings. Everything else works without it, and every account can have a few statements a month read on the server.

Terms of Use: https://longbook.app/terms/
Privacy Policy: https://longbook.app/privacy-policy/
Questions or ideas: contact@longbook.app`
}
const WORDS = {
  name: 'longbook: money tracker',
  subtitle: 'Remember your money, with AI',
  keywords: 'recurring,expense,manager,insurance,premium,EMI,reminder,calendar,budget,MCP,family,private,bill',
  promotionalText:
    'Your longbook is a private memory of your money. Remember what you pay, to whom & from which account - without connecting your bank. Lifetime license & family sharing.',
  description: description('iPhone'),
  supportUrl: 'https://longbook.app/contact/',
  marketingUrl: 'https://longbook.app',
  privacyPolicyUrl: 'https://longbook.app/privacy-policy/',
  copyright: '2026 Rohit Kundliwal',
}
// The Mac App Store is searched apart: its keywords trade "family" for "menu bar", and its
// description names the Mac first.
const MAC_WORDS = {
  keywords: 'recurring,expense,manager,insurance,premium,EMI,rent,reminder,calendar,budget,money,MCP,menu bar',
  description: description('Mac'),
}

// What's New, shown to people updating, by version: the main changes of apps/longbook/Resources/
// changelog.json in a short list, never a price. A version with no entry here writes none.
const whatsNew = (platform: 'iPhone' | 'Mac') => `• Sign in with Apple, Google or email, with Apple's and Google's own buttons. Account shows how you signed in.
• Getting started is three steps: sign in, activate your longbook, then import a statement.
• You choose once whether to share usage and crash data, with Share and Don't Share side by side. Nothing is sent before you choose, and Settings changes it later.
• Statements are read in full: every line comes in, the account holder becomes a person, and every account and person a statement names is offered to you. Each file gets an Import Completeness Score.
• After an import, longbook shows what it found one step at a time, and Undo Import takes the whole import back.
• New screens: Charges, Earnings and Transfers. Changes is now Proposals, and Members is now People.
• Every list uses one card, and every card opens its own Preview with its facts and the cards connected to it.
• Select many cards to change their category or person, or delete them. Merge people or accounts that are really one, and star the ones you want at the top.
• Family Sharing: a family member who receives longbook or longbook Cloud gets it on their own account, with no Restore.
• A refund or a stopped Family Sharing is explained on screen, and Delete Account says that a longbook Cloud subscription keeps billing until you cancel it.
• Support in the app answers from the help articles, or lets you email a person.
• Each screen shows a short tutorial the first time you open it. Replay any of them in Settings > Tutorials.
• Comments on a shared report come only to you, and you can delete any of them.
${platform === 'Mac'
    ? '• On the Mac: a Settings window with its own panes, open at login, the next payment in the menu bar, and drop a statement anywhere in the window to import it.'
    : '• On iPhone: Charges, Earnings and Transfers are in Settings, and Support has its own screen.'}

Every change is listed at https://longbook.app/release-notes/`
const WHATS_NEW: Record<string, { iPhone: string; Mac: string }> = {
  '1.5.0': { iPhone: whatsNew('iPhone'), Mac: whatsNew('Mac') },
}

// What the reviewer reads before opening the app, the same for both platforms but for the walk.
const AUDIENCE = `Audience: adults who keep a household's recurring payments.
Tested on: iPhone 16, iOS 27.2; Mac Studio (M1 Max, 2022), macOS 27.2 beta`
const ABOUT = `longbook is a private record of recurring payments: bills, insurance, EMIs, rent. It does not link bank accounts, move money or give financial advice. The data is a folder of plain files in the user's iCloud Drive or on the device. Our server holds the account (email, licence, Cloud status) and, only when used: the hosted copy for the user's AI, shared reports, statement imports (the file only while read), Support questions while answered.
Services: Supabase (account, server); Anthropic, OpenAI as fallback (statements, Support); PostHog only after Share; Resend (email); Apple and Google sign-in.`
const NEW_IN = (screens: string) => `NEW IN 1.5.0
- Apple's and Google's own sign-in buttons, then "Sign in with Email".
- First open asks once about usage and crash data; nothing is sent before.
- Family Sharing unlocks a member's copy on its own after sign-in.
- Refund and stopped-sharing notices; Delete Account says Cloud keeps billing until cancelled.
- Proposals (was Changes), People (was Members), new Charges, Earnings and Transfers (${screens}).`
const SHARED = (hold: string) => `SHARED REPORTS
Viewers of a report shared by link and password can comment. Comments are private to the person who shared it; no viewer sees another's. The owner ${hold} a comment to delete it, or uses Stop sharing; the page has "Report this report" (contact@longbook.app).`
// The demo account's code comes from the keychain (npm run review:account). The contact phone
// is not here: an existing record keeps its own, and a new one reads it from the keychain.
const REVIEW = {
  contactFirstName: 'Rohit', contactLastName: 'Kundliwal', contactEmail: 'contact@longbook.app',
  demoAccountRequired: true,
  notes: `The attached PDF pictures every screen. ${AUDIENCE}

${ABOUT}

${NEW_IN('in Settings')}

DEMO ACCOUNT (no purchase and no active Cloud subscription, like a lapsed one)
1. A "Usage and crash data" sheet opens first; either choice is fine.
2. Tap "Sign in with Email", enter appreview@longbook.app, tap "Send me a code", enter the eight-digit code given as the password above, tap "Verify and continue". Nothing is emailed; the code does not expire.
3. "Activate your longbook": the In-App Purchase "longbook" is "Buy longbook" (its App Store price) at the foot; buy it in the sandbox. "See Demo" shows made-up data.
4. longbook makes its folder in iCloud Drive; with iCloud Drive off, tap "Keep It on this iPhone".
5. "Import a statement": "Securely Upload Statement" reads one (try the attached hdfc-savings-2025-2026.pdf, invented data; this account skips the recent-statement check), "Skip" opens the dashboard. Later imports add "Use My Own AI".
6. The + tab adds a commitment.
7. Settings > Account and plan: "Subscribe to longbook Cloud" is the second In-App Purchase (sandbox), with "Request a Refund", Sign out and "Delete Account...".

IN-APP PURCHASES
1. "longbook": non-consumable, Family Sharing on. Unlocks iPhone and Mac with 12 months of Cloud, except for this demo account. No free trial. For 7 days "Request a Refund" passes a request to Apple.
2. "longbook Cloud": auto-renewable monthly, app.longbook.cloud.monthly, Family Sharing on: the hosted copy for the user's AI, shared reports, more statement reading. Without it, "Subscribe to longbook Cloud" and "Let AI Read My longbook" (Settings > AI Connections) open the Cloud sheet: price, term, renewal, Subscribe, Restore Purchases, Terms, Privacy. All else works without Cloud.

STATEMENTS AND AI
- First import: a sheet names Anthropic and asks to accept the privacy policy. Our server reads the file, returns suggested charges and keeps neither; kept charges go to the user's folder.
- "Reorganise my longbook" (Settings > AI Connections) asks first, then sends the folder for one pass; the result waits in Proposals.
- "Let AI Read My longbook", off by default, lets the user's own AI read it at longbook.app/mcp; its changes wait in Proposals.

${SHARED('touches and holds')}

OTHER
- Settings > Data & privacy: what leaves the device, and the "Share usage and crash data" switch.
- "Delete Account..." (type DELETE) removes the account and ends a Sign in with Apple link.
- The widget, Siri and Shortcuts, and Settings > Try the demo are in the PDF.
No hardware needed. Questions: contact@longbook.app`,
}
// The Mac reviewer's walk: the same account and purchases, in the Mac's places.
const MAC_REVIEW = {
  ...REVIEW,
  notes: `The attached PDF pictures every screen. ${AUDIENCE}

${ABOUT}

${NEW_IN('in the sidebar')}

DEMO ACCOUNT (no purchase and no active Cloud subscription, like a lapsed one)
1. A "Usage and crash data" sheet opens first; either choice is fine.
2. Click "Sign in with Email", enter appreview@longbook.app, click "Send me a code", enter the eight-digit code given as the password above, click "Verify and continue". Nothing is emailed; the code does not expire.
3. "Activate your longbook": the In-App Purchase "longbook" is "Buy longbook" (its App Store price) at the foot; buy it in the sandbox.
4. longbook makes its folder in iCloud Drive; with iCloud Drive off, click "Keep It on this Mac".
5. "Import a statement": "Securely Upload Statement" reads one (try the attached hdfc-savings-2025-2026.pdf, invented data; this account skips the recent-statement check), "Skip" opens the dashboard. Later imports add "Use My Own AI".
6. File > New Commitment (Command-N) adds a commitment.
7. Settings > longbook Account > longbook Cloud: "Subscribe to longbook Cloud" is the second In-App Purchase (sandbox), with "Request a Refund", Sign Out and "Delete Account...".

IN-APP PURCHASES
1. "longbook": non-consumable, Family Sharing on. Unlocks Mac and iPhone with 12 months of Cloud, except for this demo account. No free trial. For 7 days "Request a Refund" passes a request to Apple.
2. "longbook Cloud": auto-renewable monthly, app.longbook.cloud.monthly, Family Sharing on: the hosted copy for the user's AI, shared reports, more statement reading. Without it, "Subscribe to longbook Cloud" and "Let AI Read My longbook" (Settings > AI) open the Cloud sheet: price, term, renewal, Subscribe, Restore Purchases, Terms, Privacy. All else works without Cloud.

STATEMENTS AND AI
- First import: a sheet names Anthropic and asks to accept the privacy policy. Our server reads the file, returns suggested charges and keeps neither; kept charges go to the user's folder.
- "Reorganise my longbook" (Settings > AI) asks first, then sends the folder for one pass; the result waits in Proposals.
- "Let AI Read My longbook", off by default, lets the user's AI read it at longbook.app/mcp; its changes wait in Proposals.
- Settings > AI > Claude Desktop > "Set Up Claude Desktop" is optional and needs Node.js.

${SHARED('Control-clicks')}

OTHER
- Settings > Data & Privacy: what leaves the Mac, and the "Share usage and crash data" switch.
- "Delete Account..." (type DELETE) removes the account and ends a Sign in with Apple link.
- Menu bar item, widget, Shortcuts and demo are in the PDF.
No hardware needed. Questions: contact@longbook.app`,
}
// A single check on the caps, so a word too long fails here and not at Apple. Apple counts
// review notes in bytes, and the rest in characters.
const caps: [string, string, number, 'bytes' | 'characters'][] = [
  ['name', WORDS.name, 30, 'characters'], ['subtitle', WORDS.subtitle, 30, 'characters'],
  ['keywords', WORDS.keywords, 100, 'characters'], ['Mac keywords', MAC_WORDS.keywords, 100, 'characters'],
  ['promotionalText', WORDS.promotionalText, 170, 'characters'],
  ['description', WORDS.description, 4000, 'characters'], ['Mac description', MAC_WORDS.description, 4000, 'characters'],
  ...Object.entries(WHATS_NEW).flatMap(([v, w]): [string, string, number, 'characters'][] => [
    [`What's New ${v}`, w.iPhone, 4000, 'characters'], [`Mac What's New ${v}`, w.Mac, 4000, 'characters']]),
  ['review notes', REVIEW.notes, 4000, 'bytes'], ['Mac review notes', MAC_REVIEW.notes, 4000, 'bytes'],
]
for (const [key, text, max, unit] of caps) {
  const size = unit === 'bytes' ? Buffer.byteLength(text, 'utf8') : [...text].length
  if (size > max) {
    console.error(`${key} is ${size} ${unit}; the limit is ${max}.`)
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
  // What's New only on an update: a first release has nothing before it, and Apple refuses the field.
  const released = ['READY_FOR_SALE', 'READY_FOR_DISTRIBUTION', 'REPLACED_WITH_NEW_VERSION', 'DEVELOPER_REMOVED_FROM_SALE', 'REMOVED_FROM_SALE']
  const isUpdate = versions.some((v: any) => v.attributes.platform === platform && released.includes(v.attributes.appStoreState))
  const notes = WHATS_NEW[marketing]?.[platform === 'MAC_OS' ? 'Mac' : 'iPhone']
  if (isUpdate && !notes) console.log(`! ${platform}: no What's New for ${marketing} in this script, so none is written.`)
  const attributes = {
    description: platform === 'MAC_OS' ? MAC_WORDS.description : WORDS.description,
    keywords: platform === 'MAC_OS' ? MAC_WORDS.keywords : WORDS.keywords, promotionalText: WORDS.promotionalText,
    supportUrl: WORDS.supportUrl, marketingUrl: WORDS.marketingUrl,
    ...(isUpdate && notes ? { whatsNew: notes } : {}),
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
