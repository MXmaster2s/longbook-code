// Currency formatting + spend equivalents. No cross-currency conversion, ever.
import type { Commitment, BillingCycle } from '../model'
import { CURRENCY_SYMBOL } from '../model'

/** Nicer locale per currency so grouping/symbol placement look native. */
const CURRENCY_LOCALE: Record<string, string> = {
  INR: 'en-IN', USD: 'en-US', EUR: 'de-DE', GBP: 'en-GB',
  AED: 'ar-AE', SGD: 'en-SG', AUD: 'en-AU', CAD: 'en-CA', JPY: 'ja-JP',
}

/** Currencies where decimals are noise (whole-number units). */
const NO_DECIMAL = new Set(['INR', 'JPY'])

export interface FmtMoneyOpts {
  /** Force 2 decimal places (exact per-item price). Default trims trailing .00. */
  cents?: boolean
  /**
   * Approximate totals: no decimals for whole-number currencies (INR/JPY),
   * at most one decimal elsewhere (e.g. ₹14,572, $20, $10.9).
   */
  approx?: boolean
}

/** Format an amount in a single currency. Falls back to "SYM 1234" if Intl lacks the currency. */
export function fmtMoney(amount: number | string, currency: string, opts: FmtMoneyOpts = {}): string {
  const n = Number(amount) || 0
  const locale = CURRENCY_LOCALE[currency]
  const noDecimal = NO_DECIMAL.has(currency)
  try {
    if (opts.approx) {
      return new Intl.NumberFormat(locale, {
        style: 'currency',
        currency,
        minimumFractionDigits: 0,
        maximumFractionDigits: noDecimal ? 0 : 1,
      }).format(n)
    }
    const s = new Intl.NumberFormat(locale, {
      style: 'currency',
      currency,
      minimumFractionDigits: opts.cents ? 2 : 0,
      maximumFractionDigits: 2,
    }).format(n)
    return opts.cents ? s : s.replace(/\.00$/, '')
  } catch {
    const sym = CURRENCY_SYMBOL[currency] ?? `${currency} `
    const digits = opts.approx ? (noDecimal ? 0 : 1) : opts.cents ? 2 : 0
    return `${sym}${n.toFixed(digits)}`
  }
}

/**
 * A per-currency total as one string: "₹149 + $20". Never blended — each currency keeps
 * its own symbol, joined with " + ". Menu bar and dashboard hero both render through
 * this, so the same day reads identically. Order is the caller's.
 */
export function fmtMoneyTotals(sums: { currency: string; amount: number }[], opts: FmtMoneyOpts = {}): string {
  return sums.map((s) => fmtMoney(s.amount, s.currency, opts)).join(' + ')
}

/** Days assumed for a custom cycle when unset. */
const DEFAULT_CUSTOM_DAYS = 30

function customDays(sub: Pick<Commitment, 'custom_cycle_days'>): number {
  return Math.max(1, sub.custom_cycle_days || DEFAULT_CUSTOM_DAYS)
}

/** Amount normalised to a monthly figure. One-time payments are not recurring → 0. */
export function monthlyEquiv(sub: Pick<Commitment, 'amount' | 'billing_cycle' | 'custom_cycle_days'>): number {
  const a = Number(sub.amount) || 0
  if (sub.billing_cycle === 'once') return 0
  if (sub.billing_cycle === 'yearly') return a / 12
  if (sub.billing_cycle === 'custom') return (a * (365.25 / 12)) / customDays(sub)
  return a
}

/** Amount normalised to an annual figure. One-time payments are not recurring → 0. */
export function annualEquiv(sub: Pick<Commitment, 'amount' | 'billing_cycle' | 'custom_cycle_days'>): number {
  const a = Number(sub.amount) || 0
  if (sub.billing_cycle === 'once') return 0
  if (sub.billing_cycle === 'yearly') return a
  if (sub.billing_cycle === 'custom') return (a * 365.25) / customDays(sub)
  return a * 12
}

/**
 * e.g. "monthly", "yearly", "one-time", "every 90 days".
 *
 * A label, not a value: authored in the register longbook speaks (`domain/casing.ts`),
 * not cased to match the union it reads. Callers render as-is.
 */
export function cycleLabel(sub: Pick<Commitment, 'billing_cycle' | 'custom_cycle_days'>): string {
  const cycle = sub.billing_cycle as BillingCycle
  if (cycle === 'monthly') return 'monthly'
  if (cycle === 'yearly') return 'yearly'
  if (cycle === 'once') return 'one-time'
  return `every ${sub.custom_cycle_days ?? DEFAULT_CUSTOM_DAYS} days`
}
