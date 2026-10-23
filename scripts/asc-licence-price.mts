#!/usr/bin/env -S npx tsx
// Sets the licence's App Store price now: the US price as the base and every storefront in
// supabase/functions/_shared/regional-prices.ts at its own price, as the server's tier step does.
// `--check` shows the prices without writing. Run: npm run asc:price -- --price 38
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { createSign } from 'node:crypto'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { REGIONAL_PRICES } from '../supabase/functions/_shared/regional-prices.ts'

const CHECK = process.argv.includes('--check')
const priceAt = process.argv.indexOf('--price')
const PRICE = priceAt >= 0 ? String(Number(process.argv[priceAt + 1])) : ''
if (!REGIONAL_PRICES[PRICE]) {
  console.error('Pass --price with a launch tier: 38, 98 or 149.')
  process.exit(1)
}

const keychain = (service: string): string =>
  execFileSync('security', ['find-generic-password', '-s', service, '-w'], { encoding: 'utf8' }).trim()
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
  return `${header}.${payload}.${b64u(signer.sign({ key: readFileSync(KEY_PATH), dsaEncoding: 'ieee-p1363' }))}`
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
    console.error(`App Store Connect refused ${method} ${path}: ${res.status}\n${text.slice(0, 600)}`)
    process.exit(1)
  }
  return text ? JSON.parse(text) : {}
}
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

const iap = (await all('/v1/apps/6795070908/inAppPurchasesV2?limit=200')).find((p: any) => p.attributes.productId === 'app.longbook.licence')
const prices = [['USA', PRICE], ...Object.entries(REGIONAL_PRICES[PRICE])]
const points: string[] = []
for (const [territory, amount] of prices) {
  const hit = (await all(`/v2/inAppPurchases/${iap.id}/pricePoints?filter[territory]=${territory}&limit=200`))
    .find((p: any) => Number(p.attributes.customerPrice) === Number(amount))
  if (!hit) {
    console.error(`No ${territory} price point at ${amount}.`)
    process.exit(1)
  }
  points.push(hit.id)
  console.log(`· ${territory} ${amount}`)
}
if (CHECK) process.exit(0)
const place = (i: number) => `\${price-${i}}`
await call('/v1/inAppPurchasePriceSchedules', 'POST', {
  data: {
    type: 'inAppPurchasePriceSchedules',
    relationships: {
      inAppPurchase: { data: { type: 'inAppPurchases', id: iap.id } },
      baseTerritory: { data: { type: 'territories', id: 'USA' } },
      manualPrices: { data: points.map((_, i) => ({ type: 'inAppPurchasePrices', id: place(i) })) },
    },
  },
  included: points.map((point, i) => ({
    type: 'inAppPurchasePrices',
    id: place(i),
    attributes: { startDate: null },
    relationships: {
      inAppPurchaseV2: { data: { type: 'inAppPurchases', id: iap.id } },
      inAppPurchasePricePoint: { data: { type: 'inAppPurchasePricePoints', id: point } },
    },
  })),
})
console.log('✓ price schedule set; every other storefront follows Apple’s equivalents of the US price')
