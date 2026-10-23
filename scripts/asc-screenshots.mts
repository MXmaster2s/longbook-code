#!/usr/bin/env -S npx tsx
// Uploads the store screenshots from images/screenshots to both platforms' listings, in the
// order named below, replacing whatever the sets held; and the in-app purchase's review
// image. Reserve, upload in Apple's chunks, commit with a checksum — then wait for COMPLETE.
// `--check` lists what would go. Run: npm run asc:screenshots
import { execFileSync } from 'node:child_process'
import { createHash, createSign } from 'node:crypto'
import { existsSync, readFileSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SHOTS = join(ROOT, 'images/screenshots')
const BUNDLE_ID = 'app.longbook.longbook'
const CHECK = process.argv.includes('--check')

// The order a shopper sees them; the first two are the ones most people ever see.
const SETS: { platform: string; displayType: string; folder: string; files: string[] }[] = [
  // Framed by `npm run store:images` from the captures in each appstore/source folder.
  { platform: 'IOS', displayType: 'APP_IPHONE_67', folder: 'ios/appstore', files: [
    '01-remember-your-money', '02-nothing-changes-without-you', '03-your-ai-keeps-it-current',
    '04-know-where-it-goes', '05-every-payment-on-its-day', '06-the-whole-household'] },
  { platform: 'MAC_OS', displayType: 'APP_DESKTOP', folder: 'mac/appstore', files: [
    '01-remember-your-money', '02-nothing-changes-without-you', '03-your-ai-keeps-it-current',
    '04-every-month-reported', '05-know-where-it-goes', '06-the-whole-household'] },
]
const IAP_SHOT = join(SHOTS, 'ios/billing.png')

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

/** Apple's three-step upload: reserve, PUT the chunks it names, commit with the checksum. */
async function upload(reservePath: string, reserveBody: unknown, file: string, commitType: string): Promise<string> {
  const bytes = readFileSync(file)
  const reserved = (await call(reservePath, 'POST', reserveBody)).data
  for (const op of reserved.attributes.uploadOperations ?? []) {
    const headers: Record<string, string> = {}
    for (const h of op.requestHeaders ?? []) headers[h.name] = h.value
    const res = await fetch(op.url, { method: op.method, headers, body: bytes.subarray(op.offset, op.offset + op.length) })
    if (!res.ok) {
      console.error(`chunk upload failed for ${file}: ${res.status}`)
      process.exit(1)
    }
  }
  await call(`/v1/${commitType}/${reserved.id}`, 'PATCH', {
    data: { type: commitType, id: reserved.id, attributes: { uploaded: true, sourceFileChecksum: createHash('md5').update(bytes).digest('hex') } },
  })
  return reserved.id
}

/** Apple processes an upload after the commit; the listing shows it only once COMPLETE. */
async function waitComplete(path: string, label: string): Promise<void> {
  for (let i = 0; i < 30; i++) {
    const state = (await call(path)).data?.attributes?.assetDeliveryState?.state
    if (state === 'COMPLETE') {
      console.log(`  ✓ ${label} — processed`)
      return
    }
    if (state === 'FAILED') {
      console.error(`  ✗ ${label} — Apple could not process it`)
      process.exit(1)
    }
    await new Promise((r) => setTimeout(r, 4000))
  }
  console.log(`  · ${label} — still processing; check App Store Connect later`)
}

const app = (await call(`/v1/apps?filter[bundleId]=${BUNDLE_ID}`)).data?.[0]
if (!app) {
  console.error(`No App Store Connect record for ${BUNDLE_ID}.`)
  process.exit(1)
}
console.log(`✓ app ${app.attributes.name} (${app.id})`)

const versions = (await call(`/v1/apps/${app.id}/appStoreVersions?fields[appStoreVersions]=platform,appStoreState&limit=10`)).data ?? []
for (const set of SETS) {
  const version = versions.find((v: any) => v.attributes.platform === set.platform && v.attributes.appStoreState === 'PREPARE_FOR_SUBMISSION')
  if (!version) {
    console.log(`· ${set.platform} — no version in preparation`)
    continue
  }
  const loc = ((await call(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations`)).data ?? []).find((l: any) => l.attributes.locale === 'en-US')
  if (!loc) {
    console.log(`· ${set.platform} — no en-US words yet; run asc:listing first`)
    continue
  }
  const files = set.files.map((name) => join(SHOTS, set.folder, `${name}.png`))
  const missing = files.filter((f) => !existsSync(f))
  if (missing.length) {
    console.error(`${set.platform}: missing ${missing.join(', ')}`)
    process.exit(1)
  }
  const sets = (await call(`/v1/appStoreVersionLocalizations/${loc.id}/appScreenshotSets?include=appScreenshots`))
  let shotSet = (sets.data ?? []).find((s: any) => s.attributes.screenshotDisplayType === set.displayType)
  const old = (sets.included ?? []).filter((s: any) => shotSet?.relationships?.appScreenshots?.data?.some((r: any) => r.id === s.id))
  console.log(`${set.platform} ${set.displayType}: ${old.length} old, ${files.length} new`)
  if (CHECK) {
    files.forEach((f) => console.log(`  · would upload ${f.replace(ROOT + '/', '')} (${statSync(f).size} bytes)`))
    continue
  }
  if (!shotSet) {
    shotSet = (await call('/v1/appScreenshotSets', 'POST', {
      data: {
        type: 'appScreenshotSets',
        attributes: { screenshotDisplayType: set.displayType },
        relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: loc.id } } },
      },
    })).data
  }
  for (const shot of old) {
    await call(`/v1/appScreenshots/${shot.id}`, 'DELETE')
    console.log(`  ✓ removed ${shot.attributes.fileName}`)
  }
  const ids: string[] = []
  for (const file of files) {
    const id = await upload('/v1/appScreenshots', {
      data: {
        type: 'appScreenshots',
        attributes: { fileName: `${set.folder}-${file.split('/').pop()}`, fileSize: statSync(file).size },
        relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: shotSet.id } } },
      },
    }, file, 'appScreenshots')
    ids.push(id)
    console.log(`  ✓ uploaded ${file.replace(ROOT + '/', '')}`)
  }
  await call(`/v1/appScreenshotSets/${shotSet.id}/relationships/appScreenshots`, 'PATCH', { data: ids.map((id) => ({ type: 'appScreenshots', id })) })
  for (const [i, id] of ids.entries()) await waitComplete(`/v1/appScreenshots/${id}`, `${set.folder} ${set.files[i]}`)
}

// ---- the purchase's review image ---------------------------------------------------------

const iap = ((await call(`/v1/apps/${app.id}/inAppPurchasesV2`)).data ?? [])[0]
if (iap && existsSync(IAP_SHOT)) {
  const have = await fetch(`${API}/v2/inAppPurchases/${iap.id}/appStoreReviewScreenshot`, { headers: { Authorization: `Bearer ${token()}` } })
  const existing = have.ok ? (await have.json()).data : null
  if (CHECK) {
    console.log(`· purchase review image — ${existing ? 'would replace' : 'would upload'} ${IAP_SHOT.replace(ROOT + '/', '')}`)
  } else {
    if (existing) await call(`/v1/inAppPurchaseAppStoreReviewScreenshots/${existing.id}`, 'DELETE')
    const id = await upload('/v1/inAppPurchaseAppStoreReviewScreenshots', {
      data: {
        type: 'inAppPurchaseAppStoreReviewScreenshots',
        attributes: { fileName: 'billing.png', fileSize: statSync(IAP_SHOT).size },
        relationships: { inAppPurchaseV2: { data: { type: 'inAppPurchases', id: iap.id } } },
      },
    }, IAP_SHOT, 'inAppPurchaseAppStoreReviewScreenshots')
    console.log('  ✓ uploaded the purchase review image')
    await waitComplete(`/v1/inAppPurchaseAppStoreReviewScreenshots/${id}`, 'purchase review image')
  }
}
console.log('\nNothing was submitted.')
