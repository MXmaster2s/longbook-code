#!/usr/bin/env -S npx tsx
// Makes the one subscription the app sells — longbook Cloud, monthly — through App Store
// Connect's API: its group, the English words for both, its price in every territory and
// where it is sold. Nothing is created twice: every step reads first. `--check` reports
// without writing. Run: npm run asc:subscription -- --check
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { createSign } from 'node:crypto'
import { homedir } from 'node:os'
import { join } from 'node:path'

const BUNDLE_ID = 'app.longbook.longbook'
// The app reads this product id; StoreClient.swift carries the same literal.
const PRODUCT_ID = 'app.longbook.cloud.monthly'
// The group's reference name and the name subscribers see for it: one product, one level.
const GROUP = 'longbook Cloud'
const NAME = 'longbook Cloud'
// App Store Connect caps the display name at 30 characters and the description at 45.
const DISPLAY_NAME = 'longbook Cloud'
const DESCRIPTION = 'Hosted copy for your AI, statements, reports'
const REVIEW_NOTE = "A monthly subscription for every feature that uses longbook's server: the hosted copy an AI reads, statement reading and shared reports. A licence purchase includes its first 12 months. Family Sharing covers the buyer's family. The app itself is the separate one-time licence."
const PERIOD = 'ONE_MONTH'
// The price the site names; the nearest App Store price point at or under it is chosen.
const PRICE_USD = 4
const CHECK = process.argv.includes('--check')

const caps: [string, string, number][] = [['display name', DISPLAY_NAME, 30], ['description', DESCRIPTION, 45], ['group name', GROUP, 30]]
for (const [what, text, max] of caps) {
  if (text.length > max) {
    console.error(`The ${what} is ${text.length} characters; the limit is ${max}.`)
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
/** A single related record, or null where App Store Connect answers 404 for "none yet". */
const one = async (path: string): Promise<any | null> => {
  const res = await fetch(`${API}${path}`, { headers: { Authorization: `Bearer ${token()}` } })
  if (!res.ok) return null
  return (await res.json()).data ?? null
}
const related = (row: any, name: string): string | undefined => row?.relationships?.[name]?.data?.id
const sub = (id: string) => ({ data: { type: 'subscriptions', id } })

// ---- the app ---------------------------------------------------------------------------

const apps = await call(`/v1/apps?filter[bundleId]=${BUNDLE_ID}`)
const app = apps.data?.[0]
if (!app) {
  console.error(`No App Store Connect record for ${BUNDLE_ID}.`)
  process.exit(1)
}
console.log(`✓ app ${app.attributes.name} (${app.id}) for ${BUNDLE_ID}`)

// ---- the group -------------------------------------------------------------------------

const groups = await all(`/v1/apps/${app.id}/subscriptionGroups?limit=200`)
let group = groups.find((g: any) => g.attributes.referenceName === GROUP)
// The product made by hand in another group would be a second one: stop rather than add to it.
for (const g of groups) {
  if (group && g.id === group.id) continue
  const rows = await all(`/v1/subscriptionGroups/${g.id}/subscriptions?limit=200`)
  if (rows.some((s: any) => s.attributes.productId === PRODUCT_ID)) {
    console.error(`${PRODUCT_ID} already exists in the group "${g.attributes.referenceName}" (${g.id}), not in "${GROUP}".`)
    process.exit(1)
  }
}
if (group) {
  console.log(`✓ subscription group "${GROUP}" — already there (${group.id})`)
} else if (CHECK) {
  console.log(`· subscription group "${GROUP}" — would be created`)
} else {
  const made = await call('/v1/subscriptionGroups', 'POST', {
    data: {
      type: 'subscriptionGroups',
      attributes: { referenceName: GROUP },
      relationships: { app: { data: { type: 'apps', id: app.id } } },
    },
  })
  group = made.data
  console.log(`✓ subscription group "${GROUP}" created (${group.id})`)
}
if (!group) {
  console.log(`· and then: group en-US words, subscription ${PRODUCT_ID} (${PERIOD}, family sharable, level 1), its en-US words, a USD price nearest under $${PRICE_USD} with Apple's equalisation elsewhere, and every territory`)
  process.exit(0)
}

// ---- the group's words -----------------------------------------------------------------

const groupLocales = await all(`/v1/subscriptionGroups/${group.id}/subscriptionGroupLocalizations?limit=50`)
if (groupLocales.some((l: any) => l.attributes.locale === 'en-US')) {
  console.log('✓ group en-US words — already there')
} else if (CHECK) {
  console.log('· group en-US words — would be written')
} else {
  await call('/v1/subscriptionGroupLocalizations', 'POST', {
    data: {
      type: 'subscriptionGroupLocalizations',
      attributes: { name: GROUP, locale: 'en-US' },
      relationships: { subscriptionGroup: { data: { type: 'subscriptionGroups', id: group.id } } },
    },
  })
  console.log('✓ group en-US words written')
}

// ---- the subscription ------------------------------------------------------------------

const subs = await all(`/v1/subscriptionGroups/${group.id}/subscriptions?limit=200`)
let product = subs.find((s: any) => s.attributes.productId === PRODUCT_ID)
if (product) {
  console.log(`✓ subscription ${PRODUCT_ID} — already there (${product.attributes.state})`)
  if (product.attributes.subscriptionPeriod !== PERIOD) console.log(`! its period is ${product.attributes.subscriptionPeriod}, not ${PERIOD}; change it in App Store Connect`)
  // Cloud covers the buyer's Apple family. Apple cannot turn Family Sharing off once it is on.
  if (!product.attributes.familySharable) {
    if (CHECK) console.log('· Family Sharing — would be turned on (permanent)')
    else {
      await call(`/v1/subscriptions/${product.id}`, 'PATCH', { data: { type: 'subscriptions', id: product.id, attributes: { familySharable: true } } })
      console.log('✓ Family Sharing turned on')
    }
  }
  if (product.attributes.reviewNote !== REVIEW_NOTE) {
    if (CHECK) console.log('· review note — would be rewritten')
    else {
      await call(`/v1/subscriptions/${product.id}`, 'PATCH', { data: { type: 'subscriptions', id: product.id, attributes: { reviewNote: REVIEW_NOTE } } })
      console.log('✓ review note rewritten')
    }
  }
} else if (CHECK) {
  console.log(`· subscription ${PRODUCT_ID} — would be created (${PERIOD}, family sharable, level 1)`)
} else {
  const made = await call('/v1/subscriptions', 'POST', {
    data: {
      type: 'subscriptions',
      attributes: { name: NAME, productId: PRODUCT_ID, subscriptionPeriod: PERIOD, familySharable: true, reviewNote: REVIEW_NOTE, groupLevel: 1 },
      relationships: { group: { data: { type: 'subscriptionGroups', id: group.id } } },
    },
  })
  product = made.data
  console.log(`✓ subscription ${PRODUCT_ID} created (${product.attributes.state})`)
}
if (!product) {
  console.log(`· and then: its en-US words, a USD price nearest under $${PRICE_USD} with Apple's equalisation elsewhere, and every territory`)
  process.exit(0)
}

// ---- the words -------------------------------------------------------------------------

const locales = await all(`/v1/subscriptions/${product.id}/subscriptionLocalizations?limit=50`)
if (locales.some((l: any) => l.attributes.locale === 'en-US')) {
  console.log('✓ en-US words — already there')
} else if (CHECK) {
  console.log('· en-US words — would be written')
} else {
  await call('/v1/subscriptionLocalizations', 'POST', {
    data: {
      type: 'subscriptionLocalizations',
      attributes: { name: DISPLAY_NAME, description: DESCRIPTION, locale: 'en-US' },
      relationships: { subscription: sub(product.id) },
    },
  })
  console.log('✓ en-US words written')
}

const territories = await all('/v1/territories?limit=200')
// ---- the territories -------------------------------------------------------------------

// Apple refuses a price in a territory the product is not yet available in, so this comes first.
// API 4.4 deprecated this resource for subscriptionPlanAvailabilities (planType MONTHLY);
// it still answers. Switch when it stops.
if (await one(`/v1/subscriptions/${product.id}/subscriptionAvailability`)) {
  console.log('✓ availability — already there')
} else if (CHECK) {
  console.log('· availability — would be every territory, and new ones as they open')
} else {
  await call('/v1/subscriptionAvailabilities', 'POST', {
    data: {
      type: 'subscriptionAvailabilities',
      attributes: { availableInNewTerritories: true },
      relationships: {
        subscription: sub(product.id),
        availableTerritories: { data: territories.map((t: any) => ({ type: 'territories', id: t.id })) },
      },
    },
  })
  console.log(`✓ availability — ${territories.length} territories, and new ones as they open`)
}

// ---- the price -------------------------------------------------------------------------

// One territory is priced from a chosen point and every other takes that point's
// equalisation. Whatever Apple fills in by itself is read back; only the rest is posted.
const prices = (): Promise<any[]> => all(`/v1/subscriptions/${product.id}/prices?include=territory,subscriptionPricePoint&limit=200`)
const pricedIn = (rows: any[]): Set<string> => new Set(rows.map((p: any) => related(p, 'territory')).filter((t): t is string => !!t))
let current = await prices()
let priced = pricedIn(current)
let basePoint = related(current.find((p: any) => related(p, 'territory') === 'USA'), 'subscriptionPricePoint')
if (basePoint) {
  console.log('✓ USA price — already there')
} else if (CHECK) {
  console.log(`· USA price — would be set at the USD point nearest under $${PRICE_USD}`)
} else {
  const points = await all(`/v1/subscriptions/${product.id}/pricePoints?filter[territory]=USA&limit=200`)
  const under = points
    .map((p: any) => ({ id: p.id as string, price: Number(p.attributes.customerPrice) }))
    .filter((p) => p.price <= PRICE_USD)
    .sort((a, b) => b.price - a.price)
  const chosen = under[0]
  if (!chosen) {
    console.error('No USD price point at or under the asking price.')
    process.exit(1)
  }
  await call('/v1/subscriptionPrices', 'POST', {
    data: {
      type: 'subscriptionPrices',
      relationships: { subscription: sub(product.id), subscriptionPricePoint: { data: { type: 'subscriptionPricePoints', id: chosen.id } } },
    },
  })
  basePoint = chosen.id
  console.log(`✓ USA price set — USD ${chosen.price.toFixed(2)} a month`)
  current = await prices()
  priced = pricedIn(current)
}
const unpriced = territories.filter((t: any) => !priced.has(t.id))
if (!unpriced.length) {
  console.log(`✓ every territory priced (${territories.length})`)
} else if (CHECK || !basePoint) {
  console.log(`· ${unpriced.length} of ${territories.length} territories have no price — would be set from the USA price's equalisation`)
} else {
  const equal = await all(`/v1/subscriptionPricePoints/${basePoint}/equalizations?include=territory&limit=200`)
  const pointFor = new Map(equal.map((p: any) => [related(p, 'territory'), p.id as string]))
  let set = 0
  const none: string[] = []
  for (const t of unpriced) {
    const point = pointFor.get(t.id)
    if (!point) {
      none.push(t.id)
      continue
    }
    await call('/v1/subscriptionPrices', 'POST', {
      data: {
        type: 'subscriptionPrices',
        relationships: { subscription: sub(product.id), subscriptionPricePoint: { data: { type: 'subscriptionPricePoints', id: point } } },
      },
    })
    set++
  }
  console.log(`✓ ${set} territories priced at Apple's equalisation of the USA price`)
  if (none.length) console.log(`! no equalisation for ${none.join(', ')}; price them in App Store Connect`)
}

// ---- the grace period, read only -------------------------------------------------------

// apple-notifications expects DID_FAIL_TO_RENEW with a GRACE_PERIOD subtype, which Apple
// sends only once the app has opted in. The switch is app-wide, so it is reported, not set.
const grace = await one(`/v1/apps/${app.id}/subscriptionGracePeriod`)
if (grace?.attributes?.optIn) {
  console.log(`✓ billing grace period on (${JSON.stringify(grace.attributes)})`)
} else {
  console.log('! billing grace period off: turn it on in App Store Connect → Subscriptions, or lapses skip the grace state')
}

console.log(`\nProduct id: ${PRODUCT_ID}. A review screenshot and the first build that sells it are submitted together.`)
