// A built disk image is published only when it is the one tried and the appcast was made from it.
// Run: npm run device-build:test.
import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { publishProblems, sha256Of } from './release-mac-direct-publish.mts'

const dir = mkdtempSync(join(tmpdir(), 'publish-built-'))
const dmgPath = join(dir, 'longbook-1.5.0-67.dmg')
writeFileSync(dmgPath, 'disk image bytes')
const base = { dmgPath, dmgName: 'longbook-1.5.0-67.dmg', tag: 'mac-1.5.0-67', repo: 'o/r', expectedSha: sha256Of(dmgPath) }
const entry = (length: number, signed = true) =>
  `<item><enclosure url="https://github.com/o/r/releases/download/mac-1.5.0-67/longbook-1.5.0-67.dmg" length="${length}" type="application/octet-stream"${signed ? ' sparkle:edSignature="abc"' : ''}/></item>`

test('the tried file with its own signed appcast entry may be published', () => {
  assert.deepEqual(publishProblems({ ...base, appcast: entry(16) }), [])
})

test('another file, a missing entry, a wrong length or no signature each stop it', () => {
  assert.match(publishProblems({ ...base, expectedSha: 'a'.repeat(64), appcast: entry(16) })[0]!, /not the one that was tried/)
  assert.match(publishProblems({ ...base, expectedSha: 'x', appcast: entry(16) })[0]!, /64 hex/)
  assert.match(publishProblems({ ...base, appcast: '<item/>' })[0]!, /no entry/)
  assert.match(publishProblems({ ...base, appcast: entry(15) })[0]!, /length 15/)
  assert.match(publishProblems({ ...base, appcast: entry(16, false) })[0]!, /no EdDSA signature/)
})
