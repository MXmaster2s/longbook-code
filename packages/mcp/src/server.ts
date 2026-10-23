// The longbook MCP server: the financial memory over stdio. Fourteen read tools, the
// document and report readers, and eighteen write tools — every edit validated, signed and
// landing in the app's Changes screen; a report request waits for the app to draw. The
// hosted twin files the same writes as proposals.
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import { ErrorCode, GetPromptRequestSchema, McpError } from '@modelcontextprotocol/sdk/types.js'
import { realpathSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { LLMS_TXT, RELEASE_VERSION } from '@longbook/core'
import { z } from 'zod'
import {
  cashflowChart,
  commitmentsList,
  messageCard,
  nextPaymentCard,
  upcomingStrip,
} from '@longbook/cards'
import { CARD_RESOURCES, RESOURCE_LIBRARY, TOOLS, instructionsFor, titled } from './catalog.js'
import { MCP_PROMPTS, MONTH_ARGUMENT_DESCRIPTION, mcpPromptMessage } from './prompts.js'
import { readGuide, whoami } from './rpc.js'
import { GUIDE_KEY_SCHEMA, guideWarning } from './guideCheck.js'
import { PROPOSAL_KINDS, isRecord } from './proposal.js'
import { LIBRARY_FILE, LLMS_FILE, SCHEMA_FILE, VaultReader, resolveVaultDir } from './vault.js'
import {
  ACCOUNT_NOTES_DESCRIPTION,
  ADD_ACCOUNT_SPEC,
  ADD_CHARGES_SPEC,
  ADD_COMMITMENTS_SPEC,
  ADD_MEMBER_SPEC,
  AMOUNT_DESCRIPTION,
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
  addAccount,
  addCharges,
  addCommitments,
  addMember,
  cancelCommitment,
  deleteCommitment,
  deleteTag,
  markPaid,
  promoteToRecurring,
  removeChargesTool,
  renameTag,
  setPlannedCount,
  updateAccount,
  updateCharge,
  updateCommitment,
  updateMember,
} from './writeTools.js'
import { REPORTS_SPEC, reports } from './reportRead.js'
import { LIST_DOCUMENTS_SPEC, READ_DOCUMENT_SPEC, listDocuments, readDocument } from './documents.js'
import { LEAVE_INSIGHT_SPEC, leaveInsight } from './insightWrite.js'
import {
  CREATE_REPORT_SPEC,
  REPORT_END_DESCRIPTION,
  REPORT_START_DESCRIPTION,
  REPORT_TITLE_DESCRIPTION,
  createReport,
} from './reportRequest.js'
import {
  accounts,
  cashflow,
  charges,
  commitments,
  members,
  nextPayment,
  search,
  spendingByAccount,
  spendingByCategory,
  spendingByMember,
  tags,
  upcoming,
} from './tools.js'

// The SDK lists a tool's fields only when it sees an object's shape, and a bare
// .default({}) hides them all; the shape rides along so the listing names every field.
// Every field these tools take is optional, so {} is always valid.
const optionalArgs = <T extends z.ZodRawShape>(shape: T) =>
  Object.assign(z.object(shape).default({} as never), { shape })

const WRITES = new Set<string>(PROPOSAL_KINDS)
const guideKeyArg = z.string().trim().max(200).optional().describe(GUIDE_KEY_SCHEMA.description)

/** The write's schema with guide_key beside its own fields, defaulted or not. */
function withGuideKey<C extends { inputSchema?: unknown }>(config: C): C {
  const schema = config.inputSchema
  if (schema instanceof z.ZodDefault && 'shape' in schema) {
    return { ...config, inputSchema: optionalArgs({ ...(schema.shape as z.ZodRawShape), guide_key: guideKeyArg }) }
  }
  if (schema instanceof z.ZodObject) return { ...config, inputSchema: schema.extend({ guide_key: guideKeyArg }) }
  return config
}

// Names, titles and descriptions come from catalog.ts — the hosted server offers the
// same words, so the words live once.
const spec = (name: string) => {
  const found = TOOLS.find((t) => t.name === name)
  if (!found) throw new Error(`no catalog entry for tool ${name}`)
  return {
    title: found.title,
    description: found.description,
    annotations: found.annotations,
    ...(found._meta ? { _meta: found._meta } : {}),
  }
}

export function buildServer(reader: VaultReader): McpServer {
  // A missing or unreadable vault answers null here; the tools say what is wrong.
  const safeLoad = () => {
    try {
      return reader.load()
    } catch {
      return null
    }
  }
  // Named apart from the hosted twin on purpose: an owner who followed both connect
  // prompts has two longbooks in one client, and must be able to tell which is which.
  const server = new McpServer(
    { name: 'longbook (this Mac)', version: RELEASE_VERSION },
    { instructions: instructionsFor(safeLoad()) },
  )
  const registerTool = ((name: string, config: Parameters<McpServer['registerTool']>[1], cb: never) =>
    server.registerTool(name, titled(WRITES.has(name) ? withGuideKey(config) : config), WRITES.has(name) ? guided(cb) : cb)) as McpServer['registerTool']

  // A write lists guide_key, and its answer says beside the result when the key is missing or wrong.
  const guided = (cb: (args: Record<string, unknown>, extra: unknown) => unknown) =>
    (async (args: Record<string, unknown>, extra: unknown) => {
      const { guide_key: _key, ...rest } = args ?? {}
      const result = (await cb(rest, extra)) as { content: { type: 'text'; text: string }[]; isError?: boolean }
      let llms = LLMS_TXT
      try {
        llms = reader.readContractFile(LLMS_FILE)
      } catch {}
      const guide_warning = guideWarning(llms, args ?? {})
      if (!guide_warning || result.isError) return result
      const said = JSON.parse(result.content[0]!.text) as unknown
      if (!isRecord(said)) return result
      return { ...result, content: [{ type: 'text' as const, text: JSON.stringify({ ...said, guide_warning }, null, 2) }] }
    }) as never

  // Tool answers are computed fresh against the file on disk, so an edit made in the
  // app between two questions is already in the second answer.
  const answer = (compute: () => unknown) => {
    try {
      return { content: [{ type: 'text' as const, text: JSON.stringify(compute(), null, 2) }] }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error)
      return { content: [{ type: 'text' as const, text: message }], isError: true }
    }
  }

  registerTool(
    'next_payment',
    {
      ...spec('next_payment'),
    },
    () => answer(() => nextPayment(reader.load())),
  )

  registerTool(
    'upcoming',
    {
      ...spec('upcoming'),
      inputSchema: optionalArgs({ days: z.number().int().min(1).max(365).default(30) }),
    },
    ({ days }) => answer(() => upcoming(reader.load(), days)),
  )

  registerTool(
    'cashflow',
    {
      ...spec('cashflow'),
      inputSchema: optionalArgs({
        currency: z.string().trim().toUpperCase().length(3).optional(),
        months_back: z.number().int().min(0).max(24).default(0),
        months_forward: z.number().int().min(0).max(24).default(12),
      }),
    },
    ({ currency, months_back, months_forward }) =>
      answer(() => cashflow(reader.load(), months_back, months_forward, currency)),
  )

  registerTool(
    'spending_by_category',
    { ...spec('spending_by_category'), inputSchema: optionalArgs({ from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(), to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional() }) },
    ({ from, to }) => answer(() => spendingByCategory(reader.load(), from, to)),
  )

  registerTool(
    'spending_by_account',
    { ...spec('spending_by_account'), inputSchema: optionalArgs({ from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(), to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional() }) },
    ({ from, to }) => answer(() => spendingByAccount(reader.load(), from, to)),
  )

  registerTool(
    'spending_by_person',
    { ...spec('spending_by_person'), inputSchema: optionalArgs({ from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(), to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional() }) },
    ({ from, to }) => answer(() => spendingByMember(reader.load(), from, to)),
  )

  registerTool(
    'charges',
    {
      ...spec('charges'),
      inputSchema: optionalArgs({
        id: z.string().optional(),
        name: z.string().optional(),
        from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
        to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
        paid: z.boolean().optional(),
      }),
    },
    (args) => answer(() => charges(reader.load(), args)),
  )

  registerTool(
    'commitments',
    {
      ...spec('commitments'),
      inputSchema: optionalArgs({ status: z.enum(['active', 'paused', 'cancelled', 'all']).default('active') }),
    },
    ({ status }) => answer(() => commitments(reader.load(), status)),
  )

  registerTool(
    'search',
    {
      ...spec('search'),
      inputSchema: z.object({ query: z.string().trim().min(1) }),
    },
    ({ query }) => answer(() => search(reader.load(), query)),
  )

  // The app's own signing names are the app's alone to write: a client wearing one
  // signs as the door, so its rows still stand for review on every device.
  const APP_NAMES = new Set(['longbook-phone', 'longbook-mac', 'longbook-ios'])
  // Provenance names who asked: the client the owner connected, as its initialize
  // handshake introduced itself. Registered here and only here — never in catalog.ts
  // or rpc.ts, so the hosted engine cannot carry a write path.
  // Signed as Changes shows it: known AIs by the hosted door's names, others as given.
  const editedBy = () => {
    const name = (server.server.getClientVersion()?.name ?? '').trim()
    const lower = name.toLowerCase()
    if (!name || APP_NAMES.has(lower)) return 'mcp'
    if (lower.includes('claude') || lower.includes('anthropic')) return 'Claude'
    if (lower.includes('chatgpt') || lower.includes('openai')) return 'ChatGPT'
    if (lower.includes('gemini')) return 'Gemini'
    if (lower.includes('cursor')) return 'Cursor'
    return name
  }

  const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/)
  // Where the data came from — a document path or a mail id — kept in _provenance.source.
  const source = z.string().trim().min(1).max(200).optional()
  // An amount's bounds are the shared checks' to judge, so both doors refuse in one sentence; zod
  // would answer first in its own words. The listing states them in the description instead.
  // A custom cycle's days are held the same way.
  const amount = z.number().describe(AMOUNT_DESCRIPTION)
  const cycleDays = z.number().describe(CUSTOM_DAYS_DESCRIPTION)
  // The commitment, account and member writes pass keys they do not list rather than strip
  // them, so a caller's details or card_name meet the refusal both doors give by name, and
  // neither door lists either.
  const rowSchema = z.object({
    name: z.string().trim().min(1),
    amount,
    currency: z.string().trim().regex(/^[A-Za-z]{3}$/),
    billing_cycle: z.enum(['monthly', 'yearly', 'custom', 'once']),
    custom_cycle_days: cycleDays.optional(),
    first_charge: day.optional(),
    date: day.optional(),
    plan_months: z.number().int().min(1).max(600).optional(),
    plan_count: z.number().int().min(1).max(PLANNED_COUNT_CEILING).optional().describe('How many charges to write for a recurring commitment, counted from first_charge — 240 at most. When given, plan_months is not read.'),
    ends_on: day.optional(),
    status: z.enum(['active', 'paused', 'cancelled']).optional(),
    paid: z.boolean().optional(),
    paid_on: day.optional(),
    basis: z.enum(['statement', 'user', 'email', 'plan']).optional(),
    direction: z.enum(['in', 'out', 'transfer']).optional().describe(DIRECTION_DESCRIPTION),
    note: z.string().max(300).optional(),
    tag: z.string().optional(),
    notes: z.string().optional().describe(NOTES_DESCRIPTION),
    member: z.string().optional(),
    account: z.string().optional(),
  }).passthrough()
  // The day the money moved and a charge's note: null clears either.
  const paidOn = day.nullable().optional().describe('The day the money moved, when it was not the due date. Null clears.')
  const chargeNote = z.string().max(300).nullable().optional().describe('A word about this one charge. Null clears.')

  registerTool(
    'add_commitments',
    {
      ...ADD_COMMITMENTS_SPEC,
      inputSchema: z.object({ rows: z.array(rowSchema).min(1).max(200), source: source }),
    },
    (args) => answer(() => addCommitments(reader.dir, editedBy(), args)),
  )

  registerTool(
    'update_commitment',
    {
      ...UPDATE_COMMITMENT_SPEC,
      inputSchema: z.object({
        id: z.string().optional(),
        name: z.string().optional(),
        source: source,
        set: z.object({
          name: z.string().trim().min(1).optional(),
          amount: amount.optional(),
          from: day.optional(),
          date: day.optional(),
          currency: z.string().trim().regex(/^[A-Za-z]{3}$/).optional(),
          billing_cycle: z.enum(['monthly', 'yearly', 'custom', 'once']).optional(),
          custom_cycle_days: cycleDays.nullable().optional(),
          ends_on: day.nullable().optional(),
          status: z.enum(['active', 'paused', 'cancelled']).optional(),
          direction: z.enum(['in', 'out', 'transfer']).nullable().optional().describe(`${DIRECTION_DESCRIPTION} Null, like "out", makes it a charge.`),
          tag: z.string().nullable().optional(),
          notes: z.string().nullable().optional().describe(`${NOTES_DESCRIPTION} Rewritten as the commitment now stands, never appended to.`),
          member: z.string().nullable().optional(),
          account: z.string().nullable().optional(),
          free_trial: z.boolean().optional().describe(FREE_TRIAL_DESCRIPTION),
        }).passthrough(),
      }),
    },
    (args) => answer(() => updateCommitment(reader.dir, editedBy(), args)),
  )

  registerTool(
    'mark_paid',
    {
      ...MARK_PAID_SPEC,
      inputSchema: z.object({
        id: z.string().optional(),
        name: z.string().optional(),
        date: day,
        paid: z.boolean().default(true),
        amount: amount.optional(),
        paid_on: paidOn,
        note: chargeNote,
        source: source,
      }),
    },
    (args) => answer(() => markPaid(reader.dir, editedBy(), args)),
  )

  registerTool(
    'add_charges',
    {
      ...ADD_CHARGES_SPEC,
      inputSchema: z.object({
        id: z.string().optional(),
        name: z.string().optional(),
        charges: z.array(z.object({
          date: day,
          amount: amount.optional(),
          paid: z.boolean().optional(),
          paid_on: paidOn,
          basis: z.enum(['statement', 'user', 'email', 'plan', 'mark_paid']).optional(),
          note: chargeNote,
          currency: z.string().trim().regex(/^[A-Za-z]{3}$/).optional(),
        })).min(1).max(600),
        source: source,
      }),
    },
    (args) => answer(() => addCharges(reader.dir, editedBy(), args)),
  )

  registerTool(
    'update_charge',
    {
      ...UPDATE_CHARGE_SPEC,
      inputSchema: z.object({
        id: z.string().optional(),
        name: z.string().optional(),
        date: day.describe('The day the charge sits on.'),
        set: z.object({
          date: day.optional().describe('The day to move it to. A day that already holds a charge is refused.'),
          amount: amount.optional(),
          paid: z.boolean().optional(),
          paid_on: paidOn,
          note: chargeNote,
          and_later: z.boolean().optional().describe('Reach the unpaid planned rows after it: they follow a move a cycle apart, keeping their amounts, and take a new amount with the commitment\'s price.'),
        }).passthrough(),
        source: source,
      }),
    },
    (args) => answer(() => updateCharge(reader.dir, editedBy(), args)),
  )

  registerTool(
    'set_planned_count',
    {
      ...SET_PLANNED_COUNT_SPEC,
      inputSchema: z.object({
        id: z.string().optional(),
        name: z.string().optional(),
        count: z.number().int().min(1).max(PLANNED_COUNT_CEILING).describe('How many charges stand from today on. 240 at most.'),
        source: source,
      }),
    },
    (args) => answer(() => setPlannedCount(reader.dir, editedBy(), args)),
  )

  registerTool(
    'remove_charges',
    {
      ...REMOVE_CHARGES_SPEC,
      inputSchema: z.object({
        id: z.string().optional(),
        name: z.string().optional(),
        dates: z.array(day).min(1).max(600),
        source: source,
      }),
    },
    (args) => answer(() => removeChargesTool(reader.dir, editedBy(), args)),
  )

  registerTool(
    'promote_to_recurring',
    {
      ...PROMOTE_SPEC,
      inputSchema: z.object({
        ids: z.array(z.string().trim().min(1)).min(1).max(200),
        billing_cycle: z.enum(['monthly', 'yearly', 'custom']),
        custom_cycle_days: cycleDays.optional(),
        plan_months: z.number().int().min(1).max(600).optional(),
        ends_on: day.optional(),
        name: z.string().trim().min(1).optional(),
        tag: z.string().nullable().optional(),
        member: z.string().nullable().optional(),
        account: z.string().nullable().optional(),
        notes: z.string().nullable().optional().describe(NOTES_DESCRIPTION),
        source: source,
      }).passthrough(),
    },
    (args) => answer(() => promoteToRecurring(reader.dir, editedBy(), args)),
  )

  registerTool(
    'reports',
    {
      ...REPORTS_SPEC,
      inputSchema: optionalArgs({ id: z.string().trim().min(1).optional() }),
    },
    (args) => answer(() => reports(reader.dir, args)),
  )

  registerTool(
    'list_documents',
    { ...LIST_DOCUMENTS_SPEC },
    () => answer(() => listDocuments(reader.dir)),
  )

  registerTool(
    'read_document',
    {
      ...READ_DOCUMENT_SPEC,
      inputSchema: z.object({
        name: z.string().trim().min(1),
        offset: z.number().int().nonnegative().optional(),
      }),
    },
    async (args) => {
      try {
        const result = await readDocument(reader.dir, args)
        return { content: [{ type: 'text' as const, text: JSON.stringify(result, null, 2) }] }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error)
        return { content: [{ type: 'text' as const, text: message }], isError: true }
      }
    },
  )

  registerTool(
    'leave_insight',
    {
      ...LEAVE_INSIGHT_SPEC,
      inputSchema: z.object({
        module: z.string().trim().min(1),
        text: z.string().trim().min(1),
      }),
    },
    (args) => answer(() => leaveInsight(reader.dir, args)),
  )

  registerTool(
    'cancel_commitment',
    {
      ...CANCEL_COMMITMENT_SPEC,
      inputSchema: optionalArgs({
        id: z.string().optional(),
        name: z.string().optional(),
        source: source,
      }),
    },
    (args) => answer(() => cancelCommitment(reader.dir, editedBy(), args)),
  )

  registerTool(
    'update_account',
    {
      ...UPDATE_ACCOUNT_SPEC,
      inputSchema: z.object({
        id: z.string().optional(),
        name: z.string().optional(),
        source: source,
        set: z.object({
          name: z.string().trim().min(1).optional(),
          tag: z.string().nullable().optional(),
          balance: z.number().finite().nullable().optional(),
          balance_date: day.nullable().optional(),
          linked_to: z.string().nullable().optional().describe('The account this one is linked to — a card to the bank account that pays it — by name or id. One level only. Null clears.'),
          parent: z.string().nullable().optional().describe('An older name for linked_to, still accepted.'),
          parent_account: z.string().nullable().optional().describe('An older name for linked_to, still accepted.'),
          notes: z.string().nullable().optional().describe(ACCOUNT_NOTES_DESCRIPTION),
          member: z.string().nullable().optional().describe('The person the account belongs to, by name or id. Null or "" clears.'),
        }).passthrough(),
      }),
    },
    (args) => answer(() => updateAccount(reader.dir, editedBy(), args)),
  )

  registerTool(
    'update_person',
    {
      ...UPDATE_MEMBER_SPEC,
      inputSchema: z.object({
        id: z.string().optional(),
        name: z.string().optional(),
        source: source,
        set: z.object({
          name: z.string().trim().min(1).optional(),
          email: z.string().nullable().optional(),
          tag: z.string().nullable().optional().describe('Their role in the owner\'s finances — a member tag: family, household help, landlord. Null or "" clears.'),
        }).passthrough(),
      }),
    },
    (args) => answer(() => updateMember(reader.dir, editedBy(), args)),
  )

  registerTool(
    'add_person',
    {
      ...ADD_MEMBER_SPEC,
      inputSchema: z.object({
        name: z.string().trim().min(1).describe('The name, as the owner said it. Refused when another person already wears it.'),
        tag: z.string().optional().describe('Their role in the owner\'s finances — a member tag: family, household help, landlord.'),
        email: z.string().optional().describe('Where a shared report reaches them.'),
        source: source,
      }).passthrough(),
    },
    (args) => answer(() => addMember(reader.dir, editedBy(), args)),
  )

  registerTool(
    'add_account',
    {
      ...ADD_ACCOUNT_SPEC,
      inputSchema: z.object({
        name: z.string().trim().min(1).describe('The display name — "Visa 9292", the last four digits at most. Refused when another account already wears it.'),
        tag: z.string().optional().describe('The account type, in the app\'s own words — "credit card", "bank account", "UPI", "wallet", "cash".'),
        linked_to: z.string().optional().describe('The account this one is linked to — a card to the bank account that pays it — by name or id. One level only.'),
        member: z.string().optional().describe('The person the account belongs to, by name or id as the memory holds them.'),
        notes: z.string().optional().describe(ACCOUNT_NOTES_DESCRIPTION),
        balance: z.number().finite().optional().describe('What the account held on balance_date.'),
        balance_date: day.optional().describe('The day the balance was true. Left out beside a balance, the day of the write is used.'),
        source: source,
      }).passthrough(),
    },
    (args) => answer(() => addAccount(reader.dir, editedBy(), args)),
  )

  registerTool(
    'rename_tag',
    {
      ...RENAME_TAG_SPEC,
      inputSchema: z.object({
        kind: z.enum(TAG_KINDS).describe('Which list the tag belongs to.'),
        from: z.string().trim().min(1).describe('The tag as the vault holds it, any casing.'),
        to: z.string().trim().min(1).describe('The new name, in the owner\'s words.'),
        source: source,
      }),
    },
    (args) => answer(() => renameTag(reader.dir, editedBy(), args)),
  )

  registerTool(
    'delete_tag',
    {
      ...DELETE_TAG_SPEC,
      inputSchema: z.object({
        kind: z.enum(TAG_KINDS).describe('Which list the tag belongs to.'),
        name: z.string().trim().min(1).describe('The tag as the vault holds it, any casing.'),
        source: source,
      }),
    },
    (args) => answer(() => deleteTag(reader.dir, editedBy(), args)),
  )

  registerTool(
    'delete_commitment',
    {
      ...DELETE_COMMITMENT_SPEC,
      inputSchema: z.object({
        id: z.string().trim().min(1).describe('The commitment id, from commitments or search. By id only, never by name.'),
        source: source,
      }),
    },
    (args) => answer(() => deleteCommitment(reader.dir, editedBy(), args)),
  )

  // Loose on purpose, as the amounts are: the shared check judges every field and refuses a
  // key longbook draws itself in one sentence on both doors, so zod passes them through.
  const scopeNames = (what: string) =>
    z.array(z.string()).nullish().describe(`${what}, each by name as the memory holds it. Left out or empty: all of them.`)
  registerTool(
    'create_report',
    {
      ...CREATE_REPORT_SPEC,
      inputSchema: z.object({
        title: z.string().describe(REPORT_TITLE_DESCRIPTION),
        start_date: z.string().describe(REPORT_START_DESCRIPTION),
        end_date: z.string().describe(REPORT_END_DESCRIPTION),
        accounts: scopeNames('The accounts the report covers, or "No account" for charges billed to none'),
        members: scopeNames('The people the report covers'),
        categories: scopeNames('The categories the report covers, or "No category" for untagged charges'),
        source: source,
      }).passthrough(),
    },
    (args) => answer(() => createReport(reader.dir, editedBy(), args)),
  )

  registerTool(
    'read_guide',
    {
      ...spec('read_guide'),
      inputSchema: optionalArgs({ section: z.string().optional() }),
    },
    (args) => answer(() => readGuide(reader.readContractFile(LLMS_FILE), args.section)),
  )

  registerTool('tags', { ...spec('tags') }, () => answer(() => tags(reader.load())))

  registerTool('accounts', { ...spec('accounts') }, () => answer(() => accounts(reader.load())))

  registerTool('people', { ...spec('people') }, () => answer(() => members(reader.load())))

  // The same answer the hosted door gives, from this machine's side: this server writes
  // the file itself, so "can_write" is true and there is no key or inbox to speak of.
  registerTool('whoami', { ...spec('whoami') }, () =>
    answer(() =>
      whoami({
        loadData: safeLoad,
        llmsText: () => reader.readContractFile(LLMS_FILE),
        schemaText: () => reader.readContractFile(SCHEMA_FILE),
        writeMode: 'direct',
        identity: () => ({
          server: 'longbook (this Mac)',
          vault: reader.dir,
          connected_as: editedBy(),
          writes: 'straight to the folder — every batch lands in the app\'s Changes screen for review',
        }),
      }),
    ),
  )

  // longbook's prompts, the hosted door's menu word for word: a month argument only where
  // the prompt's words name a month.
  for (const prompt of MCP_PROMPTS) {
    const message = (month?: string) => {
      const got = mcpPromptMessage(prompt.name, month)
      if (!got) throw new Error(`no catalogue entry for prompt ${prompt.name}`)
      return got
    }
    if (prompt.arguments) {
      server.registerPrompt(
        prompt.name,
        {
          title: prompt.title,
          description: prompt.description,
          argsSchema: { month: z.string().optional().describe(MONTH_ARGUMENT_DESCRIPTION) },
        },
        ({ month }) => message(month),
      )
    } else {
      server.registerPrompt(prompt.name, { title: prompt.title, description: prompt.description }, () => message())
    }
  }
  // The SDK reads a month prompt's arguments as a required object, so a client that leaves the
  // optional month out was refused. prompts/get is answered here instead, as the hosted door
  // answers it, with the month in progress taken from this machine's calendar.
  server.server.setRequestHandler(GetPromptRequestSchema, (request) => {
    const got = mcpPromptMessage(request.params.name, request.params.arguments?.month, new Date(), (day) => day.getMonth())
    if (!got) {
      throw new McpError(ErrorCode.InvalidParams, `No prompt named ${request.params.name}. Prompts: ${MCP_PROMPTS.map((p) => p.name).join(', ')}`)
    }
    return got
  })

  server.registerResource(
    'llms',
    `longbook://vault/${LLMS_FILE}`,
    {
      title: 'How to read this memory',
      description: "The vault's own llms.txt — the contract any AI reading these files follows.",
      mimeType: 'text/plain',
    },
    (uri) => ({
      contents: [{ uri: uri.href, mimeType: 'text/plain', text: reader.readContractFile(LLMS_FILE) }],
    }),
  )

  server.registerResource(
    'schema',
    `longbook://vault/${SCHEMA_FILE}`,
    {
      title: 'Financial memory schema',
      description: 'The JSON Schema the financial memory file conforms to.',
      mimeType: 'application/json',
    },
    (uri) => ({
      contents: [{ uri: uri.href, mimeType: 'application/json', text: reader.readContractFile(SCHEMA_FILE) }],
    }),
  )

  server.registerResource(
    RESOURCE_LIBRARY.name,
    RESOURCE_LIBRARY.uri,
    { title: RESOURCE_LIBRARY.title, description: RESOURCE_LIBRARY.description, mimeType: RESOURCE_LIBRARY.mimeType },
    (uri) => ({
      contents: [{ uri: uri.href, mimeType: RESOURCE_LIBRARY.mimeType, text: reader.readContractFile(LIBRARY_FILE) }],
    }),
  )

  // The cards: each read renders the memory as it stands, one self-contained HTML
  // file per view — @longbook/cards over the same tools, no second arithmetic.
  const renderers: [uri: string, render: () => string][] = [
    ['ui://longbook/next-payment.html', () => nextPaymentCard(nextPayment(reader.load()))],
    ['ui://longbook/upcoming.html', () => upcomingStrip(upcoming(reader.load(), 30))],
    ['ui://longbook/cashflow.html', () => cashflowChart(cashflow(reader.load(), 0, 12))],
    ['ui://longbook/commitments.html', () => commitmentsList(commitments(reader.load(), 'active'))],
  ]
  for (const [uri, render] of renderers) {
    const card = CARD_RESOURCES.find((c) => c.uri === uri)
    if (!card) throw new Error(`no catalog entry for card ${uri}`)
    server.registerResource(
      card.name,
      card.uri,
      { title: card.title, description: card.description, mimeType: card.mimeType },
      (resourceUri) => {
        let html: string
        try {
          html = render()
        } catch (error) {
          html = messageCard(error instanceof Error ? error.message : String(error))
        }
        return { contents: [{ uri: resourceUri.href, mimeType: card.mimeType, text: html }] }
      },
    )
  }

  return server
}

async function main() {
  let reader: VaultReader
  try {
    reader = new VaultReader(resolveVaultDir())
  } catch (error) {
    // A usage error — a --vault flag with no value — still refuses loudly.
    console.error(error instanceof Error ? error.message : String(error))
    process.exit(1)
  }
  try {
    reader.load()
  } catch (error) {
    // A missing or unreadable vault is a conversation, not a crash: the server stays
    // up and every tool answers with what is wrong and how to fix it.
    console.error(error instanceof Error ? error.message : String(error))
  }
  await buildServer(reader).connect(new StdioServerTransport())
}

// npx starts the server through a link in node_modules/.bin, so compare the file the link names.
if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  void main()
}
