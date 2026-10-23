// "Reorganise my longbook": the app sends the book, Claude reads it with the guide's own
// chapter and answers proposals, sieved here by the same validator both doors use. The
// app applies them as one change in Changes. A run counts against a monthly share.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { hasCloud } from '../_shared/has-cloud.ts'
import { shareFor, withinShare } from '../_shared/statement-shares.ts'
import { LLMS_TXT, digest, guideSection, parseVault, reorganiseInstructions, REORGANISE_SHAPE, takeProposals } from '../mcp/engine.mjs'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') ?? ''
const ANTHROPIC_MODEL = Deno.env.get('REORGANISE_MODEL') ?? Deno.env.get('ANTHROPIC_MODEL') ?? 'claude-sonnet-5-5'
/** Runs a rolling month allows an account: without and with longbook Cloud. Never shown. */
const SHARES = {
  free: Number(Deno.env.get('REORGANISE_FREE') ?? 2),
  cloud: Number(Deno.env.get('REORGANISE_CLOUD') ?? 10),
}
/** The book as sent, and what the model may read and write of it. */
const MAX_VAULT_BYTES = 2_000_000
const DIGEST_CHARS = 160_000
const MAX_OUTPUT_TOKENS = 32_000
/** The ledger shares the statements' table; a run's id wears this so neither counts the other. */
const LEDGER_PREFIX = 'reorg-'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS, 'content-type': 'application/json' } })

const SHARE_SPENT = "longbook's server has reorganised your longbook as often as it can for now. Try again next month, or ask your own AI with the \"Reorganise my longbook\" prompt."
const NOT_NOW = 'Your longbook could not be reorganised right now. Try again in a minute.'

interface Request_ {
  /** One id per run, chosen by the app. */
  run_id: string
  /** The book's financial_memory.json, as text. */
  vault: string
}

type Ledger = { fresh: boolean } | { spent: string; resets_on: string }

// deno-lint-ignore no-explicit-any
async function ledger(service: any, userId: string, runId: string, cloud: boolean): Promise<Ledger> {
  const { data: row } = await service.from('statement_imports').select('outcome').eq('user_id', userId).eq('import_id', runId).maybeSingle()
  if (row && row.outcome !== 'refused') return { fresh: false }
  const since = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000).toISOString()
  const { data: recent } = await service.from('statement_imports').select('started_at')
    .eq('user_id', userId).eq('outcome', 'read').like('import_id', `${LEDGER_PREFIX}%`).gte('started_at', since)
  const share = withinShare(shareFor(SHARES, cloud, null), (recent ?? []).map((r: { started_at: string }) => String(r.started_at)))
  if (share.resetsOn) return { spent: SHARE_SPENT, resets_on: share.resetsOn }
  return { fresh: true }
}

// deno-lint-ignore no-explicit-any
async function mark(service: any, userId: string, runId: string, outcome: 'read' | 'refused'): Promise<void> {
  const { error } = await service.from('statement_imports').upsert({ user_id: userId, import_id: runId, outcome }, { onConflict: 'user_id,import_id' })
  if (error) console.error('ledger', error.message)
}

/** One question to Claude, answered in the shape; the body is never logged. */
async function ask(instructions: string, text: string): Promise<{ ok: true; result: unknown; tokens: number } | { ok: false; response: Response; tokens: number }> {
  const answer = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'x-api-key': ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
    body: JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: MAX_OUTPUT_TOKENS,
      system: instructions,
      messages: [{ role: 'user', content: [{ type: 'text', text: `The longbook, as a digest:\n\n${text}\n\nReorganise it and answer in the shape.` }] }],
      output_config: { format: { type: 'json_schema', schema: REORGANISE_SHAPE } },
    }),
  }).catch(() => null)
  if (!answer) {
    console.error('anthropic', 'unreachable')
    return { ok: false, response: json({ error: NOT_NOW }, 502), tokens: 0 }
  }
  const raw = await answer.text()
  if (!answer.ok) {
    let type = ''
    try { type = String(JSON.parse(raw)?.error?.type ?? '') } catch { /* unlogged */ }
    console.error('anthropic', answer.status, type)
    return { ok: false, response: json({ error: NOT_NOW }, 502), tokens: 0 }
  }
  let text_ = ''
  let tokens = 0
  try {
    const parsed = JSON.parse(raw)
    tokens = Number(parsed.usage?.input_tokens ?? 0) + Number(parsed.usage?.output_tokens ?? 0)
    for (const part of parsed.content ?? []) if (part.type === 'text') text_ += part.text
    if (parsed.stop_reason === 'max_tokens') return { ok: false, response: json({ error: 'The answer ran long. Try again; a second pass usually fits.' }, 422), tokens }
    if (parsed.stop_reason === 'refusal') return { ok: false, response: json({ error: 'The model would not read this longbook.' }, 422), tokens }
    return { ok: true, result: JSON.parse(text_), tokens }
  } catch {
    console.error('shape', text_.length, tokens)
    return { ok: false, response: json({ error: 'The longbook was read but the answer did not fit. Try again.' }, 502), tokens }
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)

  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer /, '')
  if (!jwt) return json({ error: 'Sign in first.' }, 401)
  const asCaller = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  const { data: { user }, error } = await asCaller.auth.getUser(jwt)
  if (error || !user) return json({ error: 'That session is no longer valid.' }, 401)
  if (!ANTHROPIC_API_KEY) return json({ error: 'The server has no model key yet.' }, 503)

  const length = Number(req.headers.get('content-length') ?? 0)
  if (length > MAX_VAULT_BYTES + 10_000) return json({ error: 'This longbook is larger than the server reorganises. Ask your own AI with the prompt instead.' }, 413)
  let body: Request_
  try {
    body = await req.json()
  } catch {
    return json({ error: 'The longbook could not be read.' }, 400)
  }
  const runId = typeof body.run_id === 'string' ? body.run_id.trim() : ''
  if (!/^[A-Za-z0-9-]{8,56}$/.test(runId)) return json({ error: 'The longbook could not be read.' }, 400)
  if (typeof body.vault !== 'string' || !body.vault) return json({ error: 'No longbook was sent.' }, 400)
  if (body.vault.length > MAX_VAULT_BYTES) return json({ error: 'This longbook is larger than the server reorganises. Ask your own AI with the prompt instead.' }, 413)
  let data
  try {
    data = parseVault(body.vault)
  } catch {
    return json({ error: 'The longbook could not be read as a longbook.' }, 400)
  }
  const chapter = guideSection(LLMS_TXT, 'reorganise-my-longbook')
  if (!chapter) return json({ error: 'The server has no method yet.' }, 503)

  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const cloud = await hasCloud(service, user.id)
  const ledgerId = LEDGER_PREFIX + runId
  const row = await ledger(service, user.id, ledgerId, cloud)
  if ('spent' in row) return json({ error: row.spent, code: 'share_spent', resets_on: row.resets_on }, 429)
  if (row.fresh) await mark(service, user.id, ledgerId, 'read')

  const asked = await ask(reorganiseInstructions(chapter.text, new Date().toISOString().slice(0, 10)), digest(data, DIGEST_CHARS))
  const { error: kept } = await service.rpc('statement_import_spend', { p_user: user.id, p_import: ledgerId, p_tokens: asked.tokens })
  if (kept) console.error('ledger update', kept.message)
  if (!asked.ok) {
    // A run that gave nothing back does not count.
    await mark(service, user.id, ledgerId, 'refused')
    return asked.response
  }
  const taken = takeProposals(asked.result, data)
  return json({ proposals: taken.proposals, dropped: taken.dropped, summary: taken.summary, model: ANTHROPIC_MODEL, tokens: asked.tokens })
})
