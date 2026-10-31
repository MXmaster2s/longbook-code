// The questions for lines the device read: what is accepted, the rules each prompt says, and
// answers trimmed to the lines asked about with no full number left on them.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { readFileSync } from 'node:fs'
import { statementRuleText, statementRules } from '../packages/core/src/statement-rules'
import { MAX_LINES_PER_CALL, answerMode, headText, linesText, parseRows, readLines } from '../supabase/functions/_shared/statement-lines.ts'
import { HEAD_SHAPE, LINES_SHAPE, REPEATS_SHAPE, headInstructions, linesInstructions, repeatsInstructions } from '../supabase/functions/_shared/statement-prompts.ts'

const line = (n: number, over: Record<string, unknown> = {}) => ({ n, date: '2026-07-01', amount: 100.5, direction: 'out', text: 'UPI-SHOP', ...over })
const inputs = { categories: ['rent'], members: [], accounts: [], currency: 'INR', account_hint: 'HDFC savings 4417', holder: 'Asha Rao' }

test('lines are proved before anything is spent on them', () => {
  assert.equal(readLines([line(1)])?.[0].text, 'UPI-SHOP')
  for (const bad of [undefined, [], 'lines', [line(1.5)], [line(1, { date: '01/07/2026' })], [line(1, { amount: '100' })], [line(1, { direction: 'sideways' })], [line(1, { text: 3 })]]) {
    assert.equal(readLines(bad), null)
  }
  assert.equal(readLines(Array.from({ length: MAX_LINES_PER_CALL + 1 }, (_, i) => line(i))), null, 'one call has its limit')
  assert.equal(readLines([line(1, { text: `  a \n ${'b'.repeat(900)}` })])?.[0].text.length, 400)
})

test('the model reads a line as number, day, way, amount and the line', () => {
  assert.equal(linesText(readLines([line(7), line(8, { amount: 2000, direction: 'in' })])!), '7 | 2026-07-01 | out | 100.50 | UPI-SHOP\n8 | 2026-07-01 | in | 2000.00 | UPI-SHOP')
  const said = headText('a.pdf', 'MR ASHA RAO', readLines([line(1)])!)
  assert.match(said, /"a\.pdf"/)
  assert.match(said, /MR ASHA RAO/)
  assert.match(said, /1 \| 2026-07-01/)
})

test('rows are kept for lines asked about, once each, with a counterpart cut to four digits', () => {
  const asked = readLines([line(1), line(2), line(3)])!
  const row = (n: unknown, over: Record<string, unknown> = {}) => ({ n, name: 'Shop', kind: 'spend', category: null, member: null, counterpart: null, counterpart_kind: null, counterpart_bank: null, ...over })
  const rows = parseRows([row(1), row(1), row(9), row(2, { name: ' ' }), row(3, { counterpart: 'HDFC SAV 501000123456', counterpart_kind: 'account', counterpart_bank: 'x@okaxis' })], asked)
  assert.deepEqual(rows.map((r) => r.n), [1, 3])
  assert.equal(rows[1].counterpart, 'HDFC SAV ••3456')
  assert.equal(rows[1].counterpart_bank, null)
  assert.deepEqual(parseRows('nothing', asked), [])
})

test('the answers never carry a day or an amount, so a charge stays a fact', () => {
  const props = LINES_SHAPE.properties.rows.items.properties as Record<string, unknown>
  assert.ok(!('date' in props) && !('amount' in props) && !('narration' in props))
  assert.deepEqual(LINES_SHAPE.properties.rows.items.required, Object.keys(props))
  const repeat = REPEATS_SHAPE.properties.repeats.items.properties as Record<string, unknown>
  assert.ok(!('dates' in repeat) && !('amount' in repeat) && !('guessed' in repeat))
  assert.ok('lines' in repeat)
  assert.deepEqual(REPEATS_SHAPE.properties.repeats.items.required, Object.keys(repeat))
  assert.deepEqual(HEAD_SHAPE.required, Object.keys(HEAD_SHAPE.properties))
})

test('the head asks the gate and names the holder by the rule', () => {
  const said = headInstructions()
  assert.match(said, /bank, card, wallet, loan or broker statement/)
  assert.ok(said.includes(statementRules('people').find((r) => r.id === 'holder')!.text))
})

test('the lines prompt says every kinds, transfers, people, other-side and names rule, word for word', () => {
  const said = linesInstructions(inputs)
  for (const group of ['kinds', 'transfers', 'people', 'counterparts', 'names'] as const) {
    assert.ok(said.includes(statementRuleText(group)), group)
  }
  assert.match(said, /HDFC savings 4417/)
  assert.match(said, /Asha Rao/)
  assert.match(said, /A reference is never written anywhere/)
  assert.match(said, /never yours to change/)
})

test('the repeats prompt says every commitments rule, word for word', () => {
  assert.ok(repeatsInstructions(inputs).includes(statementRuleText('commitments')))
})

test('a plain task has thinking off at low effort; every other task is untouched', () => {
  const shape = { type: 'object' }
  assert.deepEqual(answerMode(shape, 'claude-sonnet-5-5', false), { output_config: { format: { type: 'json_schema', schema: shape } } })
  assert.deepEqual(answerMode(shape, 'claude-sonnet-5-5', true), { output_config: { format: { type: 'json_schema', schema: shape }, effort: 'low' }, thinking: { type: 'between_tools' } })
  assert.deepEqual(answerMode(shape, 'claude-haiku-5-5', true), { output_config: { format: { type: 'json_schema', schema: shape }, effort: 'low' }, thinking: { type: 'disabled' } })
})

test('the function keeps the document path and answers the new tasks', () => {
  const source = readFileSync(new URL('../supabase/functions/statement-extract/index.ts', import.meta.url), 'utf8')
  assert.match(source, /body\.task === 'charges' \? tidyCounterparts\(asked\.result\)/, 'old apps get the same answer')
  assert.match(source, /parseRows\(asked\.result\.rows/)
  assert.match(source, /\(body\.task === 'charges' && !body\.account_hint\) \|\| body\.task === 'lines'/, 'lines on a fresh file are still gated')
  assert.match(source, /code: 'not_statement'/)
  assert.match(source, /statement_import_spend/)
})
