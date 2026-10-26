// Every tool's answer, read from the rows and shaped for a model to read. Raw numbers and
// formatted text travel together so the AI can quote either without doing arithmetic —
// its arithmetic is the one thing this server exists to replace.
import {
  allCharges,
  chargesOf,
  chargesInRange,
  cycleLabel,
  defaultWindow,
  displayStatus,
  dueLabel,
  fmtMoney,
  fmtMoneyTotals,
  isEffectivelyActive,
  isIncome,
  isLiveCommitment,
  isTransfer,
  nextUnpaidChargeOnOrAfter,
  nextDueDay,
  plannedThrough,
  plansRunningShort,
  spendByTag,
  spendByMember,
  spendByMethod,
  spendSeriesRange,
  sumByCurrency,
  toISO,
  todayMid,
  transferCharges,
  daysBetween,
  parseDate,
} from '@longbook/core'
import { LIBRARY_TAGS } from '@longbook/core'
import type { Account, Charge, LoadedData, Commitment, Member } from '@longbook/core'

/** How a row is flagged: money that arrives, a movement between own accounts, or a charge. */
type Flag = 'in' | 'transfer' | null
const flag = (sub: Commitment): Flag => (isIncome(sub) ? 'in' : isTransfer(sub) ? 'transfer' : null)

interface ChargeRow {
  commitment_id: string
  name: string
  date: string
  due: string
  amount: number
  currency: string
  amount_text: string
  paid: boolean
  paid_on: string | null
  basis: string | null
  note: string | null
  tag: string | null
  member: string | null
  account: string | null
  /** "in" for money that arrives, "transfer" for a movement in no total; null for a charge. */
  direction: Flag
}

interface Money {
  currency: string
  amount: number
  text: string
}

function names(data: LoadedData, sub: Commitment): { member: string | null; account: string | null } {
  return {
    member: sub.member_id
      ? (data.members.find((m) => m.id === sub.member_id)?.name ?? null)
      : null,
    account: sub.account_id
      ? (data.methods.find((m) => m.id === sub.account_id)?.name ?? null)
      : null,
  }
}

function chargeRow(data: LoadedData, charge: Charge, today: Date): ChargeRow {
  const { member, account } = names(data, charge.sub)
  return {
    commitment_id: charge.sub.id,
    name: charge.sub.name,
    date: toISO(charge.date),
    due: dueLabel(daysBetween(today, charge.date)),
    amount: charge.amount,
    currency: charge.currency,
    amount_text: fmtMoney(charge.amount, charge.currency),
    paid: charge.paid,
    paid_on: charge.row.paid_on ?? null,
    basis: charge.row.basis ?? null,
    note: charge.row.note ?? null,
    tag: charge.sub.tag,
    member,
    account,
    direction: flag(charge.sub),
  }
}

function moneyRows(charges: Charge[]): Money[] {
  return sumByCurrency(charges).map((s) => ({ ...s, text: fmtMoney(s.amount, s.currency) }))
}

const perCurrency = (byCur: Record<string, number>): Money[] =>
  Object.entries(byCur)
    .map(([currency, amount]) => ({ currency, amount, text: fmtMoney(amount, currency, { approx: true }) }))
    .sort((a, b) => b.amount - a.amount)

/** A window the spend tools answer for: the days given, else the twelve months from today. */
function window(from: string | undefined, to: string | undefined, today: Date): { from: Date; to: Date } {
  const d = defaultWindow(today)
  return { from: from ? parseDate(from) : d.from, to: to ? parseDate(to) : d.to }
}

/** Said wherever a list holds a transfer, so its total is never misread. */
const TRANSFER_NOTE =
  'Rows with direction "transfer" are movements between the owner\'s own accounts — a card bill, a move to savings. They are listed and never in total; their own sum is transfers_total.'

/** Transfers keep their own figure beside a spending total; absent when the list holds none. */
function transferFigures(transfers: Charge[]) {
  if (transfers.length === 0) return {}
  const sums = moneyRows(transfers)
  return { transfer_count: transfers.length, transfers_total: sums, transfers_total_text: fmtMoneyTotals(sums), note: TRANSFER_NOTE }
}

const byDate = (a: Charge, b: Charge) => a.date.getTime() - b.date.getTime()

export function nextPayment(data: LoadedData, today: Date = todayMid()) {
  const day = nextDueDay(data.subs, data.charges, today)
  if (!day) return { message: 'Nothing is due. There are no active commitments with an unpaid charge ahead.' }
  const total = moneyRows(day.charges)
  return {
    date: toISO(day.date),
    due: dueLabel(day.days),
    total,
    total_text: total.length ? fmtMoneyTotals(total) : 'no spending',
    ...transferFigures(day.transfers),
    charges: [...day.charges, ...day.transfers].map((c) => chargeRow(data, c, today)),
  }
}

export function upcoming(data: LoadedData, days: number, today: Date = todayMid()) {
  const to = new Date(today.getTime() + days * 86400000)
  const spending = chargesInRange(data.subs, data.charges, today, to)
  const transfers = transferCharges(data.subs, data.charges, today).filter((c) => c.date >= today && c.date <= to)
  const listed = [...spending, ...transfers].sort(byDate)
  const total = moneyRows(spending)
  const short = plansRunningShort(data.subs, data.charges, days, today)
  return {
    window_days: days,
    count: listed.length,
    total,
    total_text: total.length ? fmtMoneyTotals(total) : 'nothing',
    ...transferFigures(transfers),
    charges: listed.map((c) => chargeRow(data, c, today)),
    plans_running_short: short.map((p) => ({ commitment_id: p.sub.id, name: p.sub.name, planned_through: toISO(p.through) })),
  }
}

export function charges(
  data: LoadedData,
  opts: { id?: string; name?: string; from?: string; to?: string; paid?: boolean },
  today: Date = todayMid(),
) {
  let rows: Charge[]
  if (opts.id || opts.name) {
    const key = (opts.name ?? '').trim().toLowerCase()
    const matches = data.subs.filter((s) => (opts.id ? s.id === opts.id : s.name.trim().toLowerCase() === key))
    const sub = matches[0]
    if (!sub) return { message: `No commitment ${opts.id ? `with id ${opts.id}` : `called "${opts.name}"`}.` }
    // A name two commitments share is never answered with the first one's rows.
    if (matches.length > 1) {
      return {
        message: `"${opts.name?.trim()}" matches more than one commitment — pass an id to read one's charges.`,
        ambiguous: matches.map((s) => {
          const own = chargesOf(s, data.charges, today)
          return {
            id: s.id,
            name: s.name,
            status: displayStatus(s, today),
            cycle: cycleLabel(s),
            direction: flag(s),
            charges: own.length,
            first_charge: own.length ? toISO(own[0]!.date) : null,
            last_charge: own.length ? toISO(own[own.length - 1]!.date) : null,
          }
        }),
      }
    }
    rows = chargesOf(sub, data.charges, today)
  } else {
    // The ledger of what was spent, with the transfers the owner keeps in view beside it.
    rows = [...allCharges(data.subs, data.charges, today), ...transferCharges(data.subs, data.charges, today)].sort(byDate)
  }
  if (opts.from) rows = rows.filter((c) => c.date >= parseDate(opts.from!))
  if (opts.to) rows = rows.filter((c) => c.date <= parseDate(opts.to!))
  if (opts.paid !== undefined) rows = rows.filter((c) => c.paid === opts.paid)
  const total = moneyRows(rows.filter((c) => c.sub.direction !== 'transfer'))
  return {
    count: rows.length,
    total,
    total_text: total.length ? fmtMoneyTotals(total) : 'nothing',
    ...transferFigures(rows.filter((c) => c.sub.direction === 'transfer')),
    charges: rows.map((c) => chargeRow(data, c, today)),
  }
}

export function cashflow(
  data: LoadedData,
  monthsBack: number,
  monthsForward: number,
  currency?: string,
  today: Date = todayMid(),
) {
  // Every currency a row carries, so a month in a second currency is never dropped.
  const currencies = currency
    ? [currency]
    : [...new Set(allCharges(data.subs, data.charges, today).map((c) => c.currency))]
  return {
    note: 'Summed from the charges written, month by month. A month with no rows is an empty month, not a projection; months ahead are the plan as written. Spending only: money in and transfers between the owner\'s own accounts are in no month\'s total.',
    series: currencies.map((cur) => ({
      currency: cur,
      months: spendSeriesRange(data.subs, data.charges, cur, monthsBack, monthsForward, today).map((p) => ({
        month: `${p.year}-${String(p.month + 1).padStart(2, '0')}`,
        total: p.total,
        total_text: fmtMoney(p.total, cur, { approx: true }),
        planned: p.estimated,
      })),
    })),
  }
}

function spendNote(w: { from: Date; to: Date }): string {
  return `Summed from the charges written between ${toISO(w.from)} and ${toISO(w.to)} — never amortised from a rule, never blended across currencies. Spending only: money in and transfers between the owner's own accounts are in no group.`
}

export function spendingByCategory(data: LoadedData, from?: string, to?: string, today: Date = todayMid()) {
  const w = window(from, to, today)
  return {
    from: toISO(w.from),
    to: toISO(w.to),
    note: spendNote(w),
    groups: spendByTag(data.subs, data.charges, w.from, w.to).map((g) => ({
      tag: g.name,
      total: perCurrency(g.totalByCurrency),
      charges: g.count,
      commitments: g.commitments,
    })),
  }
}

export function spendingByAccount(data: LoadedData, from?: string, to?: string, today: Date = todayMid()) {
  const w = window(from, to, today)
  return {
    from: toISO(w.from),
    to: toISO(w.to),
    note: spendNote(w),
    groups: spendByMethod(data.subs, data.charges, data.methods, w.from, w.to).map((g) => ({
      account: g.name,
      total: perCurrency(g.totalByCurrency),
      charges: g.count,
      commitments: g.commitments,
    })),
  }
}

export function spendingByMember(data: LoadedData, from?: string, to?: string, today: Date = todayMid()) {
  const w = window(from, to, today)
  return {
    from: toISO(w.from),
    to: toISO(w.to),
    note: spendNote(w),
    groups: spendByMember(data.subs, data.charges, data.members, w.from, w.to).map((g) => ({
      member: g.name,
      total: perCurrency(g.totalByCurrency),
      charges: g.count,
      commitments: g.commitments,
    })),
  }
}

interface CommitmentRow {
  id: string
  name: string
  amount: number
  currency: string
  amount_text: string
  cycle: string
  status: string
  tag: string | null
  member: string | null
  account: string | null
  next_charge: { date: string; due: string; amount: number; amount_text: string } | null
  planned_through: string | null
  charges: number
  cancelling_on: string | null
  notes: string | null
  /** The row's details, when it holds any: longbook's own statement_line, and fields a vault written under an older guide kept there. */
  details?: Record<string, unknown>
  /** "in" for money that arrives, "transfer" for a movement in no total; null for a charge. */
  direction: Flag
  /** Present, and true, only while the owner marks it a free trial. */
  free_trial?: true
}

function commitmentRow(data: LoadedData, sub: Commitment, today: Date): CommitmentRow {
  const next = nextUnpaidChargeOnOrAfter(sub, data.charges, today)
  const through = plannedThrough(sub, data.charges)
  const { member, account } = names(data, sub)
  return {
    id: sub.id,
    name: sub.name,
    amount: sub.amount,
    currency: sub.currency,
    amount_text: fmtMoney(sub.amount, sub.currency),
    cycle: cycleLabel(sub),
    status: displayStatus(sub, today),
    tag: sub.tag,
    member,
    account,
    next_charge: next
      ? { date: toISO(next.date), due: dueLabel(daysBetween(today, next.date)), amount: next.amount, amount_text: fmtMoney(next.amount, next.currency) }
      : null,
    planned_through: through ? toISO(through) : null,
    charges: chargesOf(sub, data.charges, today).length,
    cancelling_on: sub.ends_on,
    notes: sub.notes,
    ...(sub.details && Object.keys(sub.details).length > 0 ? { details: sub.details } : {}),
    direction: flag(sub),
    ...(sub.free_trial === true ? { free_trial: true as const } : {}),
  }
}

export type StatusFilter = 'active' | 'paused' | 'cancelled' | 'all'

/**
 * `active` is the commitments still ahead. A one-time line whose charge is behind today or
 * paid is that charge now — counted here, listed by `charges` — so a vault full of statement
 * lines does not read as hundreds of commitments.
 */
export function commitments(data: LoadedData, status: StatusFilter, today: Date = todayMid()) {
  const wanted = (s: Commitment) =>
    status === 'all' ? true : status === 'active' ? isLiveCommitment(s, data.charges, today) : displayStatus(s, today) === status
  const rows = data.subs
    .filter(wanted)
    .map((s) => commitmentRow(data, s, today))
    .sort((a, b) => (a.next_charge?.date ?? '9999').localeCompare(b.next_charge?.date ?? '9999'))
  const settled = status === 'active'
    ? data.subs.filter((s) => displayStatus(s, today) === 'active' && !isLiveCommitment(s, data.charges, today)).length
    : 0
  const short = plansRunningShort(data.subs, data.charges, 90, today)
  return {
    count: rows.length,
    ...(settled
      ? {
          settled_one_time: settled,
          note: `${settled} one-time commitment${settled === 1 ? '' : 's'} whose charge is behind today or paid ${settled === 1 ? 'is' : 'are'} not listed: each is a charge now, read with charges.`,
        }
      : {}),
    commitments: rows,
    plans_running_short: short.map((p) => ({ commitment_id: p.sub.id, name: p.sub.name, planned_through: toISO(p.through) })),
    ...(data.toFillIn?.length
      ? {
          to_fill_in: data.toFillIn,
          to_fill_in_note:
            `${data.toFillIn.length} commitment${data.toFillIn.length === 1 ? '' : 's'} the owner named without details. ` +
            `These come first: search every statement for each one by name, loosely (a person paid ` +
            `on the 1st can be a salary), and add_commitments what you find under the same name. For ` +
            `the rest, ask the owner in one table — commitment | your question | your best guess — ` +
            `and say a spoken answer is fine. If the statements do not reach far enough, ask for ` +
            `older or longer statements before guessing.`,
        }
      : {}),
    ...(data.hints?.length
      ? {
          hints: data.hints.map((h) => ({ name: h.name, kind: h.kind === 'member' ? 'person' : 'account', tag: h.tag ?? null })),
          hints_note:
            `${data.hints.length} hint${data.hints.length === 1 ? '' : 's'} the owner picked at setup: people by role and accounts by kind. ` +
            `Use them when reading statements — a monthly payment to a person may be the cook, a statement's account may be the ` +
            `savings account. A hint is not a person or an account: never write a charge to its name. Add the person or the account ` +
            `under the name the statement or the owner gives, with add_person or add_account.`,
        }
      : {}),
  }
}

export function search(data: LoadedData, query: string, today: Date = todayMid()) {
  const q = query.trim().toLowerCase()
  const hit = (sub: Commitment) => {
    const { member, account } = names(data, sub)
    return [sub.name, sub.tag, sub.notes, member, account]
      .some((field) => field?.toLowerCase().includes(q))
  }
  const rows = data.subs.filter(hit).map((s) => commitmentRow(data, s, today))
  return { query, count: rows.length, commitments: rows }
}

interface NextUnpaid {
  commitment_id: string
  name: string
  date: string
  due: string
  amount: number
  currency: string
  amount_text: string
  direction: Flag
}

/** What some commitments hold between them: how many, their rows, and what is owed next. */
function usage(data: LoadedData, subs: Commitment[], today: Date) {
  const ids = new Set(subs.map((s) => s.id))
  // Money in is never owed, so it is never what comes next; a transfer is, and says so.
  const next = subs
    .filter((s) => !isIncome(s) && isEffectivelyActive(s, today))
    .map((s) => nextUnpaidChargeOnOrAfter(s, data.charges, today))
    .filter((c): c is Charge => c !== null)
    .sort((a, b) => byDate(a, b) || b.amount - a.amount)[0]
  const next_unpaid_charge: NextUnpaid | null = next
    ? {
        commitment_id: next.sub.id,
        name: next.sub.name,
        date: toISO(next.date),
        due: dueLabel(daysBetween(today, next.date)),
        amount: next.amount,
        currency: next.currency,
        amount_text: fmtMoney(next.amount, next.currency),
        direction: flag(next.sub),
      }
    : null
  return {
    commitments: subs.length,
    charges: (data.charges ?? []).filter((r) => ids.has(r.commitment_id)).length,
    next_unpaid_charge,
  }
}

/** The details a row holds, exactly as stored, when it holds any: longbook's own, read never written. */
const heldDetails = (row: Account | Member) =>
  row.details && Object.keys(row.details).length > 0 ? { details: row.details } : {}

/**
 * The balance an account holds, held against its rows: the day it was true and the newest
 * confirmed charge past it — dated today or earlier, basis anything but plan, as the
 * reports count. Null when the account holds no balance, or no charge outruns it.
 */
export function staleBalance(data: LoadedData, account: Account, today: Date = todayMid()): { balance_date: string; newest_charge: string } | null {
  if (typeof account.balance !== 'number' || !account.balance_date) return null
  const billed = new Set(data.subs.filter((s) => s.account_id === account.id).map((s) => s.id))
  const limit = toISO(today)
  const newest = (data.charges ?? [])
    .filter((r) => billed.has(r.commitment_id) && r.date <= limit && r.basis !== 'plan')
    .reduce((latest, r) => (r.date > latest ? r.date : latest), '')
  return newest > account.balance_date ? { balance_date: account.balance_date, newest_charge: newest } : null
}

/** Said only when it is so: the balance held is older than the newest confirmed charge on the account. */
const balanceNote = (data: LoadedData, account: Account, today: Date) => {
  const stale = staleBalance(data, account, today)
  return stale
    ? { balance_note: `Balance as of ${stale.balance_date}, older than the newest confirmed charge on ${stale.newest_charge} — a statement that prints a closing balance updates it with update_account (balance_date its last day).` }
    : {}
}

/**
 * What a write answers beside its counts: one line per account whose held balance is older
 * than the newest confirmed day just written to it, by account id. Undefined when none is.
 */
export function balanceNoteFor(
  accounts: Array<Pick<Account, 'id' | 'name' | 'balance' | 'balance_date'>>,
  newest: Map<string, string>,
): string | undefined {
  const lines = accounts.flatMap((a) => {
    const day = newest.get(a.id)
    return day && typeof a.balance === 'number' && a.balance_date && day > a.balance_date
      ? [`${a.name}: balance as of ${a.balance_date} is older than the newest charge written, ${day} — when the statement prints a closing balance, update_account with balance and balance_date its last day.`]
      : []
  })
  return lines.length > 0 ? lines.join('\n') : undefined
}

/** Every account as the owner would describe it, with what is billed to it. */
export function accounts(data: LoadedData, today: Date = todayMid()) {
  const nameOf = (rows: Array<Account | Member>, id: string | null) => (id ? (rows.find((r) => r.id === id)?.name ?? null) : null)
  return {
    count: data.methods.length,
    note:
      'type is the account\'s tag. notes hold what is particular about it, one detail per line — on a card, "Card name: …", the product printed on it. details, when an account holds any, is longbook\'s own, returned as stored. linked_to is the account this one is linked to — a card to the bank account that pays it. starred is true for an account the owner starred to keep it first. balance_note appears when the balance held is older than the newest confirmed charge. commitments and charges count everything billed to the account, every status, past and planned.',
    accounts: data.methods.map((account) => ({
      id: account.id,
      name: account.name,
      type: account.tag,
      ...(account.institution ? { institution: account.institution } : {}),
      ...(account.last4 ? { last4: account.last4 } : {}),
      belongs_to: nameOf(data.members, account.member_id),
      linked_to: nameOf(data.methods, account.parent_account_id),
      balance: account.balance ?? null,
      balance_date: account.balance_date ?? null,
      ...balanceNote(data, account, today),
      notes: account.notes ?? null,
      ...(account.starred ? { starred: true } : {}),
      ...heldDetails(account),
      ...usage(data, data.subs.filter((s) => s.account_id === account.id), today),
    })),
  }
}

/** Every person the memory holds, with the accounts that are theirs and what is for them. */
export function members(data: LoadedData, today: Date = todayMid()) {
  return {
    count: data.members.length,
    note:
      'tag is the person\'s role in the owner\'s finances — family, household help, landlord. accounts are the ones that belong to them. starred is true for a person the owner starred to keep them first. details, when a person holds any, is longbook\'s own, returned as stored. commitments and charges count everything that is for them, every status, past and planned.',
    members: data.members.map((member) => ({
      id: member.id,
      name: member.name,
      tag: member.tag,
      email: member.email,
      accounts: data.methods.filter((a) => a.member_id === member.id).map((a) => a.name),
      ...(member.starred ? { starred: true } : {}),
      ...heldDetails(member),
      ...usage(data, data.subs.filter((s) => s.member_id === member.id), today),
    })),
  }
}

/**
 * The tag vocabulary an agent may use: the vault's own registry first, then longbook's
 * library for tags nobody has worn yet — so nothing invents a tag or guesses its casing.
 * Each carries its icon; no tag carries a template.
 */
export function tags(data: LoadedData) {
  const registered = data.tags ?? []
  const worn = new Map<string, number>()
  for (const sub of data.subs) {
    const key = sub.tag?.trim().toLowerCase()
    if (key) worn.set(key, (worn.get(key) ?? 0) + 1)
  }
  const inVault = registered.map((tag) => ({
    kind: tag.kind,
    name: tag.name,
    name_key: tag.name_key,
    icon: tag.icon,
    from_library: tag.is_default,
    worn_by: tag.kind === 'commitment' ? (worn.get(tag.name_key) ?? 0) : undefined,
  }))
  const known = new Set(registered.map((t) => `${t.kind}:${t.name_key}`))
  const library = LIBRARY_TAGS.filter((t) => !known.has(`${t.kind}:${t.name.toLowerCase()}`)).map((t) => ({
    kind: t.kind,
    name: t.name,
    icon: t.icon,
  }))
  return {
    note:
      'Use a name from in_vault first; then one from library, which registers itself with its icon on first use. Invent one only when nothing fits. No tag carries a template: a commitment\'s three most important details go in its notes, one per line — read_guide "notes" lists them by category — and an account\'s details are lines of its notes too.',
    in_vault: inVault,
    library,
  }
}

export { isEffectivelyActive }
