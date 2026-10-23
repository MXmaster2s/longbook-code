// Which row a write addresses, matched as the app matches at apply time: id exact, else
// the name key. The local write tools resolve through these finders; the hosted door
// checks a proposal here before filing, so a miss names the real rows now.
import { displayStatus, nameKey } from '@longbook/core'
import type { Account, Commitment, LoadedData, Member } from '@longbook/core'
import { VaultWriteError } from './errors.js'
import {
  NOTHING_TO_PLAN,
  NO_ACCOUNT,
  NO_CATEGORY,
  dayTakenRefusal,
  linkedTo,
  mixedDirections,
  noChargeRefusal,
  notActiveRefusal,
  oneTimeMoveRefusal,
  oneTimeRefusal,
  tagTwinRefusal,
} from './proposal.js'
import type { AccountSet, Proposal, ProposalKind } from './proposal.js'

type Row = Record<string, unknown>
const str = (v: unknown): string => (typeof v === 'string' ? v : '')

/** A row's key: the stored name_key when present, else the name's. */
export const entityKey = (r: Row): string => str(r.name_key) || nameKey(str(r.name))

export type Match<T> =
  | { row: T; miss?: undefined; matches?: undefined }
  | { row?: undefined; miss: 'no_id' | 'no_name' | 'ambiguous'; matches: T[] }

/** The one matching rule: an id is exact; a name matches by key and must match one row. */
export function matchRow<T>(
  rows: T[],
  id: string | undefined,
  name: string | undefined,
  idOf: (r: T) => string,
  keyOf: (r: T) => string,
): Match<T> {
  if (id) {
    const row = rows.find((r) => idOf(r) === id)
    return row ? { row } : { miss: 'no_id', matches: [] }
  }
  const wanted = nameKey(name ?? '')
  const matches = rows.filter((r) => keyOf(r) === wanted)
  if (matches.length === 1) return { row: matches[0]! }
  return { miss: matches.length === 0 ? 'no_name' : 'ambiguous', matches }
}

const rawId = (r: Row): string => str(r.id)
const commitmentKey = (r: Row): string => nameKey(str(r.name))

/** One commitment by id, or by exact name when the name is unique. */
export function findCommitment(rows: Row[], id?: string, name?: string): Row {
  const found = matchRow(rows, id, name, rawId, commitmentKey)
  if (found.row) return found.row
  if (found.miss === 'no_id') throw new VaultWriteError(`No commitment has the id ${id}.`)
  if (found.miss === 'no_name') throw new VaultWriteError(`No commitment is named "${name}".`)
  const candidates = found.matches.map((m) => `"${str(m.name)}" (id ${str(m.id)}, ${str(m.status)})`).join('; ')
  throw new VaultWriteError(`"${name}" matches more than one commitment — pass an id instead: ${candidates}.`)
}

/** One account or person by id, or by exact name when the name is unique. */
export function findEntity(rows: Row[], noun: string, id?: string, name?: string): Row {
  const found = matchRow(rows, id, name, rawId, entityKey)
  if (found.row) return found.row
  if (found.miss === 'no_id') throw new VaultWriteError(`No ${noun} has the id ${id}.`)
  if (found.miss === 'no_name') throw new VaultWriteError(`No ${noun} is named "${name}".`)
  const candidates = found.matches.map((m) => `"${str(m.name)}" (id ${str(m.id)})`).join('; ')
  throw new VaultWriteError(`"${name}" matches more than one ${noun} — pass an id instead: ${candidates}.`)
}

/** A row a set names in passing — by id, else by a name only one row wears. */
function findNamed(rows: Row[], wanted: string, noun: string, missing: string): Row {
  const byId = rows.find((r) => rawId(r) === wanted)
  if (byId) return byId
  const found = matchRow(rows, undefined, wanted, rawId, entityKey)
  if (found.row) return found.row
  if (found.miss === 'ambiguous') {
    const candidates = found.matches.map((m) => `"${str(m.name)}" (id ${str(m.id)})`).join('; ')
    throw new VaultWriteError(`"${wanted}" matches more than one ${noun} — pass its id instead: ${candidates}.`)
  }
  throw new VaultWriteError(missing)
}

/** The account another is linked to — a card to the bank account that pays it. */
export function findLinked(rows: Row[], wanted: string): Row {
  return findNamed(rows, wanted, 'account', "That linked account isn't in the vault.")
}

/** The person an account belongs to. Never made here: an update names people the memory holds. */
export function findOwner(rows: Row[], wanted: string): Row {
  const known = rows.map((r) => `"${str(r.name)}"`).join(', ')
  return findNamed(rows, wanted, 'person', `No person is named "${wanted}".${known ? ` People: ${known}.` : ''}`)
}

// ---------------------------------------------------------------------------------------------
// The hosted door: a proposal checked against the copy before it is filed.

/** A proposal aimed at a row the copy does not hold, or at more than one. */
export class TargetMiss extends Error {
  constructor(
    readonly code: 'not_found' | 'validation_failed',
    message: string,
    readonly extra: Record<string, unknown> = {},
  ) {
    super(message)
  }
}

/** The kinds checked against the copy: those addressing a row in it, and those a twin would refuse. */
export const TARGETED_KINDS: ReadonlySet<ProposalKind> = new Set<ProposalKind>([
  'update_commitment',
  'mark_paid',
  'add_charges',
  'remove_charges',
  'cancel_commitment',
  'promote_to_recurring',
  'update_account',
  'update_person',
  'update_charge',
  'set_planned_count',
  'add_person',
  'add_account',
  'rename_tag',
  'delete_tag',
  'delete_commitment',
  'create_report',
])

/** Where a miss is said to be: the hosted copy, or the vault itself on this machine. */
export interface TargetPlace {
  copy: string
  /** The same place opening a sentence of its own. */
  holder: string
}

/** The local door's place: it checks against the folder it is about to write beside. */
export const VAULT_PLACE: TargetPlace = { copy: 'the vault', holder: 'The vault' }

interface Candidate {
  name: string
  id: string
  status?: string
}

const candidate = (r: { id: string; name: string }): Candidate => ({ name: r.name, id: r.id })
const commitmentCandidate = (r: Commitment): Candidate => ({ name: r.name, id: r.id, status: r.status })
const listed = (rows: Candidate[]): string =>
  rows.map((r) => `"${r.name}" (id ${r.id}${r.status ? `, ${r.status}` : ''})`).join(', ')

const REST = 'Read commitments (status "all") or search for the rest, then pass a name exactly or its id.'

/** The ten commitments with the latest written charge, so a miss shows what is live. */
function recent(data: LoadedData): Commitment[] {
  const latest = new Map<string, string>()
  for (const c of data.charges ?? []) {
    const seen = latest.get(c.commitment_id)
    if (!seen || c.date > seen) latest.set(c.commitment_id, c.date)
  }
  const stamp = (s: Commitment) => latest.get(s.id) ?? s.updated_at.slice(0, 10)
  return [...data.subs].sort((a, b) => stamp(b).localeCompare(stamp(a))).slice(0, 10)
}

class Checker {
  readonly copy: string
  readonly holder: string
  readonly extra: Record<string, unknown>

  constructor(readonly data: LoadedData, pushedAt: string | null, place?: TargetPlace) {
    this.copy = place?.copy ?? (pushedAt ? `the hosted copy (pushed ${pushedAt.slice(0, 10)})` : 'the hosted copy')
    this.holder = place?.holder ?? 'The copy'
    this.extra = place ? {} : { hosted_copy_pushed_at: pushedAt }
  }

  miss(code: TargetMiss['code'], message: string, candidates: Candidate[]): never {
    throw new TargetMiss(code, message, { ...this.extra, candidates })
  }

  commitment(id: string, name: string): Commitment {
    const subs = this.data.subs
    const found = matchRow(subs, id || undefined, name, (s) => s.id, (s) => nameKey(s.name))
    if (found.row) return found.row
    if (found.miss === 'ambiguous') {
      const rows = found.matches.map(commitmentCandidate)
      this.miss('validation_failed', `"${name}" matches more than one commitment in ${this.copy} — pass an id instead: ${listed(rows)}.`, rows)
    }
    const wanted = nameKey(name)
    const near = wanted
      ? subs.filter((s) => { const k = nameKey(s.name); return k.includes(wanted) || wanted.includes(k) })
      : []
    const rows = (near.length ? near : recent(this.data)).map(commitmentCandidate)
    const where = found.miss === 'no_id' ? `has the id ${id}` : `is called "${name}"`
    const shown = rows.length ? ` ${near.length ? 'Nearest by name' : 'Most recent'}: ${listed(rows)}.` : ''
    this.miss('not_found', `No commitment in ${this.copy} ${where}.${shown} ${REST}`, rows)
  }

  entity<T extends Account | Member>(rows: T[], noun: string, label: string, id: string, name: string): T {
    const found = matchRow(rows, id || undefined, name, (r) => r.id, (r) => r.name_key || nameKey(r.name))
    if (found.row) return found.row
    if (found.miss === 'ambiguous') {
      const all = found.matches.map(candidate)
      this.miss('validation_failed', `"${name}" matches more than one ${noun} in ${this.copy} — pass an id instead: ${listed(all)}.`, all)
    }
    const all = rows.map(candidate)
    const where = found.miss === 'no_id' ? `has the id ${id}` : `is called "${name}"`
    const shown = all.length ? ` ${label}: ${listed(all)}. Pass one of these names exactly, or its id.` : ` ${this.holder} holds none.`
    this.miss('not_found', `No ${noun} in ${this.copy} ${where}.${shown}`, all)
  }

  collision<T extends Account | Member>(rows: T[], row: T, name: string, article: string): void {
    const key = nameKey(name)
    const other = rows.find((r) => r.id !== row.id && (r.name_key || nameKey(r.name)) === key)
    if (!other) return
    this.miss('validation_failed', `There's already ${article} called "${name.trim()}" in ${this.copy} (id ${other.id}). Renaming onto it is refused rather than merged.`, [candidate(other)])
  }

  /** A name a set carries in passing: an id is taken as it is, a name must be one row's. */
  named<T extends Account | Member>(rows: T[], noun: string, label: string, wanted: string): T {
    return rows.find((r) => r.id === wanted) ?? this.entity(rows, noun, label, '', wanted)
  }

  /** A new row's name against every row the copy holds: a twin is refused, never doubled. */
  twin<T extends Account | Member>(rows: T[], name: string, article: string, changer: string): void {
    const key = nameKey(name)
    const other = rows.find((r) => (r.name_key || nameKey(r.name)) === key)
    if (!other) return
    this.miss('validation_failed', `There's already ${article} called "${name.trim()}" in ${this.copy} (id ${other.id}). Adding a twin is refused; ${changer} changes it.`, [candidate(other)])
  }

  /** The rows of a kind, as a tag of that kind is worn. */
  private wearers(kind: string): Array<{ tag: string | null }> {
    return kind === 'member' ? this.data.members : kind === 'account' ? this.data.methods : this.data.subs
  }

  /** A tag of one kind exists when the registry holds it or a row wears it; a miss lists the kind's tags. */
  tag(kind: string, name: string): void {
    const key = nameKey(name)
    const registered = (this.data.tags ?? []).some((t) => t.kind === kind && t.name_key === key)
    if (registered || this.wearers(kind).some((r) => nameKey(r.tag ?? '') === key)) return
    const held = [...new Set([
      ...(this.data.tags ?? []).filter((t) => t.kind === kind).map((t) => t.name),
      ...this.wearers(kind).map((r) => r.tag ?? '').filter(Boolean),
    ])]
    const shown = held.length ? ` ${kind} tags: ${held.map((t) => `"${t}"`).join(', ')}.` : ` ${this.holder} holds no ${kind} tag.`
    this.miss('not_found', `No ${kind} tag in ${this.copy} is called "${name.trim()}".${shown}`, [])
  }

  /** Two tags of one kind sharing a name would be one tag the owner cannot tell apart. */
  tagTwin(kind: string, from: string, to: string): void {
    const fromKey = nameKey(from)
    const toKey = nameKey(to)
    if (toKey === fromKey) return
    const other = (this.data.tags ?? []).find((t) => t.kind === kind && t.name_key === toKey)
    if (other) this.miss('validation_failed', tagTwinRefusal(to), [])
  }

  linked(row: Account, wanted: string): void {
    const rows = this.data.methods
    const linked = this.named(rows, 'account', 'Accounts', wanted)
    if (linked.id === row.id) this.miss('validation_failed', `"${row.name}" can't be linked to itself.`, [candidate(row)])
    if (linked.parent_account_id) {
      this.miss('validation_failed', `"${linked.name}" (id ${linked.id}) is already linked to another account — one level only.`, [candidate(linked)])
    }
    if (rows.some((r) => r.parent_account_id === row.id)) {
      this.miss('validation_failed', `Other accounts are linked to "${row.name}", so it can't be linked to another.`, [candidate(row)])
    }
  }
}

/** The commitment a proposal addresses in the copy, matched as checkTargets matches it. */
export function addressedCommitment(payload: Record<string, unknown>, data: LoadedData): Commitment | undefined {
  return matchRow(data.subs, str(payload.id).trim() || undefined, str(payload.name).trim(), (s) => s.id, (s) => nameKey(s.name)).row
}

/** The names one of a report request's lists carries; absent is none. */
const namesIn = (value: unknown): string[] =>
  Array.isArray(value) ? value.filter((v): v is string => typeof v === 'string') : []

/**
 * Refuses now what the app would refuse at apply time: the addressed row exists once, a
 * rename or a new row collides with nothing, a linked account is one level, an owner and a
 * tag are held. A member or account name makes a placeholder, never a miss.
 */
export function checkTargets(proposal: Proposal, data: LoadedData, pushedAt: string | null = null, place?: TargetPlace): void {
  const check = new Checker(data, pushedAt, place)
  const body = proposal.payload
  const id = str(body.id).trim()
  const name = str(body.name).trim()
  const set = (typeof body.set === 'object' && body.set !== null ? body.set : {}) as Record<string, unknown>

  switch (proposal.kind) {
    case 'update_commitment': {
      const row = check.commitment(id, name)
      // One row cannot hold a recurring commitment's charges, as the app refuses at apply time.
      const held = (data.charges ?? []).filter((c) => c.commitment_id === row.id).length
      if (set.billing_cycle === 'once' && row.billing_cycle !== 'once' && held > 1) {
        check.miss('validation_failed', oneTimeRefusal(held), [commitmentCandidate(row)])
      }
      // Nor can one date stand for a one-time commitment's several charges.
      if ((set.billing_cycle ?? row.billing_cycle) === 'once' && typeof set.date === 'string' && set.date && held > 1) {
        check.miss('validation_failed', oneTimeMoveRefusal(held), [commitmentCandidate(row)])
      }
      // A member or account it names and the copy lacks becomes a placeholder at apply time, as on the local door.
      return
    }
    case 'mark_paid':
    case 'add_charges':
    case 'remove_charges':
      check.commitment(id, name)
      return
    case 'cancel_commitment': {
      const row = check.commitment(id, name)
      if (row.status === 'cancelled') {
        check.miss('validation_failed', `"${row.name}" (id ${row.id}) is already cancelled in ${check.copy}.`, [commitmentCandidate(row)])
      }
      return
    }
    case 'promote_to_recurring': {
      const rows = (body.ids as string[]).map((each) => check.commitment(each.trim(), ''))
      for (const row of rows) {
        if (row.billing_cycle !== 'once') {
          check.miss('validation_failed', `"${row.name}" (id ${row.id}) is ${row.billing_cycle}, not a one-time commitment; promote_to_recurring takes one-time commitments only.`, [commitmentCandidate(row)])
        }
      }
      const mixed = mixedDirections(rows)
      if (mixed) check.miss('validation_failed', mixed, rows.map(commitmentCandidate))
      return
    }
    case 'update_account': {
      const row = check.entity(data.methods, 'account', 'Accounts', id, name)
      if (typeof set.name === 'string') check.collision(data.methods, row, set.name, 'an account')
      const link = linkedTo(set as AccountSet)
      if (typeof link === 'string' && link.trim()) check.linked(row, link.trim())
      if (typeof set.member === 'string' && set.member.trim()) check.named(data.members, 'person', 'People', set.member.trim())
      return
    }
    case 'update_person': {
      const row = check.entity(data.members, 'person', 'People', id, name)
      if (typeof set.name === 'string') check.collision(data.members, row, set.name, 'a person')
      return
    }
    case 'update_charge': {
      const row = check.commitment(id, name)
      const date = str(body.date)
      const held = (data.charges ?? []).filter((c) => c.commitment_id === row.id)
      if (!held.some((c) => c.date === date)) {
        const days = held.map((c) => c.date).sort()
        const shown = days.length ? ` Its charges in ${check.copy}: ${days.join(', ')}.` : ` It holds no charge in ${check.copy}.`
        check.miss('not_found', `${noChargeRefusal(date, row.name)}${shown}`, [commitmentCandidate(row)])
      }
      // A move alone lands on a free day; with the rows after it the app judges each landing.
      const to = typeof set.date === 'string' ? set.date : ''
      if (to && to !== date && set.and_later !== true && held.some((c) => c.date === to)) {
        check.miss('validation_failed', dayTakenRefusal(to), [commitmentCandidate(row)])
      }
      return
    }
    case 'set_planned_count': {
      const row = check.commitment(id, name)
      if (row.billing_cycle === 'once') check.miss('validation_failed', NOTHING_TO_PLAN, [commitmentCandidate(row)])
      // A plan under a paused or cancelled commitment is one the app's own form never writes.
      const status = displayStatus(row)
      if (status !== 'active') check.miss('validation_failed', notActiveRefusal(row.name, status), [commitmentCandidate(row)])
      return
    }
    case 'delete_commitment':
      check.commitment(id, '')
      return
    case 'add_person':
      check.twin(data.members, name, 'a person', 'update_person')
      return
    case 'add_account': {
      check.twin(data.methods, name, 'an account', 'update_account')
      const link = linkedTo(body as AccountSet)
      if (typeof link === 'string' && link.trim()) {
        const linked = check.named(data.methods, 'account', 'Accounts', link.trim())
        if (linked.parent_account_id) {
          check.miss('validation_failed', `"${linked.name}" (id ${linked.id}) is already linked to another account — one level only.`, [candidate(linked)])
        }
      }
      if (typeof body.member === 'string' && body.member.trim()) check.named(data.members, 'person', 'People', body.member.trim())
      return
    }
    case 'rename_tag': {
      const kind = str(body.kind)
      check.tag(kind, str(body.from))
      check.tagTwin(kind, str(body.from), str(body.to))
      return
    }
    case 'delete_tag':
      check.tag(str(body.kind), name)
      return
    case 'create_report':
      // Here no placeholder: a report narrows to rows that exist, and a name nobody wears
      // would draw an empty report.
      for (const wanted of namesIn(body.accounts)) {
        if (wanted !== NO_ACCOUNT) check.named(data.methods, 'account', 'Accounts', wanted)
      }
      for (const wanted of namesIn(body.members)) check.named(data.members, 'person', 'People', wanted)
      for (const wanted of namesIn(body.categories)) {
        if (wanted !== NO_CATEGORY) check.tag('commitment', wanted)
      }
      return
    default:
      return
  }
}
