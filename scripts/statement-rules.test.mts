// The statement rules are one source: every rule is a sentence, the Deno copy carries the
// same words, and each prompt says every rule of the groups it is built from.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { STATEMENT_RULE_GROUPS, statementRuleText } from '../packages/core/src/statement-rules'
import { STATEMENT_RULE_GROUPS as COPIED } from '../supabase/functions/_shared/statement-rules.ts'
import { chargesInstructions, reviewInstructions } from '../supabase/functions/_shared/statement-prompts.ts'

const inputs = { categories: ['rent', 'insurance'], members: [], accounts: [], currency: 'INR' }

test('every rule is one sentence or a few, with a stable id of its own', () => {
  const ids = new Set<string>()
  for (const group of STATEMENT_RULE_GROUPS) {
    assert.ok(group.rules.length > 0, group.id)
    for (const rule of group.rules) {
      assert.ok(!ids.has(`${group.id}.${rule.id}`), `${group.id}.${rule.id} twice`)
      ids.add(`${group.id}.${rule.id}`)
      assert.match(rule.text, /[.)"]$/, `${rule.id} ends as a sentence`)
      assert.ok(!/Longbook/.test(rule.text), `${rule.id} spells longbook in lowercase`)
    }
  }
})

test('the Deno copy carries the same words', () => {
  assert.deepEqual(COPIED, STATEMENT_RULE_GROUPS)
})

test('the charges prompt says every reading, kinds, people, other-side and names rule, word for word', () => {
  const said = chargesInstructions(inputs)
  for (const group of ['reading', 'kinds', 'people', 'counterparts', 'names'] as const) {
    assert.ok(said.includes(statementRuleText(group)), `${group} rules, as one paragraph`)
  }
})

test('the review prompt says every commitments and people rule, word for word', () => {
  const said = reviewInstructions(inputs)
  for (const group of ['commitments', 'people'] as const) {
    assert.ok(said.includes(statementRuleText(group)), `${group} rules, as one paragraph`)
  }
  assert.match(said, /guessed is true with the reason in reason/)
})
