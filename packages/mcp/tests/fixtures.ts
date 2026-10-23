// One seeded memory the tool tests share: two currencies, a yearly row, a custom cycle, a
// cancelled row with its past, and one charge already marked paid. Every charge is a row.
import type { Member, LoadedData, Account, ChargeRow, Commitment } from '@longbook/core'
import { todayMid } from '@longbook/core'

// Anchored on the real today: the rpc tests run the dispatcher with its own clock, so a
// pinned date would put "in 3 days" into the past as the calendar moves.
export const TODAY = todayMid()

const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
export const inDays = (n: number) => iso(new Date(TODAY.getFullYear(), TODAY.getMonth(), TODAY.getDate() + n))
// The day is clamped to the target month's length: day 31 of a 30-day month would otherwise roll into the next.
export const inMonths = (n: number, day = TODAY.getDate()) => {
  const last = new Date(TODAY.getFullYear(), TODAY.getMonth() + n + 1, 0).getDate()
  return iso(new Date(TODAY.getFullYear(), TODAY.getMonth() + n, Math.min(day, last)))
}
// The second charge of a monthlyRun that starts n days out, derived the way monthlyRun derives it.
export const aMonthAfterInDays = (n: number) => {
  const first = new Date(TODAY.getFullYear(), TODAY.getMonth(), TODAY.getDate() + n)
  return iso(new Date(first.getFullYear(), first.getMonth() + 1, first.getDate()))
}

// A month key derived from a date. An assertion that types one instead is true for a month
// and false for every month after it.
export const monthOf = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`

export function mkSub(over: Partial<Commitment> & Pick<Commitment, 'id' | 'name' | 'amount'>): Commitment {
  return {
    currency: 'INR',
    billing_cycle: 'monthly',
    custom_cycle_days: null,
    tag: null,
    status: 'active',
    account_id: null,
    member_id: null,
    notes: null,
    ends_on: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    ...over,
  }
}

export function mkRow(commitment_id: string, date: string, amount: number, over: Partial<ChargeRow> = {}): ChargeRow {
  return { commitment_id, date, amount, paid: false, basis: 'plan', written_at: '2026-01-01T00:00:00Z', ...over }
}

/** A run of monthly rows starting `firstOffsetDays` from today, one per month. */
function monthlyRun(id: string, amount: number, firstOffsetDays: number, months: number, over: Partial<ChargeRow> = {}): ChargeRow[] {
  const first = new Date(TODAY.getFullYear(), TODAY.getMonth(), TODAY.getDate() + firstOffsetDays)
  return Array.from({ length: months }, (_, k) =>
    mkRow(id, iso(new Date(first.getFullYear(), first.getMonth() + k, first.getDate())), amount, over))
}

const member = (id: string, name: string): Member => ({
  id, name, name_key: name.toLowerCase(), tag: null, avatar_seed: id,
  is_incomplete: false, email: null, created_at: '2026-01-01T00:00:00Z',
})

const method = (id: string, name: string): Account => ({
  id, name, name_key: name.toLowerCase(), nickname: null, institution: null, last4: null,
  tag: null, member_id: null, parent_account_id: null, is_incomplete: false, created_at: '2026-01-01T00:00:00Z',
})

export function fixture(): LoadedData {
  const subs: Commitment[] = [
    mkSub({ id: 's-netflix', name: 'Netflix', amount: 649, tag: 'Entertainment', member_id: 'm-diya', account_id: 'pm-icici' }),
    mkSub({ id: 's-rent', name: 'Rent', amount: 42000, tag: 'Home', member_id: 'm-rohit', account_id: 'pm-hdfc',
      notes: 'landlord raises this every august' }),
    mkSub({ id: 's-icloud', name: 'iCloud+', amount: 179, tag: 'Entertainment', account_id: 'pm-hdfc' }),
    mkSub({ id: 's-carins', name: 'Car insurance', amount: 18400, tag: 'Insurance', billing_cycle: 'yearly',
      member_id: 'm-rohit', account_id: 'pm-hdfc' }),
    mkSub({ id: 's-claude', name: 'Claude', amount: 20, currency: 'USD', tag: 'Work', account_id: 'pm-hdfc' }),
    mkSub({ id: 's-water', name: 'Water cans', amount: 300, billing_cycle: 'custom', custom_cycle_days: 10, tag: 'Home' }),
    mkSub({ id: 's-old', name: 'Hotstar', amount: 299, tag: 'Entertainment', status: 'cancelled' }),
    mkSub({ id: 's-flight', name: 'Flight to Goa', amount: 4560, billing_cycle: 'once', tag: 'Travel' }),
  ]
  const charges: ChargeRow[] = [
    // Netflix: last month paid from a statement, the one in three days marked paid, then the plan.
    mkRow('s-netflix', inMonths(-1, TODAY.getDate() + 3), 649, { paid: true, basis: 'statement' }),
    ...monthlyRun('s-netflix', 649, 3, 12).map((r, i) => (i === 0 ? { ...r, paid: true, basis: 'mark_paid' } : r)),
    ...monthlyRun('s-rent', 42000, 3, 12),
    ...monthlyRun('s-icloud', 179, 8, 12),
    mkRow('s-carins', inDays(40), 18400),
    ...monthlyRun('s-claude', 20, 3, 12),
    mkRow('s-water', inDays(5), 300), mkRow('s-water', inDays(15), 300), mkRow('s-water', inDays(25), 300),
    // Hotstar was cancelled; its past is still money that left.
    mkRow('s-old', inMonths(-2), 299, { paid: true, basis: 'statement' }),
    mkRow('s-old', inMonths(-1), 299, { paid: true, basis: 'statement' }),
    mkRow('s-flight', inDays(60), 4560),
  ]
  return {
    subs,
    members: [member('m-rohit', 'Rohit'), member('m-diya', 'Diya')],
    methods: [method('pm-hdfc', 'HDFC Current account'), method('pm-icici', 'ICICI Joint Account')],
    undo: null,
    charges,
  }
}
