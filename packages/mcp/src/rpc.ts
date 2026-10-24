// The MCP method surface as one pure function: a JSON-RPC message in, a response out,
// storage behind a tiny context. The stdio server speaks through the SDK; the hosted
// server speaks through this, so both answer with the same arithmetic.
import { nameKey, toISO, todayMid } from '@longbook/core'
import type { LoadedData } from '@longbook/core'
import {
  cashflowChart,
  commitmentsList,
  messageCard,
  nextPaymentCard,
  upcomingStrip,
} from '@longbook/cards'
import { LIBRARY_JSON, RELEASE_VERSION, WHOLE_GUIDE, contractRevisionOf, findPrompt, guideKey, guideSection, guideSections, promptGuideKey } from '@longbook/core'
import { CARD_RESOURCES, RESOURCE_LIBRARY, RESOURCE_LLMS, RESOURCE_SCHEMA, TOOLS, instructionsFor, titled } from './catalog.js'
import { MCP_PROMPTS, mcpPromptMessage } from './prompts.js'
import { VaultWriteError } from './errors.js'
import { guideWarning } from './guideCheck.js'
import { failure } from './failure.js'
import type { Failure, FailureCode } from './failure.js'
import { WRITE_TOOLS, checkProposal, entitySetOutcome, setOutcome, canonicalToolName } from './proposal.js'
import type { ChargeInput, CommitmentRowInput, Proposal } from './proposal.js'
import { TARGETED_KINDS, TargetMiss, addressedCommitment, checkTargets } from './targets.js'
import {
  accounts,
  balanceNoteFor,
  cashflow,
  charges,
  commitments,
  members,
  nextPayment,
  search,
  spendingByAccount,
  spendingByCategory,
  spendingByMember,
  staleBalance,
  tags,
  upcoming,
} from './tools.js'
import type { StatusFilter } from './tools.js'

/** What a proposal door answers: the entry the owner's app will apply, or an existing one. */
export interface ProposeResult {
  entry_id: string
  created: boolean
  pending_count?: number
}

export interface RpcContext {
  /** The memory to answer from, or null when no hosted copy exists yet. */
  loadData: () => LoadedData | null
  /**
   * The names waiting in to_fill_in, for a door that answers a handshake without loading
   * the memory, so initialize still says them. Unneeded where loadData carries the memory.
   */
  toFillIn?: () => LoadedData['toFillIn']
  llmsText: () => string
  schemaText: () => string
  /** The day the arithmetic answers from. Tests pin it; live servers omit it. */
  today?: () => Date
  /** The tag library; the bundled copy when a host does not supply one. */
  libraryText?: () => string
  /** Who this connection is and what it may do — the whoami answer, minus the tags. */
  identity?: () => Record<string, unknown>
  /**
   * Where a write goes. Absent means this door offers no write tools at all, which is
   * how a read-only connection stays read-only: they never appear in tools/list.
   */
  propose?: (proposal: Proposal) => ProposeResult | Promise<ProposeResult>
  /**
   * How writes reach the memory here: "direct" is the local server writing the file
   * itself, "proposal" is the hosted door filing for the app. whoami says which.
   */
  writeMode?: 'direct' | 'proposal'
  /** Why this connection cannot write, in the owner's words, when it cannot. */
  whyReadOnly?: () => string
  /** What the owner would do to let it — named so the agent can ask for it by name. */
  howToEnable?: () => string
}

export const WHY_READ_ONLY = {
  unknown: 'This connection may read, not write.',
  oauth: 'This is a signed-in web connection, and suggestions from the web are switched off.',
  key: 'This key may read, not suggest changes.',
}

/** Where the owner turns writing on: the Automations screen, More on iPhone, Settings on the Mac. */
const AUTOMATIONS_SCREEN = 'the Automations screen (More on iPhone, Settings on the Mac)'

export const HOW_TO_ENABLE = {
  unknown: `In the longbook app, open ${AUTOMATIONS_SCREEN} — the box "Let signed-in AIs suggest changes", or a key with "Read and suggest changes".`,
  oauth: `In the longbook app, open ${AUTOMATIONS_SCREEN} — the box "Let signed-in AIs suggest changes".`,
  key: `In the longbook app, open ${AUTOMATIONS_SCREEN} and make a key with "Read and suggest changes".`,
}

/**
 * The guide whole, or one chapter, or one of longbook's prompts — named by its id or the
 * owner's words — with its procedure and the chapter it builds on from the guide in hand.
 * An unknown name answers with the chapter list.
 */
export function readGuide(llms: string, section: unknown): unknown {
  const revision = contractRevisionOf(llms)
  const all = guideSections(llms)
  const sections = all.map((s) => ({ id: s.id, title: s.title }))
  if (section === undefined || section === null || section === '') {
    return { revision, sections, text: llms, guide_key: guideKey(WHOLE_GUIDE, revision, llms) }
  }
  if (typeof section !== 'string') throw new RangeError('section must be a chapter id or a word from its title')
  const prompt = findPrompt(section)
  if (prompt) {
    const chapter = prompt.chapter ? all.find((s) => s.id === prompt.chapter) : undefined
    return {
      revision,
      prompt: prompt.id,
      title: prompt.title,
      says: prompt.phrases,
      attachments: prompt.attachments,
      result: prompt.result,
      needs: prompt.needs ?? [],
      procedure: prompt.procedure.join('\n'),
      chapter: chapter ? { id: chapter.id, title: chapter.title, text: chapter.text } : null,
      guide_key: promptGuideKey(prompt, revision),
    }
  }
  const found = guideSection(llms, section)
  if (!found) {
    throw new RangeError(`No chapter matches "${section}". Chapters: ${sections.map((s) => s.id).join(', ')}`)
  }
  return { revision, section: found.id, title: found.title, text: found.text, guide_key: guideKey(found.id, revision, found.text) }
}

interface RpcMessage {
  jsonrpc?: string
  id?: number | string | null
  method?: string
  params?: Record<string, unknown>
}

const PROTOCOLS = ['2025-06-18', '2025-03-26', '2024-11-05']

// The same four renderers the stdio server serves — no second arithmetic.
const CARD_RENDER: Record<string, (data: LoadedData, today: Date) => string> = {
  'ui://longbook/next-payment.html': (d, t) => nextPaymentCard(nextPayment(d, t)),
  'ui://longbook/upcoming.html': (d, t) => upcomingStrip(upcoming(d, 30, t)),
  'ui://longbook/cashflow.html': (d, t) => cashflowChart(cashflow(d, 0, 12, undefined, t)),
  'ui://longbook/commitments.html': (d, t) => commitmentsList(commitments(d, 'active', t)),
}

const NO_COPY_MESSAGE =
  'No hosted copy of your financial memory exists yet. Turn on the MCP server switch in the longbook app, then ask again.'

const result = (id: RpcMessage['id'], value: unknown) => ({ jsonrpc: '2.0', id: id ?? null, result: value })

/** A refusal an unattended agent can act on: the code and the advice ride in the text. */
const toolFailure = (id: RpcMessage['id'], code: FailureCode, message: string, extra: Record<string, unknown> = {}) =>
  result(id, {
    content: [{ type: 'text', text: JSON.stringify({ error: failure(code, message, extra) }, null, 2) }],
    isError: true,
  })
const rpcError = (id: RpcMessage['id'], code: number, message: string) => ({
  jsonrpc: '2.0',
  id: id ?? null,
  error: { code, message },
})

const answer = (id: RpcMessage['id'], compute: () => unknown) => {
  try {
    return result(id, {
      content: [{ type: 'text', text: JSON.stringify(compute(), null, 2) }],
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return result(id, { content: [{ type: 'text', text: message }], isError: true })
  }
}

function dayArg(args: Record<string, unknown>, name: string): string | undefined {
  const v = args[name]
  if (v === undefined) return undefined
  if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v)) throw new RangeError(`${name} must be a YYYY-MM-DD day`)
  return v
}

function intArg(args: Record<string, unknown>, name: string, fallback: number, min: number, max: number): number {
  const v = args[name]
  if (v === undefined) return fallback
  if (typeof v !== 'number' || !Number.isInteger(v) || v < min || v > max) {
    throw new RangeError(`${name} must be an integer between ${min} and ${max}`)
  }
  return v
}

/** When the copy was last pushed, as the door's identity states it; null when unknown. */
function pushedAtOf(ctx: RpcContext): string | null {
  const copy = ctx.identity?.()?.hosted_copy
  if (typeof copy !== 'object' || copy === null) return null
  const pushed = (copy as Record<string, unknown>).pushed_at
  return typeof pushed === 'string' ? pushed : null
}

/**
 * The balance_note the local door's add_commitments and add_charges answer with, read from
 * the copy and the payload: the confirmed day each row writes, by the account it bills to.
 * A recurring row's charges are all plan; an account the copy lacks holds no balance.
 */
function writtenBalanceNote(proposal: Proposal, data: LoadedData | null, today: Date): string | undefined {
  if (!data) return undefined
  const limit = toISO(today)
  const newest = new Map<string, string>()
  const written = (accountId: string | null | undefined, date: unknown, basis: string) => {
    if (!accountId || typeof date !== 'string' || basis === 'plan' || date > limit) return
    if ((newest.get(accountId) ?? '') < date) newest.set(accountId, date)
  }
  if (proposal.kind === 'add_commitments') {
    for (const row of proposal.payload.rows as CommitmentRowInput[]) {
      if (row.billing_cycle !== 'once' || !row.account?.trim()) continue
      const account = data.methods.find((m) => m.name_key === nameKey(row.account!))
      written(account?.id, row.date ?? row.first_charge, row.basis ?? (row.paid ? 'user' : 'plan'))
    }
  } else if (proposal.kind === 'add_charges') {
    const sub = addressedCommitment(proposal.payload, data)
    for (const c of proposal.payload.charges as ChargeInput[]) {
      written(sub?.account_id, c.date, c.basis ?? (c.paid || c.amount !== undefined ? 'user' : 'plan'))
    }
  }
  return balanceNoteFor(data.methods, newest)
}

/** A report request reaches no review: the app draws the report, on its Reports screen. */
export const REPORT_FILED_NOTE =
  'Filed. longbook draws the report on its Reports screen the next time the owner opens the app — tell them so, and stop here. A report is drawn from the rows; nothing waits in Changes.'

/** A write, held to the shared contract and then handed to whichever door this is. */
async function callWrite(name: string, args: Record<string, unknown>, ctx: RpcContext, id: RpcMessage['id']) {
  if (!ctx.propose) {
    return toolFailure(id, 'insufficient_scope', ctx.whyReadOnly?.() ?? WHY_READ_ONLY.unknown, {
      scope: 'memory:propose',
      how_to_enable: ctx.howToEnable?.() ?? HOW_TO_ENABLE.unknown,
    })
  }
  let proposal: Proposal
  try {
    // A day of slack for create_report's start: this door's clock is UTC, not the owner's.
    proposal = checkProposal(name, args, { daySlack: 1 })
  } catch (error) {
    if (error instanceof VaultWriteError) return toolFailure(id, 'validation_failed', error.message)
    throw error
  }
  // A write that addresses a row is held to the copy before it is filed: what the app
  // would refuse at apply time is refused here, with the real names to correct it.
  let ignored: string[] = []
  if (TARGETED_KINDS.has(proposal.kind)) {
    const data = ctx.loadData()
    if (!data) return toolFailure(id, 'not_found', NO_COPY_MESSAGE)
    try {
      checkTargets(proposal, data, pushedAtOf(ctx))
    } catch (error) {
      if (error instanceof TargetMiss) return toolFailure(id, error.code, error.message, error.extra)
      throw error
    }
    // Keys an update's set carries that the app will not apply, named as the Mac door names them.
    if (proposal.kind === 'update_commitment') {
      const set = proposal.payload.set as Record<string, unknown>
      const row = addressedCommitment(proposal.payload, data)
      const held = (data.charges ?? []).filter((c) => c.commitment_id === row?.id).length
      ignored = setOutcome(set, set.billing_cycle ?? row?.billing_cycle, held).ignored
    } else if (proposal.kind === 'update_account' || proposal.kind === 'update_person') {
      ignored = entitySetOutcome(proposal.kind, proposal.payload.set as object).ignored
    }
  }
  const guide_warning = guideWarning(ctx.llmsText(), args)
  // Said beside the filing, as the local door says it: the balance the rows just written outrun.
  const balance_note = proposal.kind === 'add_commitments' || proposal.kind === 'add_charges'
    ? writtenBalanceNote(proposal, ctx.loadData(), ctx.today?.() ?? todayMid())
    : undefined
  try {
    const out = await ctx.propose(proposal)
    return answer(id, () => ({
      ...out,
      ...(ignored.length > 0 ? { ignored } : {}),
      ...(balance_note ? { balance_note } : {}),
      ...(guide_warning ? { guide_warning } : {}),
      note: !out.created
        ? 'This exact write was already filed, so nothing was added again.'
        : proposal.kind === 'create_report'
          ? REPORT_FILED_NOTE
          : 'Filed for review. It reaches the owner\'s Changes screen the next time they open longbook — tell them so, and stop here.'
            + (proposal.kind === 'add_commitments' ? ' A recurring row is planned plan_months ahead, 24 when unsaid: say so, and that the owner can change any charge, or ask you to.' : ''),
    }))
  } catch (error) {
    if (error instanceof RpcFailure) return toolFailure(id, error.code, error.message, error.extra)
    if (error instanceof VaultWriteError) return toolFailure(id, 'validation_failed', error.message)
    return toolFailure(id, 'upstream_error', error instanceof Error ? error.message : String(error))
  }
}

async function callTool(rawName: string, args: Record<string, unknown>, ctx: RpcContext, id: RpcMessage['id']) {
  // A client holding last revision's names is still answered.
  const name = canonicalToolName(rawName)
  const isWrite = WRITE_TOOLS.some((t) => t.name === name)
  if (!TOOLS.some((t) => t.name === name) && !isWrite) return rpcError(id, -32602, `unknown tool: ${name}`)
  // The guide and identity need no memory: they answer before a hosted copy exists.
  if (name === 'read_guide') return answer(id, () => readGuide(ctx.llmsText(), args.section))
  if (name === 'whoami') return answer(id, () => whoami(ctx))
  if (isWrite) return callWrite(name, args, ctx, id)
  const data = ctx.loadData()
  // Typed, not a cheerful empty answer: an agent that reads "no rows" as "an empty
  // ledger" proposes adding everything the owner already has.
  if (!data) return toolFailure(id, 'not_found', NO_COPY_MESSAGE)
  const today = ctx.today?.() ?? todayMid()

  switch (name) {
    case 'next_payment':
      return answer(id, () => nextPayment(data, today))
    case 'upcoming': {
      const days = intArg(args, 'days', 30, 1, 365)
      return answer(id, () => upcoming(data, days, today))
    }
    case 'cashflow': {
      const back = intArg(args, 'months_back', 0, 0, 24)
      const forward = intArg(args, 'months_forward', 12, 0, 24)
      const currency = args.currency
      if (currency !== undefined && (typeof currency !== 'string' || currency.trim().length !== 3)) {
        throw new RangeError('currency must be a three-letter code')
      }
      return answer(id, () => cashflow(data, back, forward, currency?.trim().toUpperCase(), today))
    }
    case 'spending_by_category':
      return answer(id, () => spendingByCategory(data, dayArg(args, 'from'), dayArg(args, 'to'), today))
    case 'spending_by_account':
      return answer(id, () => spendingByAccount(data, dayArg(args, 'from'), dayArg(args, 'to'), today))
    case 'spending_by_person':
      return answer(id, () => spendingByMember(data, dayArg(args, 'from'), dayArg(args, 'to'), today))
    case 'charges': {
      const paid = args.paid
      if (paid !== undefined && typeof paid !== 'boolean') throw new RangeError('paid must be true or false')
      return answer(id, () => charges(data, {
        id: typeof args.id === 'string' ? args.id : undefined,
        name: typeof args.name === 'string' ? args.name : undefined,
        from: dayArg(args, 'from'),
        to: dayArg(args, 'to'),
        paid: paid as boolean | undefined,
      }, today))
    }
    case 'commitments': {
      const status = (args.status ?? 'active') as StatusFilter
      if (!['active', 'paused', 'cancelled', 'all'].includes(status)) {
        throw new RangeError('status must be active, paused, cancelled or all')
      }
      return answer(id, () => commitments(data, status, today))
    }
    case 'search': {
      const query = args.query
      if (typeof query !== 'string' || !query.trim()) throw new RangeError('query must be a non-empty string')
      return answer(id, () => search(data, query, today))
    }
    case 'accounts':
      return answer(id, () => accounts(data, today))
    case 'people':
      return answer(id, () => members(data, today))
    case 'tags':
      return answer(id, () => tags(data))
    default:
      return rpcError(id, -32602, `unknown tool: ${name}`)
  }
}

/** Thrown by a door that knows exactly why it refused; carried out as a typed tool error. */
export class RpcFailure extends Error {
  constructor(readonly code: FailureCode, message: string, readonly extra: Record<string, unknown> = {}) {
    super(message)
  }
}

const CLOSER_DOOR =
  "On the owner's own computer, prefer their longbook folder: the longbook app's own server " +
  'there (write_mode "direct"), or financial_memory.json by the schema beside it. Nothing ' +
  "passes through longbook's server that way. This hosted door is for when the folder is out of reach."

/**
 * One call that tells an unattended agent whether the rest of the run will work: who it
 * is, what it may do, what is left of its allowance, and where the schemas are.
 */
export function whoami(ctx: RpcContext): Record<string, unknown> {
  const data = ctx.loadData()
  const identity = ctx.identity?.() ?? {}
  const vocabulary = data ? tags(data) : null
  const canWrite = ctx.propose != null || ctx.writeMode === 'direct'
  return {
    ...identity,
    can_write: canWrite,
    write_mode: canWrite ? (ctx.writeMode ?? 'proposal') : null,
    // Named even when refused: every write tool exists, and a refusal will say why.
    write_tools: WRITE_TOOLS.map((t) => t.name),
    ...(canWrite
      ? {}
      : {
          cannot_write_because: ctx.whyReadOnly?.() ?? WHY_READ_ONLY.unknown,
          how_to_enable: ctx.howToEnable?.() ?? HOW_TO_ENABLE.unknown,
        }),
    memory: data
      ? {
          commitments: data.subs.length,
          members: data.members.length,
          accounts: data.methods.length,
          account_names: data.methods.map((m) => m.name),
          member_names: data.members.map((m) => m.name),
          // Every account whose held balance is older than its newest confirmed charge; empty when none.
          stale_balances: data.methods.flatMap((m) => {
            const stale = staleBalance(data, m, ctx.today?.() ?? todayMid())
            return stale ? [{ account: m.name, ...stale }] : []
          }),
        }
      : null,
    // A hosted door says where the better one is: the owner's own folder, when in reach.
    ...(ctx.writeMode === 'direct' ? {} : { closer_door: CLOSER_DOOR }),
    // What setup named and nobody has filled in: an agent that calls whoami first sees them.
    to_fill_in: (data?.toFillIn ?? []).map((p) => ({ name: p.name, group: p.group ?? null })),
    tags: vocabulary
      ? {
          in_vault: vocabulary.in_vault.map((t) => ({ kind: t.kind, name: t.name })),
          library: vocabulary.library.map((t) => ({ kind: t.kind, name: t.name })),
        }
      : null,
    guide: {
      revision: contractRevisionOf(ctx.llmsText()),
      read_guide: guideSections(ctx.llmsText()).map((s) => s.id),
      // read_guide answers to each prompt's name too, with its procedure.
      prompts: MCP_PROMPTS.map((p) => p.name),
      llms_txt: 'https://longbook.app/llms.txt',
      prompts_json: 'https://longbook.app/prompts.json',
      schema: 'https://longbook.app/schema/longbook.schema.json',
      library: 'https://longbook.app/library.json',
    },
  }
}

/**
 * One message in, one response out — or null for a notification, which has no answer.
 * Async because a write may travel to a proposal door; every read answers immediately.
 */
export async function handleRpc(message: unknown, ctx: RpcContext): Promise<Record<string, unknown> | null> {
  const msg = (typeof message === 'object' && message !== null ? message : {}) as RpcMessage
  const { id, method } = msg
  const params = msg.params ?? {}

  if (typeof method !== 'string') return rpcError(id, -32600, 'not a request: no method')
  if (method.startsWith('notifications/')) return null

  try {
    switch (method) {
      case 'initialize': {
        const asked = typeof params.protocolVersion === 'string' ? params.protocolVersion : ''
        // A door that skipped the memory for the handshake still hands over the names.
        const waiting = ctx.loadData() ?? (ctx.toFillIn ? { toFillIn: ctx.toFillIn() } : null)
        return result(id, {
          protocolVersion: PROTOCOLS.includes(asked) ? asked : PROTOCOLS[0],
          capabilities: { tools: {}, resources: {}, prompts: {} },
          // Distinct from the local server's name — see server.ts.
          serverInfo: { name: 'longbook (hosted)', version: RELEASE_VERSION },
          instructions: instructionsFor(waiting),
        })
      }
      case 'ping':
        return result(id, {})
      case 'tools/list':
        // Listed even where they will be refused. A tool that is merely absent teaches
        // an agent nothing; a typed refusal tells it what to ask the owner for.
        return result(id, { tools: [...TOOLS, ...WRITE_TOOLS].map(titled) })
      case 'tools/call': {
        const name = typeof params.name === 'string' ? params.name : ''
        const args = (params.arguments ?? {}) as Record<string, unknown>
        return await callTool(name, args, ctx, id)
      }
      case 'prompts/list':
        return result(id, { prompts: MCP_PROMPTS })
      case 'prompts/get': {
        const name = typeof params.name === 'string' ? params.name : ''
        const args = (params.arguments ?? {}) as Record<string, unknown>
        const got = mcpPromptMessage(name, args.month)
        if (!got) return rpcError(id, -32602, `unknown prompt: ${name}. Prompts: ${MCP_PROMPTS.map((p) => p.name).join(', ')}`)
        return result(id, got)
      }
      case 'resources/list':
        return result(id, { resources: [RESOURCE_LLMS, RESOURCE_SCHEMA, RESOURCE_LIBRARY, ...CARD_RESOURCES] })
      case 'resources/read': {
        const uri = typeof params.uri === 'string' ? params.uri : ''
        if (uri === RESOURCE_LLMS.uri) {
          return result(id, { contents: [{ uri, mimeType: RESOURCE_LLMS.mimeType, text: ctx.llmsText() }] })
        }
        if (uri === RESOURCE_SCHEMA.uri) {
          return result(id, { contents: [{ uri, mimeType: RESOURCE_SCHEMA.mimeType, text: ctx.schemaText() }] })
        }
        if (uri === RESOURCE_LIBRARY.uri) {
          const text = ctx.libraryText ? ctx.libraryText() : LIBRARY_JSON
          return result(id, { contents: [{ uri, mimeType: RESOURCE_LIBRARY.mimeType, text }] })
        }
        const renderCard = CARD_RENDER[uri]
        if (renderCard) {
          const data = ctx.loadData()
          const html = data ? renderCard(data, ctx.today?.() ?? todayMid()) : messageCard(NO_COPY_MESSAGE)
          const mime = CARD_RESOURCES.find((c) => c.uri === uri)?.mimeType ?? 'text/html'
          return result(id, { contents: [{ uri, mimeType: mime, text: html }] })
        }
        return rpcError(id, -32002, `unknown resource: ${uri}`)
      }
      default:
        return rpcError(id, -32601, `method not found: ${method}`)
    }
  } catch (error) {
    if (error instanceof RangeError) return rpcError(id, -32602, error.message)
    return rpcError(id, -32603, error instanceof Error ? error.message : String(error))
  }
}
