// What the server offers, said once: names, titles, descriptions and plain JSON
// Schemas shared by the stdio server (which pairs them with zod) and the hosted one.
import { LLMS_TXT, PROMPTS, guideSections } from '@longbook/core'
import type { LoadedData } from '@longbook/core'

export const HONESTY = 'Amounts are per-currency and never converted, blended, or amortised.'

/** The prompts' titles, quoted, for the connect-time sentence that names them. */
const PROMPT_TITLES = PROMPTS.map((p) => `"${p.title}"`).join(', ')

/** One owner's sentence that names a month, as read_guide's description shows it. */
const PROMPT_EXAMPLE = (PROMPTS.find((p) => p.template) ?? PROMPTS[0]!).phrases[0]!

// The compact working method: instructions reach the model at connect time in every
// serious client, so the load-bearing rules ride here, and read_guide holds the rest.
export const INSTRUCTIONS =
  `longbook is the owner's financial memory: every commitment — subscriptions, insurance, ` +
  `EMIs, rent, fees, salaries, one-time spends — in a folder they own. These tools return real ` +
  `arithmetic from that memory; quote the numbers, never recompute them. ${HONESTY} ` +
  `Before any write, call read_guide with the owner's prompt or the chapter for the task, ` +
  `follow it, and pass the guide_key it returns with every write. ` +
  `Every charge is a stored row, past or planned: history is exactly the rows before today, ` +
  `the plan is exactly the rows from today on, and nothing is computed from a rule. ` +
  `The working method: read first (commitments with status "all", search) and match names ` +
  `loosely; update an existing row rather than adding a twin. A statement is evidence: write ` +
  `every line that is a charge as a one-time row at its real date and amount, paid, basis ` +
  `"statement" — never skipped, never guessed into monthly — then promote_to_recurring a ` +
  `payee the statement shows at least three times, a steady month, quarter or year apart, ` +
  `still going at its end, and show it in the table; ask about the rest; plan 24 months ` +
  `unless the owner says otherwise. Where writes are proposals, the rows are not in the ` +
  `memory until the owner's app applies them: list those repeats in the table, and promote ` +
  `them after the owner answers, once commitments shows the rows. When the statement prints a closing balance, set it on the account with ` +
  `update_account — balance, and balance_date the statement's last day — after its charges are ` +
  `written. Money in — salary, a refund, interest, cashback, a dividend — is written ` +
  `too, as a one-time row with direction "in", paid, basis "statement", kept apart from ` +
  `spending; skip only movements between the owner's own accounts — card bill payments, ATM ` +
  `withdrawals, own transfers — unless the owner wants one remembered (direction "transfer", ` +
  `shown, never summed), or the memory holds that bill as a transfer row: add_charges on ` +
  `it, paid. Direction rides along a promotion. Tags from the library first; members only ` +
  `when the owner named them. When commitments answers with to_fill_in, those names come first. accounts and members list ` +
  `what the memory holds; update_account and update_person change them. Write in one batch, then ` +
  `stop and say "review it in the app's Changes screen" — the owner keeps or undoes it ` +
  `there; never loop write-review-rewrite. Never write a card number, CVV, ` +
  `expiry, PIN or credential; the validator refuses and names the row. longbook draws a ` +
  `report for every month holding a confirmed charge — one dated today or earlier whose ` +
  `basis is anything but "plan" — counting those charges alone: total expenses, accounts, ` +
  `categories, every confirmed charge. reports reads them with the comments left on them, ` +
  `so a question about a month is answered from the report and fixed in that month's rows. ` +
  `create_report asks longbook to draw one over other days, narrowed to accounts, people or ` +
  `categories; it shows on the Reports screen, never in Changes. Statements ` +
  `live in the vault's documents folder (list_documents, read_document); read_guide returns ` +
  `any chapter of llms.txt by name — "importing-statements" before an import, ` +
  `"reading-reports" before a report question, "notes" before you write one. The owner may ` +
  `give one of longbook's prompts, word for word or in their own words: ${PROMPT_TITLES}. ` +
  `read_guide with its name or the owner's words returns its procedure: follow it. A commitment's notes ` +
  `hold its three most important details, one per line as "Label: value" — for insurance the ` +
  `policy number, the policy's official name and its file in documents/ — only what the source ` +
  `states, as it now stands: rewritten, never appended. No tag has fields to fill, and details ` +
  `are longbook's own on every row: never write them. An account's card name and any other ` +
  `detail are lines of its notes; a person carries a name, a tag, an email and linked ` +
  `accounts, nothing else. A truer ` +
  `start date is a question for the owner before old charges are written. Call whoami before ` +
  `writing: failed_to_apply lists suggestions the owner's app could not apply, each with its ` +
  `reason — usually a name the memory does not hold. Fix the cause with the real names from ` +
  `commitments, accounts and members, file it again under the same idempotency_key so the ` +
  `corrected proposal replaces the failed one, and never ` +
  `resend the same payload.`

/**
 * The instructions for one connection: the working method, plus the names waiting in
 * to_fill_in when the memory holds any, so an agent knows its first job at connect time.
 */
export function instructionsFor(data: Pick<LoadedData, 'toFillIn'> | null): string {
  const waiting = data?.toFillIn ?? []
  if (waiting.length === 0) return INSTRUCTIONS
  return (
    `${INSTRUCTIONS} Waiting in to_fill_in, named by the owner without details: ` +
    `${waiting.map((p) => `“${p.name}”`).join(', ')}. These come first: search every statement for ` +
    `each one by name, loosely (a person paid on the 1st can be a salary), and write what you ` +
    `find with add_commitments under the same name. For the rest, ask the owner in one table — ` +
    `commitment | your question | your best guess — and say a spoken answer is fine. If the ` +
    `statements do not reach far enough, ask for older or longer statements before guessing.`
  )
}

/** The chapter ids read_guide answers to, from the bundled curriculum itself. */
export const GUIDE_SECTION_IDS = guideSections(LLMS_TXT).map((s) => s.id)

// Directories read a tool's display name from annotations.title, so both doors say the title there too.
export const titled = <T extends { title?: string; annotations?: Record<string, unknown> }>(tool: T): T => ({
  ...tool,
  annotations: { title: tool.title, ...tool.annotations },
})

export interface ToolSpec {
  name: string
  title: string
  description: string
  inputSchema: Record<string, unknown>
  annotations: Record<string, boolean>
  _meta?: Record<string, unknown>
}

const NO_ARGS = { type: 'object', properties: {} }

// Every tool reads and only reads — said formally, so hosts can render them as safe.
const READ_ONLY = {
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
}

// SEP-1865's key and OpenAI's documented alias, pointing a tool at its card.
const cardMeta = (name: string) => ({
  ui: { resourceUri: `ui://longbook/${name}.html` },
  'openai/outputTemplate': `ui://longbook/${name}.html`,
})

export const TOOLS: ToolSpec[] = [
  {
    name: 'next_payment',
    annotations: READ_ONLY,
    _meta: cardMeta('next-payment'),
    title: 'Next payment day',
    description:
      `The nearest day any commitment still owes, and every charge landing on it. ` +
      `Charges already marked paid are skipped. A transfer due that day is listed with ` +
      `direction "transfer" and kept out of total, under transfers_total. ${HONESTY}`,
    inputSchema: NO_ARGS,
  },
  {
    name: 'upcoming',
    annotations: READ_ONLY,
    _meta: cardMeta('upcoming'),
    title: 'Upcoming charges',
    description:
      `Every charge written for the next N days (default 30), soonest first, with per-currency ` +
      `totals — and which plans run out inside the window. Transfers between the owner's own ` +
      `accounts are listed with direction "transfer" and summed apart, never in total. ${HONESTY}`,
    inputSchema: {
      type: 'object',
      properties: { days: { type: 'integer', minimum: 1, maximum: 365, default: 30 } },
    },
  },
  {
    name: 'cashflow',
    annotations: READ_ONLY,
    _meta: cardMeta('cashflow'),
    title: 'Monthly cash flow',
    description:
      `Monthly totals per currency, summed from the charges written: past months are the ` +
      `record, months ahead are the plan as written, a month with no rows is empty. Spending ` +
      `only — money in and transfers are in no month. ${HONESTY}`,
    inputSchema: {
      type: 'object',
      properties: {
        currency: { type: 'string', minLength: 3, maxLength: 3 },
        months_back: { type: 'integer', minimum: 0, maximum: 24, default: 0 },
        months_forward: { type: 'integer', minimum: 0, maximum: 24, default: 12 },
      },
    },
  },
  {
    name: 'spending_by_category',
    annotations: READ_ONLY,
    title: 'Spending by category',
    description:
      `Spend per category over a window, summed from the charges written in it — the twelve ` +
      `months from today unless you say otherwise; a past window gives what was spent. ` +
      `Money in and transfers are left out. ${HONESTY}`,
    inputSchema: {
      type: 'object',
      properties: {
        from: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$', description: 'First day of the window, YYYY-MM-DD. Default: today.' },
        to: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$', description: 'Last day, inclusive. Default: twelve months from today.' },
      },
    },
  },
  {
    name: 'spending_by_account',
    annotations: READ_ONLY,
    title: 'Spending by account',
    description:
      `Spend per account over a window, summed from the charges written in it — the twelve ` +
      `months from today unless you say otherwise. Money in and transfers are left out. ${HONESTY}`,
    inputSchema: {
      type: 'object',
      properties: {
        from: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$', description: 'First day of the window, YYYY-MM-DD. Default: today.' },
        to: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$', description: 'Last day, inclusive. Default: twelve months from today.' },
      },
    },
  },
  {
    name: 'spending_by_person',
    annotations: READ_ONLY,
    title: 'Spending by person',
    description:
      `Spend per person over a window, summed from the charges written in it — the twelve ` +
      `months from today unless you say otherwise. Money in and transfers are left out. ${HONESTY}`,
    inputSchema: {
      type: 'object',
      properties: {
        from: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$', description: 'First day of the window, YYYY-MM-DD. Default: today.' },
        to: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$', description: 'Last day, inclusive. Default: twelve months from today.' },
      },
    },
  },
  {
    name: 'commitments',
    annotations: READ_ONLY,
    _meta: cardMeta('commitments'),
    title: 'List commitments',
    description:
      `Every commitment with its attributes — price now, cycle, status, category, member, ` +
      `account — plus its next unpaid charge, how many charges it has, and how far it is ` +
      `planned. Plans running short are named. \`active\` is what still lies ahead: a one-time ` +
      `commitment whose charge is behind today or paid is a charge now, counted in ` +
      `settled_one_time and read with charges. direction flags money in ("in") and a movement ` +
      `between the owner's own accounts ("transfer"). ${HONESTY}`,
    inputSchema: {
      type: 'object',
      properties: {
        status: { type: 'string', enum: ['active', 'paused', 'cancelled', 'all'], default: 'active' },
      },
    },
  },
  {
    name: 'charges',
    annotations: READ_ONLY,
    title: 'List charges',
    description:
      `The rows themselves: every charge, or one commitment's, optionally inside a window ` +
      `or only paid / only unpaid — each with its amount, paid state, the day the money ` +
      `moved, what backs it, and its note. A charge behind today reads paid whatever its row ` +
      `says. Transfers are listed with direction "transfer" and summed apart, never in total; ` +
      `money in is read by naming its commitment. This is the ledger; nothing here is computed. ${HONESTY}`,
    inputSchema: {
      type: 'object',
      properties: {
        id: { type: 'string', description: 'A commitment id.' },
        name: { type: 'string', description: 'Or its exact name. A name more than one commitment wears answers with their ids, not with rows.' },
        from: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$' },
        to: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$' },
        paid: { type: 'boolean' },
      },
    },
  },
  {
    name: 'search',
    annotations: READ_ONLY,
    title: 'Search commitments',
    description:
      `Finds commitments by name, category, notes, member, or account — case-insensitive, ` +
      `substring match.`,
    inputSchema: {
      type: 'object',
      properties: { query: { type: 'string', minLength: 1 } },
      required: ['query'],
    },
  },
  {
    name: 'accounts',
    annotations: READ_ONLY,
    title: 'List accounts',
    description:
      `Every account the memory holds: id, name, type (its tag), institution and last4 when ` +
      `present, belongs_to (the person it belongs to), linked_to (the account it is linked ` +
      `to: a card to the bank account that pays it), balance with balance_date, notes — what ` +
      `is particular about it, one detail per line, a card's name ("Card name: …", the thing ` +
      `to look up for offers) among them — details as stored when it holds any, how many ` +
      `commitments and charges are billed to it, and its next unpaid charge.`,
    inputSchema: NO_ARGS,
  },
  {
    name: 'people',
    annotations: READ_ONLY,
    title: 'List people',
    description:
      `Every person the memory holds: id, name, tag (their role in the owner's finances — ` +
      `family, household help, landlord), email, the accounts that belong to them, details as ` +
      `stored when they hold any, how many commitments and charges are for them, and their ` +
      `next unpaid charge.`,
    inputSchema: NO_ARGS,
  },
  {
    name: 'tags',
    annotations: READ_ONLY,
    title: 'The tag vocabulary',
    description:
      `Every tag this vault already uses — with its icon and how many rows wear it — and ` +
      `then longbook's library for the rest, with the owner's own casing. A tag carries no ` +
      `template: a commitment's or an account's own details live in its notes.`,
    inputSchema: NO_ARGS,
  },
  {
    name: 'whoami',
    annotations: READ_ONLY,
    title: 'Who am I here',
    description:
      `Answers who this connection belongs to, what it may do (read, or read and propose ` +
      `changes), how much of its rate allowance is left, whether a hosted copy exists and ` +
      `when it was last pushed, how many proposals are waiting for the owner's app, which ` +
      `ones it could not apply and why (failed_to_apply), and where the schemas live. One ` +
      `call, so it also shows whether the connection can read and write.`,
    inputSchema: NO_ARGS,
  },
  {
    name: 'read_guide',
    annotations: READ_ONLY,
    title: 'Read the guide',
    description:
      `Returns longbook's llms.txt — the contract and working method for an AI using longbook — ` +
      `whole, or one chapter by name. Chapters: ${GUIDE_SECTION_IDS.join(', ')}. ` +
      `"importing-statements" covers importing, "reading-reports" report questions, ` +
      `"unattended-runs" scheduled runs, "daily-email-round" the morning look at the owner's ` +
      `mail. Given one of longbook's ${PROMPTS.length} prompts — by its name ` +
      `(${PROMPTS.map((p) => p.id).join(', ')}) or the owner's own words for it, a month's ` +
      `name and all ("${PROMPT_EXAMPLE}") — it returns that prompt's procedure, with the ` +
      `chapter it builds on. A partial name finds its chapter.`,
    inputSchema: {
      type: 'object',
      properties: {
        section: {
          type: 'string',
          description: 'A chapter id or a word from its title; omit for the whole guide.',
        },
      },
    },
  },
]

export const RESOURCE_LLMS = {
  uri: 'longbook://vault/llms.txt',
  name: 'llms',
  title: 'How to read this memory',
  description: "The vault's own llms.txt — the contract any AI reading these files follows.",
  mimeType: 'text/plain',
}

export const RESOURCE_SCHEMA = {
  uri: 'longbook://vault/longbook.schema.json',
  name: 'schema',
  title: 'Financial memory schema',
  description: 'The JSON Schema the financial memory file conforms to.',
  mimeType: 'application/json',
}

export const RESOURCE_LIBRARY = {
  uri: 'longbook://vault/library.json',
  name: 'library',
  title: 'Tag library',
  description: 'The seeded tag library — names and icons for commitments, members and accounts.',
  mimeType: 'application/json',
}

/// The four cards, one entry per view — mimeType per MCP Apps: an HTML app profile.
export const CARD_RESOURCES = ['next-payment', 'upcoming', 'cashflow', 'commitments'].map((name) => ({
  uri: `ui://longbook/${name}.html`,
  name: `card-${name}`,
  title: `${name.replace('-', ' ')} card`,
  description: 'A complete, self-contained HTML card over the memory as it stands.',
  mimeType: 'text/html;profile=mcp-app',
}))
