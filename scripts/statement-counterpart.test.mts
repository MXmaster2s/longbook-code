// The other side of a statement line: required but nullable in the shape, and every
// answer tidied so a counterpart keeps four digits at most and passes the data policy.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { readFileSync } from 'node:fs'
import { COUNTERPART_PROPERTIES, COUNTERPART_REQUIRED, tidyCounterpart, tidyCounterparts } from '../supabase/functions/_shared/statement-counterpart.ts'
import { scanText } from '../packages/core/src/domain/dataPolicy'

test('the counterpart is required and may be null, with its kind', () => {
  assert.deepEqual([...COUNTERPART_REQUIRED], ['counterpart', 'counterpart_kind'])
  assert.deepEqual(COUNTERPART_PROPERTIES.counterpart.type, ['string', 'null'])
  assert.deepEqual(COUNTERPART_PROPERTIES.counterpart_kind.anyOf, [{ type: 'string', enum: ['account', 'person'] }, { type: 'null' }])
  // Anthropic refuses a schema whose enum holds a value its declared type does not.
  for (const field of Object.values(COUNTERPART_PROPERTIES) as { type?: unknown; enum?: unknown[] }[]) {
    assert.ok(!field.enum?.includes(null), 'no null inside an enum')
  }
})

test('the function asks for both fields on every charge and tidies the answer', () => {
  const source = readFileSync(new URL('../supabase/functions/statement-extract/index.ts', import.meta.url), 'utf8')
  assert.match(source, /required: \[[^\]]*\.\.\.COUNTERPART_REQUIRED\]/)
  assert.match(source, /\.\.\.COUNTERPART_PROPERTIES/)
  assert.match(source, /COUNTERPART_INSTRUCTIONS,/)
  assert.match(source, /tidyCounterparts\(asked\.result\)/, 'the tidy runs after ask(), so both readers pass it')
})

test('numbers keep their last four digits after the dots', () => {
  assert.equal(tidyCounterpart('HDFC SAV XX4417'), 'HDFC SAV ••4417')
  assert.equal(tidyCounterpart('Axis card ••1234'), 'Axis card ••1234')
  assert.equal(tidyCounterpart('xxxx-xxxx-4417 SBI'), '••4417 SBI')
  assert.equal(tidyCounterpart('HDFC 4111 1111 1111 1111'), 'HDFC ••1111')
  assert.equal(tidyCounterpart('DE89370400440532013000'), 'DE ••3000')
})

test('a handle, a blank or a bare number is no counterpart', () => {
  assert.equal(tidyCounterpart('ramesh.k@okaxis'), null)
  assert.equal(tidyCounterpart('   '), null)
  assert.equal(tidyCounterpart('123'), null)
  assert.equal(tidyCounterpart(42), null)
  assert.equal(tidyCounterpart('Ramesh K ramesh.k@okaxis'), 'Ramesh K')
})

test('what is handed on passes the same scan the vault writer runs', () => {
  for (const raw of ['4111 1111 1111 1111', 'HDFC 5500-0055-5555-5559', 'transfer to DE89370400440532013000', 'card 4111111111111111']) {
    assert.notEqual(scanText(raw), null, `${raw} is refused as it stands`)
    const tidy = tidyCounterpart(raw)
    assert.equal(tidy === null ? null : scanText(tidy), null, `${raw} → ${tidy} must pass`)
  }
})

test('a kind without a counterpart, or an unknown kind, is dropped', () => {
  const out = tidyCounterparts({
    account: 'Kotak savings 1020',
    charges: [
      { name: 'Transfer', counterpart: 'TRF TO HDFC SAV XX4417', counterpart_kind: 'account' },
      { name: 'Cook', counterpart: 'Ramesh K', counterpart_kind: 'person' },
      { name: 'Netflix', counterpart: null, counterpart_kind: 'account' },
      { name: 'Odd', counterpart: 'Shop', counterpart_kind: 'merchant' },
      { name: 'Older answer' },
    ],
  })
  const charges = out.charges as Record<string, unknown>[]
  assert.deepEqual(charges.map((c) => [c.counterpart, c.counterpart_kind]), [
    ['TRF TO HDFC SAV ••4417', 'account'],
    ['Ramesh K', 'person'],
    [null, null],
    [null, null],
    [null, null],
  ])
  assert.equal(out.account, 'Kotak savings 1020')
})
