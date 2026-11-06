// The directories' rule for tool annotations: every tool on either door carries a title and
// readOnlyHint, destructiveHint and openWorldHint as explicit booleans. A tool missing one fails here.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { Client } from '@modelcontextprotocol/sdk/client/index.js'
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js'
import { TOOLS, titled } from '../src/catalog.js'
import { WRITE_TOOLS } from '../src/proposal.js'
import { buildServer } from '../src/server.js'
import { VaultReader } from '../src/vault.js'

const HINTS = ['readOnlyHint', 'destructiveHint', 'openWorldHint'] as const

type Listed = { name: string; title?: string; annotations?: Record<string, unknown> }

function missing(tool: Listed): string[] {
  const out: string[] = []
  if (typeof tool.title !== 'string' || !tool.title.trim()) out.push('title')
  if (typeof tool.annotations?.title !== 'string' || !String(tool.annotations.title).trim()) out.push('annotations.title')
  for (const hint of HINTS) if (typeof tool.annotations?.[hint] !== 'boolean') out.push(hint)
  return out
}

function check(tools: Listed[]): void {
  for (const tool of tools) assert.deepEqual(missing(tool), [], `${tool.name} lacks ${missing(tool).join(', ')}`)
  for (const tool of tools) {
    const a = tool.annotations!
    if (a.readOnlyHint === true) assert.equal(a.destructiveHint, false, `${tool.name}: a read never destroys`)
  }
}

test('the hosted door: every tool carries a title and all three hints', () => {
  const tools = [...TOOLS, ...WRITE_TOOLS].map(titled)
  assert.equal(tools.length, 32)
  check(tools)
})

test('the local door: every tool carries a title and all three hints', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-mcp-annotations-'))
  writeFileSync(join(dir, 'financial_memory.json'), JSON.stringify({ app: 'longbook', version: 3, commitments: [], charges: [], members: [], accounts: [] }))
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair()
  await buildServer(new VaultReader(dir)).connect(serverTransport)
  const client = new Client({ name: 'annotations-test', version: '0.0.0' })
  await client.connect(clientTransport)
  const tools = (await client.listTools()).tools as Listed[]
  assert.equal(tools.length, 35)
  check(tools)
})

test('the missing check itself notices a tool without a hint', () => {
  assert.deepEqual(missing({ name: 'x', title: 'X', annotations: { title: 'X', readOnlyHint: true, destructiveHint: false } }), ['openWorldHint'])
})
