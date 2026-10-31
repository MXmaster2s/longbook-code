// The price step bound to the database, App Store Connect and the owner's inbox. Either
// seller's function runs it after a sale; the claim lives in licence_price_steps.
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { setLicencePrice, type AscKey } from './app-store-price.ts'
import { notifyOwner } from './owner-mail.ts'
import { stepPrices } from './price-step.ts'
import { soldSeats } from './seat-count.ts'

const APP_STORE_PRODUCT_ID = 'app.longbook.licence'

/** App Store Connect's key from the function secrets, or null when any part is missing. */
export function ascKeyFromEnv(read: (name: string) => string | undefined): AscKey | null {
  const privateKey = read('ASC_PRIVATE_KEY'), keyId = read('ASC_KEY_ID'), issuerId = read('ASC_ISSUER_ID')
  return privateKey && keyId && issuerId ? { privateKey, keyId, issuerId } : null
}

export async function runPriceStep(
  service: SupabaseClient,
  keys: { asc: AscKey | null; resend: string | undefined },
): Promise<number[]> {
  return await stepPrices({
    sold: () => soldSeats(service),
    async claim(tier, price, sold) {
      const { data } = await service.from('licence_price_steps').insert({ tier, price, sold }).select('tier').maybeSingle()
      return !!data
    },
    async setAppStorePrice(price) {
      if (!keys.asc) throw new Error('no App Store Connect key on the function')
      await setLicencePrice(keys.asc, APP_STORE_PRODUCT_ID, price)
    },
    async record(tier, error) {
      await service.from('licence_price_steps')
        .update(error ? { error } : { applied_at: new Date().toISOString() }).eq('tier', tier)
    },
    notify: (subject, text) => notifyOwner(keys.resend, subject, text),
  })
}
