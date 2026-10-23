// Spend grouped by category, account and member — summed from the charges written in a
// window, never amortised from a rule. Where the app draws the same groups it uses the same
// window arithmetic, so the two cannot disagree. Money in and transfers are in no group:
// `chargesInRange` reads spending only.
import type { Commitment, Member, Account, ChargeRow } from './model'
import { todayMid, addMonthsClamped } from './domain/dates'
import { chargesInRange } from './ledger'

/** The default window every spend tool answers for: the twelve months from today. */
export function defaultWindow(today: Date = todayMid()): { from: Date; to: Date } {
  return { from: today, to: new Date(addMonthsClamped(today, 12).getTime() - 86400000) }
}

interface GroupSpend {
  /** Total per currency over the window, e.g. { INR: 7788, USD: 240 }. Never blended. */
  totalByCurrency: Record<string, number>
  /** Charges contributing per currency. */
  countByCurrency: Record<string, number>
  /** Distinct commitments in the group. */
  commitments: number
  /** Charges in the group across every currency. */
  count: number
}

export interface TagSpend extends GroupSpend {
  /** The raw category value, or null when the commitment has none. */
  tag: string | null
  /** Display label — 'Untagged' stands in for a missing category. */
  name: string
}

export interface MethodSpend extends GroupSpend {
  methodId: string | null
  name: string
}

export interface MemberSpend extends GroupSpend {
  memberId: string | null
  name: string
}

function grouped<T extends GroupSpend>(
  subs: Commitment[],
  rows: ChargeRow[] | undefined,
  from: Date,
  to: Date,
  keyOf: (sub: Commitment) => string,
  make: (sub: Commitment) => Omit<T, keyof GroupSpend>,
): T[] {
  const groups = new Map<string, T & { ids: Set<string> }>()
  for (const c of chargesInRange(subs, rows, from, to)) {
    const key = keyOf(c.sub)
    let entry = groups.get(key)
    if (!entry) {
      entry = { ...make(c.sub), totalByCurrency: {}, countByCurrency: {}, commitments: 0, count: 0, ids: new Set() } as T & { ids: Set<string> }
      groups.set(key, entry)
    }
    entry.totalByCurrency[c.currency] = (entry.totalByCurrency[c.currency] ?? 0) + c.amount
    entry.countByCurrency[c.currency] = (entry.countByCurrency[c.currency] ?? 0) + 1
    entry.count += 1
    entry.ids.add(c.sub.id)
  }
  return [...groups.values()]
    .map(({ ids, ...rest }) => ({ ...rest, commitments: ids.size }) as unknown as T)
    .sort(
      (a, b) =>
        Object.values(b.totalByCurrency).reduce((x, y) => x + y, 0) -
        Object.values(a.totalByCurrency).reduce((x, y) => x + y, 0),
    )
}

/** Per-category spend over a window, split by currency. */
export function spendByTag(
  subs: Commitment[],
  rows: ChargeRow[] | undefined,
  from: Date,
  to: Date,
): TagSpend[] {
  return grouped<TagSpend>(subs, rows, from, to, (s) => s.tag?.trim() || 'Untagged', (s) => ({
    tag: s.tag,
    name: s.tag?.trim() || 'Untagged',
  }))
}

/** Per-account spend over a window, split by currency. */
export function spendByMethod(
  subs: Commitment[],
  rows: ChargeRow[] | undefined,
  methods: Account[],
  from: Date,
  to: Date,
): MethodSpend[] {
  const nameOf = (id: string | null) => (id ? methods.find((m) => m.id === id)?.name ?? 'Unknown' : 'Unassigned')
  return grouped<MethodSpend>(subs, rows, from, to, (s) => s.account_id ?? '__unassigned', (s) => ({
    methodId: s.account_id,
    name: nameOf(s.account_id),
  }))
}

/** Per-member spend over a window, split by currency. */
export function spendByMember(
  subs: Commitment[],
  rows: ChargeRow[] | undefined,
  members: Member[],
  from: Date,
  to: Date,
): MemberSpend[] {
  const nameOf = (id: string | null) => (id ? members.find((m) => m.id === id)?.name ?? 'Unknown' : 'Unknown')
  return grouped<MemberSpend>(subs, rows, from, to, (s) => s.member_id ?? '__unknown', (s) => ({
    memberId: s.member_id,
    name: nameOf(s.member_id),
  }))
}
