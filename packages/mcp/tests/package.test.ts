// What `npx @longbook/mcp` installs. The bin is one esbuild bundle importing nothing but
// node: builtins, so the manifest must not send npm looking for anything else — the
// workspace packages it was built from are private and would fail the install with E404.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { isBuiltin } from 'node:module'
import { join } from 'node:path'

const root = join(import.meta.dirname, '..')
const manifest = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'))

test('the published package asks npm to install nothing', () => {
  assert.deepEqual(manifest.dependencies ?? {}, {})
})

test('every published path is one npm ships', () => {
  const shipped: string[] = manifest.files
  for (const path of [manifest.main, manifest.bin['longbook-mcp']]) {
    assert.ok(
      shipped.some((entry) => path === entry || path.startsWith(`${entry}/`)),
      `${path} is not covered by "files"`,
    )
  }
})

test('nothing is left out of the bundle for npm to fetch', () => {
  // Asserted on the generator, not by scanning minified output: esbuild resolves every
  // import at build time, so the only way an external could appear is this config gaining
  // an `external` list. Read from source — the bytes it emits are checked by local:server.
  const generator = readFileSync(join(root, '..', '..', 'scripts', 'gen-local-server.mts'), 'utf8')
  assert.ok(/bundle:\s*true/.test(generator), 'the bin must be bundled whole')
  assert.ok(!/\bexternal\s*:/.test(generator), 'an external would need a runtime dependency')
})
