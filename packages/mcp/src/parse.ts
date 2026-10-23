// Parsing and validation for one financial memory, filesystem-free on purpose: the
// stdio server reads a folder, the hosted server reads a row, both land here. Format 3
// only — any other version is refused by name rather than read with the wrong shape.
import type { LoadedData, Commitment, Member, Account, ChargeRow, Details, Tag } from '@longbook/core'
import { nameKey, storedDirection } from '@longbook/core'

export class VaultReadError extends Error {}

/** The format this server reads and writes. */
export const VAULT_FORMAT_VERSION = 3

type RawVault = {
  app?: unknown
  version?: unknown
  commitments?: unknown
  members?: unknown
  accounts?: unknown
  charges?: unknown
  tags?: unknown
}

const str = (v: unknown, fallback = ''): string => (typeof v === 'string' ? v : fallback)
const orNull = (v: unknown): string | null => (typeof v === 'string' && v !== '' ? v : null)
const details = (v: unknown): Details | undefined =>
  typeof v === 'object' && v !== null && !Array.isArray(v) ? (v as Details) : undefined

const CYCLES = ['monthly', 'yearly', 'custom', 'once']
const STATUSES = ['active', 'paused', 'cancelled']
const DAY = /^\d{4}-\d{2}-\d{2}$/

/**
 * A value core's arithmetic would silently turn into wrong charges refuses here
 * instead, naming the row — the same stance the app takes on its own saves.
 */
function refuse(row: Record<string, unknown>, field: string): never {
  const who = str(row.name) || str(row.id) || 'a commitment'
  throw new VaultReadError(
    `"${who}" has an unreadable ${field} in financial_memory.json. Fix it there or in the app, then ask again.`,
  )
}

/**
 * The schema requires only what identity needs; the rest defaults here so core's
 * arithmetic always sees the full shape it types.
 */
function normalizeSub(raw: Record<string, unknown>): Commitment {
  if (typeof raw.amount !== 'number' || !Number.isFinite(raw.amount)) refuse(raw, 'amount')
  if (!CYCLES.includes(raw.billing_cycle as string)) refuse(raw, 'billing_cycle')
  if (!STATUSES.includes(raw.status as string)) refuse(raw, 'status')
  if (orNull(raw.ends_on) !== null && !DAY.test(raw.ends_on as string)) refuse(raw, 'ends_on')
  return {
    ...raw,
    id: str(raw.id),
    name: str(raw.name),
    amount: raw.amount,
    currency: str(raw.currency),
    billing_cycle: raw.billing_cycle as Commitment['billing_cycle'],
    custom_cycle_days: typeof raw.custom_cycle_days === 'number' ? raw.custom_cycle_days : null,
    tag: orNull(raw.tag),
    details: details(raw.details),
    status: raw.status as Commitment['status'],
    account_id: orNull(raw.account_id),
    member_id: orNull(raw.member_id),
    notes: orNull(raw.notes),
    ends_on: orNull(raw.ends_on),
    // As the file stores it: "out" is absence, and a word this version does not know is
    // kept, read as a charge, so both doors see the row the app will.
    direction: storedDirection(raw.direction),
    // Only a true is a trial; anything else the file holds reads as none.
    free_trial: raw.free_trial === true ? true : null,
    created_at: str(raw.created_at),
    updated_at: str(raw.updated_at),
  }
}

function normalizeMember(raw: Record<string, unknown>): Member {
  return {
    ...raw,
    id: str(raw.id),
    name: str(raw.name),
    name_key: str(raw.name_key),
    tag: orNull(raw.tag),
    details: details(raw.details),
    avatar_seed: str(raw.avatar_seed),
    is_incomplete: raw.is_incomplete === true,
    email: orNull(raw.email),
    created_at: str(raw.created_at),
  }
}

function normalizeMethod(raw: Record<string, unknown>): Account {
  return {
    ...raw,
    id: str(raw.id),
    name: str(raw.name),
    name_key: str(raw.name_key),
    nickname: orNull(raw.nickname),
    institution: orNull(raw.institution),
    last4: orNull(raw.last4),
    tag: orNull(raw.tag),
    details: details(raw.details),
    member_id: orNull(raw.member_id),
    parent_account_id: orNull(raw.parent_account_id),
    notes: orNull(raw.notes),
    balance: typeof raw.balance === 'number' && Number.isFinite(raw.balance) ? raw.balance : null,
    balance_date: orNull(raw.balance_date),
    is_incomplete: raw.is_incomplete === true,
    created_at: str(raw.created_at),
  }
}

function normalizeTag(raw: Record<string, unknown>): Tag {
  // A template reads as none on every kind of tag; the file keeps whatever it holds.
  const rest: Record<string, unknown> = { ...raw }
  delete rest.template
  return {
    ...rest,
    id: str(raw.id),
    kind: (raw.kind as Tag['kind']) ?? 'commitment',
    name: str(raw.name),
    name_key: str(raw.name_key) || nameKey(str(raw.name)),
    icon: orNull(raw.icon),
    is_default: raw.is_default === true,
    sort: typeof raw.sort === 'number' ? raw.sort : 0,
    created_at: str(raw.created_at),
  }
}

// Element-lossy, matching the Swift reader: one malformed row drops alone and the charges
// around it survive — never a parse that refuses the whole vault for one bad line.
function normalizeCharge(raw: Record<string, unknown>): ChargeRow | null {
  const commitment_id = str(raw.commitment_id)
  const date = str(raw.date)
  if (!commitment_id || !DAY.test(date)) return null
  if (typeof raw.amount !== 'number' || !Number.isFinite(raw.amount)) return null
  return {
    commitment_id,
    date,
    amount: raw.amount,
    currency: orNull(raw.currency),
    paid: raw.paid === true,
    paid_on: orNull(raw.paid_on),
    basis: orNull(raw.basis),
    note: orNull(raw.note),
    written_at: orNull(raw.written_at),
  }
}

const rows = (v: unknown): Record<string, unknown>[] =>
  Array.isArray(v) ? v.filter((x): x is Record<string, unknown> => typeof x === 'object' && x !== null) : []

/** Parses one vault file's bytes. Split from any storage so every server shares it. */
export function parseVault(text: string): LoadedData {
  let parsed: Record<string, unknown>
  try {
    parsed = JSON.parse(text) as Record<string, unknown>
  } catch {
    throw new VaultReadError("That file is not valid JSON. It may be mid-save, so try again in a moment.")
  }
  if (parsed['app'] !== 'longbook') {
    throw new VaultReadError("That file is not a longbook financial memory.")
  }
  if (parsed['version'] !== VAULT_FORMAT_VERSION) {
    throw new VaultReadError(
      `That financial memory is format ${String(parsed['version'])}; this server reads format ${VAULT_FORMAT_VERSION}.`,
    )
  }
  const raw = parsed as RawVault
  return {
    subs: rows(raw.commitments).map(normalizeSub),
    members: rows(raw.members).map(normalizeMember),
    methods: rows(raw.accounts).map(normalizeMethod),
    undo: null,
    charges: rows(raw.charges).map(normalizeCharge).filter((c): c is ChargeRow => c !== null),
    tags: rows(raw.tags).map(normalizeTag),
    toFillIn: rows(parsed['to_fill_in'])
      .filter((r) => typeof r['id'] === 'string' && typeof r['name'] === 'string' && (r['name'] as string).trim() !== '')
      .map((r) => ({
        id: r['id'] as string,
        name: r['name'] as string,
        ...(typeof r['group'] === 'string' ? { group: r['group'] } : {}),
        ...(typeof r['tag'] === 'string' ? { tag: r['tag'] } : {}),
      })),
  }
}
