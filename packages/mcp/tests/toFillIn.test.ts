import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { parseVault } from '../src/parse.js'
import { commitments } from '../src/tools.js'
import { INSTRUCTIONS, instructionsFor } from '../src/catalog.js'
import { handleRpc, whoami } from '../src/rpc.js'
import type { RpcContext } from '../src/rpc.js'

const VAULT = {
  app: 'longbook',
  version: 3,
  commitments: [],
  to_fill_in: [
    { id: 'p1', name: 'Home rent', group: 'Rent', tag: 'rent' },
    { id: 'p2', name: 'Cook salary' },
    { id: 'p3', name: '' },
    { name: 'no id' },
  ],
}

describe('to_fill_in', () => {
  it('reads what setup named, dropping rows without an id or a name', () => {
    const data = parseVault(JSON.stringify(VAULT))
    assert.deepEqual(data.toFillIn, [
      { id: 'p1', name: 'Home rent', group: 'Rent', tag: 'rent' },
      { id: 'p2', name: 'Cook salary' },
    ])
  })

  it('the commitments tool names them and says what to do', () => {
    const data = parseVault(JSON.stringify(VAULT))
    const out = commitments(data, 'all') as { to_fill_in?: unknown[]; to_fill_in_note?: string }
    assert.equal(out.to_fill_in?.length, 2)
    assert.match(out.to_fill_in_note ?? '', /2 commitments the owner named without details/)
    assert.match(out.to_fill_in_note ?? '', /commitment \| your question \| your best guess/)
    const bare = commitments(parseVault(JSON.stringify({ app: 'longbook', version: 3, commitments: [] })), 'all') as { to_fill_in?: unknown }
    assert.equal(bare.to_fill_in, undefined)
  })

  it('the instructions name them at connect time, and only then', () => {
    const data = parseVault(JSON.stringify(VAULT))
    const text = instructionsFor(data)
    assert.ok(text.startsWith(INSTRUCTIONS))
    assert.match(text, /Waiting in to_fill_in, named by the owner without details: “Home rent”, “Cook salary”\./)
    assert.match(text, /commitment \| your question \| your best guess/)
    assert.match(text, /older or longer statements/)
    assert.equal(instructionsFor(null), INSTRUCTIONS)
    assert.equal(instructionsFor(parseVault(JSON.stringify({ app: 'longbook', version: 3, commitments: [] }))), INSTRUCTIONS)
  })

  it('initialize names them from the door when the memory was not loaded', async () => {
    const data = parseVault(JSON.stringify(VAULT))
    const base: RpcContext = { loadData: () => null, llmsText: () => '# longbook\n', schemaText: () => '{}' }
    const init = { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26' } }
    const said = async (ctx: RpcContext) =>
      ((await handleRpc(init, ctx)) as { result: { instructions: string } }).result.instructions
    assert.match(
      await said({ ...base, toFillIn: () => data.toFillIn }),
      /Waiting in to_fill_in, named by the owner without details: “Home rent”, “Cook salary”\./,
    )
    assert.equal(await said({ ...base, toFillIn: () => [] }), INSTRUCTIONS)
    assert.equal(await said(base), INSTRUCTIONS)
    // The memory says them itself where a door loaded it.
    assert.match(await said({ ...base, loadData: () => data, toFillIn: () => [] }), /“Home rent”, “Cook salary”/)
  })

  it('whoami lists them by name and group', () => {
    const data = parseVault(JSON.stringify(VAULT))
    const ctx = { loadData: () => data, llmsText: () => '# longbook\n', schemaText: () => '{}' }
    assert.deepEqual(whoami(ctx).to_fill_in, [
      { name: 'Home rent', group: 'Rent' },
      { name: 'Cook salary', group: null },
    ])
    assert.deepEqual(whoami({ ...ctx, loadData: () => null }).to_fill_in, [])
  })
})
