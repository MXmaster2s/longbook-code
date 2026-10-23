// Hand-owned domain types — the shapes stored in the vault file. Authored directly, not
// generated: the vault's on-disk contract is the source of truth (see docs/vault-format.md),
// not a database schema. A field added here is a contract-revision bump, not a migration.

export type BillingCycle = 'monthly' | 'yearly' | 'custom' | 'once'
export type SubStatus = 'active' | 'paused' | 'cancelled'

/** A details value: scalar or a flat list of scalars — never nested objects. */
export type DetailValue = string | number | boolean | null | Array<string | number>

/** Structured extras, longbook's own on every row: a commitment's statement line, and whatever
 * else a vault holds there, read as stored. No write tool takes them. Scanned by
 * domain/dataPolicy.ts before every write — never a place for secrets. */
export type Details = Record<string, DetailValue>

/**
 * A commitment's attributes — what every charge of it shares. Nothing about an occurrence
 * lives here: dates, amounts and whether it was paid are rows in `charges[]`. `amount` is the
 * price now, what a newly planned charge is written at.
 */
export interface Commitment {
  id: string
  name: string
  amount: number
  currency: string
  /** Recurring — monthly, yearly, custom every N days — or once. Shown as Commitment Type. */
  billing_cycle: BillingCycle
  custom_cycle_days: number | null
  /** A name from tags[] (kind "commitment"), or a new one. One tag per row. */
  tag: string | null
  details?: Details
  status: SubStatus
  account_id: string | null
  member_id: string | null
  /** Free text. Scanned by domain/dataPolicy.ts before every write — never a place for secrets. */
  notes: string | null
  /** ISO date the commitment stops. Nothing is planned past it. */
  ends_on: string | null
  /**
   * "in" for money that arrives, "transfer" for a movement between the owner's own accounts
   * they still want to see; absent or "out" is a charge. Only a charge counts as spending.
   * A word a newer contract names is kept as written, and read as a charge until then.
   */
  direction?: 'in' | 'out' | 'transfer' | (string & {}) | null
  /** True while the owner marks it a free trial — a pill, never a charge row. Absent or null otherwise. */
  free_trial?: boolean | null
  created_at: string
  updated_at: string
}

/** What backs a charge row. Anything but "plan" is a fact, and nothing reprices a fact. */
export type ChargeBasis = 'statement' | 'user' | 'mark_paid' | 'plan' | 'email'

/**
 * One charge — a stored occurrence, past or planned. Keyed by (commitment_id, date); one row
 * per commitment per due date. What is not a row did not happen and is not planned.
 */
export interface ChargeRow {
  /** FK → commitments[].id */
  commitment_id: string
  /** The due date, ISO YYYY-MM-DD — with commitment_id, the identity. */
  date: string
  amount: number
  /** Only when it differs from the commitment's own currency. */
  currency?: string | null
  paid: boolean
  /** ISO date the money actually moved, when that differs from `date`. */
  paid_on?: string | null
  basis?: ChargeBasis | string | null
  note?: string | null
  /** ISO timestamp of when the row was written. Bookkeeping, never a change signal. */
  written_at?: string | null
}

export type CommitmentInsert = Omit<Commitment, 'id' | 'created_at' | 'updated_at'> &
  Partial<Pick<Commitment, 'id' | 'created_at' | 'updated_at'>>
export type CommitmentUpdate = Partial<Commitment>

export interface Member {
  id: string
  name: string
  name_key: string
  /** A name from tags[] (kind "member"), or a new one. */
  tag: string | null
  details?: Details
  avatar_seed: string
  is_incomplete: boolean
  /** Where a shared report reaches them; never required. */
  email: string | null
  created_at: string
}

/**
 * An account the vault remembers — identification only, per the data-minimization
 * policy: name (e.g. "Visa 9292"), institution, last 4 digits, a nickname. Deliberately
 * no field for a full number, CVV, expiry, or PIN — what has no field cannot be stored
 * correctly. See domain/dataPolicy.ts.
 */
export interface Account {
  id: string
  name: string
  name_key: string
  nickname: string | null
  institution: string | null
  last4: string | null
  /** A name from tags[] (kind "account"), or a new one. */
  tag: string | null
  details?: Details
  member_id: string | null
  /** The linked account — a card to the bank account that pays it. One level only. */
  parent_account_id: string | null
  /** Free text about the account. Scanned like every note — never a number or a credential. */
  notes?: string | null
  /** What the account held on balance_date, as last said; informational. */
  balance?: number | null
  balance_date?: string | null
  is_incomplete: boolean
  created_at: string
}

/** A merge's pre-merge snapshot, kept for one-shot undo. A store-layer shape only — since
 * format v2 it is never written into the vault file. */
export interface MergeUndoRow {
  owner_id: string
  entity_type: string
  snapshot: unknown
  created_at: string
}

/** What kind of thing a tag describes — one vocabulary per list. */
export type TagKind = 'commitment' | 'member' | 'account'

/**
 * The vault's tag vocabulary: seeded from the library, extended by the owner and their AI.
 * Rows wear a tag by NAME (readable in place); the registry carries its icon. A template a
 * vault still holds on any tag is read as none.
 */
export interface Tag {
  id: string
  kind: TagKind
  name: string
  name_key: string
  icon: string | null
  is_default: boolean
  sort: number
  created_at: string
}

/** Fields every group carries, whatever it happens to hold. */
type GroupCommon = {
  /** UUID. Stable across renames — the name is the part that moves, so nothing keys on the name. */
  id: string
  /** As the owner typed it, inline in the sidebar. Never transformed on the way in or out. */
  name: string
  /** Normalised name (trimmed + lowercased) — the same de-duplication convention members and
   * accounts already use. Deduped per kind: "household" may exist under both sections. */
  name_key: string
  /** An SF Symbol name; optional. */
  icon?: string | null
  /** Seeded by the app on a vault's first open. Still entirely the owner's — renameable and
   * deletable like any other. The flag records where a group came from, never what may be done
   * to it. */
  is_default: boolean
  /** Display order within its kind. */
  sort: number
  created_at: string
}

/**
 * A group of accounts — the sidebar's "payments" section: "credit cards", "my amex stuff".
 *
 * Note what is absent: there is no field here to put a person in.
 */
export type AccountGroup = GroupCommon & {
  kind: 'account'
  /** FK → accounts[].id */
  account_ids: string[]
}

/** A group of people — the sidebar's "members" section: "household", "teams". */
export type MemberGroup = GroupCommon & {
  kind: 'member'
  /** FK → members[].id */
  member_ids: string[]
}

/**
 * A group over tags — "business", "household". Tags are worn by name, so this holds
 * their normalised names.
 */
export type TagGroup = GroupCommon & {
  kind: 'tag'
  /** Normalised tag names (trimmed + lowercased). A tag belongs to at most one group. */
  tag_keys: string[]
}

/**
 * A label the owner arranges their vault with — data in the vault file, not app chrome.
 * Membership lives on the group, not the entity, so no reader needs a contract change.
 * `kind` is a discriminator, not a hint — a future kind carries its own field.
 */
export type Group = AccountGroup | MemberGroup | TagGroup

/** What a group holds. New kinds join by extending the union above; nothing here is open-ended,
 * because the owner names groups and we name kinds. */
export type GroupKind = Group['kind']

/** Which free-text entity a value refers to. */
export type EntityKind = 'member' | 'account'

/** Currencies offered in the picker. INR/USD/EUR are surfaced as quick buttons in the UI. */
export const CURRENCIES = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD', 'AUD', 'CAD', 'JPY'] as const
export type CurrencyCode = (typeof CURRENCIES)[number]

/** The three shown as one-tap buttons; the rest live behind a picker. */
export const QUICK_CURRENCIES: CurrencyCode[] = ['INR', 'USD', 'EUR']

export const CURRENCY_SYMBOL: Record<string, string> = {
  INR: '₹', USD: '$', EUR: '€', GBP: '£', AED: 'AED',
  SGD: 'S$', AUD: 'A$', CAD: 'C$', JPY: '¥',
}

/** A commitment named at setup and not yet filled in: the vault's `to_fill_in[]`. */
export interface Placeholder {
  id: string
  name: string
  group?: string
  tag?: string
}
