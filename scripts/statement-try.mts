#!/usr/bin/env -S npx tsx
// One real statement through the reader's own questions, from this Mac: the gate, the
// charges, the review, the tidy. Only counts are printed, never a line of the file or the
// answer. Run: ANTHROPIC_API_KEY=$(security find-generic-password -s 'Claude API Key' -w) npm run statement:try -- <pdf>
import { readFileSync } from 'node:fs'
import { basename } from 'node:path'
import { tidyCounterparts } from '../supabase/functions/_shared/statement-counterpart.ts'
import {
  CHARGES_SHAPE, GATE_INSTRUCTIONS, GATE_SHAPE, REVIEW_SHAPE, chargesInstructions, reviewInstructions,
} from '../supabase/functions/_shared/statement-prompts.ts'

const file = process.argv[2]
if (!file) {
  console.error('usage: npm run statement:try -- <statement.pdf>')
  process.exit(2)
}
const key = process.env.ANTHROPIC_API_KEY ?? ''
if (!key) {
  console.error('ANTHROPIC_API_KEY is not set; pipe it from the keychain, never paste it.')
  process.exit(2)
}

/** The function's defaults, overridable the same way. */
const MODEL = process.env.ANTHROPIC_MODEL ?? 'claude-sonnet-5-5'
const GATE_MODEL = process.env.STATEMENT_GATE_MODEL ?? 'claude-haiku-5-5'
const MAX_OUTPUT_TOKENS = 60_000

const library = JSON.parse(readFileSync(new URL('../packages/core/contract/library.json', import.meta.url), 'utf8')) as { tags: { kind: string; name: string }[] }
const inputs = {
  categories: library.tags.filter((t) => t.kind === 'commitment').map((t) => t.name),
  members: [], accounts: [], currency: 'INR',
}

type Part = { type: 'document'; source: { type: 'base64'; media_type: 'application/pdf'; data: string }; title: string } | { type: 'text'; text: string }

/** The request askAnthropic builds, byte for byte in what matters: system, parts, shape. */
async function ask(name: string, model: string, instructions: string, parts: Part[], shape: unknown, allowance: number): Promise<Record<string, unknown>> {
  const answer = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
    body: JSON.stringify({
      model,
      max_tokens: Math.max(2_000, Math.min(MAX_OUTPUT_TOKENS, allowance)),
      system: instructions,
      messages: [{ role: 'user', content: parts }],
      output_config: { format: { type: 'json_schema', schema: shape } },
    }),
  })
  const raw = await answer.text()
  if (!answer.ok) {
    let type = ''
    try { type = String(JSON.parse(raw)?.error?.type ?? '') } catch { /* unlogged */ }
    throw new Error(`${name}: ${answer.status} ${type}`)
  }
  const parsed = JSON.parse(raw)
  const tokens = Number(parsed.usage?.input_tokens ?? 0) + Number(parsed.usage?.output_tokens ?? 0)
  if (parsed.stop_reason !== 'end_turn') throw new Error(`${name}: stopped for ${parsed.stop_reason}`)
  let text = ''
  for (const part of parsed.content ?? []) if (part.type === 'text') text += part.text
  console.log(`${name}: ${model}, ${tokens} tokens`)
  return JSON.parse(text) as Record<string, unknown>
}

const base64 = readFileSync(file).toString('base64')
const filename = basename(file)
const pdf: Part = { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: base64 }, title: filename }

const gate = await ask('gate', GATE_MODEL, GATE_INSTRUCTIONS,
  [pdf, { type: 'text', text: 'Is the file above a statement? Answer in the shape.' }], GATE_SHAPE, 2_000)
console.log(`statement: ${gate.statement === true} (${String(gate.kind)})`)
if (gate.statement !== true) process.exit(1)

const read = tidyCounterparts(await ask('charges', MODEL, chargesInstructions(inputs),
  [pdf, { type: 'text', text: 'Read the piece above and answer in the shape with every charge in it.' }], CHARGES_SHAPE, 250_000))
type Charge = { date: string; amount: number; name: string; narration: string; kind: string; member: string | null; counterpart: string | null; counterpart_kind: string | null }
const charges = (read.charges as Charge[]) ?? []
const account = String(read.account ?? '').trim()

const lines = charges.map((c) => `${c.date} | ${c.amount} | ${c.name} | ${c.narration} | ${c.kind}`).join('\n')
const looked = await ask('review', MODEL, reviewInstructions(inputs), [{ type: 'text', text: lines }], REVIEW_SHAPE, 250_000)
const members = (looked.members as { name: string }[]) ?? []
const repeats = (looked.repeats as unknown[]) ?? []

/** Each name once, however it is cased. */
const distinct = (names: string[]) => new Set(names.map((n) => n.trim().toLowerCase()).filter(Boolean)).size
const people = distinct([
  ...members.map((m) => m.name),
  ...charges.filter((c) => c.counterpart_kind === 'person').map((c) => c.counterpart ?? ''),
  ...charges.map((c) => c.member ?? ''),
])
const accounts = distinct(charges.filter((c) => c.counterpart_kind === 'account').map((c) => c.counterpart ?? ''))
/** How many of the names the lines print the review listed: the owner wants all of them. */
const onLines = new Set(charges.flatMap((c) => [c.counterpart_kind === 'person' ? c.counterpart ?? '' : '', c.member ?? '']).map((n) => n.trim().toLowerCase()).filter(Boolean))
const listed = new Set(members.map((m) => m.name.trim().toLowerCase()))
const covered = [...onLines].filter((n) => listed.has(n)).length
const kinds = Object.fromEntries(['spend', 'for_member', 'fee', 'own_transfer', 'card_bill', 'income'].map((k) => [k, charges.filter((c) => c.kind === k).length]))

console.log(`account found: ${account ? 'yes' : 'NO'}`)
console.log(`balance found: ${read.closing_balance != null ? 'yes' : 'no'}`)
console.log(`charges: ${charges.length} (${Object.entries(kinds).map(([k, n]) => `${k} ${n}`).join(', ')})`)
console.log(`people: ${people} (review ${members.length}; ${covered} of ${onLines.size} names on lines listed)`)
console.log(`accounts: ${accounts} (other side of lines)`)
console.log(`repeats: ${repeats.length}`)
