// addMonthsClamped — the month-length clamp every renewal date rolls forward through.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { addMonthsClamped, monthsBetween, daysBetween, parseDate, toISO } from '../src/domain/dates'

test('Jan 31 + 1 month clamps to Feb 28 in a non-leap year', () => {
  const d = addMonthsClamped(new Date(2026, 0, 31), 1)
  assert.equal(toISO(d), '2026-02-28')
})

test('Jan 31 + 1 month clamps to Feb 29 in a leap year', () => {
  const d = addMonthsClamped(new Date(2028, 0, 31), 1)
  assert.equal(toISO(d), '2028-02-29')
})

test('a day that fits the target month is not clamped', () => {
  const d = addMonthsClamped(new Date(2026, 0, 15), 1)
  assert.equal(toISO(d), '2026-02-15')
})

test('adding 12 months rolls the year over', () => {
  const d = addMonthsClamped(new Date(2026, 6, 21), 12)
  assert.equal(toISO(d), '2027-07-21')
})

test('negative months walk backward and still clamp', () => {
  const d = addMonthsClamped(new Date(2026, 2, 31), -1)
  assert.equal(toISO(d), '2026-02-28', 'March 31 minus 1 month clamps into February')
})

test('multiple elapsed cycles land on the right month, not just +1', () => {
  const d = addMonthsClamped(new Date(2026, 0, 31), 25) // 25 months from Jan 2026
  assert.equal(toISO(d), '2028-02-29', '25 months from Jan 2026 is Feb 2028, clamped to the leap day')
})

test('parseDate/toISO round-trip through local midnight, no timezone drift', () => {
  const iso = '2026-08-06'
  assert.equal(toISO(parseDate(iso)), iso)
})

test('daysBetween counts whole days', () => {
  assert.equal(daysBetween(parseDate('2026-08-01'), parseDate('2026-08-11')), 10)
  assert.equal(daysBetween(parseDate('2026-08-11'), parseDate('2026-08-01')), -10)
})

test('monthsBetween counts whole calendar months regardless of day-of-month', () => {
  assert.equal(monthsBetween(parseDate('2026-01-31'), parseDate('2026-03-01')), 2)
  assert.equal(monthsBetween(parseDate('2026-01-01'), parseDate('2027-01-01')), 12)
})
