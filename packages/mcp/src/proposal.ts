// A proposal is the shape a write takes on either door: tool name, payload, idempotency
// key, source. Validated here with no filesystem in sight, so both servers hold a payload
// to one contract — local then writes the file, hosted files the proposal.
import { daysBetween, fmtDate, nameKey, parseDate, scanFields, scanText, scannableWords, policyFix, storedDirection, toISO, todayMid, CUSTOM_DAYS_LIMIT, DATA_POLICY_REFUSAL } from '@longbook/core'
import { VaultWriteError } from './errors.js'

export const PROPOSAL_KINDS = [
  'add_commitments',
  'update_commitment',
  'mark_paid',
  'add_charges',
  'remove_charges',
  'cancel_commitment',
  'promote_to_recurring',
  'leave_insight',
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
] as const
export type ProposalKind = (typeof PROPOSAL_KINDS)[number]

/** The names these tools wore before contract revision 41. A door still answers to them. */
export const LEGACY_TOOL_NAMES: Record<string, string> = {
  update_member: 'update_person',
  add_member: 'add_person',
  members: 'people',
  spending_by_member: 'spending_by_person',
}
export const canonicalToolName = (name: string): string => LEGACY_TOOL_NAMES[name] ?? name

export interface Proposal {
  kind: ProposalKind
  payload: Record<string, unknown>
  idempotency_key?: string
  source_ref?: string
}

/** 256 KB: a 200-row batch with notes is well under it; a pasted statement is not. */
export const MAX_PAYLOAD_BYTES = 256 * 1024

/** The largest amount either door writes, as the app's own validator holds it. */
export const AMOUNT_LIMIT = 1e15
/** Refusing an amount past it, worded once for both doors and the app alike. */
export const AMOUNT_LIMIT_PROBLEM = "the amount can't be more than 1,000,000,000,000,000"

/** The same refusal as a sentence of its own, as the app's validator says it. */
export const AMOUNT_LIMIT_REFUSAL = "The amount can't be more than 1,000,000,000,000,000."

/** An amount's bounds in words, for a listing whose schema states them without enforcing them first. */
export const AMOUNT_DESCRIPTION = 'A number, zero or more, up to 1,000,000,000,000,000.'

/** Refusing a custom cycle's days outside 1 to 36,500, worded once for both doors. */
export const CUSTOM_DAYS_PROBLEM = 'custom_cycle_days is a whole number of days, 1 to 36,500'

/** A custom cycle's bounds in words, for a listing whose schema states them without enforcing them first. */
export const CUSTOM_DAYS_DESCRIPTION = 'The days between charges of a custom cycle: a whole number, 1 to 36,500.'

/** Days a custom cycle may hold between charges, as the app's own validator takes them. */
const isCycleDays = (days: unknown): boolean =>
  typeof days === 'number' && Number.isInteger(days) && days >= 1 && days <= CUSTOM_DAYS_LIMIT

/** Why a recurring commitment holding several charges cannot become a one-time one, in the app's words. */
export const oneTimeRefusal = (charges: number): string =>
  `One-time holds a single charge, and this has ${charges}. Cancel it instead to stop its plan.`

/** Why a one-time commitment holding several charges takes no date, in the app's words. */
export const oneTimeMoveRefusal = (charges: number): string =>
  `This one-time commitment has ${charges} charges. Move the one you mean from the charge itself.`

/** The most charges one plan is set to, as the app's PlannedCount.ceiling caps it. */
export const PLANNED_COUNT_CEILING = 240

/** Why a one-time commitment takes no plan, in the app's words. */
export const NOTHING_TO_PLAN = 'A one-time commitment has its one charge; there is nothing to plan.'

/** A plan asked of a paused or cancelled commitment, in one sentence on every door and in the app. */
export const notActiveRefusal = (name: string, status: string): string =>
  `"${name}" is ${status}; set its status to active first, then plan.`

/** A name a write needs and did not get, in the app's words. */
export const EMPTY_NAME_REFUSAL = "Give it a name. That's what you'll recognise it by."

/** A day as the app says it in a refusal, in the reader's own locale. */
const dayWord = (iso: string): string => (isRealDay(iso) ? fmtDate(parseDate(iso)) : iso)

/** A move onto a day that already holds a charge, in the app's words. */
export const dayTakenRefusal = (day: string): string => `A charge already sits on ${dayWord(day)}. Move or remove it first.`

/** A move with the rows after it that would land past the cancelling date, in the app's words. */
export const pastCancellingRefusal = (end: string): string =>
  `That day is past the cancelling date, ${dayWord(end)}. Move the cancelling date first, or move this charge on its own.`

/** A charge update_charge names that the commitment does not hold. */
export const noChargeRefusal = (day: string, name: string): string => `No charge on ${day} is written for "${name}".`

/** A second tag of one kind wearing a name, in the app's words. */
export const tagTwinRefusal = (name: string): string => `There's already one called "${name.trim()}".`

/** A second person or account wearing a name, in the app's words. */
export const entityTwinRefusal = (article: string, name: string): string => `There's already ${article} called ${name.trim()}.`

/** The lists a tag kind names. */
export const TAG_KINDS = ['commitment', 'member', 'account'] as const

export interface CommitmentRowInput {
  name: string
  amount: number
  currency: string
  billing_cycle: 'monthly' | 'yearly' | 'custom' | 'once'
  custom_cycle_days?: number
  /** Where the plan starts, or a one-time commitment's own day. `date` is accepted as its alias. */
  first_charge?: string
  date?: string
  /** How many months of charges to write for a recurring commitment. Default 24. */
  plan_months?: number
  /** How many charges to write, counted from the first; when given, plan_months is not read. */
  plan_count?: number
  ends_on?: string
  status?: 'active' | 'paused' | 'cancelled'
  /** A one-time row from a statement arrives paid, with what backs it. */
  paid?: boolean
  paid_on?: string
  basis?: 'statement' | 'user' | 'email' | 'plan'
  note?: string
  tag?: string
  /** The three details that matter, one per line. A commitment's details are longbook's own. */
  notes?: string
  member?: string
  account?: string
  /** "in" for money that arrives, "transfer" for a movement between own accounts; absent is a charge. */
  direction?: 'in' | 'out' | 'transfer'
  /** longbook's own on a commitment. A row sending any is refused. */
  details?: unknown
}

export interface ChargeInput {
  date: string
  amount?: number
  paid?: boolean
  /** Null clears. */
  paid_on?: string | null
  basis?: 'statement' | 'user' | 'email' | 'plan' | 'mark_paid'
  /** Null clears. */
  note?: string | null
  currency?: string
}

/** What update_charge changes on one row: undefined leaves a field alone; null clears a clearable one. */
export interface ChargeSet {
  /** The day to move it to. */
  date?: string
  amount?: number
  paid?: boolean
  paid_on?: string | null
  note?: string | null
  /** Reach the unpaid planned rows after it: they follow a move a cycle apart, and take a new amount. */
  and_later?: boolean
}

/** A new person, with what is known. */
export interface NewMember {
  name: string
  tag?: string
  email?: string
  /** longbook's own on a person. A write sending a non-empty one is refused. */
  card_name?: unknown
  details?: unknown
}

/** A new account, with what is known. */
export interface NewAccount {
  name: string
  tag?: string
  linked_to?: string
  /** Older names for linked_to, taken as update_account takes them; linked_to wins. */
  parent?: string
  parent_account?: string
  member?: string
  notes?: string
  balance?: number
  balance_date?: string
  /** longbook's own on an account. A write sending a non-empty one is refused. */
  card_name?: unknown
  details?: unknown
}

/** Account fields: undefined leaves one alone; null clears it. */
export interface AccountSet {
  name?: string
  /** The account type — a tag of kind "account". Null or "" clears. */
  tag?: string | null
  /** Null clears the balance and its day together. */
  balance?: number | null
  /** The day the balance was true. Left out with a balance, today is written. */
  balance_date?: string | null
  /** The linked account by name or id — a card to the bank that pays it. One level; null clears. */
  linked_to?: string | null
  /** Older names for linked_to, still accepted; linked_to wins when both are given. */
  parent?: string | null
  parent_account?: string | null
  /** What is particular about the account, one detail per line — "Card name: Platinum Reserve". Null or "" clears. */
  notes?: string | null
  /** The person the account belongs to, by name or id. Null or "" clears. */
  member?: string | null
  /** longbook's own on an account: a set sending a non-empty one is refused, an empty one ignored. */
  card_name?: unknown
  details?: unknown
}

export interface MemberSet {
  name?: string
  /** Null or "" clears. */
  email?: string | null
  /** Their role in the owner's finances — a member tag, the library's first. Null or "" clears. */
  tag?: string | null
  /** longbook's own on a person: a set sending a non-empty one is refused, an empty one ignored. */
  card_name?: unknown
  details?: unknown
}

/** The linked account a set names, under whichever of its three names; undefined when none. */
export function linkedTo(set: Pick<AccountSet, 'linked_to' | 'parent' | 'parent_account'>): string | null | undefined {
  if (set.linked_to !== undefined) return set.linked_to
  if (set.parent !== undefined) return set.parent
  return set.parent_account
}

const REVIEW =
  `Writes are schema-validated and provenance-stamped, and land in the app's Changes screen ` +
  `where the owner keeps or undoes the whole batch. Card numbers, CVVs and credentials are ` +
  `refused by the validator, which names the row. \`source\` ("documents/hdfc-2026.pdf", ` +
  `"gmail:18c2…") records where a row came from in the diff.`

const HOSTED_NOTE =
  ` On the hosted server a write files a proposal, applied when the owner next opens longbook ` +
  `on any device; \`idempotency_key\` makes a retried call add nothing twice.`

/** How every row-addressing write names its row, worded once. */
const BY_NAME = 'by id or the exact name as the memory holds it — a miss answers with the real names'

// ---------------------------------------------------------------------------------------------
// JSON Schemas — the hosted tools/list speaks these; the stdio server pairs them with zod.

const DAY_SCHEMA = { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$' }
const SOURCE_SCHEMA = {
  type: 'string',
  minLength: 1,
  maxLength: 200,
  description: 'Where the data came from — a document path or a mail id — kept in _provenance.source.',
}
const IDEMPOTENCY_SCHEMA = {
  type: 'string',
  minLength: 1,
  maxLength: 200,
  description: 'Hosted only: a key unique per intended write, e.g. "brief:2026-08-21:<mail id>". A repeat answers already_exists.',
}

const BASIS_SCHEMA = { type: 'string', enum: ['statement', 'user', 'email', 'plan'] }
/** What a commitment's `notes` holds, worded once for both doors. */
export const NOTES_DESCRIPTION =
  'The three details that matter most, one per line, each "Label: value" — for insurance "Policy number: …", ' +
  '"Policy name: …", "Document: documents/…". Only what the source states; read_guide "notes" lists the three ' +
  'by category. Card numbers, whole account numbers and credentials are refused.'
/** What an account's `notes` holds, worded once for both doors. */
export const ACCOUNT_NOTES_DESCRIPTION =
  'What is particular about the account, one detail per line, each "Label: value" — on a card, "Card name: ' +
  'Platinum Reserve", the product printed on it; its number is refused. Rewritten as the account now stands. Null or "" clears.'
/** What `direction` means, worded once for both doors. */
export const DIRECTION_DESCRIPTION =
  '"in" for money that arrives — salary, a refund, interest. "transfer" for a movement between the owner\'s own ' +
  'accounts they want to see — a card bill due, a standing move to savings. Neither is ever summed with spending.'
/** What `free_trial` means, worded once for both doors. */
export const FREE_TRIAL_DESCRIPTION =
  'True while the owner marks it a free trial: longbook shows a Free trial pill, and no charge row changes. False takes the mark off.'

const ROW_SCHEMA = {
  type: 'object',
  required: ['name', 'amount', 'currency', 'billing_cycle'],
  properties: {
    name: { type: 'string', minLength: 1, description: 'The name as the owner would say it, such as "Netflix" or "Car EMI"; a detail worth keeping lives in notes.' },
    amount: { type: 'number', minimum: 0, maximum: AMOUNT_LIMIT },
    currency: { type: 'string', minLength: 3, maxLength: 3 },
    billing_cycle: { type: 'string', enum: ['monthly', 'yearly', 'custom', 'once'] },
    custom_cycle_days: { type: 'integer', minimum: 1, maximum: CUSTOM_DAYS_LIMIT },
    first_charge: { ...DAY_SCHEMA, description: 'The first charge, YYYY-MM-DD — where a recurring plan starts. Required unless `date` is given.' },
    date: { ...DAY_SCHEMA, description: 'A one-time commitment\'s own day; an alias of first_charge.' },
    plan_months: { type: 'integer', minimum: 1, maximum: 600, description: 'Months of charges to write for a recurring commitment. Default 24; write as many as the owner asked for.' },
    plan_count: { type: 'integer', minimum: 1, maximum: PLANNED_COUNT_CEILING, description: 'How many charges to write for a recurring commitment, counted from first_charge — the form\'s own count, 240 at most. When given, plan_months is not read.' },
    ends_on: DAY_SCHEMA,
    status: { type: 'string', enum: ['active', 'paused', 'cancelled'] },
    paid: { type: 'boolean', description: 'For a one-time row: whether the money left. A statement line is paid.' },
    paid_on: DAY_SCHEMA,
    basis: { ...BASIS_SCHEMA, description: 'What backs a one-time row — "statement" for a line read from one.' },
    note: { type: 'string', maxLength: 300 },
    tag: { type: 'string', description: 'The category, from `tags` — what kind of thing this is. It carries no template; the row\'s own details go in notes.' },
    notes: { type: 'string', description: NOTES_DESCRIPTION },
    member: { type: 'string', description: 'A member by name; a new name becomes a placeholder.' },
    account: { type: 'string', description: 'An account by name; a new name becomes a placeholder.' },
    direction: { type: 'string', enum: ['in', 'out', 'transfer'], description: DIRECTION_DESCRIPTION },
  },
}

const SET_SCHEMA = {
  type: 'object',
  minProperties: 1,
  properties: {
    name: { type: 'string', minLength: 1 },
    amount: { type: 'number', minimum: 0, maximum: AMOUNT_LIMIT, description: 'The price now. Reaches only unpaid planned charges from `from` (default today); nothing before today changes.' },
    from: { ...DAY_SCHEMA, description: 'The day an amount change applies from. Default today.' },
    date: { ...DAY_SCHEMA, description: 'For a one-time commitment: moves its single charge to this day.' },
    currency: { type: 'string', minLength: 3, maxLength: 3 },
    billing_cycle: { type: 'string', enum: ['monthly', 'yearly', 'custom', 'once'] },
    custom_cycle_days: { type: ['integer', 'null'], minimum: 1, maximum: CUSTOM_DAYS_LIMIT },
    ends_on: { ...DAY_SCHEMA, type: ['string', 'null'] },
    status: { type: 'string', enum: ['active', 'paused', 'cancelled'] },
    direction: { type: ['string', 'null'], enum: ['in', 'out', 'transfer', null], description: `${DIRECTION_DESCRIPTION} Null, like "out", makes it a charge.` },
    tag: { type: ['string', 'null'] },
    notes: { type: ['string', 'null'], description: `${NOTES_DESCRIPTION} Rewritten as the commitment now stands, never appended to.` },
    member: { type: ['string', 'null'] },
    account: { type: ['string', 'null'] },
    free_trial: { type: 'boolean', description: FREE_TRIAL_DESCRIPTION },
  },
}

/** The fields update_commitment's set takes. A set naming none of them changes nothing. */
export const COMMITMENT_SET_FIELDS = [
  'name', 'amount', 'from', 'date', 'currency', 'billing_cycle', 'custom_cycle_days',
  'ends_on', 'status', 'direction', 'tag', 'notes', 'member', 'account', 'free_trial',
] as const

/** The key meant, for a key update_commitment's set does not take. */
const SET_HINTS = new Map<string, string>([
  ['cancelling_on', 'the cancelling date is ends_on'],
  ['cancel_on', 'the cancelling date is ends_on'],
  ['cancellation_date', 'the cancelling date is ends_on'],
  ['end_date', 'the cancelling date is ends_on'],
  ['category', 'the category is tag'],
  ['price', 'the price is amount'],
  ['cycle', 'the cycle is billing_cycle'],
  ['frequency', 'the cycle is billing_cycle'],
  ['note', "the commitment's details are notes"],
  ['member_id', 'the person is member, by name'],
  ['account_id', 'the account is account, by name'],
  ['paid', 'a charge is marked paid with mark_paid'],
  ['details', "a commitment's details are lines of its notes"],
  ['trial', 'the free trial mark is free_trial'],
  ['plan_months', 'the plan is set with set_planned_count'],
  ['plan_count', 'the plan is set with set_planned_count'],
])

const DATE_HINT = "only a one-time commitment's charge moves by date"
const NO_CHARGE_HINT = 'the commitment holds no charge to move; add_charges writes one'
const DAYS_HINT = 'custom_cycle_days goes with billing_cycle custom'

/** Why a key the tool takes writes nothing here, or undefined when it is written. */
function unwritten(key: string, value: unknown, cycle: unknown, held: number): string | undefined {
  if (key === 'date') return cycle !== 'once' ? DATE_HINT : held === 0 ? NO_CHARGE_HINT : undefined
  if (key === 'custom_cycle_days' && value !== null && cycle !== 'custom') return DAYS_HINT
  return undefined
}

/**
 * What a set writes, given the cycle after it and the charges held: each key the tool takes,
 * but a date moving no charge and days off a custom cycle. The rest are ignored, named with the
 * key meant where one exists; the write lands. Both doors answer with it.
 */
export function setOutcome(set: Record<string, unknown>, cycle: unknown, held: number): { fields: string[]; ignored: string[] } {
  const fields: string[] = []
  const ignored: string[] = []
  for (const [key, value] of Object.entries(set)) {
    if (value === undefined) continue
    const taken = (COMMITMENT_SET_FIELDS as readonly string[]).includes(key)
    const hint = taken ? unwritten(key, value, cycle, held) : SET_HINTS.get(key)
    if (taken && hint === undefined) {
      fields.push(key)
      continue
    }
    ignored.push(hint ? `${key} — ${hint}` : key)
  }
  return { fields, ignored }
}

const ACCOUNT_SET_SCHEMA = {
  type: 'object',
  minProperties: 1,
  properties: {
    name: { type: 'string', minLength: 1, description: 'A new name. Refused when another account already wears it.' },
    tag: { type: ['string', 'null'], description: 'The account type, in the app\'s own words — "credit card", "bank account", "UPI", "wallet", "cash". Null clears.' },
    balance: { type: ['number', 'null'], description: 'What the account held on balance_date. Null clears the balance and its day together.' },
    balance_date: { ...DAY_SCHEMA, type: ['string', 'null'], description: 'The day the balance was true. Left out beside a balance, the day of the write is used; alone, it moves the day of a balance already held.' },
    linked_to: { type: ['string', 'null'], description: 'The account this one is linked to — a card to the bank account that pays it — by name or id. One level only. Null clears.' },
    parent: { type: ['string', 'null'], description: 'An older name for linked_to, still accepted.' },
    parent_account: { type: ['string', 'null'], description: 'An older name for linked_to, still accepted.' },
    notes: { type: ['string', 'null'], description: ACCOUNT_NOTES_DESCRIPTION },
    member: { type: ['string', 'null'], description: 'The person the account belongs to, by name or id as the memory holds them. Null or "" clears.' },
  },
}

const MEMBER_SET_SCHEMA = {
  type: 'object',
  minProperties: 1,
  properties: {
    name: { type: 'string', minLength: 1, description: 'A new name. Refused when another person already wears it.' },
    email: { type: ['string', 'null'], description: 'Where a shared report reaches them. Null or "" clears.' },
    tag: { type: ['string', 'null'], description: 'Their role in the owner\'s finances — a member tag from `tags`: family, household help, landlord. Null or "" clears.' },
  },
}

const WRITER = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false }

export interface WriteToolSpec {
  name: ProposalKind
  title: string
  description: string
  annotations: Record<string, boolean>
  inputSchema: Record<string, unknown>
}

export const ADD_COMMITMENTS_SPEC = {
  title: 'Add commitments',
  description:
    `Adds up to 200 commitments in one call, as one reviewable batch. A recurring row is ` +
    `planned from first_charge for plan_months (24 by default); a one-time row is its single ` +
    `charge on \`date\`. A statement line that is a charge is a one-time row at its real date ` +
    `and amount with paid: true and basis "statement". Money in — salary, a refund, interest, ` +
    `cashback, a dividend — is a one-time row with direction "in", paid, basis "statement", ` +
    `kept apart from spending. Movements between the owner's own accounts (card bill ` +
    `payments, ATM withdrawals, own transfers) are not charges; a row with direction ` +
    `"transfer" keeps one in view, shown and never summed. A member or account is named in ` +
    `words, and a new name becomes a placeholder row as the app would create it. A tag from ` +
    `the library (any casing) arrives with its icon. \`notes\` holds a row's three most ` +
    `important details, one per line, such as an insurance policy's number, its official name ` +
    `or its file in documents/. Where writes are proposals, rows can be promoted to recurring ` +
    `once the owner's app has applied the batch. ${REVIEW}`,
  annotations: WRITER,
}

export const UPDATE_COMMITMENT_SPEC = {
  title: 'Update a commitment',
  description:
    `Changes a commitment's attributes, ${BY_NAME}; everything not named stays as it was, and ` +
    `an explicit null clears an optional field. \`direction\` turns a row into money in ` +
    `("in") or a transfer between the owner's own accounts ("transfer"), and "out" back into ` +
    `a charge. \`amount\` is the price now and reaches only unpaid planned charges from ` +
    `\`from\` (default today); nothing before today is repriced, and a charge priced by hand ` +
    `or proved by a statement stays as it is. \`notes\` is the commitment's three details ` +
    `that matter, one per line, rewritten as it now stands. \`status\` pauses, resumes or ` +
    `cancels: pausing or cancelling unwrites the unpaid planned charges after today and keeps ` +
    `what happened; back to active plans nothing. \`free_trial\` true marks it a free trial, ` +
    `shown as a pill; false takes the mark off; no charge row changes either way. ${REVIEW}`,
  annotations: WRITER,
}

export const MARK_PAID_SPEC = {
  title: 'Mark a charge paid',
  description:
    `Records that one charge was paid, or takes the mark back with paid: false. The ` +
    `commitment is named ${BY_NAME}. The charge is a row; if no row exists for that day one ` +
    `is written at the commitment's price. \`amount\` records what left the account when it ` +
    `differed, and \`paid_on\` the day the money moved when it was not the due date; they ` +
    `change that one row and no other, and a null paid_on or note clears it. ${REVIEW}`,
  annotations: { ...WRITER, idempotentHint: true },
}

export const ADD_CHARGES_SPEC = {
  title: 'Add charges',
  description:
    `Writes rows into one commitment by date: a statement's months for a commitment that ` +
    `already exists (paid, basis "statement"), or more planned months than the app keeps. The ` +
    `app never grows a plan on its own, so this is how one grows. The commitment is named ` +
    `${BY_NAME}. A row already there for a day is updated in place, never doubled. An amount ` +
    `left out is the commitment's price. The answer carries balance_note when the account's ` +
    `balance is now older than the newest row written. ${REVIEW}`,
  annotations: { ...WRITER, idempotentHint: true },
}

export const REMOVE_CHARGES_SPEC = {
  title: 'Remove charges',
  description:
    `Deletes named rows from one commitment, named ${BY_NAME}: a plan that was wrong. A paid ` +
    `row is a fact, so removing one is destructive. ${REVIEW}`,
  annotations: { ...WRITER, destructiveHint: true },
}

export const PROMOTE_SPEC = {
  title: 'Promote one-time commitments to a recurring one',
  description:
    `Takes the ids of one-time commitments that are one thing repeating and makes one ` +
    `recurring commitment: their charges move under it exactly as they are — dates, amounts, ` +
    `paid, basis — the one-time rows go, and the plan continues from the step after the ` +
    `latest, never before today, for plan_months (24 by default), or stops at ends_on for a ` +
    `repeat that has ended. Attributes start as the first row's, direction included, so money ` +
    `in stays money in and a transfer stays a transfer; ids that do not share one direction ` +
    `are refused. Name, tag, member, account and notes may be given; notes are the ` +
    `commitment's three details that matter, one per line. Where writes are proposals, a row ` +
    `is promotable once the owner's app has applied it and commitments shows its id. Every id ` +
    `must be a one-time commitment the memory holds; a miss answers with the real names. ` +
    `${REVIEW}`,
  annotations: WRITER,
}

export const CANCEL_COMMITMENT_SPEC = {
  title: 'Cancel a commitment',
  description:
    `Cancels one commitment, ${BY_NAME}. What was only planned after ` +
    `today is unwritten; what happened stays, so its past charges keep counting. Already-` +
    `cancelled rows refuse. ${REVIEW}`,
  annotations: { ...WRITER, destructiveHint: true },
}

export const LEAVE_INSIGHT_SPEC = {
  title: 'Leave an insight',
  description:
    `Leaves one short note on an app module; the latest note per module shows on that ` +
    `module's own screen. Modules: dashboard.next_payment, dashboard.active_commitments, ` +
    `dashboard.next_30_days, dashboard.this_month, dashboard.by_account, ` +
    `dashboard.by_category, account.<id>, member.<id>. There are no reports.* modules: the ` +
    `Reports screen shows the months longbook drew. A note is a sentence or two. Notes are ` +
    `appended, and the last note per module wins.`,
  annotations: WRITER,
}

export const UPDATE_ACCOUNT_SPEC = {
  title: 'Update an account',
  description:
    `Changes an account's own attributes — its name, its type (\`tag\` — the same words as ` +
    `the app's Account Type), its \`notes\`, the person it belongs to (\`member\`), its ` +
    `balance with the day it was true, and the account it is linked to (\`linked_to\`) — ` +
    `${BY_NAME}. \`notes\` holds what is particular about the account, one detail per line, ` +
    `such as a card's printed name as "Card name: Platinum Reserve"; numbers are refused. ` +
    `card_name and details are longbook's own, and a set sending a non-empty one is refused. ` +
    `Everything not named stays as it was; an explicit null clears. A balance carries its ` +
    `date; left out, the day of the write is used. A linked account is one level only: a card ` +
    `to the bank account that pays it, never a chain. \`member\` and \`linked_to\` name rows ` +
    `the memory already holds. Renaming onto a name another account wears is refused rather ` +
    `than merged. ${REVIEW}`,
  annotations: { ...WRITER, idempotentHint: true },
}

export const UPDATE_MEMBER_SPEC = {
  title: 'Update a person',
  description:
    `Changes a person's name, email or tag, ${BY_NAME}; everything not named stays as it was, ` +
    `and an explicit null clears the email or the tag. \`tag\` is their role in the owner's ` +
    `finances — family, household help, landlord — from the member tags. A person carries a ` +
    `name, a tag, an email and linked accounts; details and card_name are longbook's own, and ` +
    `a set sending a non-empty one is refused. Renaming onto a name another person wears is ` +
    `refused rather than merged. ${REVIEW}`,
  annotations: { ...WRITER, idempotentHint: true },
}

const PAID_ON_SCHEMA = { ...DAY_SCHEMA, type: ['string', 'null'], description: 'The day the money moved, when it was not the due date. Null clears.' }
const NOTE_SCHEMA = { type: ['string', 'null'], maxLength: 300, description: 'A word about this one charge. Null clears.' }

const CHARGE_SCHEMA = {
  type: 'object',
  required: ['date'],
  properties: {
    date: DAY_SCHEMA,
    amount: { type: 'number', minimum: 0, maximum: AMOUNT_LIMIT },
    paid: { type: 'boolean' },
    paid_on: PAID_ON_SCHEMA,
    basis: { type: 'string', enum: ['statement', 'user', 'email', 'plan', 'mark_paid'] },
    note: NOTE_SCHEMA,
    currency: { type: 'string', minLength: 3, maxLength: 3 },
  },
}

const CHARGE_SET_SCHEMA = {
  type: 'object',
  minProperties: 1,
  properties: {
    date: { ...DAY_SCHEMA, description: 'The day to move it to. A day that already holds a charge is refused.' },
    amount: { type: 'number', minimum: 0, maximum: AMOUNT_LIMIT, description: 'What this one charge costs, by the owner\'s hand. On a one-time commitment it is the price too.' },
    paid: { type: 'boolean' },
    paid_on: PAID_ON_SCHEMA,
    note: NOTE_SCHEMA,
    and_later: { type: 'boolean', default: false, description: 'Reach the unpaid planned rows after it: they follow a move a cycle apart, keeping their amounts, and take a new amount with the commitment\'s price. Paid and hand-set rows stay.' },
  },
}

const TAG_KIND_SCHEMA = { type: 'string', enum: [...TAG_KINDS], description: 'Which list the tag belongs to.' }

const whichOf = (noun: string) => ({
  id: { type: 'string', description: `The ${noun} id, or leave it and name the row.` },
  name: { type: 'string', description: 'The exact name, when it is unique.' },
})
const WHICH = whichOf('commitment')

export const UPDATE_CHARGE_SPEC = {
  title: 'Change a charge',
  description:
    `Changes one charge where it sits — its amount, its day, its paid mark, the day the money ` +
    `moved, its note. The commitment is named ${BY_NAME}, and \`date\` is the day the row ` +
    `sits on. \`set.date\` moves it: alone, the row keeps its amount as the owner's fact; ` +
    `with \`and_later\` every unpaid planned row after it follows a cycle apart and keeps its ` +
    `amount, and paid or hand-priced rows stay. \`set.amount\` with \`and_later\` reprices ` +
    `the unpaid planned rows after it too, and the commitment's price with them. A day that ` +
    `already holds a charge is refused, and so is a move past the cancelling date. Null ` +
    `clears paid_on or the note. mark_paid is the one-field way to mark. ${REVIEW}`,
  annotations: WRITER,
}

export const SET_PLANNED_COUNT_SPEC = {
  title: 'Set the planned count',
  description:
    `Sets how many charges stand from today on for a recurring commitment, named ${BY_NAME} — ` +
    `240 at most. More are written a cycle apart after the last row, at the commitment's ` +
    `price; unpaid planned rows past the count are unwritten; paid rows, hand-set rows and ` +
    `the past stay. A one-time commitment has its one charge and is refused. ${REVIEW}`,
  annotations: { ...WRITER, idempotentHint: true },
}

export const ADD_MEMBER_SPEC = {
  title: 'Add a person',
  description:
    `Makes a person with what is known — a \`tag\` for their role in the owner's finances ` +
    `(family, household help, landlord — the library's member tags first) and an \`email\`. A ` +
    `name another person already wears is refused rather than doubled; update_person changes ` +
    `one that exists. ${REVIEW}`,
  annotations: WRITER,
}

export const ADD_ACCOUNT_SPEC = {
  title: 'Add an account',
  description:
    `Makes an account — a card, a bank account, UPI, a wallet, cash — with what is known: its ` +
    `type (\`tag\`, the app's own words: "credit card", "bank account"), the account it is ` +
    `linked to (\`linked_to\`, a card to the bank account that pays it, one level), the ` +
    `person it belongs to (\`member\`, someone the memory holds), its \`notes\` (one detail ` +
    `per line, such as a card's printed name as "Card name: Platinum Reserve"; numbers are ` +
    `refused) and a \`balance\` with the day it was true. A name another account already ` +
    `wears is refused rather than doubled; update_account changes one that exists. ${REVIEW}`,
  annotations: WRITER,
}

export const RENAME_TAG_SPEC = {
  title: 'Rename a tag',
  description:
    `Renames one tag in the vault's own vocabulary — \`kind\` says which list, commitment, ` +
    `member or account — and carries every row wearing it, the owner's tag groups too. A name ` +
    `another tag of that kind already wears is refused. ${REVIEW}`,
  annotations: { ...WRITER, idempotentHint: true },
}

export const DELETE_TAG_SPEC = {
  title: 'Delete a tag',
  description:
    `Removes one tag from the vault's vocabulary — \`kind\` says which list — and the rows ` +
    `that wore it are left with no category; nothing else about them changes. A row left ` +
    `without a category shows under "No category" until one is set. ${REVIEW}`,
  annotations: { ...WRITER, destructiveHint: true },
}

export const DELETE_COMMITMENT_SPEC = {
  title: 'Delete a commitment',
  description:
    `Deletes one commitment and every charge it ever had, by id. This is destructive; ` +
    `cancel_commitment keeps what happened instead. ${REVIEW}`,
  annotations: { ...WRITER, destructiveHint: true },
}

/** What create_report's fields hold, worded once for both doors. */
export const REPORT_TITLE_DESCRIPTION = 'The report\'s name, as the owner said it — "Goa", "Q3 household". 1 to 80 characters.'
export const REPORT_START_DESCRIPTION = 'The first day covered, YYYY-MM-DD. Today or earlier.'
export const REPORT_END_DESCRIPTION = 'The last day covered, YYYY-MM-DD: on or after start_date, 366 days at most counting both.'

export const CREATE_REPORT_SPEC = {
  title: 'Create a report',
  description:
    `Asks longbook to draw a report from the ledger over the days and scope named. \`title\` ` +
    `is its name, \`start_date\` and \`end_date\` its first and last day (366 days at most, ` +
    `starting today or earlier), and \`accounts\`, \`members\` and \`categories\` narrow it — ` +
    `left out or empty means all. "No account" names charges billed to no account and "No ` +
    `category" untagged ones; any other name the memory does not hold is refused with the ` +
    `real names, and nothing is ever created. longbook draws the report on its Reports screen ` +
    `the next time the app is open, counting confirmed charges only; nothing waits in ` +
    `Changes. The same name, days and scope asked again redraws the same report.`,
  annotations: { ...WRITER, idempotentHint: true },
}

/** How a report request names an account, a person or a category, worded once for both doors. */
const reportNames = (noun: string, extra = '') => ({
  type: 'array',
  maxItems: 50,
  items: { type: 'string', minLength: 1 },
  description: `The ${noun} the report covers, each by name as the memory holds it (1 to 80 characters)${extra}. Left out or empty: all of them.`,
})

/** The eighteen write tools as the hosted server lists them — same names, same words, plus the note. */
const WRITE_TOOL_SPECS: WriteToolSpec[] = [
  {
    name: 'add_commitments',
    ...ADD_COMMITMENTS_SPEC,
    inputSchema: {
      type: 'object',
      required: ['rows'],
      properties: { rows: { type: 'array', minItems: 1, maxItems: 200, items: ROW_SCHEMA }, source: SOURCE_SCHEMA, idempotency_key: IDEMPOTENCY_SCHEMA },
    },
  },
  {
    name: 'update_commitment',
    ...UPDATE_COMMITMENT_SPEC,
    inputSchema: { type: 'object', required: ['set'], properties: { ...WHICH, set: SET_SCHEMA, source: SOURCE_SCHEMA, idempotency_key: IDEMPOTENCY_SCHEMA } },
  },
  {
    name: 'mark_paid',
    ...MARK_PAID_SPEC,
    inputSchema: {
      type: 'object',
      required: ['date'],
      properties: { ...WHICH, date: DAY_SCHEMA, paid: { type: 'boolean', default: true }, amount: { type: 'number', minimum: 0, maximum: AMOUNT_LIMIT }, paid_on: PAID_ON_SCHEMA, note: NOTE_SCHEMA, source: SOURCE_SCHEMA, idempotency_key: IDEMPOTENCY_SCHEMA },
    },
  },
  {
    name: 'add_charges',
    ...ADD_CHARGES_SPEC,
    inputSchema: {
      type: 'object',
      required: ['charges'],
      properties: { ...WHICH, charges: { type: 'array', minItems: 1, maxItems: 600, items: CHARGE_SCHEMA }, source: SOURCE_SCHEMA, idempotency_key: IDEMPOTENCY_SCHEMA },
    },
  },
  {
    name: 'remove_charges',
    ...REMOVE_CHARGES_SPEC,
    inputSchema: {
      type: 'object',
      required: ['dates'],
      properties: { ...WHICH, dates: { type: 'array', minItems: 1, maxItems: 600, items: DAY_SCHEMA }, source: SOURCE_SCHEMA, idempotency_key: IDEMPOTENCY_SCHEMA },
    },
  },
  {
    name: 'cancel_commitment',
    ...CANCEL_COMMITMENT_SPEC,
    inputSchema: { type: 'object', properties: { ...WHICH, source: SOURCE_SCHEMA, idempotency_key: IDEMPOTENCY_SCHEMA } },
  },
  {
    name: 'promote_to_recurring',
    ...PROMOTE_SPEC,
    inputSchema: {
      type: 'object',
      required: ['ids', 'billing_cycle'],
      properties: {
        ids: { type: 'array', minItems: 1, maxItems: 200, items: { type: 'string', minLength: 1 }, description: 'The one-time commitments that repeat.' },
        billing_cycle: { type: 'string', enum: ['monthly', 'yearly', 'custom'] },
        custom_cycle_days: { type: 'integer', minimum: 1, maximum: CUSTOM_DAYS_LIMIT },
        plan_months: { type: 'integer', minimum: 1, maximum: 600 },
        ends_on: { ...DAY_SCHEMA, description: 'A known end — the repeat stopped, or will. Nothing is planned past it.' },
        name: { type: 'string', minLength: 1, description: 'The name the promoted commitment wears, as the owner would say it, such as "Netflix".' },
        tag: { type: ['string', 'null'] },
        member: { type: ['string', 'null'] },
        account: { type: ['string', 'null'] },
        notes: { type: ['string', 'null'], description: NOTES_DESCRIPTION },
        source: SOURCE_SCHEMA,
        idempotency_key: IDEMPOTENCY_SCHEMA,
      },
    },
  },
  {
    name: 'leave_insight',
    ...LEAVE_INSIGHT_SPEC,
    inputSchema: {
      type: 'object',
      required: ['module', 'text'],
      properties: { module: { type: 'string', minLength: 1 }, text: { type: 'string', minLength: 1, maxLength: 600 }, idempotency_key: IDEMPOTENCY_SCHEMA },
    },
  },
  {
    name: 'update_account',
    ...UPDATE_ACCOUNT_SPEC,
    inputSchema: { type: 'object', required: ['set'], properties: { ...whichOf('account'), set: ACCOUNT_SET_SCHEMA, source: SOURCE_SCHEMA, idempotency_key: IDEMPOTENCY_SCHEMA } },
  },
  {
    name: 'update_person',
    ...UPDATE_MEMBER_SPEC,
    inputSchema: { type: 'object', required: ['set'], properties: { ...whichOf('member'), set: MEMBER_SET_SCHEMA, source: SOURCE_SCHEMA, idempotency_key: IDEMPOTENCY_SCHEMA } },
  },
  {
    name: 'update_charge',
    ...UPDATE_CHARGE_SPEC,
    inputSchema: {
      type: 'object',
      required: ['date', 'set'],
      properties: { ...WHICH, date: { ...DAY_SCHEMA, description: 'The day the charge sits on.' }, set: CHARGE_SET_SCHEMA, source: SOURCE_SCHEMA, idempotency_key: IDEMPOTENCY_SCHEMA },
    },
  },
  {
    name: 'set_planned_count',
    ...SET_PLANNED_COUNT_SPEC,
    inputSchema: {
      type: 'object',
      required: ['count'],
      properties: { ...WHICH, count: { type: 'integer', minimum: 1, maximum: PLANNED_COUNT_CEILING, description: 'How many charges stand from today on. 240 at most.' }, source: SOURCE_SCHEMA, idempotency_key: IDEMPOTENCY_SCHEMA },
    },
  },
  {
    name: 'add_person',
    ...ADD_MEMBER_SPEC,
    inputSchema: {
      type: 'object',
      required: ['name'],
      properties: {
        name: { type: 'string', minLength: 1, description: 'The name, as the owner said it. Refused when another person already wears it.' },
        tag: { type: 'string', description: MEMBER_SET_SCHEMA.properties.tag.description },
        email: { type: 'string', description: 'Where a shared report reaches them.' },
        source: SOURCE_SCHEMA,
        idempotency_key: IDEMPOTENCY_SCHEMA,
      },
    },
  },
  {
    name: 'add_account',
    ...ADD_ACCOUNT_SPEC,
    inputSchema: {
      type: 'object',
      required: ['name'],
      properties: {
        name: { type: 'string', minLength: 1, description: 'The display name — "Visa 9292", the last four digits at most. Refused when another account already wears it.' },
        tag: { type: 'string', description: ACCOUNT_SET_SCHEMA.properties.tag.description },
        linked_to: { type: 'string', description: ACCOUNT_SET_SCHEMA.properties.linked_to.description },
        member: { type: 'string', description: ACCOUNT_SET_SCHEMA.properties.member.description },
        notes: { type: 'string', description: ACCOUNT_NOTES_DESCRIPTION },
        balance: { type: 'number', description: ACCOUNT_SET_SCHEMA.properties.balance.description },
        balance_date: { ...DAY_SCHEMA, description: ACCOUNT_SET_SCHEMA.properties.balance_date.description },
        source: SOURCE_SCHEMA,
        idempotency_key: IDEMPOTENCY_SCHEMA,
      },
    },
  },
  {
    name: 'rename_tag',
    ...RENAME_TAG_SPEC,
    inputSchema: {
      type: 'object',
      required: ['kind', 'from', 'to'],
      properties: {
        kind: TAG_KIND_SCHEMA,
        from: { type: 'string', minLength: 1, description: 'The tag as the vault holds it, any casing.' },
        to: { type: 'string', minLength: 1, description: 'The new name, in the owner\'s words.' },
        source: SOURCE_SCHEMA,
        idempotency_key: IDEMPOTENCY_SCHEMA,
      },
    },
  },
  {
    name: 'delete_tag',
    ...DELETE_TAG_SPEC,
    inputSchema: {
      type: 'object',
      required: ['kind', 'name'],
      properties: {
        kind: TAG_KIND_SCHEMA,
        name: { type: 'string', minLength: 1, description: 'The tag as the vault holds it, any casing.' },
        source: SOURCE_SCHEMA,
        idempotency_key: IDEMPOTENCY_SCHEMA,
      },
    },
  },
  {
    name: 'delete_commitment',
    ...DELETE_COMMITMENT_SPEC,
    inputSchema: {
      type: 'object',
      required: ['id'],
      properties: {
        id: { type: 'string', minLength: 1, description: 'The commitment id, from commitments or search. Identified by id, not by name.' },
        source: SOURCE_SCHEMA,
        idempotency_key: IDEMPOTENCY_SCHEMA,
      },
    },
  },
  {
    name: 'create_report',
    ...CREATE_REPORT_SPEC,
    inputSchema: {
      type: 'object',
      required: ['title', 'start_date', 'end_date'],
      properties: {
        title: { type: 'string', minLength: 1, description: REPORT_TITLE_DESCRIPTION },
        start_date: { ...DAY_SCHEMA, description: REPORT_START_DESCRIPTION },
        end_date: { ...DAY_SCHEMA, description: REPORT_END_DESCRIPTION },
        accounts: reportNames('accounts', ', or "No account" for charges billed to none'),
        members: reportNames('people'),
        categories: reportNames('categories (commitment tags)', ', or "No category" for untagged charges'),
        source: SOURCE_SCHEMA,
        idempotency_key: IDEMPOTENCY_SCHEMA,
      },
    },
  },
]

export const WRITE_TOOLS: WriteToolSpec[] = WRITE_TOOL_SPECS.map((tool) => ({
  ...tool,
  description: tool.description + HOSTED_NOTE,
}))

// ---------------------------------------------------------------------------------------------
// Validation

const str = (v: unknown): string => (typeof v === 'string' ? v : '')

export const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v)

const DAY = /^\d{4}-\d{2}-\d{2}$/

/** True only for a real calendar day — 2026-02-30 does not round-trip. */
export const isRealDay = (s: string): boolean => DAY.test(s) && toISO(parseDate(s)) === s

const DIRECTIONS: readonly string[] = ['in', 'out', 'transfer']
const DIRECTION_PROBLEM =
  'direction is "in" for money that arrives, "transfer" for a movement between the owner\'s own accounts, "out" or left out for a charge'

/** A commitment's details are longbook's own: a write sending any is refused in these words, on both doors. */
export const DETAILS_REFUSAL = "details is longbook's own — write a commitment's details as lines of its notes"

/** An account's card name and details are longbook's own: a write sending a non-empty one is refused in these words. */
export const ACCOUNT_DETAILS_REFUSAL = "card_name and details are longbook's own — write an account's details as lines of its notes"

/** A person's details are longbook's own: a write sending non-empty details or a card name is refused in these words. */
export const MEMBER_DETAILS_REFUSAL = "details is longbook's own — a member carries a name, a tag, an email and linked accounts"

/** Whether a write sends details: absent, null, or an empty object, list or string sends none. */
export function sendsDetails(value: unknown): boolean {
  if (value === undefined || value === null) return false
  if (typeof value === 'string') return value.trim() !== ''
  if (Array.isArray(value)) return value.length > 0
  if (isRecord(value)) return Object.keys(value).length > 0
  return true
}

/**
 * Checks zod cannot express cleanly, so a direct caller is held to the same contract. With
 * `priceChanged` false the row's amount is the file's already, and meets no bound; with
 * `daysChanged` false, so are its custom cycle's days.
 */
export function rowProblems(
  row: CommitmentRowInput,
  opts: { existing?: boolean; priceChanged?: boolean; daysChanged?: boolean } = {},
): string[] {
  const problems: string[] = []
  if (!row.name?.trim()) problems.push('needs a name')
  const judged = opts.priceChanged !== false
  if (judged && (typeof row.amount !== 'number' || !Number.isFinite(row.amount) || row.amount < 0)) {
    problems.push('the amount has to be a number, zero or more')
  } else if (judged && row.amount > AMOUNT_LIMIT) {
    problems.push(AMOUNT_LIMIT_PROBLEM)
  }
  if (!/^[A-Za-z]{3}$/.test(row.currency?.trim() ?? '')) {
    problems.push('the currency is a three-letter ISO code, e.g. INR or USD')
  }
  if (!['monthly', 'yearly', 'custom', 'once'].includes(row.billing_cycle)) {
    problems.push('billing_cycle is monthly, yearly, custom or once')
  }
  const first = row.first_charge ?? row.date
  if (!opts.existing && !isRealDay(first ?? '')) {
    problems.push(row.billing_cycle === 'once'
      ? 'a one-time row needs date, a real calendar day written YYYY-MM-DD'
      : 'needs first_charge, a real calendar day written YYYY-MM-DD — where the plan starts')
  }
  for (const field of ['ends_on', 'paid_on'] as const) {
    const value = row[field]
    if (value != null && !isRealDay(value)) problems.push(`${field} must be a real YYYY-MM-DD date`)
  }
  if (row.plan_months != null && !(Number.isInteger(row.plan_months) && row.plan_months > 0 && row.plan_months <= 600)) {
    problems.push('plan_months is a whole number of months, 1 to 600')
  }
  if (row.plan_count != null && !isPlannedCount(row.plan_count)) problems.push(PLANNED_COUNT_PROBLEM)
  if (row.plan_count != null && row.billing_cycle === 'once') problems.push('plan_count belongs to a recurring row; a one-time row is its one charge')
  if (row.billing_cycle !== 'once' && (row.paid != null || row.basis != null || row.paid_on != null)) {
    problems.push('paid, paid_on and basis belong to a one-time row; for a recurring one use add_charges after')
  }
  if (row.basis != null && !['statement', 'user', 'email', 'plan'].includes(row.basis)) {
    problems.push('basis is statement, user, email or plan')
  }
  if (row.status != null && !['active', 'paused', 'cancelled'].includes(row.status)) {
    problems.push('status is active, paused or cancelled')
  }
  if (row.direction != null && !DIRECTIONS.includes(row.direction)) problems.push(DIRECTION_PROBLEM)
  const days = row.custom_cycle_days
  if (row.billing_cycle === 'custom' && days == null) {
    problems.push('a custom cycle needs custom_cycle_days — the days between charges')
  } else if (row.billing_cycle === 'custom' && opts.daysChanged !== false && !isCycleDays(days)) {
    problems.push(CUSTOM_DAYS_PROBLEM)
  }
  if (row.billing_cycle !== 'custom' && days != null) {
    problems.push('custom_cycle_days only belongs with billing_cycle "custom"')
  }
  if (sendsDetails(row.details)) problems.push(DETAILS_REFUSAL)
  return problems
}

/** The full batch checked before anything is written: all-or-nothing, every offender named. */
export function checkRows(rows: CommitmentRowInput[]): void {
  if (!Array.isArray(rows) || rows.length === 0) throw new VaultWriteError('rows must carry at least one commitment.')
  if (rows.length > 200) throw new VaultWriteError('At most 200 rows per call — send the rest in a second batch.')
  const complaints: string[] = []
  rows.forEach((row, i) => {
    if (!isRecord(row)) {
      complaints.push(`row ${i + 1}: must be an object`)
      return
    }
    for (const problem of rowProblems(row)) {
      complaints.push(`row ${i + 1} ("${row.name?.trim() || 'unnamed'}"): ${problem}`)
    }
  })
  if (complaints.length > 0) {
    throw new VaultWriteError(`Nothing was written. Fix these and send the batch again — ${complaints.join('; ')}.`)
  }
}

/** Each charge row held to its shape; a bad one names itself. */
export function checkCharges(charges: unknown): void {
  if (!Array.isArray(charges) || charges.length === 0) throw new VaultWriteError('charges must carry at least one row.')
  if (charges.length > 600) throw new VaultWriteError('At most 600 charges per call.')
  const problems: string[] = []
  charges.forEach((c, i) => {
    if (!isRecord(c)) { problems.push(`charge ${i + 1}: must be an object`); return }
    if (!isRealDay(str(c.date))) problems.push(`charge ${i + 1}: date must be a real YYYY-MM-DD day`)
    if (c.amount !== undefined && (typeof c.amount !== 'number' || !Number.isFinite(c.amount) || c.amount < 0)) problems.push(`charge ${i + 1}: amount is a number, zero or more`)
    else if (typeof c.amount === 'number' && c.amount > AMOUNT_LIMIT) problems.push(`charge ${i + 1}: ${AMOUNT_LIMIT_PROBLEM}`)
    if (c.paid !== undefined && typeof c.paid !== 'boolean') problems.push(`charge ${i + 1}: paid is true or false`)
    if (c.paid_on != null && !isRealDay(str(c.paid_on))) problems.push(`charge ${i + 1}: paid_on must be a real YYYY-MM-DD day`)
    if (c.basis != null && !['statement', 'user', 'email', 'plan', 'mark_paid'].includes(str(c.basis))) problems.push(`charge ${i + 1}: basis is statement, user, email, plan or mark_paid`)
    if (c.currency != null && !/^[A-Za-z]{3}$/.test(str(c.currency))) problems.push(`charge ${i + 1}: currency is a three-letter code`)
    if (c.note != null && (typeof c.note !== 'string' || c.note.length > 300)) problems.push(`charge ${i + 1}: note is text under 300 characters, or null to clear it`)
  })
  if (problems.length > 0) throw new VaultWriteError(`Nothing was written. Fix these — ${problems.join('; ')}.`)
}

/** Refusing a planned count outside 1 to 240, worded once for both doors. */
export const PLANNED_COUNT_PROBLEM = 'count is a whole number of charges, 1 to 240'

const isPlannedCount = (count: unknown): boolean =>
  typeof count === 'number' && Number.isInteger(count) && count >= 1 && count <= PLANNED_COUNT_CEILING

/** A count of planned charges, as set_planned_count takes it. */
export function checkPlannedCount(count: unknown): void {
  if (!isPlannedCount(count)) throw new VaultWriteError(`${PLANNED_COUNT_PROBLEM}.`)
}

/** The fields update_charge's set takes. */
export const CHARGE_SET_FIELDS = ['date', 'amount', 'paid', 'paid_on', 'note', 'and_later'] as const

/** One charge's set, held field by field: a day, an amount within the limit, a mark, a clearable paid_on and note. */
export function checkChargeSet(set: unknown): asserts set is ChargeSet {
  if (!isRecord(set) || Object.keys(set).length === 0) throw new VaultWriteError('set must name at least one field to change.')
  const problems: string[] = []
  const changes = CHARGE_SET_FIELDS.filter((k) => k !== 'and_later')
  if (!changes.some((k) => set[k] !== undefined)) problems.push(`set names none of ${changes.join(', ')}`)
  if (set.date !== undefined && !isRealDay(str(set.date))) problems.push('date is the day to move the charge to, a real YYYY-MM-DD day')
  if (set.amount !== undefined && (typeof set.amount !== 'number' || !Number.isFinite(set.amount) || set.amount < 0)) {
    problems.push('amount is a number, zero or more')
  } else if (typeof set.amount === 'number' && set.amount > AMOUNT_LIMIT) {
    problems.push(AMOUNT_LIMIT_PROBLEM)
  }
  if (set.paid !== undefined && typeof set.paid !== 'boolean') problems.push('paid is true or false')
  if (set.paid_on != null && !isRealDay(str(set.paid_on))) problems.push('paid_on is the day the money moved, a real YYYY-MM-DD day, or null to clear it')
  if (set.note != null && (typeof set.note !== 'string' || set.note.length > 300)) problems.push('note is text under 300 characters, or null to clear it')
  if (set.and_later !== undefined && typeof set.and_later !== 'boolean') problems.push('and_later is true or false')
  if (problems.length > 0) throw new VaultWriteError(`Nothing was changed. Fix these — ${problems.join('; ')}.`)
}

/** A new person: a name, and what is known held as update_member holds it. */
export function checkNewMember(body: unknown): asserts body is NewMember {
  if (!isRecord(body) || !str(body.name).trim()) throw new VaultWriteError(`${EMPTY_NAME_REFUSAL}`)
  const set: Record<string, unknown> = {}
  for (const key of ['tag', 'email']) if (body[key] !== undefined) set[key] = body[key]
  // Details that say nothing describe nothing; non-empty ones meet the refusal by name.
  for (const key of ['card_name', 'details']) if (sendsDetails(body[key])) set[key] = body[key]
  if (Object.keys(set).length > 0) checkMemberSet(set)
}

/** A new account: a name, and what is known held as update_account holds it. */
/** What describes a new account, under the names update_account's set takes. */
export const NEW_ACCOUNT_FIELDS = ['tag', 'linked_to', 'parent', 'parent_account', 'member', 'notes', 'balance', 'balance_date'] as const

export function checkNewAccount(body: unknown): asserts body is NewAccount {
  if (!isRecord(body) || !str(body.name).trim()) throw new VaultWriteError(`${EMPTY_NAME_REFUSAL}`)
  const set: Record<string, unknown> = {}
  for (const key of NEW_ACCOUNT_FIELDS) {
    if (body[key] !== undefined) set[key] = body[key]
  }
  for (const key of ['card_name', 'details']) if (sendsDetails(body[key])) set[key] = body[key]
  if (Object.keys(set).length > 0) checkAccountSet(set)
  // A new account holds no balance to date: the day only ever comes with one.
  if (set.balance_date !== undefined && set.balance === undefined) {
    throw new VaultWriteError('Nothing was changed. Fix these — a balance carries its day; give balance with balance_date.')
  }
}

const isTagKind = (kind: unknown): kind is TagKindName => (TAG_KINDS as readonly string[]).includes(str(kind))
type TagKindName = (typeof TAG_KINDS)[number]

/** A tag rename: a kind, the tag as held, and a new name that is not empty. */
export function checkTagRename(body: Record<string, unknown>): void {
  if (!isTagKind(body.kind)) throw new VaultWriteError(`kind is ${TAG_KINDS.join(', ')} — which list the tag belongs to.`)
  if (!str(body.from).trim()) throw new VaultWriteError('from names the tag as the vault holds it.')
  if (!str(body.to).trim()) throw new VaultWriteError(EMPTY_NAME_REFUSAL)
}

/** A tag delete: a kind and the tag as held. */
export function checkTagDelete(body: Record<string, unknown>): void {
  if (!isTagKind(body.kind)) throw new VaultWriteError(`kind is ${TAG_KINDS.join(', ')} — which list the tag belongs to.`)
  if (!str(body.name).trim()) throw new VaultWriteError('name names the tag as the vault holds it.')
}

/** A delete names its row by id alone: a name could reach the wrong one. */
export function checkDeleteId(body: Record<string, unknown>): void {
  if (!str(body.id).trim()) throw new VaultWriteError('Say which commitment: pass its id. delete_commitment takes no name.')
}

/** The keys a report request names. longbook draws the rest — id, currency, modules and all. */
export const REPORT_REQUEST_FIELDS = ['title', 'start_date', 'end_date', 'accounts', 'members', 'categories'] as const

/** Any other key, refused in one sentence on both doors. */
export const REPORT_DRAWN_REFUSAL =
  'longbook draws the report; name only title, start_date, end_date, accounts, members and categories.'

/** The scope names that stand for no row: charges billed to no account, and untagged charges. */
export const NO_ACCOUNT = 'No account'
export const NO_CATEGORY = 'No category'

/** The days one report may cover, counting both ends. */
export const REPORT_SPAN_LIMIT = 366

const REPORT_SCOPE: Array<{ key: 'accounts' | 'members' | 'categories'; noun: string; none?: string }> = [
  { key: 'accounts', noun: 'account names', none: NO_ACCOUNT },
  { key: 'members', noun: 'people\'s names' },
  { key: 'categories', noun: 'category names', none: NO_CATEGORY },
]

/**
 * A report request held to its shape, against the server's own calendar day; returns the
 * payload as filed — trimmed, a "No account" in any casing written as the app reads it, an
 * empty list dropped. Unknown keys are refused, so a misspelt scope never widens a report.
 */
export function checkReportRequest(body: Record<string, unknown>, today: string = toISO(todayMid()), slackDays = 0): Record<string, unknown> {
  const taken: readonly string[] = [...REPORT_REQUEST_FIELDS, 'source']
  if (Object.keys(body).some((key) => !taken.includes(key))) throw new VaultWriteError(REPORT_DRAWN_REFUSAL)
  const title = str(body.title).trim()
  if (!title) throw new VaultWriteError(EMPTY_NAME_REFUSAL)
  if (title.length > 80) throw new VaultWriteError('A report\'s name is 80 characters at most.')
  const start = str(body.start_date)
  const end = str(body.end_date)
  if (!isRealDay(start)) throw new VaultWriteError('start_date is the first day the report covers, a real YYYY-MM-DD day.')
  if (!isRealDay(end)) throw new VaultWriteError('end_date is the last day the report covers, a real YYYY-MM-DD day.')
  if (end < start) throw new VaultWriteError('end_date comes on or after start_date.')
  // The hosted door runs on UTC, a day behind or ahead of the owner; it allows a day and the
  // app checks the owner's own day when it draws.
  const bound = parseDate(today)
  bound.setDate(bound.getDate() + slackDays)
  const latest = toISO(bound)
  if (start > latest) {
    throw new VaultWriteError(`start_date is after today, ${today}: a report counts charges dated today or earlier, so it starts on a day that has come.`)
  }
  if (daysBetween(parseDate(start), parseDate(end)) + 1 > REPORT_SPAN_LIMIT) {
    throw new VaultWriteError(`A report covers ${REPORT_SPAN_LIMIT} days at most, counting both start_date and end_date.`)
  }
  const out: Record<string, unknown> = { title, start_date: start, end_date: end }
  for (const { key, noun, none } of REPORT_SCOPE) {
    const value = body[key]
    if (value === undefined || value === null) continue
    const problem = `${key} lists up to 50 ${noun}, each 1 to 80 characters.`
    if (!Array.isArray(value) || value.length > 50) throw new VaultWriteError(problem)
    const names = value.map((name) => (typeof name === 'string' ? name.trim() : ''))
    if (names.some((name) => !name || name.length > 80)) throw new VaultWriteError(problem)
    if (names.length > 0) out[key] = names.map((name) => (none && nameKey(name) === nameKey(none) ? none : name))
  }
  if (body.source !== undefined) out.source = body.source
  return out
}

/** How a refusal names one row's direction. */
const directionWord = (direction: string | null): string =>
  direction === null ? 'spending' : direction === 'in' ? 'money in' : direction === 'transfer' ? 'a transfer' : `"${direction}"`

/**
 * A promotion keeps its rows where they are counted, so every id must share one stored
 * direction. Null when they do; else the refusal, naming each row. Both doors ask here.
 */
export function mixedDirections(rows: Array<{ name: string; direction?: unknown }>): string | null {
  const stored = rows.map((r) => storedDirection(r.direction))
  if (new Set(stored).size <= 1) return null
  const named = rows.map((r, i) => `"${r.name}" is ${directionWord(stored[i]!)}`).join(', ')
  return `These rows do not share a direction: promote spending, money in and transfers separately — ${named}.`
}

/** A promotion held to its shape. Both doors ask here, so both refuse in the same words. */
export function checkPromotion(body: Record<string, unknown>): void {
  if (!Array.isArray(body.ids) || body.ids.length === 0 || !body.ids.every((id) => typeof id === 'string' && id.trim())) {
    throw new VaultWriteError('ids names the one-time commitments that repeat.')
  }
  if (!['monthly', 'yearly', 'custom'].includes(str(body.billing_cycle))) {
    throw new VaultWriteError('billing_cycle is monthly, yearly or custom — promoting makes a recurring commitment.')
  }
  if (body.billing_cycle === 'custom' && body.custom_cycle_days == null) {
    throw new VaultWriteError('a custom cycle needs custom_cycle_days — the days between charges.')
  }
  if (body.billing_cycle === 'custom' && !isCycleDays(body.custom_cycle_days)) throw new VaultWriteError(`${CUSTOM_DAYS_PROBLEM}.`)
  if (body.plan_months != null && !(Number.isInteger(body.plan_months) && (body.plan_months as number) > 0 && (body.plan_months as number) <= 600)) {
    throw new VaultWriteError('plan_months is a whole number of months, 1 to 600.')
  }
  if (body.name !== undefined && !str(body.name).trim()) throw new VaultWriteError('name cannot be empty.')
  if (body.ends_on !== undefined && !isRealDay(str(body.ends_on))) throw new VaultWriteError('ends_on must be a real YYYY-MM-DD day.')
  if (sendsDetails(body.details)) throw new VaultWriteError(`${DETAILS_REFUSAL}.`)
}

/** A charge's note as mark_paid takes it: text under 300 characters, or null to clear it. */
export function checkChargeNote(note: unknown): void {
  if (note == null) return
  if (typeof note !== 'string' || note.length > 300) throw new VaultWriteError('note is text under 300 characters, or null to clear it.')
}

/** What mark_paid says left the account, when it names an amount: a number, zero or more, within the limit. */
export function checkPaidAmount(amount: unknown): void {
  if (amount === undefined) return
  if (typeof amount !== 'number' || !Number.isFinite(amount) || amount < 0) {
    throw new VaultWriteError('amount is what actually left the account, a number zero or more.')
  }
  if (amount > AMOUNT_LIMIT) throw new VaultWriteError(AMOUNT_LIMIT_REFUSAL)
}

function checkWhich(payload: Record<string, unknown>, noun = 'commitment'): void {
  if (!str(payload.id).trim() && !str(payload.name).trim()) {
    throw new VaultWriteError(`Say which ${noun}: pass its id, or its exact name.`)
  }
}

/** Loose on purpose, as the app's own check: an @ with something either side. */
export const isEmailShape = (address: string): boolean => {
  const at = address.indexOf('@')
  return at > 0 && at < address.length - 1
}

/** The fields update_account's set takes, the linked account under its two older names too. */
export const ACCOUNT_SET_FIELDS = ['name', 'tag', 'notes', 'member', 'balance', 'balance_date', 'linked_to', 'parent', 'parent_account'] as const

/** The fields update_member's set takes. */
export const MEMBER_SET_FIELDS = ['name', 'email', 'tag'] as const

/** The linked account's three names, newest first: the first of them a set gives is written. */
const LINK_KEYS: readonly string[] = ['linked_to', 'parent', 'parent_account']

/** The key meant, for a key update_account's set does not take. */
const ACCOUNT_SET_HINTS = new Map<string, string>([
  ['type', 'the account type is tag'],
  ['belongs_to', 'the person is member'],
  ['member_id', 'the person is member, by name'],
  ['parent_account_id', 'the linked account is linked_to'],
  ['note', "the account's details are notes"],
  ['card_name', "a card's name is a line of notes"],
  ['details', "an account's details are lines of its notes"],
])

/** The key meant, for a key update_member's set does not take. */
const MEMBER_SET_HINTS = new Map<string, string>([
  ['role', 'their role is tag'],
  ['relationship', 'their role is tag'],
  ['notes', 'what is said about a person goes in the notes of the commitment it is about'],
  ['accounts', "an account's person is set with update_account's member"],
  ['card_name', 'a member carries a name, a tag, an email and linked accounts'],
  ['details', 'a member carries a name, a tag, an email and linked accounts'],
])

/**
 * What an account's or a person's set writes, in the order sent: each key its tool takes, but an
 * older name for the linked account beside the one written. The rest are ignored, named with the
 * key meant where one exists; the write lands. Both doors answer with it.
 */
export function entitySetOutcome(kind: 'update_account' | 'update_person', set: object): { fields: string[]; ignored: string[] } {
  const takes: readonly string[] = kind === 'update_account' ? ACCOUNT_SET_FIELDS : MEMBER_SET_FIELDS
  const hints = kind === 'update_account' ? ACCOUNT_SET_HINTS : MEMBER_SET_HINTS
  const sent = Object.entries(set).filter(([, value]) => value !== undefined).map(([key]) => key)
  const link = LINK_KEYS.find((key) => sent.includes(key))
  const fields: string[] = []
  const ignored: string[] = []
  for (const key of sent) {
    if (!takes.includes(key)) {
      const hint = hints.get(key)
      ignored.push(hint ? `${key} — ${hint}` : key)
    } else if (LINK_KEYS.includes(key) && key !== link) {
      ignored.push(`${key} — ${link} wins`)
    } else {
      fields.push(key)
    }
  }
  return { fields, ignored }
}

/** An account's set, held field by field; the names it carries are checked against the memory in targets.ts. */
export function checkAccountSet(set: unknown): asserts set is AccountSet {
  if (!isRecord(set) || Object.keys(set).length === 0) throw new VaultWriteError('set must name at least one field to change.')
  const problems: string[] = []
  const named = ACCOUNT_SET_FIELDS.filter((k) => k !== 'parent' && k !== 'parent_account')
  if (sendsDetails(set.card_name) || sendsDetails(set.details)) problems.push(ACCOUNT_DETAILS_REFUSAL)
  else if (!ACCOUNT_SET_FIELDS.some((k) => set[k] !== undefined)) problems.push(`set names none of ${named.join(', ')}`)
  if (set.name !== undefined && !str(set.name).trim()) problems.push('name cannot be empty')
  if (set.tag !== undefined && set.tag !== null && typeof set.tag !== 'string') problems.push('tag is the account type, in words, or null')
  if (set.balance !== undefined && set.balance !== null && (typeof set.balance !== 'number' || !Number.isFinite(set.balance))) {
    problems.push('balance is a number, or null to clear it')
  }
  if (set.balance_date != null && !isRealDay(str(set.balance_date))) problems.push('balance_date must be a real YYYY-MM-DD date')
  if (set.balance === null && set.balance_date != null) problems.push('a null balance clears its day too — leave balance_date out')
  if (typeof set.balance === 'number' && set.balance_date === null) problems.push('a balance carries its day — give balance_date, or leave it out for today')
  if (set.balance === undefined && set.balance_date === null) problems.push('a balance carries its day — set balance to null to clear both')
  for (const field of ['linked_to', 'parent', 'parent_account']) {
    if (set[field] !== undefined && set[field] !== null && !str(set[field]).trim()) {
      problems.push(`${field} is an account name or id, or null to clear it`)
    }
  }
  for (const field of ['notes', 'member']) {
    if (set[field] !== undefined && set[field] !== null && typeof set[field] !== 'string') problems.push(`${field} is text, or null to clear it`)
  }
  if (problems.length > 0) throw new VaultWriteError(`Nothing was changed. Fix these — ${problems.join('; ')}.`)
}

/** A person's set: a name, an email that reads as one, a tag in words; null clears either. */
export function checkMemberSet(set: unknown): asserts set is MemberSet {
  if (!isRecord(set) || Object.keys(set).length === 0) throw new VaultWriteError('set must name at least one field to change.')
  const problems: string[] = []
  if (sendsDetails(set.details) || sendsDetails(set.card_name)) problems.push(MEMBER_DETAILS_REFUSAL)
  else if (!MEMBER_SET_FIELDS.some((k) => set[k] !== undefined)) problems.push(`set names none of ${MEMBER_SET_FIELDS.join(', ')}`)
  if (set.tag !== undefined && set.tag !== null && typeof set.tag !== 'string') problems.push('tag is their role, in words, or null to clear it')
  if (set.name !== undefined && !str(set.name).trim()) problems.push('name cannot be empty')
  if (set.email !== undefined && set.email !== null) {
    if (typeof set.email !== 'string') problems.push('email is text, or null to clear it')
    else if (set.email !== '' && !isEmailShape(set.email)) problems.push('an email needs an @ with something either side')
  }
  if (problems.length > 0) throw new VaultWriteError(`Nothing was changed. Fix these — ${problems.join('; ')}.`)
}

/**
 * The update's set, held to the row contract field by field — the merge happens at apply time.
 * Both doors ask here, so both refuse in the same words.
 */
export function checkCommitmentSet(set: unknown): void {
  if (!isRecord(set) || Object.keys(set).length === 0) throw new VaultWriteError('set must name at least one field to change.')
  const problems: string[] = []
  if (sendsDetails(set.details)) problems.push(DETAILS_REFUSAL)
  else if (!COMMITMENT_SET_FIELDS.some((k) => set[k] !== undefined)) problems.push(`set names none of ${COMMITMENT_SET_FIELDS.join(', ')}`)
  if (set.name !== undefined && !str(set.name).trim()) problems.push('name cannot be empty')
  if (set.amount !== undefined && (typeof set.amount !== 'number' || !Number.isFinite(set.amount) || set.amount < 0)) {
    problems.push('amount has to be a number, zero or more')
  } else if (typeof set.amount === 'number' && set.amount > AMOUNT_LIMIT) {
    problems.push(AMOUNT_LIMIT_PROBLEM)
  }
  if (set.currency !== undefined && !/^[A-Za-z]{3}$/.test(str(set.currency).trim())) problems.push('currency is a three-letter code')
  if (set.billing_cycle !== undefined && !['monthly', 'yearly', 'custom', 'once'].includes(str(set.billing_cycle))) {
    problems.push('billing_cycle is monthly, yearly, custom or once')
  }
  if (set.status !== undefined && !['active', 'paused', 'cancelled'].includes(str(set.status))) problems.push('status is active, paused or cancelled')
  if (set.direction != null && !DIRECTIONS.includes(str(set.direction))) problems.push(DIRECTION_PROBLEM)
  for (const field of ['ends_on', 'from', 'date'] as const) {
    const value = set[field]
    if (value != null && !isRealDay(str(value))) problems.push(`${field} must be a real YYYY-MM-DD date`)
  }
  if (set.from != null && set.amount === undefined) problems.push('from only goes with an amount')
  if (set.custom_cycle_days != null && !isCycleDays(set.custom_cycle_days)) problems.push(CUSTOM_DAYS_PROBLEM)
  if (set.free_trial !== undefined && typeof set.free_trial !== 'boolean') problems.push('free_trial is true or false')
  if (problems.length > 0) throw new VaultWriteError(`Nothing was changed. Fix these — ${problems.join('; ')}.`)
}

const KNOWN_MODULE = /^(dashboard\.[a-z_]+|account\.[^\s]+|member\.[^\s]+)$/
// The Reports screen carries only written reports, so no reports.* id names a module.
const RETIRED_MODULE = /^reports\.[a-z_]+$/

/** A note for an insight module. An unknown id waits for the version that names it; a
 *  retired one has no version coming, so it says where the words belong instead. */
export function insightNote(module: string): string | undefined {
  if (KNOWN_MODULE.test(module)) return undefined
  if (RETIRED_MODULE.test(module)) {
    return `"${module}" is no longer a module in the app, so this note has no screen to appear on. It is kept as written. The Reports screen shows the months longbook drew; read one with reports, and say what you noticed in the conversation or on the dashboard module it is about.`
  }
  return `"${module}" is not a module this app version names; the note is kept and shows when a version does.`
}

/** A source reference is short and never carries what the file refuses. */
export function checkSource(source: unknown): string | undefined {
  if (source === undefined || source === null) return undefined
  if (typeof source !== 'string' || !source.trim()) throw new VaultWriteError('source, when given, is a short reference like "documents/hdfc-2026.pdf".')
  const ref = source.trim()
  if (ref.length > 200) throw new VaultWriteError('source stays under 200 characters — a path or an id, not the content.')
  if (scanFields({ source: ref }).length > 0) throw new VaultWriteError(`${DATA_POLICY_REFUSAL} (source)`)
  return ref
}

/**
 * Every value a payload carries, flattened for the data-policy scan. A scalar is rendered
 * whatever its type — a number is a digit run, and a card number in a number-hinted field is
 * a number — using the same rendering swift-core scans by, so both doors refuse one input.
 */
export function payloadTexts(value: unknown, out: Record<string, string> = {}, path = 'payload'): Record<string, string> {
  if (Array.isArray(value)) value.forEach((v, i) => payloadTexts(v, out, `${path}.${i}`))
  else if (isRecord(value)) for (const [k, v] of Object.entries(value)) payloadTexts(v, out, `${path}.${k}`)
  else {
    const word = scannableWords(value)[0]
    if (word !== undefined) out[path] = word
  }
  return out
}

/**
 * The row a refused value sits on, in words a refusal can carry: a batch row by its place and
 * name, any other write by the name or id it addresses. A name the scan refuses is never repeated.
 */
function refusedRow(kind: ProposalKind, body: Record<string, unknown>, path: string): string {
  const clean = (value: unknown): string => {
    const text = typeof value === 'string' ? value.trim() : ''
    return text && !scanText(text) ? text : ''
  }
  const batch = kind === 'add_commitments' ? /^payload\.rows\.(\d+)(?:\.|$)/.exec(path) : null
  if (batch) {
    const place = Number(batch[1])
    const row = Array.isArray(body.rows) ? body.rows[place] : undefined
    const name = clean(isRecord(row) ? row.name : undefined)
    return name ? ` (row ${place + 1}: "${name}")` : ` (row ${place + 1})`
  }
  if (kind === 'leave_insight') return ''
  const name = clean(body.name) || clean(body.id)
  if (name) return ` (row: "${name}")`
  const ids = kind === 'promote_to_recurring' && Array.isArray(body.ids) ? body.ids.map(clean).filter(Boolean) : []
  return ids.length > 0 ? ` (ids: ${ids.join(', ')})` : ''
}

/**
 * One proposal held to the contract: the kind is known, the payload has the shape its tool
 * takes, no string carries what the file refuses, and the whole thing stays under the cap.
 * Returns it normalised; throws VaultWriteError with the reason an agent can act on.
 */
export function checkProposal(kind: string, payload: unknown, options: { daySlack?: number } = {}): Proposal {
  kind = canonicalToolName(kind)
  if (!(PROPOSAL_KINDS as readonly string[]).includes(kind)) {
    throw new VaultWriteError(`No write tool named "${kind}". The write tools: ${PROPOSAL_KINDS.join(', ')}.`)
  }
  if (!isRecord(payload)) throw new VaultWriteError('arguments must be an object.')
  const bytes = JSON.stringify(payload).length
  if (bytes > MAX_PAYLOAD_BYTES) {
    throw new VaultWriteError(`This call is ${Math.round(bytes / 1024)} KB; the cap is 256 KB. Split the batch.`)
  }
  let body: Record<string, unknown> = { ...payload }
  const idempotency = body.idempotency_key
  delete body.idempotency_key
  if (idempotency != null && (typeof idempotency !== 'string' || !idempotency.trim() || idempotency.length > 200)) {
    throw new VaultWriteError('idempotency_key is a short string, 1–200 characters.')
  }
  const sourceRef = checkSource(body.source)
  if (sourceRef) body.source = sourceRef
  else delete body.source

  switch (kind as ProposalKind) {
    case 'add_commitments':
      checkRows(body.rows as CommitmentRowInput[])
      break
    case 'update_commitment':
      checkWhich(body)
      checkCommitmentSet(body.set)
      break
    case 'mark_paid':
      checkWhich(body)
      if (!isRealDay(str(body.date))) throw new VaultWriteError('date must be the charge\'s due date, a real YYYY-MM-DD day.')
      if (body.paid !== undefined && typeof body.paid !== 'boolean') throw new VaultWriteError('paid is true or false.')
      checkPaidAmount(body.amount)
      if (body.paid_on != null && !isRealDay(str(body.paid_on))) throw new VaultWriteError('paid_on is the day the money moved, a real YYYY-MM-DD day, or null to clear it.')
      checkChargeNote(body.note)
      break
    case 'add_charges':
      checkWhich(body)
      checkCharges(body.charges)
      break
    case 'remove_charges':
      checkWhich(body)
      if (!Array.isArray(body.dates) || body.dates.length === 0) throw new VaultWriteError('dates names the charges to remove, YYYY-MM-DD each.')
      for (const d of body.dates) if (!isRealDay(str(d))) throw new VaultWriteError(`"${String(d)}" is not a real YYYY-MM-DD day.`)
      break
    case 'cancel_commitment':
      checkWhich(body)
      break
    case 'promote_to_recurring':
      checkPromotion(body)
      break
    case 'leave_insight': {
      const module = str(body.module).trim()
      const text = str(body.text).trim()
      if (!module) throw new VaultWriteError('module names the app module the note belongs to.')
      if (!text) throw new VaultWriteError('text is the note itself.')
      if (text.length > 600) throw new VaultWriteError('An insight is a sentence or two — under 600 characters.')
      break
    }
    case 'update_account':
      checkWhich(body, 'account')
      checkAccountSet(body.set)
      break
    case 'update_person':
      checkWhich(body, 'person')
      checkMemberSet(body.set)
      break
    case 'update_charge':
      checkWhich(body)
      if (!isRealDay(str(body.date))) throw new VaultWriteError('date is the day the charge sits on, a real YYYY-MM-DD day.')
      checkChargeSet(body.set)
      break
    case 'set_planned_count':
      checkWhich(body)
      checkPlannedCount(body.count)
      break
    case 'add_person':
      checkNewMember(body)
      break
    case 'add_account':
      checkNewAccount(body)
      break
    case 'rename_tag':
      checkTagRename(body)
      break
    case 'delete_tag':
      checkTagDelete(body)
      break
    case 'delete_commitment':
      checkDeleteId(body)
      break
    case 'create_report':
      body = checkReportRequest(body, toISO(todayMid()), options.daySlack ?? 0)
      break
  }

  // Refused whole, naming the row the first refused value sits on, as the local door names it.
  const refused = Object.entries(payloadTexts(body)).find(([, text]) => scanText(text))
  if (refused) {
    const field = refused[0].split('.').filter((part) => part !== 'payload' && !/^\d+$/.test(part)).pop()
    throw new VaultWriteError(`${DATA_POLICY_REFUSAL}${refusedRow(kind as ProposalKind, body, refused[0])}${policyFix(scanText(refused[1])!, field)}`)
  }

  return {
    kind: kind as ProposalKind,
    payload: body,
    ...(typeof idempotency === 'string' ? { idempotency_key: idempotency.trim() } : {}),
    ...(sourceRef ? { source_ref: sourceRef } : {}),
  }
}
