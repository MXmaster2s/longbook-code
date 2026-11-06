// The ledger, read: every charge is a stored row, and nothing here computes an occurrence.
// Ported in BEHAVIOUR to Swift's Selectors — if the two drift, the hosted server and the
// app disagree about one file. The one generator, `planCharges`, writes rows on request.
import type { Commitment, ChargeRow } from './model'
import { parseDate, toISO, todayMid, daysBetween, addMonthsClamped } from './domain/dates'
import { isEffectivelyActive, cancelInfo } from './domain/renewal'

/**
 * One charge as a reader sees it: the stored row joined to its commitment. A charge behind
 * today reads as paid whatever its row says — the money was due and the day has passed; the
 * row keeps its own mark.
 */
export interface Charge {
  sub: Commitment
  row: ChargeRow
  date: Date
  amount: number
  /** The row's own currency when it states one, else the commitment's. */
  currency: string
  /** The row's mark, or the calendar: a charge dated before today is paid. */
  paid: boolean
}

function join(sub: Commitment, row: ChargeRow, today: Date): Charge | null {
  let date: Date
  try {
    date = parseDate(row.date)
  } catch {
    return null
  }
  if (Number.isNaN(date.getTime())) return null
  return { sub, row, date, amount: row.amount, currency: row.currency ?? sub.currency, paid: row.paid || date < today }
}

type Directed = Pick<Commitment, 'direction'>

/** Money that arrives: remembered, never owed, never summed with spending. */
export const isIncome = (sub: Directed): boolean => sub.direction === 'in'

/** A movement between the owner's own accounts: shown and owed, in no sum at all. */
export const isTransfer = (sub: Directed): boolean => sub.direction === 'transfer'

/** What a spending total may hold: neither money in nor a transfer. */
export const isSpending = (sub: Directed): boolean => !isIncome(sub) && !isTransfer(sub)

/**
 * What the file keeps of a direction. Nothing, "" and "out" are a charge, written as
 * absence; any other word is kept as written, so one a newer contract names survives an
 * edit here. Read, an unknown word is still spending.
 */
export function storedDirection(value: unknown): string | null {
  return typeof value === 'string' && value !== '' && value !== 'out' ? value : null
}

/**
 * Every spending charge joined to its commitment, date order — the rows every sum is made
 * of. A row whose commitment is gone, or whose date is unreadable, is skipped. Money in and
 * transfers are not charges: `incomeCharges` and `transferCharges` read them.
 */
export function allCharges(subs: Commitment[], rows: ChargeRow[] | undefined, today: Date = todayMid()): Charge[] {
  return joined(subs, rows, today).filter((c) => isSpending(c.sub))
}

/** Every row of money in, joined and in date order — salary, refunds, interest. */
export function incomeCharges(subs: Commitment[], rows: ChargeRow[] | undefined, today: Date = todayMid()): Charge[] {
  return joined(subs, rows, today).filter((c) => isIncome(c.sub))
}

/** Every transfer row, joined and in date order — a card bill, a standing move to savings. */
export function transferCharges(subs: Commitment[], rows: ChargeRow[] | undefined, today: Date = todayMid()): Charge[] {
  return joined(subs, rows, today).filter((c) => isTransfer(c.sub))
}

function joined(subs: Commitment[], rows: ChargeRow[] | undefined, today: Date): Charge[] {
  const byId = new Map(subs.map((s) => [s.id, s]))
  const out: Charge[] = []
  for (const row of rows ?? []) {
    const sub = byId.get(row.commitment_id)
    if (!sub) continue
    const charge = join(sub, row, today)
    if (charge) out.push(charge)
  }
  return out.sort((a, b) => a.date.getTime() - b.date.getTime())
}

/** The rows of one commitment, date order. */
export function chargesOf(sub: Commitment, rows: ChargeRow[] | undefined, today: Date = todayMid()): Charge[] {
  return (rows ?? [])
    .filter((r) => r.commitment_id === sub.id)
    .map((r) => join(sub, r, today))
    .filter((c): c is Charge => c !== null)
    .sort((a, b) => a.date.getTime() - b.date.getTime())
}

/**
 * Every charge across the vault between two days, inclusive. Status is not consulted: a
 * cancelled commitment's past charges happened, and its future ones were removed when it was
 * cancelled. What the rows say is what there is.
 */
export function chargesInRange(
  subs: Commitment[],
  rows: ChargeRow[] | undefined,
  from: Date,
  to: Date,
  today: Date = todayMid(),
): Charge[] {
  return allCharges(subs, rows, today).filter((c) => c.date >= from && c.date <= to)
}

/** The soonest charge for one commitment on or after today — paid or not. */
export function nextChargeOnOrAfter(sub: Commitment, rows: ChargeRow[] | undefined, today: Date = todayMid()): Charge | null {
  return chargesOf(sub, rows, today).find((c) => c.date >= today) ?? null
}

/** The soonest charge on or after today that still needs the owner's attention. */
export function nextUnpaidChargeOnOrAfter(
  sub: Commitment,
  rows: ChargeRow[] | undefined,
  today: Date = todayMid(),
): Charge | null {
  return chargesOf(sub, rows, today).find((c) => c.date >= today && !c.paid) ?? null
}

/**
 * A commitment is what still lies ahead. A recurring one is a commitment while active; a
 * one-time one until its charge is behind today or marked paid, after which it is that charge
 * and nothing more. One with no charge written is still owed.
 */
export function isLiveCommitment(sub: Commitment, rows: ChargeRow[] | undefined, today: Date = todayMid()): boolean {
  if (!isEffectivelyActive(sub, today)) return false
  if (sub.billing_cycle !== 'once') return true
  const own = chargesOf(sub, rows, today)
  return own.length === 0 || own.some((c) => c.date >= today && !c.paid)
}

/** The commitments still ahead, in the vault's own order. */
export function liveCommitments(subs: Commitment[], rows: ChargeRow[] | undefined, today: Date = todayMid()): Commitment[] {
  return subs.filter((s) => isLiveCommitment(s, rows, today))
}

/** The last day this commitment has a charge written for — how far its plan reaches. */
export function plannedThrough(sub: Commitment, rows: ChargeRow[] | undefined): Date | null {
  const all = chargesOf(sub, rows)
  return all.length ? all[all.length - 1]!.date : null
}

export interface DueMeta {
  sub: Commitment
  date: Date
  /** Whole days from today (0 = today, negative = overdue). */
  days: number
}

/** Effectively-active commitments with an unpaid charge ahead, soonest first — transfers among them. */
export function activeUpcoming(subs: Commitment[], rows: ChargeRow[] | undefined, today: Date = todayMid()): DueMeta[] {
  return subs
    .filter((s) => isEffectivelyActive(s, today))
    .map((sub) => {
      const next = nextUnpaidChargeOnOrAfter(sub, rows, today)
      return next ? { sub, date: next.date, days: daysBetween(today, next.date) } : null
    })
    .filter((d): d is DueMeta => d !== null)
    .sort((a, b) => a.date.getTime() - b.date.getTime() || a.sub.name.localeCompare(b.sub.name))
}

export interface PaymentDay {
  date: Date
  /** Whole days from today (0 = today). */
  days: number
  /** The spending landing on this day, across currencies, biggest first — all a total may hold. */
  charges: Charge[]
  /** The transfers due the same day, biggest first: shown beside the charges, never summed. */
  transfers: Charge[]
}

/** The day's rows from each commitment's next unpaid charge; `anchor` picks whose day it is. */
function owedDay(subs: Commitment[], rows: ChargeRow[] | undefined, today: Date, anchor: (c: Charge) => boolean): PaymentDay | null {
  const nexts = subs
    .filter((s) => !isIncome(s) && isEffectivelyActive(s, today))
    .map((s) => nextUnpaidChargeOnOrAfter(s, rows, today))
    .filter((c): c is Charge => c !== null)
  const anchors = nexts.filter(anchor)
  if (anchors.length === 0) return null
  const soonest = anchors.reduce((a, b) => (a.date < b.date ? a : b)).date
  const key = toISO(soonest)
  const onDay = nexts.filter((c) => toISO(c.date) === key).sort((a, b) => b.amount - a.amount)
  return {
    date: soonest,
    days: daysBetween(today, soonest),
    charges: onDay.filter((c) => isSpending(c.sub)),
    transfers: onDay.filter((c) => isTransfer(c.sub)),
  }
}

/**
 * The nearest day on or after today that spending is still owed. A *day*, not a single
 * row — two things due together both show. A transfer never makes a payment day; one due
 * on that day rides in `transfers`.
 */
export function nextPaymentDay(subs: Commitment[], rows: ChargeRow[] | undefined, today: Date = todayMid()): PaymentDay | null {
  return owedDay(subs, rows, today, (c) => isSpending(c.sub))
}

/** The nearest day anything is still owed — spending or a transfer. Either list may be empty, never both. */
export function nextDueDay(subs: Commitment[], rows: ChargeRow[] | undefined, today: Date = todayMid()): PaymentDay | null {
  return owedDay(subs, rows, today, () => true)
}

/**
 * A plan that has run short: active recurring commitments with no cancelling date whose last
 * written charge falls within `withinDays` of today. Named, never extended on anyone's behalf.
 */
export function plansRunningShort(
  subs: Commitment[],
  rows: ChargeRow[] | undefined,
  withinDays = 90,
  today: Date = todayMid(),
): Array<{ sub: Commitment; through: Date }> {
  const limit = new Date(today.getTime() + withinDays * 86400000)
  return subs
    .filter((s) => isEffectivelyActive(s, today) && s.billing_cycle !== 'once' && !s.ends_on)
    .map((sub) => ({ sub, through: plannedThrough(sub, rows) }))
    .filter((p): p is { sub: Commitment; through: Date } => p.through !== null && p.through <= limit)
    .sort((a, b) => a.through.getTime() - b.through.getTime())
}

export interface CurrencyAmount {
  currency: string
  amount: number
}

/** One amount per currency — never blended, biggest first. */
export function sumByCurrency(charges: Charge[]): CurrencyAmount[] {
  const totals = new Map<string, number>()
  for (const c of charges) totals.set(c.currency, (totals.get(c.currency) ?? 0) + c.amount)
  return [...totals].map(([currency, amount]) => ({ currency, amount })).sort((a, b) => b.amount - a.amount)
}

export interface MonthPoint {
  year: number
  /** 0-indexed month. */
  month: number
  total: number
  /** The month is ahead of today's — its rows are the plan, not the record. */
  estimated: boolean
}

/**
 * Monthly totals in one currency, `back` past months through `forward` future months (index
 * 0 = current month), every month a bucket. Read straight from the rows: a month nobody wrote
 * a charge for is an empty month, not a projected one.
 */
export function spendSeriesRange(
  subs: Commitment[],
  rows: ChargeRow[] | undefined,
  currency: string,
  back: number,
  forward: number,
  today: Date = todayMid(),
): MonthPoint[] {
  const first = new Date(today.getFullYear(), today.getMonth() - back, 1)
  const last = new Date(today.getFullYear(), today.getMonth() + forward + 1, 0)
  const points: MonthPoint[] = []
  for (let i = 0; i <= back + forward; i++) {
    const d = new Date(first.getFullYear(), first.getMonth() + i, 1)
    points.push({ year: d.getFullYear(), month: d.getMonth(), total: 0, estimated: i > back })
  }
  for (const c of chargesInRange(subs, rows, first, last, today)) {
    if (c.currency !== currency) continue
    const i = (c.date.getFullYear() - first.getFullYear()) * 12 + c.date.getMonth() - first.getMonth()
    if (i >= 0 && i < points.length) points[i]!.total += c.amount
  }
  return points
}

// ---- the one generator ------------------------------------------------------------------

/** The most days a custom cycle holds between charges, a hundred years. Every door refuses more. */
export const CUSTOM_DAYS_LIMIT = 36_500

/** One cycle step from an anchor. Months for monthly and yearly, days for custom; once never steps. */
export function stepFrom(sub: Pick<Commitment, 'billing_cycle' | 'custom_cycle_days'>, anchor: Date, k: number): Date {
  if (k === 0) return anchor
  switch (sub.billing_cycle) {
    case 'once':
      return anchor
    case 'custom': {
      // Days a file holds past what a write takes step as the most a write takes, as the app steps them.
      const days = Math.min(Math.max(1, sub.custom_cycle_days ?? 30), CUSTOM_DAYS_LIMIT)
      return new Date(anchor.getTime() + k * days * 86400000)
    }
    case 'monthly':
      return addMonthsClamped(anchor, k)
    case 'yearly':
      return addMonthsClamped(anchor, k * 12)
  }
}

/**
 * The rows a plan writes, on request and never otherwise: from `first`, one per cycle, for
 * `months` calendar months (exclusive) or up to the cancelling date (inclusive). A one-time
 * commitment gets its single charge. Dates already holding a row are skipped.
 */
export function planCharges(
  sub: Pick<Commitment, 'id' | 'billing_cycle' | 'custom_cycle_days' | 'ends_on'>,
  first: Date,
  months: number,
  amount: number,
  existing: ReadonlySet<string>,
  writtenAt: string,
  horizonFrom: Date = first,
): ChargeRow[] {
  // The horizon is measured from `horizonFrom` — the first charge for a new plan, the last
  // written charge when extending — so "twelve more months" never reaches a renewal three
  // years out just because it is the next one.
  const horizon = addMonthsClamped(horizonFrom, Math.max(1, months))
  const cancel = cancelInfo(sub).date
  const out: ChargeRow[] = []
  for (let k = 0; k < 4000; k++) {
    const date = stepFrom(sub, first, k)
    if (sub.billing_cycle !== 'once' && date >= horizon) break
    if (cancel && date > cancel) break
    const iso = toISO(date)
    if (!existing.has(iso)) {
      out.push({ commitment_id: sub.id, date: iso, amount, paid: false, basis: 'plan', written_at: writtenAt })
    }
    if (sub.billing_cycle === 'once') break
  }
  return out
}
