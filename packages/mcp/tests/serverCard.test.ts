import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { SERVER_CARD } from '../src/serverCard.js'
import { handleRpc } from '../src/rpc.js'

const registry = JSON.parse(readFileSync(new URL('../server.json', import.meta.url), 'utf8'))

test('the Server Card names the server as the registry entry does', () => {
  for (const key of ['name', 'title', 'description', 'version', 'websiteUrl', 'repository', 'icons'] as const) {
    assert.deepEqual(SERVER_CARD[key], registry[key], key)
  }
  assert.deepEqual(SERVER_CARD.remotes.map(({ type, url }) => ({ type, url })), registry.remotes)
})

test('the Server Card claims what initialize answers', async () => {
  const reply = await handleRpc({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: 'none' } },
    { loadData: () => null } as never) as { result: { serverInfo: { version: string }, protocolVersion: string } }
  assert.equal(reply.result.serverInfo.version, SERVER_CARD.version)
  assert.ok(SERVER_CARD.remotes[0]?.supportedProtocolVersions.includes(reply.result.protocolVersion))
})
