#!/usr/bin/env -S npx tsx
// A local stand-in for statement-extract, for `swift run statement-run`: the same questions to
// the same models, no account or ledger. Logs each call's task, model, time and tokens, never
// a line. Run: ANTHROPIC_API_KEY=$(security find-generic-password -s 'Claude API Key' -w) npm run statement:serve -- --log <file>
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { createServer } from 'node:http'
import { join } from 'node:path'
import { tidyCounterparts } from '../supabase/functions/_shared/statement-counterpart.ts'
import { answerMode, headText, linesText, parseRows, readLines } from '../supabase/functions/_shared/statement-lines.ts'
import {
  CHARGES_SHAPE, GATE_INSTRUCTIONS, GATE_SHAPE, HEAD_SHAPE, LINES_SHAPE, REPEATS_SHAPE, REVIEW_SHAPE, chargesInstructions,
  headInstructions, linesInstructions, repeatsInstructions, reviewInstructions,
} from '../supabase/functions/_shared/statement-prompts.ts'

const args = process.argv.slice(2)
const flag = (name: string) => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined)
const key = process.env.ANTHROPIC_API_KEY ?? ''
if (!key) {
  console.error('ANTHROPIC_API_KEY is not set; pipe it from the keychain, never paste it.')
  process.exit(2)
}
const PORT = Number(flag('--port') ?? 8788)
const LOG = flag('--log')
/** Answers kept by question, so a later run can change one step and pay only for that. */
const CACHE = flag('--cache')
if (CACHE) mkdirSync(CACHE, { recursive: true })

const GATE_MODEL = process.env.STATEMENT_GATE_MODEL ?? 'claude-haiku-5-5'
const LINES_MODEL = process.env.STATEMENT_LINES_MODEL ?? 'claude-sonnet-5-5'
const REPEATS_MODEL = process.env.STATEMENT_REPEATS_MODEL ?? 'claude-sonnet-5-5'
const DOCUMENT_MODEL = process.env.ANTHROPIC_MODEL ?? 'claude-sonnet-5-5'
/** Dollars per million tokens, in and out. */
const PRICE: Record<string, [number, number]> = { 'claude-haiku-5-5': [0.1, 0.5], 'claude-sonnet-5-5': [2, 10] }

type Part = { type: 'document'; source: { type: 'base64'; media_type: 'application/pdf'; data: string }; title: string } | { type: 'text'; text: string }

interface Asked { task: string; model: string; system: string; parts: Part[]; shape: unknown; plain: boolean }

async function ask(q: Asked): Promise<Record<string, unknown>> {
  const request = {
    model: q.model,
    max_tokens: q.task === 'head' ? 2_000 : 60_000,
    system: q.system,
    messages: [{ role: 'user', content: q.parts }],
    ...answerMode(q.shape, q.model, q.plain),
  }
  const digest = createHash('sha256').update(JSON.stringify(request)).digest('hex').slice(0, 24)
  const kept = CACHE && join(CACHE, `${q.task}-${digest}.json`)
  const started = Date.now()
  if (kept && existsSync(kept)) return JSON.parse(readFileSync(kept, 'utf8')) as Record<string, unknown>
  let raw = ''
  let status = 0
  for (let attempt = 0; attempt < 3; attempt++) {
    const answer = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify(request),
    })
    raw = await answer.text()
    status = answer.status
    if (status !== 429 && status < 500) break
    await new Promise((done) => setTimeout(done, 2_000 * (attempt + 1)))
  }
  if (status !== 200) {
    let type = ''
    try { type = String(JSON.parse(raw)?.error?.type ?? '') } catch { /* unlogged */ }
    throw new Error(`${q.task}: ${status} ${type}`)
  }
  const parsed = JSON.parse(raw)
  const input = Number(parsed.usage?.input_tokens ?? 0)
  const output = Number(parsed.usage?.output_tokens ?? 0)
  const [priceIn, priceOut] = PRICE[q.model] ?? [0, 0]
  const row = { task: q.task, model: q.model, ms: Date.now() - started, input, output, dollars: (input * priceIn + output * priceOut) / 1e6, stop: parsed.stop_reason }
  console.log(JSON.stringify(row))
  if (LOG) appendFileSync(LOG, JSON.stringify(row) + '\n')
  if (parsed.stop_reason !== 'end_turn') throw new Error(`${q.task}: stopped for ${parsed.stop_reason}`)
  let text = ''
  for (const part of parsed.content ?? []) if (part.type === 'text') text += part.text
  const result = JSON.parse(text) as Record<string, unknown>
  if (kept) writeFileSync(kept, JSON.stringify(result), { mode: 0o600 })
  return result
}

async function answer(body: Record<string, any>): Promise<unknown> {
  const inputs = { categories: body.categories ?? [], members: body.members ?? [], accounts: body.accounts ?? [], currency: body.currency ?? 'INR', account_hint: body.account_hint, holder: body.holder }
  switch (body.task) {
    case 'head': {
      const lines = readLines(body.lines)
      if (!lines) throw new Error('head: no lines')
      return ask({ task: 'head', model: GATE_MODEL, system: headInstructions(), parts: [{ type: 'text', text: headText(String(body.file_name ?? 'statement'), String(body.header ?? ''), lines) }], shape: HEAD_SHAPE, plain: true })
    }
    case 'lines': {
      const lines = readLines(body.lines)
      if (!lines) throw new Error('lines: no lines')
      const result = await ask({ task: 'lines', model: LINES_MODEL, system: linesInstructions(inputs), parts: [{ type: 'text', text: linesText(lines) }], shape: LINES_SHAPE, plain: true })
      return { rows: parseRows(result.rows, lines) }
    }
    case 'repeats':
      return ask({ task: 'repeats', model: REPEATS_MODEL, system: repeatsInstructions(inputs), parts: [{ type: 'text', text: String(body.groups) }], shape: REPEATS_SHAPE, plain: true })
    case 'review':
      return ask({ task: 'review', model: DOCUMENT_MODEL, system: reviewInstructions(inputs), parts: [{ type: 'text', text: String(body.charges) }], shape: REVIEW_SHAPE, plain: false })
    case 'charges': {
      const file = body.file
      const parts: Part[] = file.type === 'pdf'
        ? [{ type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: file.data }, title: file.name }]
        : [{ type: 'text', text: `Statement file "${file.name}", as rows of cells:\n${file.data}` }]
      if (!body.account_hint) await ask({ task: 'gate', model: GATE_MODEL, system: GATE_INSTRUCTIONS, parts: [parts[0], { type: 'text', text: 'Is the file above a statement? Answer in the shape.' }], shape: GATE_SHAPE, plain: false })
      parts.push({ type: 'text', text: 'Read the piece above and answer in the shape with every charge in it.' })
      if (body.hint) parts.push({ type: 'text', text: String(body.hint) })
      return tidyCounterparts(await ask({ task: 'charges', model: DOCUMENT_MODEL, system: chargesInstructions(inputs), parts, shape: CHARGES_SHAPE, plain: false }))
    }
    default:
      throw new Error('unknown task')
  }
}

createServer((req, res) => {
  const chunks: Buffer[] = []
  req.on('data', (chunk) => chunks.push(chunk))
  req.on('end', () => {
    answer(JSON.parse(Buffer.concat(chunks).toString('utf8')))
      .then((result) => { res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(result)) })
      .catch((error: Error) => { console.error(error.message); res.writeHead(502); res.end('{}') })
  })
}).listen(PORT, '127.0.0.1', () => console.log(`statement stand-in on http://127.0.0.1:${PORT}`))
