// The launch price steps up once a tier fills, whichever seller made the sale. Each step is
// claimed once, so two sales landing together raise it once. The App Store price is set
// through its API; Polar's is raised by hand from the email this sends.
import { TIERS, seatsFor, tiersDue } from './licence-seats.ts'

export interface StepDeps {
  sold(): Promise<number>
  /** True only for the call that took this tier's step. */
  claim(tier: number, price: string, sold: number): Promise<boolean>
  /** Throws when the App Store price could not be set. */
  setAppStorePrice(price: string): Promise<void>
  record(tier: number, error: string | null): Promise<void>
  notify(subject: string, text: string): Promise<void>
}

export interface StepNotice {
  sold: number
  price: string
  /** Seats left at this price; null when none are counted. */
  left: number | null
  appStoreError: string | null
}

export function stepNotice(n: StepNotice): { subject: string; text: string } {
  const appStore = n.appStoreError
    ? `The App Store price could not be changed automatically (${n.appStoreError}). Set the licence to $${n.price} in App Store Connect, under In-App Purchases.`
    : `The App Store price of the licence is now $${n.price}, set automatically. Apple applies it within the hour.`
  const polar = `Set the longbook product to $${n.price} on Polar by hand, in the Polar dashboard under Products. The Polar price is never changed automatically.`
  const left = n.left === null ? '' : `\n\n${n.left} seats are left at $${n.price}.`
  return {
    subject: `longbook: ${n.sold} licences sold, the price is now $${n.price}`,
    text: `${n.sold} licences have been bought on the App Store and longbook.app together, so the launch price stepped up.\n\n${appStore}\n\n${polar}${left}`,
  }
}

/** Applies every step the count has reached and not yet claimed; returns the tiers it applied. */
export async function stepPrices(deps: StepDeps): Promise<number[]> {
  const sold = await deps.sold()
  const now = seatsFor(sold)
  const applied: number[] = []
  for (const tier of tiersDue(sold)) {
    const price = TIERS[tier]!.price
    if (!(await deps.claim(tier, price, sold))) continue
    let appStoreError: string | null = null
    try {
      await deps.setAppStorePrice(price)
    } catch (e) {
      appStoreError = (e as Error).message.slice(0, 300)
    }
    await deps.record(tier, appStoreError)
    const mail = stepNotice({ sold, price, left: now.tier === tier ? now.left : null, appStoreError })
    await deps.notify(mail.subject, mail.text)
    applied.push(tier)
  }
  return applied
}
