// Sets the licence's App Store price through App Store Connect's API: the US price as the base,
// the storefronts in REGIONAL_PRICES at their own price, every other one following Apple's
// equivalents, starting now. Used when a launch
// pricing tier fills. The key is App Store Connect's, held as function secrets.
import * as jose from 'npm:jose@5'
import { REGIONAL_PRICES } from './regional-prices.ts'

const API = 'https://api.appstoreconnect.apple.com'
const APP_ID = '6795070908'

export interface AscKey {
  keyId: string
  issuerId: string
  /** The .p8 file's text. */
  privateKey: string
}

async function token(key: AscKey): Promise<string> {
  const signing = await jose.importPKCS8(key.privateKey, 'ES256')
  return await new jose.SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: key.keyId, typ: 'JWT' })
    .setIssuer(key.issuerId)
    .setIssuedAt()
    .setExpirationTime('10m')
    .setAudience('appstoreconnect-v1')
    .sign(signing)
}

/** Sets `price` in US dollars ("98") on the in-app purchase `productId`; throws with Apple's words. */
export async function setLicencePrice(key: AscKey, productId: string, price: string): Promise<void> {
  const auth = { Authorization: `Bearer ${await token(key)}` }
  const get = async (path: string) => {
    const res = await fetch(`${API}${path}`, { headers: auth })
    const body = await res.json()
    if (!res.ok) throw new Error(`${path}: ${res.status} ${body?.errors?.[0]?.detail ?? ''}`)
    return body
  }
  const iaps = await get(`/v1/apps/${APP_ID}/inAppPurchasesV2?limit=50`)
  const iap = (iaps.data ?? []).find((x: { attributes: { productId: string } }) => x.attributes.productId === productId)
  if (!iap) throw new Error(`no in-app purchase ${productId}`)
  const pointAt = async (territory: string, amount: string): Promise<string> => {
    let next: string | null = `/v2/inAppPurchases/${iap.id}/pricePoints?filter[territory]=${territory}&limit=200`
    while (next) {
      const page = await get(next)
      const hit = (page.data ?? []).find((p: { attributes: { customerPrice: string } }) => Number(p.attributes.customerPrice) === Number(amount))
      if (hit) return hit.id
      next = page.links?.next ? String(page.links.next).replace(API, '') : null
    }
    throw new Error(`no ${territory} price point at ${amount}`)
  }
  const prices = [['USA', price], ...Object.entries(REGIONAL_PRICES[String(Number(price))] ?? {})]
  const points = await Promise.all(prices.map(([territory, amount]) => pointAt(territory, amount)))
  const res = await fetch(`${API}/v1/inAppPurchasePriceSchedules`, {
    method: 'POST',
    headers: { ...auth, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      data: {
        type: 'inAppPurchasePriceSchedules',
        relationships: {
          inAppPurchase: { data: { type: 'inAppPurchases', id: iap.id } },
          baseTerritory: { data: { type: 'territories', id: 'USA' } },
          manualPrices: { data: points.map((_, i) => ({ type: 'inAppPurchasePrices', id: `\${price-${i}}` })) },
        },
      },
      included: points.map((point, i) => ({
        type: 'inAppPurchasePrices',
        id: `\${price-${i}}`,
        attributes: { startDate: null },
        relationships: {
          inAppPurchaseV2: { data: { type: 'inAppPurchases', id: iap.id } },
          inAppPurchasePricePoint: { data: { type: 'inAppPurchasePricePoints', id: point } },
        },
      })),
    }),
  })
  if (!res.ok) {
    const body = await res.json().catch(() => ({}))
    throw new Error(`price schedule: ${res.status} ${body?.errors?.[0]?.detail ?? ''}`)
  }
}
