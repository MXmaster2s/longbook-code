// A statement into rows: "charges" reads one piece of a file, "review" looks a year over
// for members and repeats. A file's first piece is first checked to be a statement. Each
// file counts against a monthly share, larger with Cloud. Claude reads; OpenAI stands in.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { hasCloud } from '../_shared/has-cloud.ts'
import { shareFor, withinShare } from '../_shared/statement-shares.ts'
import { tidyCounterparts } from '../_shared/statement-counterpart.ts'
import { CHARGES_SHAPE, GATE_INSTRUCTIONS, GATE_SHAPE, REVIEW_SHAPE, chargesInstructions, reviewInstructions } from '../_shared/statement-prompts.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
/** Which reader answers first: "anthropic" (the default) or "openai". The other stands in. */
const READER = Deno.env.get('STATEMENT_READER') === 'openai' ? 'openai' : 'anthropic'
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') ?? ''
const ANTHROPIC_MODEL = Deno.env.get('ANTHROPIC_MODEL') ?? 'claude-sonnet-5-5'
/** The gate's model: one question per file, so the small one. */
const GATE_MODEL = Deno.env.get('STATEMENT_GATE_MODEL') ?? 'claude-haiku-5-5'
const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''
const OPENAI_MODEL = Deno.env.get('OPENAI_MODEL') ?? 'gpt-5'
/** How hard OpenAI's model thinks: reading is transcription, so little; the review a little more. */
const CHARGES_EFFORT = Deno.env.get('OPENAI_CHARGES_EFFORT') ?? 'minimal'
const REVIEW_EFFORT = Deno.env.get('OPENAI_REVIEW_EFFORT') ?? 'low'

/** What one file may spend, in tokens in and out together. A page read as text and image
 *  is about 2,500 tokens, so a forty-page year fits with room. */
const IMPORT_TOKEN_BUDGET = Number(Deno.env.get('IMPORT_TOKEN_BUDGET') ?? 250_000)
/** Files a rolling month allows an account: without and with longbook Cloud. Never shown
 *  to the reader; the words say only that the server has read what it can for now. */
const SHARES = {
  free: Number(Deno.env.get('IMPORTS_FREE') ?? 30),
  cloud: Number(Deno.env.get('IMPORTS_CLOUD') ?? 100),
}
/** The most one piece may carry: three pages of a bank's own PDF, or a run of rows. */
const MAX_PDF_BASE64 = 6_000_000
const MAX_TEXT_CHARS = 60_000
const MAX_REVIEW_CHARS = 150_000
const MAX_OUTPUT_TOKENS = 60_000
/** What the gate looks at: the piece, or the head of a long run of rows. */
const GATE_TEXT_CHARS = 8_000
/** The most a second reading may be told about the first. */
const MAX_HINT_CHARS = 2_000

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS, 'content-type': 'application/json' } })

const SHARE_SPENT = "longbook's server has read all the statements it can for your account for now. Write to us to read more, or use your own AI for this step."
const NOT_A_STATEMENT = 'does not look like a bank, card or wallet statement, so it was not read.'

interface Upload {
  name: string
  /** A PDF as base64, or rows already flattened to text by the app. */
  type: 'pdf' | 'text'
  data: string
}

interface Request_ {
  task: 'charges' | 'review'
  /** One id per file, chosen by the app: every piece and the review count against it. */
  import_id: string
  file?: Upload
  /** For "charges": what earlier pieces of the same file said the account is. */
  account_hint?: string
  /** For "charges" asked again: what the first reading of this piece left out. */
  hint?: string
  /** For "review": the year's charges, one a line: date | amount | name | narration | kind. */
  charges?: string
  categories: string[]
  members: string[]
  accounts: string[]
  currency: string
}

/** One piece as each reader takes it. */
type Content = { kind: 'pdf'; filename: string; base64: string } | { kind: 'text'; text: string }

/** What the model answered and what it cost, or the refusal to hand back. `standIn` says
 *  the other reader may be tried: the model was busy or broken, not the file. */
type Asked =
  | { ok: true; result: Record<string, unknown>; tokens: number; model: string }
  | { ok: false; response: Response; tokens: number; standIn: boolean }

interface Question {
  instructions: string
  content: Content[]
  shape: unknown
  name: string
  allowance: number
  /** OpenAI's reasoning effort for this task. */
  effort: string
  /** Anthropic's model for this task. */
  model: string
}

async function askAnthropic(q: Question): Promise<Asked> {
  const parts = q.content.map((c) =>
    c.kind === 'pdf'
      ? { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: c.base64 }, title: c.filename }
      : { type: 'text', text: c.text })
  const answer = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'x-api-key': ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
    body: JSON.stringify({
      model: q.model,
      max_tokens: Math.max(2_000, Math.min(MAX_OUTPUT_TOKENS, q.allowance)),
      system: q.instructions,
      messages: [{ role: 'user', content: parts }],
      output_config: { format: { type: 'json_schema', schema: q.shape } },
    }),
  }).catch(() => null)
  if (!answer) {
    console.error('anthropic', 'unreachable')
    return { ok: false, response: json({ error: 'The statement could not be read right now. Try again in a minute.' }, 502), tokens: 0, standIn: true }
  }
  const raw = await answer.text()
  if (!answer.ok) {
    // Only the status and the error's type are logged, never the body.
    let type = ''
    try { type = String(JSON.parse(raw)?.error?.type ?? '') } catch { /* unlogged */ }
    console.error('anthropic', answer.status, type)
    const busy = answer.status === 429 || answer.status >= 500
    return { ok: false, response: json({ error: 'The statement could not be read right now. Try again in a minute.' }, 502), tokens: 0, standIn: busy }
  }
  let text = ''
  let tokens = 0
  try {
    const parsed = JSON.parse(raw)
    tokens = Number(parsed.usage?.input_tokens ?? 0) + Number(parsed.usage?.output_tokens ?? 0)
    for (const part of parsed.content ?? []) if (part.type === 'text') text += part.text
    if (parsed.stop_reason === 'max_tokens') {
      return { ok: false, response: json({ error: 'This piece is too long to read within its budget. Pick the statement itself, not an export with extra columns.' }, 422), tokens, standIn: false }
    }
    if (parsed.stop_reason === 'refusal') {
      console.error('anthropic', 'refusal', q.name)
      return { ok: false, response: json({ error: 'The model would not read this file.' }, 422), tokens, standIn: false }
    }
    const result = JSON.parse(text) as Record<string, unknown>
    return { ok: true, result, tokens, model: q.model }
  } catch {
    // The answer is the reader's own money; only its size is logged, never a line of it.
    console.error('shape', 'anthropic', text.length, tokens)
    return { ok: false, response: json({ error: 'The statement was read but the answer did not fit. Try again.' }, 502), tokens, standIn: true }
  }
}

async function askOpenAI(q: Question): Promise<Asked> {
  const parts = q.content.map((c) =>
    c.kind === 'pdf'
      ? { type: 'input_file', filename: c.filename, file_data: `data:application/pdf;base64,${c.base64}` }
      : { type: 'input_text', text: c.text })
  const answer = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      instructions: q.instructions,
      input: [{ role: 'user', content: parts }],
      reasoning: { effort: q.effort },
      max_output_tokens: Math.max(2_000, Math.min(MAX_OUTPUT_TOKENS, q.allowance)),
      text: { format: { type: 'json_schema', name: q.name, strict: true, schema: q.shape } },
      store: false,
    }),
  }).catch(() => null)
  if (!answer) {
    console.error('openai', 'unreachable')
    return { ok: false, response: json({ error: 'The statement could not be read right now. Try again in a minute.' }, 502), tokens: 0, standIn: true }
  }
  const raw = await answer.text()
  if (!answer.ok) {
    let kind = ''
    try {
      const failed = JSON.parse(raw)?.error ?? {}
      kind = [failed.type, failed.code].filter((part) => typeof part === 'string').join('/')
    } catch { /* an unparsed body stays unlogged */ }
    console.error('openai', answer.status, kind)
    const busy = answer.status === 429 || answer.status >= 500
    return { ok: false, response: json({ error: 'The statement could not be read right now. Try again in a minute.' }, 502), tokens: 0, standIn: busy }
  }
  let text = ''
  let tokens = 0
  try {
    const parsed = JSON.parse(raw)
    tokens = Number(parsed.usage?.total_tokens ?? 0)
    for (const item of parsed.output ?? []) {
      for (const part of item.content ?? []) {
        if (part.type === 'output_text') text += part.text
      }
    }
    if (parsed.status === 'incomplete') {
      return { ok: false, response: json({ error: 'This piece is too long to read within its budget. Pick the statement itself, not an export with extra columns.' }, 422), tokens, standIn: false }
    }
    const result = JSON.parse(text) as Record<string, unknown>
    return { ok: true, result, tokens, model: OPENAI_MODEL }
  } catch {
    console.error('shape', 'openai', text.length, tokens)
    return { ok: false, response: json({ error: 'The statement was read but the answer did not fit. Try again.' }, 502), tokens, standIn: true }
  }
}

/** The first reader, then the other when the first was busy or broken and the other has a key. */
async function ask(q: Question): Promise<Asked> {
  const order = READER === 'openai' ? ['openai', 'anthropic'] : ['anthropic', 'openai']
  const keyed = order.filter((r) => (r === 'openai' ? OPENAI_API_KEY : ANTHROPIC_API_KEY))
  let last: Asked | null = null
  let spent = 0
  for (const reader of keyed) {
    const asked = reader === 'openai' ? await askOpenAI(q) : await askAnthropic(q)
    if (asked.ok) return spent ? { ...asked, tokens: asked.tokens + spent } : asked
    spent += asked.tokens
    last = asked
    if (!asked.standIn) break
    console.error('stand-in', reader, '→', keyed[keyed.indexOf(reader) + 1] ?? 'none')
  }
  return last ? { ...last, tokens: spent } : { ok: false, response: json({ error: 'The server has no model key yet.' }, 503), tokens: 0, standIn: false }
}

/** Is this file a statement? One cheap look at its first piece; a yes costs nothing more. */
async function gate(content: Content[]): Promise<{ statement: boolean; kind: string } | null> {
  const looked = content.map((c) => (c.kind === 'text' ? { ...c, text: c.text.slice(0, GATE_TEXT_CHARS) } : c))
  const asked = await ask({
    instructions: GATE_INSTRUCTIONS, content: [...looked, { kind: 'text', text: 'Is the file above a statement? Answer in the shape.' }],
    shape: GATE_SHAPE, name: 'statement_gate', allowance: 2_000, effort: 'minimal', model: GATE_MODEL,
  })
  if (!asked.ok) return null
  const statement = asked.result.statement === true
  return { statement, kind: String(asked.result.kind ?? 'other') }
}

type Ledger = { calls: number; tokens: number; fresh: boolean } | { spent: string; resets_on: string }

/** The file's ledger row, or whether one may be opened: the account's month, by Cloud or
 *  by its own grant, counts the files already read. The row itself is made by `open`. */
async function ledger(service: ReturnType<typeof createClient>, userId: string, importId: string, cloud: boolean): Promise<Ledger> {
  const { data: row } = await service.from('statement_imports').select('calls, tokens, outcome').eq('user_id', userId).eq('import_id', importId).maybeSingle()
  if (row && row.outcome !== 'refused') return { calls: Number(row.calls), tokens: Number(row.tokens), fresh: false }
  const since = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000).toISOString()
  // Reorganise runs share the table under their own prefix and their own share.
  const { data: recent } = await service.from('statement_imports').select('started_at').eq('user_id', userId).eq('outcome', 'read')
    .not('import_id', 'like', 'reorg-%').gte('started_at', since)
  const { data: grant } = await service.from('statement_allowances').select('imports_per_month').eq('user_id', userId).maybeSingle()
  const allowed = shareFor(SHARES, cloud, grant ? Number(grant.imports_per_month) : null)
  const share = withinShare(allowed, (recent ?? []).map((r) => String(r.started_at)))
  if (share.resetsOn) return { spent: SHARE_SPENT, resets_on: share.resetsOn }
  return { calls: 0, tokens: 0, fresh: true }
}

/** The ledger row for a file, read or refused. A refused file never counts. */
async function open(service: ReturnType<typeof createClient>, userId: string, importId: string, outcome: 'read' | 'refused'): Promise<void> {
  const { error } = await service.from('statement_imports').upsert({ user_id: userId, import_id: importId, outcome }, { onConflict: 'user_id,import_id' })
  if (error) console.error('ledger insert', error.message)
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)

  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer /, '')
  if (!jwt) return json({ error: 'Sign in first.' }, 401)
  const asCaller = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  const { data: { user }, error } = await asCaller.auth.getUser(jwt)
  if (error || !user) return json({ error: 'That session is no longer valid.' }, 401)
  if (!ANTHROPIC_API_KEY && !OPENAI_API_KEY) return json({ error: 'The server has no model key yet.' }, 503)

  let body: Request_
  try {
    body = await req.json()
  } catch {
    return json({ error: 'The upload could not be read.' }, 400)
  }
  const importId = typeof body.import_id === 'string' ? body.import_id.trim() : ''
  if (!/^[A-Za-z0-9-]{8,64}$/.test(importId)) return json({ error: 'The upload could not be read.' }, 400)
  const words = (list: unknown) => Array.isArray(list) ? list.slice(0, 60).map((s) => String(s).slice(0, 40)) : []
  body.categories = words(body.categories)
  body.members = words(body.members)
  body.accounts = words(body.accounts)
  body.currency = typeof body.currency === 'string' && body.currency ? body.currency.slice(0, 3) : 'INR'
  if (typeof body.account_hint === 'string') body.account_hint = body.account_hint.slice(0, 80)
  if (typeof body.hint === 'string') body.hint = body.hint.slice(0, MAX_HINT_CHARS)

  // What this call carries, checked before anything is spent on it.
  let content: Content[]
  let instructions: string
  let shape: unknown
  let name: string
  let filename = 'statement'
  if (body.task === 'review') {
    const lines = typeof body.charges === 'string' ? body.charges : ''
    if (!lines.trim()) return json({ error: 'No charges were sent.' }, 400)
    if (lines.length > MAX_REVIEW_CHARS) return json({ error: 'That is more charges than one statement holds. Read one file at a time.' }, 413)
    content = [{ kind: 'text', text: lines }]
    instructions = reviewInstructions(body)
    shape = REVIEW_SHAPE
    name = 'statement_review'
  } else {
    const file = body.file
    if (!file || typeof file.data !== 'string' || !file.data) return json({ error: 'No statement was sent.' }, 400)
    filename = String(file.name ?? 'statement').slice(0, 120)
    if (file.type === 'pdf') {
      if (file.data.length > MAX_PDF_BASE64) return json({ error: `${filename} is larger than a few pages of a statement should be.` }, 413)
      content = [{ kind: 'pdf', filename, base64: file.data }]
    } else {
      if (file.data.length > MAX_TEXT_CHARS) return json({ error: `${filename} holds more than one piece can carry.` }, 413)
      content = [{ kind: 'text', text: `Statement file "${filename}", as rows of cells:\n${file.data}` }]
    }
    content.push({ kind: 'text', text: 'Read the piece above and answer in the shape with every charge in it.' })
    if (body.hint) content.push({ kind: 'text', text: body.hint })
    instructions = chargesInstructions(body)
    shape = CHARGES_SHAPE
    name = 'statement_charges'
  }

  // The ledger: this file's spend so far, or whether the month allows another. A file's
  // first piece is first asked whether it is a statement; a no is recorded and not counted.
  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const cloud = await hasCloud(service, user.id)
  const row = await ledger(service, user.id, importId, cloud)
  if ('spent' in row) return json({ error: row.spent, code: 'share_spent', resets_on: row.resets_on }, 429)
  if (row.fresh) {
    if (body.task === 'charges' && !body.account_hint) {
      const looked = await gate(content.slice(0, 1))
      if (looked && !looked.statement) {
        await open(service, user.id, importId, 'refused')
        return json({ error: `${filename} ${NOT_A_STATEMENT}`, code: 'not_statement', kind: looked.kind }, 422)
      }
    }
    await open(service, user.id, importId, 'read')
  }
  const allowance = IMPORT_TOKEN_BUDGET - row.tokens
  if (allowance < 5_000) return json({ error: 'This statement has used up its reading budget. What was read stands; the rest of the file waits for another import.' }, 429)

  const asked = await ask({
    instructions, content, shape, name, allowance,
    effort: body.task === 'review' ? REVIEW_EFFORT : CHARGES_EFFORT, model: ANTHROPIC_MODEL,
  })
  // An increment in the database: pieces read side by side must both count.
  const { error: kept } = await service.rpc('statement_import_spend', { p_user: user.id, p_import: importId, p_tokens: asked.tokens })
  if (kept) console.error('ledger update', kept.message)
  if (!asked.ok) return asked.response
  // Both readers' answers pass the same tidy: no counterpart leaves with more than four digits.
  const result = body.task === 'charges' ? tidyCounterparts(asked.result) : asked.result
  return json({ ...result, model: asked.model, tokens: asked.tokens, budget_left: Math.max(0, allowance - asked.tokens) })
})
