#!/usr/bin/env -S npx tsx
// Makes the one in-app purchase the app sells — a non-consumable licence — through App Store
// Connect's API, with its English words, its price and its territories. Nothing is created
// twice: every step reads first. `--check` reports without writing. Run: npm run asc:iap.
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { createSign } from 'node:crypto'
import { homedir } from 'node:os'
import { join } from 'node:path'

const BUNDLE_ID = 'app.longbook.longbook'
// The app reads this product id; StoreClient.swift carries the same literal.
const PRODUCT_ID = 'app.longbook.licence'
const NAME = 'longbook'
// App Store Connect caps this at 55 characters.
const DESCRIPTION = 'One purchase unlocks every platform, for good.'
const REVIEW_NOTE = 'A one-time licence, bought before first use: an account without it opens on the purchase screen. It includes the first 12 months of longbook Cloud. A refund can be requested within 7 days from Account.'
// The price the site names; the nearest App Store price point at or under it is chosen.
const PRICE_USD = 38
const CHECK = process.argv.includes('--check')

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
/** Every page of a list, followed by the API's own next links. */
const all = async (path: string): Promise<any[]> => {
  const out: any[] = []
  let next: string | undefined = path
  while (next) {
    const page = await call(next)
    out.push(...(page.data ?? []))
    next = page.links?.next
  }
  return out
}

// ---- the app ---------------------------------------------------------------------------

const apps = await call(`/v1/apps?filter[bundleId]=${BUNDLE_ID}`)
const app = apps.data?.[0]
if (!app) {
  console.error(`No App Store Connect record for ${BUNDLE_ID}.`)
  process.exit(1)
}
console.log(`✓ app ${app.attributes.name} (${app.id}) for ${BUNDLE_ID}`)

// ---- the purchase ----------------------------------------------------------------------

const existing = await all(`/v1/apps/${app.id}/inAppPurchasesV2?limit=200`)
let iap = existing.find((p: any) => p.attributes.productId === PRODUCT_ID)
if (iap) {
  console.log(`✓ in-app purchase ${PRODUCT_ID} — already there (${iap.attributes.state})`)
  // The review note follows the pricing, so an old one is rewritten.
  if (iap.attributes.reviewNote !== REVIEW_NOTE) {
    if (CHECK) console.log('· review note — would be rewritten')
    else {
      await call(`/v2/inAppPurchases/${iap.id}`, 'PATCH', { data: { type: 'inAppPurchases', id: iap.id, attributes: { reviewNote: REVIEW_NOTE } } })
      console.log('✓ review note rewritten')
    }
  }
} else if (CHECK) {
  console.log(`· in-app purchase ${PRODUCT_ID} — would be created`)
} else {
  const made = await call('/v2/inAppPurchases', 'POST', {
    data: {
      type: 'inAppPurchases',
      attributes: { name: NAME, productId: PRODUCT_ID, inAppPurchaseType: 'NON_CONSUMABLE', reviewNote: REVIEW_NOTE },
      relationships: { app: { data: { type: 'apps', id: app.id } } },
    },
  })
  iap = made.data
  console.log(`✓ in-app purchase ${PRODUCT_ID} created (${iap.attributes.state})`)
}
if (!iap) process.exit(0)

// ---- the words -------------------------------------------------------------------------

const locales = await all(`/v2/inAppPurchases/${iap.id}/inAppPurchaseLocalizations?limit=50`)
if (locales.some((l: any) => l.attributes.locale === 'en-US')) {
  console.log('✓ en-US words — already there')
} else if (CHECK) {
  console.log('· en-US words — would be written')
} else {
  await call('/v1/inAppPurchaseLocalizations', 'POST', {
    data: {
      type: 'inAppPurchaseLocalizations',
      attributes: { name: NAME, description: DESCRIPTION, locale: 'en-US' },
      relationships: { inAppPurchaseV2: { data: { type: 'inAppPurchases', id: iap.id } } },
    },
  })
  console.log('✓ en-US words written')
}

// ---- the price -------------------------------------------------------------------------

const schedule = await fetch(`${API}/v2/inAppPurchases/${iap.id}/iapPriceSchedule`, {
  headers: { Authorization: `Bearer ${token()}` },
})
if (schedule.ok && (await schedule.json()).data) {
  console.log('✓ price schedule — already there')
} else if (CHECK) {
  console.log(`· price schedule — would be set at the USD point nearest under $${PRICE_USD}`)
} else {
  const points = await all(`/v2/inAppPurchases/${iap.id}/pricePoints?filter[territory]=USA&limit=200`)
  const under = points
    .map((p: any) => ({ id: p.id, price: Number(p.attributes.customerPrice) }))
    .filter((p) => p.price <= PRICE_USD)
    .sort((a, b) => b.price - a.price)
  const chosen = under[0]
  if (!chosen) {
    console.error('No USD price point at or under the asking price.')
    process.exit(1)
  }
  await call('/v1/inAppPurchasePriceSchedules', 'POST', {
    data: {
      type: 'inAppPurchasePriceSchedules',
      relationships: {
        inAppPurchase: { data: { type: 'inAppPurchases', id: iap.id } },
        baseTerritory: { data: { type: 'territories', id: 'USA' } },
        manualPrices: { data: [{ type: 'inAppPurchasePrices', id: '${price}' }] },
      },
    },
    included: [
      {
        type: 'inAppPurchasePrices',
        id: '${price}',
        attributes: { startDate: null },
        relationships: { inAppPurchasePricePoint: { data: { type: 'inAppPurchasePricePoints', id: chosen.id } } },
      },
    ],
  })
  console.log(`✓ price schedule set — USD ${chosen.price.toFixed(2)} base, the other territories follow Apple's equalisation`)
}

// ---- the territories -------------------------------------------------------------------

const availability = await fetch(`${API}/v2/inAppPurchases/${iap.id}/inAppPurchaseAvailability`, {
  headers: { Authorization: `Bearer ${token()}` },
})
if (availability.ok && (await availability.json()).data) {
  console.log('✓ availability — already there')
} else if (CHECK) {
  console.log('· availability — would be every territory, and new ones as they open')
} else {
  const territories = await all('/v1/territories?limit=200')
  await call('/v1/inAppPurchaseAvailabilities', 'POST', {
    data: {
      type: 'inAppPurchaseAvailabilities',
      attributes: { availableInNewTerritories: true },
      relationships: {
        inAppPurchase: { data: { type: 'inAppPurchases', id: iap.id } },
        availableTerritories: { data: territories.map((t: any) => ({ type: 'territories', id: t.id })) },
      },
    },
  })
  console.log(`✓ availability — ${territories.length} territories, and new ones as they open`)
}

console.log(`\nProduct id: ${PRODUCT_ID}. A review screenshot and the first build that sells it are submitted together.`)
