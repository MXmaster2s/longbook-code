// The data-minimization enforcement layer: free text must refuse every pattern the
// Financial-Memory-Data-Policy names, and must leave ordinary financial notes alone.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { scanText, scanFields, scannableWords, numberWord } from '../src/domain/dataPolicy'

test('refuses a Luhn-valid card number, spaced like a real card', () => {
  const hit = scanText('my card is 4111 1111 1111 1111') // well-known Visa test number
  assert.ok(hit)
  assert.equal(hit!.kind, 'card_number')
})

test('refuses a Luhn-valid card number with dash separators', () => {
  const hit = scanText('5500-0055-5555-5559 is the number') // well-known Mastercard test number
  assert.equal(hit?.kind, 'card_number')
})

test('does not flag a digit run that fails the Luhn check', () => {
  assert.equal(scanText('order number 4111111111111112'), null, 'the check digit is wrong — not a real card number')
})

test('does not flag an ordinary phone number or ID as a card number', () => {
  assert.equal(scanText('call me at 9876543210'), null, 'too short to be a card number at all')
})

test('refuses an expiry date near an expiry keyword', () => {
  const hit = scanText('card expiry 08/29, keep it safe')
  assert.equal(hit?.kind, 'expiry')
})

test('does not flag a bare MM/YY-shaped date with no card context', () => {
  assert.equal(scanText('renews 08/29 every year'), null, 'not adjacent to any card/expiry keyword')
})

test('refuses a CVV near a CVV keyword', () => {
  const hit = scanText('the cvv is 123, do not share it')
  assert.equal(hit?.kind, 'cvv')
})

test('does not flag a bare 3-digit number with no CVV context', () => {
  assert.equal(scanText('paid 123 last month'), null)
})

test('refuses an IBAN-shaped string', () => {
  const hit = scanText('transfer to DE89370400440532013000')
  assert.equal(hit?.kind, 'iban')
})

test('refuses a password/secret key-value pair', () => {
  assert.equal(scanText('password: hunter2')?.kind, 'secret')
  assert.equal(scanText('api_key=sk_live_abc123')?.kind, 'secret')
})

test('an ordinary commitment note passes clean', () => {
  assert.equal(scanText('renews every year around my birthday, remember to check the price'), null)
  assert.equal(scanText('Visa 9292 — the one ending in 9292'), null)
})

test('scanFields checks every field and returns every violation found', () => {
  const violations = scanFields({
    name: 'Netflix',
    notes: 'card 4111 1111 1111 1111, cvv 123',
  })
  assert.ok(violations.length >= 1)
  assert.ok(violations.some((v) => v.kind === 'card_number'))
})

test('scanFields is clean when nothing sensitive is present', () => {
  assert.deepEqual(scanFields({ name: 'Netflix', notes: null }), [])
})

// A value the scanner never sees cannot be refused. The rule these state: every scalar a
// stored value can hold is rendered into words before it is scanned, and a whole number
// renders as its digits — never "4.1e+18", where a digit-run scan finds nothing to look at.

test('a whole number renders as its digits, however large', () => {
  assert.equal(numberWord(4111111111111111), '4111111111111111')
  assert.equal(numberWord(0), '0')
  assert.equal(numberWord(-4111111111111111), '-4111111111111111')
  for (const value of [1e15, 1e18, 4111111111111111, 5500005555555559]) {
    assert.match(numberWord(value), /^-?[0-9]+$/, `${value} must render as a bare digit run`)
  }
})

test('a number that is not whole keeps its point; a non-finite number renders to nothing', () => {
  assert.equal(numberWord(1.5), '1.5')
  assert.equal(numberWord(Number.POSITIVE_INFINITY), '')
  assert.equal(numberWord(Number.NaN), '')
})

test('scannableWords renders every scalar kind a stored value may hold', () => {
  assert.deepEqual(scannableWords('hello'), ['hello'])
  assert.deepEqual(scannableWords(4111111111111111), ['4111111111111111'])
  assert.deepEqual(scannableWords(true), ['yes'])
  assert.deepEqual(scannableWords(false), ['no'])
  assert.deepEqual(scannableWords(null), [])
  assert.deepEqual(scannableWords(undefined), [])
})

test('scannableWords flattens a list, whatever its members are', () => {
  assert.deepEqual(scannableWords(['a', 4111111111111111, true, null]), ['a', '4111111111111111', 'yes'])
  assert.deepEqual(scannableWords([['a', 1]]), ['a', '1'], 'nesting is flattened, never dropped')
})

test('a card number is refused whatever type it arrived as', () => {
  for (const value of [4111111111111111, '4111111111111111', '4111 1111 1111 1111']) {
    const words = scannableWords(value)
    assert.equal(words.length, 1)
    assert.equal(scanText(words[0]!)?.kind, 'card_number', `${typeof value} ${String(value)} must be refused`)
  }
})

test('an ordinary number in a details field is not mistaken for a secret', () => {
  for (const value of [649, 42000, 2026, 18, 1500.5]) {
    assert.equal(scanText(scannableWords(value)[0]!), null, `${value} is just a figure`)
  }
})
