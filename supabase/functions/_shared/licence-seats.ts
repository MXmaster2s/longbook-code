// The licence's launch pricing: the first 100 App Store purchases at the first price, the next
// 250 at the second, every one after at the third. Pure, so the page, the purchase function
// and the tests read the same rule.

export interface Tier {
  /** Seats sold before this tier opens. */
  from: number
  /** Seats this tier holds; null for the last, which never fills. */
  size: number | null
  /** The App Store's US price in dollars; Apple has $38, $98 and $149 as price points, not $148. */
  price: string
}

export const TIERS: Tier[] = [
  { from: 0, size: 100, price: '38' },
  { from: 100, size: 250, price: '98' },
  { from: 350, size: null, price: '149' },
]

export interface Seats {
  sold: number
  /** Which tier is on sale now, from 0. */
  tier: number
  price: string
  /** Seats left at this price; null in the last tier. */
  left: number | null
  /** The next price, once this tier fills; null in the last tier. */
  next: string | null
}

export function seatsFor(sold: number, tiers: Tier[] = TIERS): Seats {
  const n = Math.max(0, Math.floor(sold))
  const at = tiers.findIndex((t) => t.size === null || n < t.from + t.size)
  const tier = tiers[at]!
  return {
    sold: n,
    tier: at,
    price: tier.price,
    left: tier.size === null ? null : tier.from + tier.size - n,
    next: tiers[at + 1]?.price ?? null,
  }
}

/** Every price step the count has reached, from the second tier on: each is applied once, so a
 *  step two sales raced past is still applied. */
export function tiersDue(sold: number, tiers: Tier[] = TIERS): number[] {
  const at = seatsFor(sold, tiers).tier
  return Array.from({ length: at }, (_, i) => i + 1)
}
