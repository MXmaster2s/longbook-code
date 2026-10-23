// Shared conformance vectors — the SAME JSON fixtures drive this suite and
// packages/swift-core's *ConformanceTests.swift. If TypeScript and Swift ever compute a
// different answer for the same input, one of these files fails; the two implementations
// cannot silently drift apart.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { scanText } from '../src/domain/dataPolicy'

const FIXTURES = join(import.meta.dirname, 'fixtures')

function loadJSON<T>(name: string): T {
  return JSON.parse(readFileSync(join(FIXTURES, name), 'utf8'))
}

interface DataPolicyVector {
  name: string
  text: string
  expect_kind: string | null
}

test('data-policy conformance vectors match scanText', () => {
  const vectors = loadJSON<DataPolicyVector[]>('data-policy-vectors.json')
  assert.ok(vectors.length > 0, 'fixture file must not be empty')
  for (const v of vectors) {
    const hit = scanText(v.text)
    assert.equal(hit?.kind ?? null, v.expect_kind, v.name)
  }
})
