// A month prompt picked from the menu without a month names the month in progress.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mcpPromptMessage } from '../src/prompts.js'

test('a month prompt picked without a month names the month in progress', () => {
  const february = new Date('2026-02-10T12:00:00Z')
  const report = mcpPromptMessage('add-a-month-report-in-my-longbook', undefined, february)!
  assert.ok(report.messages[0]!.content.text.startsWith('Add February month report in my longbook\n'))
  const spent = mcpPromptMessage('what-did-i-spend-in-a-month', '  ', february)!
  assert.ok(spent.messages[0]!.content.text.startsWith('What did I spend in February in my longbook?\n'))
  const tidy = mcpPromptMessage('tidy-my-longbook', undefined, february)!
  assert.ok(tidy.messages[0]!.content.text.startsWith('Tidy my longbook\n'), 'a prompt without a month is untouched')
})
