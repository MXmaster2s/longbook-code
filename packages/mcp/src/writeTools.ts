// The stdio server's write tools — LOCAL ONLY, registered in server.ts and nowhere
// else; rpc.ts and catalog.ts never import this module, so the hosted engine keeps none
// of it. Every write rides vaultWrite.ts: validated, scanned, signed, reviewable, undoable.
import { randomUUID } from 'node:crypto'
import { DATA_POLICY_REFUSAL, displayStatus, libraryTag, nameKey, parseDate, planCharges, scanText, scannableWords, stepFrom, storedDirection, toISO, todayMid } from '@longbook/core'
import type { ChargeRow, Commitment, TagKind } from '@longbook/core'
import type { Mutated, RawVault, TouchedRow } from './vaultWrite.js'
import { VaultWriteError, writeVault } from './vaultWrite.js'
import type { AccountSet, ChargeInput, ChargeSet, CommitmentRowInput, MemberSet, NewAccount, NewMember } from './proposal.js'
import {
  CHARGE_SET_FIELDS,
  EMPTY_NAME_REFUSAL,
  NEW_ACCOUNT_FIELDS,
  NOTHING_TO_PLAN,
  PLANNED_COUNT_CEILING,
  checkAccountSet,
  checkChargeNote,
  checkChargeSet,
  checkCharges,
  checkCommitmentSet,
  checkMemberSet,
  checkNewAccount,
  checkNewMember,
  checkPaidAmount,
  checkPlannedCount,
  checkPromotion,
  checkRows,
  checkTagDelete,
  checkTagRename,
  dayTakenRefusal,
  entitySetOutcome,
  entityTwinRefusal,
  isRealDay,
  isRecord,
  linkedTo,
  mixedDirections,
  noChargeRefusal,
  notActiveRefusal,
  oneTimeMoveRefusal,
  oneTimeRefusal,
  pastCancellingRefusal,
  rowProblems,
  setOutcome,
  tagTwinRefusal,
} from './proposal.js'
import { entityKey, findCommitment, findEntity, findLinked, findOwner } from './targets.js'
import { balanceNoteFor } from './tools.js'

export type { AccountSet, ChargeInput, ChargeSet, CommitmentRowInput, MemberSet, NewAccount, NewMember }
export {
  ACCOUNT_NOTES_DESCRIPTION,
  ADD_ACCOUNT_SPEC,
  ADD_CHARGES_SPEC,
  ADD_COMMITMENTS_SPEC,
  ADD_MEMBER_SPEC,
  AMOUNT_DESCRIPTION,
  AMOUNT_LIMIT,
  AMOUNT_LIMIT_PROBLEM,
  CANCEL_COMMITMENT_SPEC,
  CUSTOM_DAYS_DESCRIPTION,
  DELETE_COMMITMENT_SPEC,
  DELETE_TAG_SPEC,
  DIRECTION_DESCRIPTION,
  FREE_TRIAL_DESCRIPTION,
  MARK_PAID_SPEC,
  NOTES_DESCRIPTION,
  PLANNED_COUNT_CEILING,
  PROMOTE_SPEC,
  REMOVE_CHARGES_SPEC,
  RENAME_TAG_SPEC,
  SET_PLANNED_COUNT_SPEC,
  TAG_KINDS,
  UPDATE_ACCOUNT_SPEC,
  UPDATE_CHARGE_SPEC,
  UPDATE_COMMITMENT_SPEC,
  UPDATE_MEMBER_SPEC,
} from './proposal.js'

/** How far a new recurring commitment is planned when nobody says. Mirrors the app. */
export const DEFAULT_PLAN_MONTHS = 24

export interface AddCommitmentsInput {
  rows: CommitmentRowInput[]
  /** Where the rows came from, e.g. "documents/hdfc-2026.pdf" — stamped into _provenance. */
  source?: string
}

/** Update fields: undefined leaves a field alone; null clears a clearable one. */
export interface UpdateCommitmentInput {
  id?: string
  name?: string
  source?: string
  set: {
    name?: string
    amount?: number
    /** The day an amount change applies from. Default today. */
    from?: string
    /** For a one-time commitment: moves its single charge. */
    date?: string
    currency?: string
    billing_cycle?: 'monthly' | 'yearly' | 'custom' | 'once'
    custom_cycle_days?: number | null
    ends_on?: string | null
    status?: 'active' | 'paused' | 'cancelled'
    /** Null, like "out", makes it a charge. */
    direction?: 'in' | 'out' | 'transfer' | null
    tag?: string | null
    notes?: string | null
    member?: string | null
    account?: string | null
    /** True marks a free trial, false takes the mark off; no charge row changes. */
    free_trial?: boolean
    /** longbook's own on a commitment. A set sending any is refused. */
    details?: unknown
  }
}

export interface MarkPaidInput {
  id?: string
  name?: string
  date: string
  paid?: boolean
  /** What actually left the account, when it differed. Changes this one row and no other. */
  amount?: number
  /** The day the money moved, when it was not the due date. Null clears. */
  paid_on?: string | null
  /** A word about this one charge. Null clears. */
  note?: string | null
  source?: string
}

export interface UpdateChargeInput {
  id?: string
  name?: string
  /** The day the row sits on. */
  date: string
  source?: string
  set: ChargeSet
}

export interface SetPlannedCountInput {
  id?: string
  name?: string
  /** How many charges stand from today on, 240 at most. */
  count: number
  source?: string
}

export interface AddMemberInput extends NewMember {
  source?: string
}

export interface AddAccountInput extends NewAccount {
  source?: string
}

export interface RenameTagInput {
  kind: TagKind
  from: string
  to: string
  source?: string
}

export interface DeleteTagInput {
  kind: TagKind
  name: string
  source?: string
}

export interface DeleteCommitmentInput {
  /** By id only: a name could reach the wrong row, and this one is not undone by a cancel. */
  id: string
  source?: string
}

export interface AddChargesInput {
  id?: string
  name?: string
  charges: ChargeInput[]
  source?: string
}

export interface RemoveChargesInput {
  id?: string
  name?: string
  dates: string[]
  source?: string
}

export interface PromoteInput {
  ids: string[]
  billing_cycle: 'monthly' | 'yearly' | 'custom'
  custom_cycle_days?: number
  plan_months?: number
  /** A known end — the repeat stopped, or will. Nothing is planned past it. */
  ends_on?: string
  name?: string
  tag?: string | null
  member?: string | null
  account?: string | null
  notes?: string | null
  /** longbook's own on a commitment. A promotion sending any is refused. */
  details?: unknown
  source?: string
}

export interface CancelCommitmentInput {
  id?: string
  name?: string
  source?: string
}

export interface UpdateAccountInput {
  id?: string
  name?: string
  source?: string
  set: AccountSet
}

export interface UpdateMemberInput {
  id?: string
  name?: string
  source?: string
  set: MemberSet
}

const str = (v: unknown): string => (typeof v === 'string' ? v : '')

/**
 * Every value a commitment row carries, keyed for the data-policy scan. A details value the
 * row holds is rendered whatever its type — a card number stored as a number is a number,
 * which a string-only scan never saw.
 */
function commitmentTexts(row: Record<string, unknown>): TouchedRow['fields'] {
  const fields: TouchedRow['fields'] = { name: str(row.name), notes: str(row.notes), tag: str(row.tag) }
  if (isRecord(row.details)) {
    for (const [key, value] of Object.entries(row.details)) {
      const words = scannableWords(value)
      if (Array.isArray(value)) words.forEach((word, i) => { fields[`details.${key}.${i}`] = word })
      else if (words[0] !== undefined) fields[`details.${key}`] = words[0]
    }
  }
  return fields
}

const rowsOf = (vault: RawVault, list: string): Record<string, unknown>[] =>
  Array.isArray(vault[list]) ? (vault[list] as unknown[]).filter(isRecord) : []

/**
 * Resolve a member or account by name_key, or create the app's minimal placeholder row —
 * named, not yet described — so the desktop offers it for filling in. Mirrors
 * VaultWriter.ensureEntity in swift-core.
 */
function ensureEntity(
  vault: RawVault,
  list: 'members' | 'accounts',
  name: string,
  now: string,
  touched: TouchedRow[],
): { id: string; name: string; created: boolean } {
  const clean = name.trim()
  const key = nameKey(clean)
  const rows = rowsOf(vault, list)
  const found = rows.find((r) => (str(r.name_key) || nameKey(str(r.name))) === key)
  if (found) return { id: str(found.id), name: str(found.name), created: false }
  const row = { id: randomUUID(), name: clean, name_key: key, is_incomplete: true, created_at: now }
  vault[list] = [...rows, row]
  touched.push({ id: row.id, fields: { name: clean } })
  return { id: row.id, name: clean, created: true }
}

/**
 * Make sure a worn tag exists in the registry for its kind — copied from the library with
 * its icon when it is a seeded one; bare when invented. No tag carries a template. Mirrors
 * VaultWriter.ensureTag in swift-core, sort convention included.
 */
function ensureTag(vault: RawVault, kind: TagKind, name: string, now: string): 'library' | 'new' | null {
  const clean = name.trim()
  if (!clean) return null
  const key = nameKey(clean)
  const tags = rowsOf(vault, 'tags')
  const found = tags.find(
    (t) => str(t.kind) === kind && (str(t.name_key) || nameKey(str(t.name))) === key,
  )
  if (found) return null
  const seeded = libraryTag(kind, clean)
  const entry: Record<string, unknown> = {
    id: randomUUID().toLowerCase(),
    kind,
    name: seeded?.name ?? clean,
    name_key: key,
    is_default: seeded != null,
    sort: tags.length,
    created_at: now,
  }
  if (seeded?.icon) entry.icon = seeded.icon
  vault.tags = [...tags, entry]
  return seeded ? 'library' : 'new'
}

// ---- the rows ---------------------------------------------------------------------------
// Every charge is a stored row. These mirror VaultPatch's charge functions in swift-core,
// rule for rule, so the local server and the app write the same file.

const chargeRows = (vault: RawVault): Record<string, unknown>[] => rowsOf(vault, 'charges')

/** Rows kept in date order within a commitment, commitments in their first-seen order. */
function setChargeRows(vault: RawVault, rows: Record<string, unknown>[]): void {
  const order = new Map<string, number>()
  chargeRows(vault).forEach((r, i) => {
    const id = str(r.commitment_id)
    if (!order.has(id)) order.set(id, i)
  })
  const rank = (id: string) => order.get(id) ?? Number.MAX_SAFE_INTEGER
  const sorted = [...rows].sort((a, b) => {
    const ca = str(a.commitment_id), cb = str(b.commitment_id)
    if (ca !== cb) return rank(ca) - rank(cb) || ca.localeCompare(cb)
    return str(a.date).localeCompare(str(b.date))
  })
  if (sorted.length === 0) delete vault.charges
  else vault.charges = sorted
}

const sameCharge = (r: Record<string, unknown>, id: string, date: string) =>
  str(r.commitment_id) === id && str(r.date) === date

/**
 * The charge keys a write touched, `<commitment>@<day>`, listed beside the commitment so
 * writeVault signs each as PendingApply.sign does: a stale app signature or review mark on
 * the key never outlives an edit of that charge, and no device adopts it unreviewed.
 */
const chargeKeys = (id: string, dates: Iterable<string>): TouchedRow[] =>
  [...new Set(dates)].map((date) => ({ id: `${id}@${date}`, fields: {} }))

/** A commitment's rows by day, as text, so a write can say which days it changed. */
const chargeSnapshot = (vault: RawVault, id: string): Map<string, string> =>
  new Map(chargeRows(vault).filter((r) => str(r.commitment_id) === id).map((r) => [str(r.date), JSON.stringify(r)]))

/** The days a write added, changed or removed since the snapshot. */
function changedDays(before: Map<string, string>, vault: RawVault, id: string): string[] {
  const after = chargeSnapshot(vault, id)
  const days = new Set<string>()
  for (const [day, text] of before) if (after.get(day) !== text) days.add(day)
  for (const day of after.keys()) if (!before.has(day)) days.add(day)
  return [...days]
}

function rawCharge(row: ChargeRow): Record<string, unknown> {
  const out: Record<string, unknown> = { commitment_id: row.commitment_id, date: row.date, amount: row.amount, paid: row.paid }
  if (row.currency) out.currency = row.currency
  if (row.paid_on) out.paid_on = row.paid_on
  if (row.basis) out.basis = row.basis
  if (row.note) out.note = row.note
  if (row.written_at) out.written_at = row.written_at
  return out
}

/** Writes rows in, one per (commitment, date): a row already there for that day is replaced. */
function upsertCharges(vault: RawVault, rows: ChargeRow[]): void {
  let all = chargeRows(vault)
  for (const row of rows) {
    all = all.filter((r) => !sameCharge(r, row.commitment_id, row.date))
    all.push(rawCharge(row))
  }
  setChargeRows(vault, all)
}

function removeCharges(vault: RawVault, id: string, dates: string[]): number {
  const gone = new Set(dates)
  const before = chargeRows(vault)
  const kept = before.filter((r) => !(str(r.commitment_id) === id && gone.has(str(r.date))))
  setChargeRows(vault, kept)
  return before.length - kept.length
}

/** The commitment as core types it, from the raw row, for the generator. */
function asCommitment(row: Record<string, unknown>): Pick<Commitment, 'id' | 'billing_cycle' | 'custom_cycle_days' | 'ends_on' | 'status'> {
  return {
    id: str(row.id),
    status: row.status as Commitment['status'],
    billing_cycle: row.billing_cycle as Commitment['billing_cycle'],
    custom_cycle_days: typeof row.custom_cycle_days === 'number' ? row.custom_cycle_days : null,
    ends_on: typeof row.ends_on === 'string' ? row.ends_on : null,
  }
}

/**
 * Sets what is known about one charge. A row not yet there is written at the commitment's
 * price; fields not given are left as they were. Mirrors VaultPatch.setCharge.
 */
function setCharge(
  vault: RawVault,
  sub: Record<string, unknown>,
  input: { date: string; paid?: boolean; amount?: number; paid_on?: string | null; note?: string | null; basis?: string; currency?: string },
  now: string,
): Record<string, unknown> {
  const id = str(sub.id)
  let all = chargeRows(vault)
  let row = all.find((r) => sameCharge(r, id, input.date))
  if (row) {
    all = all.filter((r) => r !== row)
  } else {
    const price = input.amount ?? (typeof sub.amount === 'number' ? sub.amount : undefined)
    if (price === undefined) throw new VaultWriteError('A charge needs an amount.')
    row = { commitment_id: id, date: input.date, amount: price, paid: false, written_at: now }
  }
  if (input.paid !== undefined) row.paid = input.paid
  if (input.amount !== undefined) row.amount = input.amount
  if (input.currency !== undefined) row.currency = input.currency.trim().toUpperCase()
  if (input.paid_on !== undefined) {
    if (input.paid_on) row.paid_on = input.paid_on
    else delete row.paid_on
  }
  if (input.note !== undefined) {
    if (input.note) row.note = input.note
    else delete row.note
  }
  // What backs the row: the caller's word, else the owner's hand when a number changed,
  // else the app's own tap when marking. A plan that was only marked stays honest.
  if (input.basis) row.basis = input.basis
  else if (input.amount !== undefined) row.basis = 'user'
  else if (input.paid === true && (row.basis === 'plan' || row.basis == null)) row.basis = 'mark_paid'
  else if (input.paid === false && row.basis === 'mark_paid') row.basis = 'plan'
  all.push(row)
  setChargeRows(vault, all)
  return row
}

function repriceUnpaidPlanned(vault: RawVault, id: string, from: Date, amount: number, includingPast: boolean): void {
  const all = chargeRows(vault)
  for (const r of all) {
    if (str(r.commitment_id) !== id || r.paid === true || (r.basis ?? 'plan') !== 'plan') continue
    if (includingPast || parseDate(str(r.date)) >= from) r.amount = amount
  }
  setChargeRows(vault, all)
}

function removeUnpaidPlanned(vault: RawVault, id: string, after: Date): void {
  const kept = chargeRows(vault).filter((r) => {
    if (str(r.commitment_id) !== id || r.paid === true || (r.basis ?? 'plan') !== 'plan') return true
    return parseDate(str(r.date)) <= after
  })
  setChargeRows(vault, kept)
}

/** Months enough to plan `count` charges of this cycle: a month is never shorter than 28 days. Mirrors VaultPatch.monthsHolding. */
function monthsHolding(count: number, sub: Record<string, unknown>): number {
  switch (sub.billing_cycle) {
    case 'monthly': return count
    case 'yearly': return count * 12
    case 'custom': return Math.floor((count * (typeof sub.custom_cycle_days === 'number' ? sub.custom_cycle_days : 30)) / 28) + 1
    default: return 1
  }
}

const isPlanRow = (r: Record<string, unknown>): boolean => r.paid !== true && (r.basis ?? 'plan') === 'plan'

/**
 * A price that changed from one charge on: that row takes it by the owner's hand, every unpaid
 * planned row after it follows, and the commitment's own price is the new one. Mirrors VaultPatch.reprice.
 */
function reprice(vault: RawVault, sub: Record<string, unknown>, from: string, amount: number, now: string): void {
  setCharge(vault, sub, { date: from, amount }, now)
  const day = parseDate(from)
  repriceUnpaidPlanned(vault, str(sub.id), new Date(day.getTime() + 86400000), amount, false)
  sub.amount = amount
  sub.updated_at = now
}

/**
 * Moves one charge to another day. Alone, the row keeps its amount as the owner's fact. With the
 * later ones, every unpaid planned row after it follows a cycle apart, keeping its amount; paid
 * and hand-priced rows stay. Returns how many rows landed. Mirrors VaultPatch.reschedule.
 */
function reschedule(vault: RawVault, sub: Record<string, unknown>, from: string, to: string, andLater: boolean, now: string): number {
  const id = str(sub.id)
  const all = chargeRows(vault)
  const at = all.findIndex((r) => sameCharge(r, id, from))
  if (at < 0) throw new VaultWriteError(noChargeRefusal(from, str(sub.name)))
  if (from === to) return 0
  if (!andLater) {
    if (all.some((r) => sameCharge(r, id, to))) throw new VaultWriteError(dayTakenRefusal(to))
    const moved: Record<string, unknown> = { ...all[at]!, date: to, written_at: now }
    if ((moved.basis ?? 'plan') === 'plan') moved.basis = 'user'
    setChargeRows(vault, [...all.filter((_, i) => i !== at), moved])
    return 1
  }
  const commitment = asCommitment(sub)
  const fromDay = parseDate(from)
  const toDay = parseDate(to)
  // The run that moves: the row named and every unpaid planned row after it, in date order.
  const moving = all
    .map((row, offset) => ({ row, offset }))
    .filter(({ row }) => {
      if (str(row.commitment_id) !== id) return false
      const day = parseDate(str(row.date))
      return day.getTime() === fromDay.getTime() || (day > fromDay && isPlanRow(row))
    })
    .sort((a, b) => str(a.row.date).localeCompare(str(b.row.date)))
  const kept = all.filter((_, i) => !moving.some((m) => m.offset === i))
  const taken = new Set(kept.filter((r) => str(r.commitment_id) === id).map((r) => str(r.date)))
  const end = commitment.ends_on ? parseDate(commitment.ends_on) : null
  const out = [...kept]
  const landed: string[] = []
  for (let k = 0; k < moving.length; k++) {
    const day = stepFrom(commitment, toDay, k)
    if (end && day > end) {
      // The named row IS the move: dropping it would delete the charge the caller asked to move.
      if (k === 0) throw new VaultWriteError(pastCancellingRefusal(commitment.ends_on!))
      break
    }
    const iso = toISO(day)
    if (taken.has(iso)) throw new VaultWriteError(dayTakenRefusal(iso))
    out.push({ ...moving[k]!.row, date: iso, written_at: now })
    landed.push(iso)
  }
  setChargeRows(vault, out)
  return landed.length
}

/**
 * One more stretch of plan, asked for, never automatic: from the step after the last written
 * charge, or from the first cycle day from today on when that step is behind it. Nothing is
 * written before today; today's cycle day is plan. Mirrors VaultPatch.plan.
 */
function plan(vault: RawVault, sub: Record<string, unknown>, months: number, now: string): ChargeRow[] {
  const commitment = asCommitment(sub)
  if (commitment.billing_cycle === 'once') throw new VaultWriteError('A one-time commitment has its one charge; there is nothing to plan.')
  const dates = chargeRows(vault).filter((r) => str(r.commitment_id) === commitment.id).map((r) => str(r.date))
  const last = dates.length ? dates.reduce((a, b) => (a > b ? a : b)) : null
  const today = todayMid()
  // The rhythm runs from the last charge, or from today when there is none.
  const anchor = last ? parseDate(last) : today
  let step = 1
  while (step < 100_000 && stepFrom(commitment, anchor, step) < today) step += 1
  const first = stepFrom(commitment, anchor, step)
  if (first < today) return []
  // "Twelve more months" is coverage beyond the last charge, that day inclusive, while the
  // plan runs ahead; a lapsed plan counts its months from the first charge it writes.
  const horizonFrom = step === 1 && last ? new Date(anchor.getTime() + 86400000) : first
  const rows = planCharges(commitment, first, Math.max(1, months), sub.amount as number, new Set(dates), now, horizonFrom)
  upsertCharges(vault, rows)
  return rows
}

function buildRow(input: CommitmentRowInput, vault: RawVault, now: string, touched: TouchedRow[], created: { members: string[]; accounts: string[]; tags: string[] }): Record<string, unknown> {
  const member = input.member?.trim() ? ensureEntity(vault, 'members', input.member, now, touched) : null
  const account = input.account?.trim() ? ensureEntity(vault, 'accounts', input.account, now, touched) : null
  if (member?.created) created.members.push(member.name)
  if (account?.created) created.accounts.push(account.name)
  if (input.tag?.trim()) {
    const registered = ensureTag(vault, 'commitment', input.tag, now)
    if (registered) created.tags.push(`${input.tag.trim()} (${registered})`)
  }
  const row: Record<string, unknown> = {
    id: randomUUID(),
    name: input.name.trim(),
    amount: input.amount,
    currency: input.currency.trim().toUpperCase(),
    billing_cycle: input.billing_cycle,
    status: input.status ?? 'active',
    created_at: now,
    updated_at: now,
  }
  if (input.billing_cycle === 'custom') row.custom_cycle_days = input.custom_cycle_days
  if (input.ends_on) row.ends_on = input.ends_on
  if (input.tag?.trim()) row.tag = input.tag.trim()
  if (input.notes?.trim()) row.notes = input.notes
  const direction = storedDirection(input.direction)
  if (direction) row.direction = direction
  if (member) row.member_id = member.id
  if (account) row.account_id = account.id
  return row
}

/** The vault's accounts as balanceNoteFor reads them: id, name, and the balance held with its day. */
const heldBalances = (vault: RawVault) =>
  rowsOf(vault, 'accounts').map((a) => ({
    id: str(a.id),
    name: str(a.name),
    balance: typeof a.balance === 'number' ? a.balance : null,
    balance_date: typeof a.balance_date === 'string' ? a.balance_date : null,
  }))

/** Keeps, per account, the newest confirmed day a write put on it: dated today or earlier, basis anything but plan. */
function noteWritten(newest: Map<string, string>, accountId: string, row: { date: string; basis?: string | null }, limit: string): void {
  if (!accountId || row.basis === 'plan' || row.date > limit) return
  if ((newest.get(accountId) ?? '') < row.date) newest.set(accountId, row.date)
}

export function addCommitments(dir: string, editedBy: string, input: AddCommitmentsInput): unknown {
  checkRows(input.rows)
  return writeVault(dir, editedBy, (vault): Mutated => {
    const touched: TouchedRow[] = []
    const now = new Date().toISOString()
    const limit = toISO(todayMid())
    const newest = new Map<string, string>()
    const created = { members: [] as string[], accounts: [] as string[], tags: [] as string[] }
    // A member or account a row names is refused by that row's place, as the row itself is.
    const built = input.rows.map((row, i) => {
      const from = touched.length
      const made = buildRow(row, vault, now, touched, created)
      for (const entity of touched.slice(from)) entity.place = i + 1
      return made
    })
    vault.commitments = [...rowsOf(vault, 'commitments'), ...built]
    let written = 0
    input.rows.forEach((spec, i) => {
      const row = built[i]!
      const first = parseDate((spec.first_charge ?? spec.date)!)
      const months = spec.billing_cycle === 'once' ? 1 : Math.max(1, spec.plan_months ?? DEFAULT_PLAN_MONTHS)
      // A count plans exactly that many from the first charge: months enough to hold them, then cut.
      const count = spec.billing_cycle !== 'once' && spec.plan_count != null ? Math.min(Math.max(spec.plan_count, 1), PLANNED_COUNT_CEILING) : null
      const rows = count
        ? planCharges(asCommitment(row), first, monthsHolding(count, row), spec.amount, new Set(), now).slice(0, count)
        : planCharges(asCommitment(row), first, months, spec.amount, new Set(), now)
      // A one-time row from a statement arrives paid, with what backs it.
      if (spec.billing_cycle === 'once' && rows[0] && (spec.paid !== undefined || spec.basis || spec.paid_on || spec.note)) {
        const only = rows[0]
        if (spec.paid !== undefined) only.paid = spec.paid
        if (spec.basis) only.basis = spec.basis
        else if (spec.paid) only.basis = 'user'
        if (spec.paid_on) only.paid_on = spec.paid_on
        if (spec.note) only.note = spec.note
      }
      upsertCharges(vault, rows)
      written += rows.length
      for (const r of rows) noteWritten(newest, str(row.account_id), r, limit)
      touched.push({ id: row.id as string, fields: { ...commitmentTexts(row), ...(spec.note ? { note: spec.note } : {}) }, place: i + 1 })
    })
    const balance_note = balanceNoteFor(heldBalances(vault), newest)
    return {
      touched,
      source: input.source,
      report: {
        added: built.length,
        charges_written: written,
        as_one_change: true,
        members_created: created.members,
        accounts_created: created.accounts,
        tags_registered: created.tags,
        planned_months_default: DEFAULT_PLAN_MONTHS,
        ...(balance_note ? { balance_note } : {}),
        note: 'The owner reviews this batch in the app, on the Proposals screen. A recurring row is planned plan_months ahead, 24 when unsaid: tell the owner, who can change any charge, or ask you to.',
      },
    }
  })
}

export function updateCommitment(dir: string, editedBy: string, input: UpdateCommitmentInput): unknown {
  const id = input.id?.trim()
  const name = input.name?.trim()
  if (!id && !name) throw new VaultWriteError('Say which commitment: pass its id, or its exact name.')
  // The hosted door's check, so both refuse a set alike: details by name, a set naming nothing.
  checkCommitmentSet(input.set)
  const set = input.set
  return writeVault(dir, editedBy, (vault): Mutated => {
    const rows = rowsOf(vault, 'commitments')
    const row = findCommitment(rows, id, name)
    const touched: TouchedRow[] = []
    const now = new Date().toISOString()
    const today = todayMid()
    const previousAmount = row.amount as number
    const previousStatus = str(row.status)
    const previousEnd = typeof row.ends_on === 'string' ? row.ends_on : null
    const wasOnce = row.billing_cycle === 'once'
    // A custom cycle the file already holds, days and all, is the file's own.
    const heldDays = row.billing_cycle === 'custom' && typeof row.custom_cycle_days === 'number' ? row.custom_cycle_days : null
    const mine = chargeRows(vault).filter((r) => str(r.commitment_id) === str(row.id))
    // A recurring commitment's charges are its history and its plan; one row cannot hold them.
    if (!wasOnce && set.billing_cycle === 'once' && mine.length > 1) throw new VaultWriteError(oneTimeRefusal(mine.length))
    // Nor can one date stand for a one-time commitment's several charges.
    if ((set.billing_cycle ?? row.billing_cycle) === 'once' && set.date && mine.length > 1) {
      throw new VaultWriteError(oneTimeMoveRefusal(mine.length))
    }

    // The preservation rule: start from the row on disk, change only what is named.
    if (set.name !== undefined) row.name = set.name
    if (set.amount !== undefined) row.amount = set.amount
    if (set.currency !== undefined) row.currency = set.currency.trim().toUpperCase()
    if (set.billing_cycle !== undefined) row.billing_cycle = set.billing_cycle
    if (set.custom_cycle_days !== undefined) row.custom_cycle_days = set.custom_cycle_days
    if (set.ends_on !== undefined) row.ends_on = set.ends_on
    if (set.status !== undefined) row.status = set.status
    if (set.tag !== undefined) row.tag = set.tag?.trim() || null
    if (set.notes !== undefined) row.notes = set.notes
    if (set.direction !== undefined) row.direction = storedDirection(set.direction)
    // A trial is a mark on the row, present only while true; false takes the key out.
    if (set.free_trial !== undefined) {
      if (set.free_trial) row.free_trial = true
      else delete row.free_trial
    }
    // A cycle leaving "custom" sheds its days — the same coherence the app's own form keeps.
    if (row.billing_cycle !== 'custom') row.custom_cycle_days = null

    if (set.member !== undefined) {
      row.member_id = set.member?.trim() ? ensureEntity(vault, 'members', set.member, now, touched).id : null
    }
    if (set.account !== undefined) {
      row.account_id = set.account?.trim() ? ensureEntity(vault, 'accounts', set.account, now, touched).id : null
    }
    if (typeof row.tag === 'string' && row.tag) ensureTag(vault, 'commitment', row.tag, now)

    const merged: CommitmentRowInput = {
      name: str(row.name),
      amount: row.amount as number,
      currency: str(row.currency),
      billing_cycle: row.billing_cycle as CommitmentRowInput['billing_cycle'],
      custom_cycle_days: typeof row.custom_cycle_days === 'number' ? row.custom_cycle_days : undefined,
      ends_on: typeof row.ends_on === 'string' ? row.ends_on : undefined,
    }
    // A price or custom days the set leaves as they were are the file's already; only changed ones meet the limits.
    const problems = rowProblems(merged, {
      existing: true,
      priceChanged: set.amount !== undefined && set.amount !== previousAmount,
      daysChanged: heldDays === null || merged.custom_cycle_days !== heldDays,
    })
    if (problems.length > 0) {
      throw new VaultWriteError(`Nothing was written — the change would leave "${merged.name}" invalid: ${problems.join('; ')}.`)
    }

    // The charges follow the rules in Ledger-Model-Plan: the attributes never reach the past.
    const rowId = str(row.id)
    const once = row.billing_cycle === 'once'
    // A one-time commitment's sole charge moves to its date, whatever its cycle was; a row
    // among several is never re-dated or dropped. Mirrors VaultPatch.moveSingleCharge.
    const single = mine.length === 1 ? mine[0]! : null
    if (once && set.date && single && str(single.date) !== set.date) {
      setChargeRows(vault, [...chargeRows(vault).filter((r) => r !== single), { ...single, date: set.date }])
    }
    if (set.amount !== undefined && set.amount !== previousAmount) {
      repriceUnpaidPlanned(vault, rowId, set.from ? parseDate(set.from) : today, set.amount, once)
    }
    if (row.status !== 'active' && previousStatus === 'active') removeUnpaidPlanned(vault, rowId, today)
    if (typeof row.ends_on === 'string' && row.ends_on !== previousEnd) removeUnpaidPlanned(vault, rowId, parseDate(row.ends_on))

    row.updated_at = now
    vault.commitments = rows
    touched.push({ id: rowId, fields: commitmentTexts(row) })
    // Only what was written is reported; a key the tool does not take is named apart.
    const { fields, ignored } = setOutcome(set, row.billing_cycle, mine.length)
    return {
      touched,
      source: input.source,
      addressed: { id, name },
      report: { updated: { id: rowId, name: str(row.name) }, fields, ...(ignored.length > 0 ? { ignored } : {}) },
    }
  })
}

export function markPaid(dir: string, editedBy: string, input: MarkPaidInput): unknown {
  const id = input.id?.trim()
  const name = input.name?.trim()
  if (!id && !name) throw new VaultWriteError('Say which commitment: pass its id, or its exact name.')
  if (!isRealDay(input.date ?? '')) {
    throw new VaultWriteError("date must be the charge's due date, a real YYYY-MM-DD day.")
  }
  if (input.paid_on != null && !isRealDay(input.paid_on)) {
    throw new VaultWriteError('paid_on is the day the money moved, a real YYYY-MM-DD day, or null to clear it.')
  }
  checkPaidAmount(input.amount)
  checkChargeNote(input.note)
  const paid = input.paid !== false
  return writeVault(dir, editedBy, (vault): Mutated => {
    const sub = findCommitment(rowsOf(vault, 'commitments'), id, name)
    const row = setCharge(vault, sub, { date: input.date, paid, amount: input.amount, paid_on: input.paid_on, note: input.note }, new Date().toISOString())
    return {
      touched: [{ id: str(sub.id), fields: { ...(input.note ? { note: input.note } : {}) } }, ...chargeKeys(str(sub.id), [input.date])],
      source: input.source,
      addressed: { id, name },
      report: { commitment: { id: str(sub.id), name: str(sub.name) }, date: input.date, paid, amount: row.amount, basis: row.basis ?? null },
    }
  })
}

export function addCharges(dir: string, editedBy: string, input: AddChargesInput): unknown {
  const id = input.id?.trim()
  const name = input.name?.trim()
  if (!id && !name) throw new VaultWriteError('Say which commitment: pass its id, or its exact name.')
  checkCharges(input.charges)
  return writeVault(dir, editedBy, (vault): Mutated => {
    const sub = findCommitment(rowsOf(vault, 'commitments'), id, name)
    const now = new Date().toISOString()
    const limit = toISO(todayMid())
    const newest = new Map<string, string>()
    const fields: TouchedRow['fields'] = {}
    for (const c of input.charges) {
      // A row someone priced or marked is their word; only an unpriced, unpaid row is a plan.
      const basis = c.basis ?? (c.paid || c.amount !== undefined ? 'user' : 'plan')
      setCharge(vault, sub, { date: c.date, paid: c.paid, amount: c.amount, paid_on: c.paid_on, note: c.note, basis, currency: c.currency }, now)
      if (c.note) fields[`note.${c.date}`] = c.note
      noteWritten(newest, str(sub.account_id), { date: c.date, basis }, limit)
    }
    const balance_note = balanceNoteFor(heldBalances(vault), newest)
    return {
      touched: [{ id: str(sub.id), fields }, ...chargeKeys(str(sub.id), input.charges.map((c) => c.date))],
      source: input.source,
      addressed: { id, name },
      report: { commitment: { id: str(sub.id), name: str(sub.name) }, written: input.charges.length, ...(balance_note ? { balance_note } : {}) },
    }
  })
}

export function removeChargesTool(dir: string, editedBy: string, input: RemoveChargesInput): unknown {
  const id = input.id?.trim()
  const name = input.name?.trim()
  if (!id && !name) throw new VaultWriteError('Say which commitment: pass its id, or its exact name.')
  if (!Array.isArray(input.dates) || input.dates.length === 0) throw new VaultWriteError('dates names the charges to remove.')
  for (const d of input.dates) if (!isRealDay(d)) throw new VaultWriteError(`"${d}" is not a real YYYY-MM-DD day.`)
  return writeVault(dir, editedBy, (vault): Mutated => {
    const sub = findCommitment(rowsOf(vault, 'commitments'), id, name)
    const subId = str(sub.id)
    // Only a day that held a row leaves a tombstone; a day named in vain signs nothing.
    const held = chargeSnapshot(vault, subId)
    const removed = removeCharges(vault, subId, input.dates)
    return {
      touched: [{ id: subId, fields: {} }, ...chargeKeys(subId, input.dates.filter((d) => held.has(d)))],
      source: input.source,
      addressed: { id, name },
      report: { commitment: { id: str(sub.id), name: str(sub.name) }, removed },
    }
  })
}

export function promoteToRecurring(dir: string, editedBy: string, input: PromoteInput): unknown {
  // The hosted door's check, so both refuse a promotion in the same words.
  checkPromotion(input as unknown as Record<string, unknown>)
  return writeVault(dir, editedBy, (vault): Mutated => {
    const rows = rowsOf(vault, 'commitments')
    const ids = new Set(input.ids)
    const olds = input.ids.map((id) => findCommitment(rows, id))
    const moving = chargeRows(vault).filter((r) => ids.has(str(r.commitment_id)))
    if (moving.length === 0) throw new VaultWriteError('None of those commitments has a charge to carry over.')
    for (const old of olds) {
      if (old.billing_cycle !== 'once') {
        throw new VaultWriteError(`"${str(old.name)}" (id ${str(old.id)}) is ${str(old.billing_cycle)}, not a one-time commitment; promote_to_recurring takes one-time commitments only.`)
      }
    }
    // One direction across the ids, or a row would move into or out of a sum.
    const mixed = mixedDirections(olds.map((old) => ({ name: str(old.name), direction: old.direction })))
    if (mixed) throw new VaultWriteError(mixed)
    const touched: TouchedRow[] = []
    const now = new Date().toISOString()
    const first = olds[0]!

    // The attributes start as the first one-time row's, then take whatever was named.
    const row: Record<string, unknown> = {
      id: randomUUID(),
      name: (input.name ?? str(first.name)).trim(),
      amount: first.amount,
      currency: str(first.currency),
      billing_cycle: input.billing_cycle,
      status: 'active',
      created_at: now,
      updated_at: now,
    }
    if (input.billing_cycle === 'custom') row.custom_cycle_days = input.custom_cycle_days
    if (input.ends_on) row.ends_on = input.ends_on
    // Direction rides along: a repeating credit stays money in, a standing transfer a transfer.
    const direction = storedDirection(first.direction)
    if (direction) row.direction = direction
    const tag = input.tag === undefined ? (typeof first.tag === 'string' ? first.tag : null) : input.tag?.trim() || null
    if (tag) { row.tag = tag; ensureTag(vault, 'commitment', tag, now) }
    // The first row's details ride along — longbook's own statement line, never an input.
    if (isRecord(first.details) && Object.keys(first.details).length > 0) row.details = first.details
    const notes = input.notes === undefined ? first.notes : input.notes
    if (typeof notes === 'string' && notes.trim()) row.notes = notes
    if (input.member === undefined) { if (first.member_id) row.member_id = first.member_id }
    else if (input.member?.trim()) row.member_id = ensureEntity(vault, 'members', input.member, now, touched).id
    if (input.account === undefined) { if (first.account_id) row.account_id = first.account_id }
    else if (input.account?.trim()) row.account_id = ensureEntity(vault, 'accounts', input.account, now, touched).id

    const merged: CommitmentRowInput = {
      name: str(row.name), amount: row.amount as number, currency: str(row.currency),
      billing_cycle: input.billing_cycle, custom_cycle_days: input.custom_cycle_days, ends_on: input.ends_on,
    }
    const problems = rowProblems(merged, { existing: true })
    if (problems.length > 0) throw new VaultWriteError(`Nothing was written — the promotion would be invalid: ${problems.join('; ')}.`)

    vault.commitments = [...rows.filter((r) => !ids.has(str(r.id))), row]
    const carried = moving.map((r) => ({ ...r, commitment_id: row.id }))
    setChargeRows(vault, [...chargeRows(vault).filter((r) => !ids.has(str(r.commitment_id))), ...carried])
    const planned = plan(vault, row, Math.max(1, input.plan_months ?? DEFAULT_PLAN_MONTHS), now)

    // The merged rows leave tombstones signed by the caller, as the app's promote does.
    for (const id of input.ids) touched.push({ id, fields: {} })
    touched.push({ id: row.id as string, fields: commitmentTexts(row) })
    return {
      touched,
      source: input.source,
      addressed: { name: input.name, ids: input.ids },
      report: {
        promoted: { id: row.id, name: str(row.name), cycle: input.billing_cycle },
        carried: carried.length,
        planned: planned.length,
        removed: input.ids,
      },
    }
  })
}

export function cancelCommitment(dir: string, editedBy: string, input: CancelCommitmentInput): unknown {
  const id = input.id?.trim()
  const name = input.name?.trim()
  if (!id && !name) throw new VaultWriteError('Say which commitment: pass its id, or its exact name.')
  return writeVault(dir, editedBy, (vault): Mutated => {
    const rows = rowsOf(vault, 'commitments')
    const row = findCommitment(rows, id, name)
    if (row.status === 'cancelled') {
      throw new VaultWriteError(`"${str(row.name)}" is already cancelled.`)
    }
    row.status = 'cancelled'
    row.updated_at = new Date().toISOString()
    // The raw rows above are the vault's own objects, so the edit is already in place;
    // reassigning drops anything non-object a broken file carried alongside them.
    vault.commitments = rows
    // What was only planned past today is unwritten; what happened stays.
    removeUnpaidPlanned(vault, str(row.id), todayMid())
    return {
      touched: [{ id: str(row.id), fields: commitmentTexts(row) }],
      source: input.source,
      addressed: { id, name },
      report: { cancelled: { id: str(row.id), name: str(row.name), status: 'cancelled' } },
    }
  })
}

/**
 * One charge's changes as one write, where it sits: a one-time commitment's price when the
 * charge counts in its currency, then the row's fields, then the reprice and the move a reach
 * carries. Mirrors VaultPatch.editCharge, refusal for refusal.
 */
export function updateCharge(dir: string, editedBy: string, input: UpdateChargeInput): unknown {
  const id = input.id?.trim()
  const name = input.name?.trim()
  if (!id && !name) throw new VaultWriteError('Say which commitment: pass its id, or its exact name.')
  if (!isRealDay(input.date ?? '')) throw new VaultWriteError('date is the day the charge sits on, a real YYYY-MM-DD day.')
  checkChargeSet(input.set)
  const set = input.set
  return writeVault(dir, editedBy, (vault): Mutated => {
    const sub = findCommitment(rowsOf(vault, 'commitments'), id, name)
    const subId = str(sub.id)
    const now = new Date().toISOString()
    const row = chargeRows(vault).find((r) => sameCharge(r, subId, input.date))
    if (!row) throw new VaultWriteError(noChargeRefusal(input.date, str(sub.name)))
    const held = chargeSnapshot(vault, subId)
    // A one-time commitment is its charge: a new amount in its own currency is its price too.
    const once = sub.billing_cycle === 'once'
    if (set.amount !== undefined && once && sub.amount !== set.amount && (row.currency == null || row.currency === sub.currency)) {
      sub.amount = set.amount
      sub.updated_at = now
    }
    setCharge(vault, sub, { date: input.date, paid: set.paid, amount: set.amount, paid_on: set.paid_on, note: set.note }, now)
    // A reprice reaches the rows after it in the plan, not ones a backward move lands behind.
    if (set.and_later && set.amount !== undefined) reprice(vault, sub, input.date, set.amount, now)
    const moved = set.date !== undefined && set.date !== input.date ? reschedule(vault, sub, input.date, set.date, set.and_later === true, now) : 0
    const fields = CHARGE_SET_FIELDS.filter((k) => k !== 'and_later' && set[k] !== undefined)
    // The day named and every row a move or a reprice carried.
    const days = [input.date, ...changedDays(held, vault, subId)]
    return {
      touched: [{ id: subId, fields: { ...(set.note ? { note: set.note } : {}) } }, ...chargeKeys(subId, days)],
      source: input.source,
      addressed: { id, name },
      report: {
        commitment: { id: subId, name: str(sub.name) },
        date: input.date,
        fields,
        ...(moved > 0 ? { moved_to: set.date, rows_moved: moved } : {}),
      },
    }
  })
}

/**
 * The charges from today on, set to exactly `count`: more are written a cycle apart after the
 * last row, unpaid planned rows past the count are unwritten; paid rows, hand-set rows and the
 * past stay. Mirrors VaultPatch.setPlannedCount.
 */
export function setPlannedCount(dir: string, editedBy: string, input: SetPlannedCountInput): unknown {
  const id = input.id?.trim()
  const name = input.name?.trim()
  if (!id && !name) throw new VaultWriteError('Say which commitment: pass its id, or its exact name.')
  checkPlannedCount(input.count)
  return writeVault(dir, editedBy, (vault): Mutated => {
    const sub = findCommitment(rowsOf(vault, 'commitments'), id, name)
    if (sub.billing_cycle === 'once') throw new VaultWriteError(NOTHING_TO_PLAN)
    const commitment = asCommitment(sub)
    // A plan under a paused or cancelled commitment is one the app's own form never writes.
    const status = displayStatus(commitment)
    if (status !== 'active') throw new VaultWriteError(notActiveRefusal(str(sub.name), status))
    const subId = commitment.id
    const today = todayMid()
    const wanted = Math.min(Math.max(input.count, 1), PLANNED_COUNT_CEILING)
    const all = chargeRows(vault)
    const ahead = all
      .map((row, offset) => ({ row, offset }))
      .filter(({ row }) => str(row.commitment_id) === subId && parseDate(str(row.date)) >= today)
      .sort((a, b) => str(a.row.date).localeCompare(str(b.row.date)))
    let written = 0
    let unwritten = 0
    // The days written or unwritten, signed as the app signs them.
    const days: string[] = []
    if (ahead.length > wanted) {
      // The latest planned rows go first; a paid or hand-set row is never taken.
      const drop = new Set<number>()
      for (const { row, offset } of [...ahead].reverse()) {
        if (ahead.length - drop.size <= wanted) break
        if (isPlanRow(row)) drop.add(offset)
      }
      setChargeRows(vault, all.filter((_, i) => !drop.has(i)))
      unwritten = drop.size
      days.push(...[...drop].map((i) => str(all[i]!.date)))
    } else if (ahead.length < wanted) {
      const dates = all.filter((r) => str(r.commitment_id) === subId).map((r) => str(r.date))
      const last = dates.length ? parseDate(dates.reduce((a, b) => (a > b ? a : b))) : today
      const end = commitment.ends_on ? parseDate(commitment.ends_on) : null
      const now = new Date().toISOString()
      const rows: ChargeRow[] = []
      let k = 1
      while (rows.length < wanted - ahead.length && k < 4000) {
        const day = stepFrom(commitment, last, k)
        k += 1
        if (end && day > end) break
        // A plan that stopped months ago resumes from today on, never back-filled.
        if (day < today) continue
        const iso = toISO(day)
        if (dates.includes(iso)) continue
        rows.push({ commitment_id: subId, date: iso, amount: sub.amount as number, paid: false, basis: 'plan', written_at: now })
      }
      upsertCharges(vault, rows)
      written = rows.length
      days.push(...rows.map((r) => r.date))
    }
    const standing = chargeRows(vault).filter((r) => str(r.commitment_id) === subId && parseDate(str(r.date)) >= today).length
    return {
      touched: [{ id: subId, fields: {} }, ...chargeKeys(subId, days)],
      source: input.source,
      addressed: { id, name },
      report: { commitment: { id: subId, name: str(sub.name) }, count: wanted, ahead: standing, written, unwritten },
    }
  })
}

/**
 * Removes the row outright and its charges — the one write here that destroys something,
 * and only on the owner's own word. Mirrors VaultPatch.delete: the provenance entries
 * outlive the rows as tombstones signed by the caller, so every device reviews the removal
 * and names who made it.
 */
export function deleteCommitment(dir: string, editedBy: string, input: DeleteCommitmentInput): unknown {
  const id = input.id?.trim()
  if (!id) throw new VaultWriteError('Say which commitment: pass its id. delete_commitment takes no name.')
  return writeVault(dir, editedBy, (vault): Mutated => {
    const rows = rowsOf(vault, 'commitments')
    const row = findCommitment(rows, id)
    const today = todayMid()
    const mine = chargeRows(vault).filter((r) => str(r.commitment_id) === id)
    // A charge behind today is paid whatever its row says.
    const paid = mine.filter((r) => r.paid === true || parseDate(str(r.date)) < today).length
    vault.commitments = rows.filter((r) => r !== row)
    setChargeRows(vault, chargeRows(vault).filter((r) => str(r.commitment_id) !== id))
    return {
      touched: [{ id, fields: {} }, ...chargeKeys(id, mine.map((r) => str(r.date)))],
      source: input.source,
      addressed: { id },
      report: { deleted: { id, name: str(row.name) }, charges_removed: mine.length, paid_charges_removed: paid },
    }
  })
}

// ---- accounts and members ---------------------------------------------------------------
// These mirror VaultPatch.renameEntity and setEntityDetails in swift-core, refusal for
// refusal, so both doors change an account or a person the way the app's own form does.
// The finders live in targets.ts, where the hosted door checks proposals by the same rule.

/** Rename in place; the id never changes. Merging two rows is refused, as the app refuses it. */
function renameEntity(rows: Record<string, unknown>[], row: Record<string, unknown>, name: string, article: string): void {
  const clean = name.trim()
  const key = nameKey(clean)
  if (rows.some((r) => r !== row && entityKey(r) === key)) {
    throw new VaultWriteError(`There's already ${article} called ${clean}.`)
  }
  row.name = clean
  row.name_key = key
  row.is_incomplete = false
}

/** What describes an account, written onto its row: mirrors VaultPatch.setEntityDetails for an account. */
function describeAccount(vault: RawVault, rows: Record<string, unknown>[], row: Record<string, unknown>, set: AccountSet, now: string): void {
  const rowId = str(row.id)
  if (set.tag !== undefined) {
    const tag = set.tag?.trim() || null
    row.tag = tag
    if (tag) ensureTag(vault, 'account', tag, now)
  }
  const link = linkedTo(set)
  if (link !== undefined) {
    const wanted = link?.trim() || null
    if (wanted) {
      const linked = findLinked(rows, wanted)
      if (linked === row) throw new VaultWriteError("An account can't be linked to itself.")
      // One level, per the contract — checked in both directions.
      if (typeof linked.parent_account_id === 'string') {
        throw new VaultWriteError('That account is already linked to another — one level only.')
      }
      if (rows.some((r) => str(r.parent_account_id) === rowId)) {
        throw new VaultWriteError("Other accounts are linked to this one, so it can't be linked to another.")
      }
      row.parent_account_id = str(linked.id)
    } else {
      row.parent_account_id = null
    }
  }
  if (set.member !== undefined) {
    const wanted = set.member?.trim() || null
    row.member_id = wanted ? str(findOwner(rowsOf(vault, 'members'), wanted).id) : null
  }
  if (set.notes !== undefined) row.notes = set.notes?.trim() ? set.notes : null
  if (set.balance !== undefined) {
    if (set.balance === null) {
      row.balance = null
      row.balance_date = null
    } else {
      row.balance = set.balance
      row.balance_date = set.balance_date ?? toISO(todayMid())
    }
  } else if (set.balance_date !== undefined) {
    // The day alone moves a balance already held; it never stands without one.
    if (typeof row.balance !== 'number') throw new VaultWriteError('This account holds no balance to date — give balance with balance_date.')
    row.balance_date = set.balance_date
  }
  if (set.starred !== undefined) setStar(row, set.starred)
}

/** The star as the app writes it: true when set, and no key at all when not. */
function setStar(row: Record<string, unknown>, starred: boolean): void {
  if (starred) row.starred = true
  else delete row.starred
}

/** What describes a person, written onto their row: mirrors VaultPatch.setEntityDetails for a member. */
function describeMember(vault: RawVault, row: Record<string, unknown>, set: MemberSet, now: string): void {
  // Stored exactly as typed, as the app stores it; empty clears.
  if (set.email !== undefined) row.email = set.email || null
  if (set.tag !== undefined) {
    const tag = set.tag?.trim() || null
    row.tag = tag
    if (tag) ensureTag(vault, 'member', tag, now)
  }
  if (set.starred !== undefined) setStar(row, set.starred)
}

export function updateAccount(dir: string, editedBy: string, input: UpdateAccountInput): unknown {
  const id = input.id?.trim()
  const name = input.name?.trim()
  if (!id && !name) throw new VaultWriteError('Say which account: pass its id, or its exact name.')
  checkAccountSet(input.set)
  const set = input.set
  return writeVault(dir, editedBy, (vault): Mutated => {
    const rows = rowsOf(vault, 'accounts')
    const row = findEntity(rows, 'account', id, name)
    const rowId = str(row.id)
    const now = new Date().toISOString()

    if (set.name !== undefined) renameEntity(rows, row, set.name, 'an account')
    describeAccount(vault, rows, row, set, now)

    vault.accounts = rows
    // Only what was written is reported; a key the tool does not take is named apart.
    const { fields, ignored } = entitySetOutcome('update_account', set)
    return {
      touched: [{ id: rowId, fields: { name: str(row.name), tag: str(row.tag), notes: str(row.notes) } }],
      source: input.source,
      addressed: { id, name },
      report: { updated: { id: rowId, name: str(row.name) }, fields, ...(ignored.length > 0 ? { ignored } : {}) },
    }
  })
}

export function updateMember(dir: string, editedBy: string, input: UpdateMemberInput): unknown {
  const id = input.id?.trim()
  const name = input.name?.trim()
  if (!id && !name) throw new VaultWriteError('Say which person: pass its id, or its exact name.')
  checkMemberSet(input.set)
  const set = input.set
  return writeVault(dir, editedBy, (vault): Mutated => {
    const rows = rowsOf(vault, 'members')
    const row = findEntity(rows, 'person', id, name)
    const rowId = str(row.id)

    if (set.name !== undefined) renameEntity(rows, row, set.name, 'a person')
    describeMember(vault, row, set, new Date().toISOString())

    vault.members = rows
    const { fields, ignored } = entitySetOutcome('update_person', set)
    return {
      touched: [{ id: rowId, fields: { name: str(row.name), email: str(row.email), tag: str(row.tag) } }],
      source: input.source,
      addressed: { id, name },
      report: { updated: { id: rowId, name: str(row.name) }, fields, ...(ignored.length > 0 ? { ignored } : {}) },
    }
  })
}

/**
 * A new person or account, written as ensureEntity writes a placeholder and then described;
 * a name the list already holds is refused rather than doubled. Named, not yet described, it
 * stays is_incomplete, as a placeholder is.
 */
function addEntity(
  vault: RawVault,
  list: 'members' | 'accounts',
  name: string,
  described: boolean,
  now: string,
  article: string,
): Record<string, unknown> {
  const clean = name.trim()
  if (!clean) throw new VaultWriteError(EMPTY_NAME_REFUSAL)
  const key = nameKey(clean)
  const rows = rowsOf(vault, list)
  if (rows.some((r) => entityKey(r) === key)) throw new VaultWriteError(entityTwinRefusal(article, clean))
  const row: Record<string, unknown> = { id: randomUUID(), name: clean, name_key: key, is_incomplete: !described, created_at: now }
  vault[list] = [...rows, row]
  return row
}

export function addMember(dir: string, editedBy: string, input: AddMemberInput): unknown {
  checkNewMember(input)
  const set: MemberSet = {}
  if (input.tag !== undefined) set.tag = input.tag
  if (input.email !== undefined) set.email = input.email
  // Details that say nothing describe nothing: a name alone stays a placeholder.
  const described = Object.keys(set).length > 0
  return writeVault(dir, editedBy, (vault): Mutated => {
    const now = new Date().toISOString()
    const row = addEntity(vault, 'members', input.name, described, now, 'a person')
    describeMember(vault, row, set, now)
    const { fields } = entitySetOutcome('update_person', set)
    return {
      touched: [{ id: str(row.id), fields: { name: str(row.name), email: str(row.email), tag: str(row.tag) } }],
      source: input.source,
      addressed: { name: input.name },
      report: { added: { id: str(row.id), name: str(row.name) }, fields },
    }
  })
}

export function addAccount(dir: string, editedBy: string, input: AddAccountInput): unknown {
  checkNewAccount(input)
  const set: AccountSet = {}
  // The link under its name or either older one, resolved as describeAccount resolves an update's.
  for (const key of NEW_ACCOUNT_FIELDS) {
    if (input[key] !== undefined) (set as Record<string, unknown>)[key] = input[key]
  }
  const described = Object.keys(set).length > 0
  return writeVault(dir, editedBy, (vault): Mutated => {
    const now = new Date().toISOString()
    const row = addEntity(vault, 'accounts', input.name, described, now, 'an account')
    describeAccount(vault, rowsOf(vault, 'accounts'), row, set, now)
    const { fields, ignored } = entitySetOutcome('update_account', set)
    return {
      touched: [{ id: str(row.id), fields: { name: str(row.name), tag: str(row.tag), notes: str(row.notes) } }],
      source: input.source,
      addressed: { name: input.name },
      report: { added: { id: str(row.id), name: str(row.name) }, fields, ...(ignored.length > 0 ? { ignored } : {}) },
    }
  })
}

// ---- tags -------------------------------------------------------------------------------
// These mirror VaultPatch.renameTag and removeTag: rows store a tag's NAME, not its id, so
// both carry every row wearing the tag, and a rename carries the owner's tag groups too.

const TAG_LIST: Record<TagKind, 'commitments' | 'members' | 'accounts'> = { commitment: 'commitments', member: 'members', account: 'accounts' }

const tagMatches = (tag: Record<string, unknown>, kind: TagKind, key: string): boolean =>
  str(tag.kind) === kind && (str(tag.name_key) || nameKey(str(tag.name))) === key

export function renameTag(dir: string, editedBy: string, input: RenameTagInput): unknown {
  checkTagRename(input as unknown as Record<string, unknown>)
  const clean = input.to.trim()
  // The new name is written onto every row wearing the tag, so it meets the scan a tag set on one row meets.
  if (scanText(clean)) throw new VaultWriteError(DATA_POLICY_REFUSAL)
  const kind = input.kind
  const oldKey = nameKey(input.from)
  const newKey = nameKey(clean)
  return writeVault(dir, editedBy, (vault): Mutated => {
    const tags = rowsOf(vault, 'tags')
    const rows = rowsOf(vault, TAG_LIST[kind])
    const wearers = rows.filter((r) => nameKey(str(r.tag)) === oldKey)
    const registered = tags.find((t) => tagMatches(t, kind, oldKey))
    if (!registered && wearers.length === 0) throw new VaultWriteError(`No ${kind} tag is called "${input.from.trim()}".`)
    // Two tags of one kind sharing a name would be one tag the owner can't tell apart.
    if (newKey !== oldKey && tags.some((t) => tagMatches(t, kind, newKey))) throw new VaultWriteError(tagTwinRefusal(clean))
    if (registered) {
      registered.name = clean
      registered.name_key = newKey
      // Renamed is the owner's own word now, whatever the library seeded.
      registered.is_default = false
      vault.tags = tags
    }
    const now = new Date().toISOString()
    const touched: TouchedRow[] = []
    for (const row of wearers) {
      row.tag = clean
      row.updated_at = now
      touched.push({ id: str(row.id), fields: { tag: clean } })
    }
    vault[TAG_LIST[kind]] = rows
    // A tag group holds normalised names, so it is carried in the same pass.
    const groups = rowsOf(vault, 'groups')
    for (const group of groups) {
      if (str(group.kind) !== 'tag' || !Array.isArray(group.tag_keys) || !group.tag_keys.includes(oldKey)) continue
      group.tag_keys = group.tag_keys.map((k: unknown) => (k === oldKey ? newKey : k))
    }
    if (groups.length > 0) vault.groups = groups
    return {
      touched,
      source: input.source,
      addressed: { name: input.from },
      report: { renamed: { from: input.from.trim(), to: clean }, kind, rows_moved: wearers.length },
    }
  })
}

export function deleteTag(dir: string, editedBy: string, input: DeleteTagInput): unknown {
  checkTagDelete(input as unknown as Record<string, unknown>)
  const kind = input.kind
  const key = nameKey(input.name)
  return writeVault(dir, editedBy, (vault): Mutated => {
    const tags = rowsOf(vault, 'tags')
    const rows = rowsOf(vault, TAG_LIST[kind])
    const wearers = rows.filter((r) => nameKey(str(r.tag)) === key)
    const kept = tags.filter((t) => !tagMatches(t, kind, key))
    if (kept.length === tags.length && wearers.length === 0) throw new VaultWriteError(`No ${kind} tag is called "${input.name.trim()}".`)
    if (kept.length < tags.length) vault.tags = kept
    const now = new Date().toISOString()
    const touched: TouchedRow[] = []
    for (const row of wearers) {
      row.tag = null
      row.updated_at = now
      touched.push({ id: str(row.id), fields: {} })
    }
    vault[TAG_LIST[kind]] = rows
    return {
      touched,
      source: input.source,
      addressed: { name: input.name },
      report: { deleted: input.name.trim(), kind, rows_cleared: wearers.length },
    }
  })
}
