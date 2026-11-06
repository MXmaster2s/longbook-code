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
  hints: [
    { id: 'h1', name: 'Cook', kind: 'member', tag: 'Cook' },
    { id: 'h2', name: 'Savings account', kind: 'account', tag: 'bank account' },
    { id: 'h3', name: 'Credit card', kind: 'account' },
    { id: 'h4', name: 'Nobody', kind: 'pet' },
    { id: 'h5', name: '', kind: 'member' },
    { name: 'no id', kind: 'account' },
  ],
}

describe('hints', () => {
  it('reads what setup kept, dropping rows without an id, a name or a known kind', () => {
    const data = parseVault(JSON.stringify(VAULT))
    assert.deepEqual(data.hints, [
      { id: 'h1', name: 'Cook', kind: 'member', tag: 'Cook' },
      { id: 'h2', name: 'Savings account', kind: 'account', tag: 'bank account' },
      { id: 'h3', name: 'Credit card', kind: 'account' },
    ])
    assert.equal(data.members.length, 0, 'a hint is never a person')
    assert.equal(data.methods.length, 0, 'a hint is never an account')
  })

  it('the commitments tool lists them as hints for reading statements', () => {
    const data = parseVault(JSON.stringify(VAULT))
    const out = commitments(data, 'all') as { hints?: unknown[]; hints_note?: string }
    assert.deepEqual(out.hints, [
      { name: 'Cook', kind: 'person', tag: 'Cook' },
      { name: 'Savings account', kind: 'account', tag: 'bank account' },
      { name: 'Credit card', kind: 'account', tag: null },
    ])
    assert.match(out.hints_note ?? '', /3 hints the owner picked at setup/)
    assert.match(out.hints_note ?? '', /never write a charge to its name/)
    const bare = commitments(parseVault(JSON.stringify({ app: 'longbook', version: 3, commitments: [] })), 'all') as { hints?: unknown }
    assert.equal(bare.hints, undefined)
  })

  it('the instructions name them at connect time, with or without to_fill_in', () => {
    const data = parseVault(JSON.stringify(VAULT))
    const text = instructionsFor(data)
    assert.ok(text.startsWith(INSTRUCTIONS))
    assert.match(text, /Hints from setup, picked by the owner by role or kind: people “Cook”; accounts “Savings account”, “Credit card”\./)
    const both = instructionsFor(parseVault(JSON.stringify({ ...VAULT, to_fill_in: [{ id: 'p1', name: 'Home rent' }] })))
    assert.match(both, /Waiting in to_fill_in, named by the owner without details: “Home rent”\./)
    assert.match(both, /Hints from setup/)
  })

  it('initialize names them from the door when the memory was not loaded', async () => {
    const data = parseVault(JSON.stringify(VAULT))
    const base: RpcContext = { loadData: () => null, llmsText: () => '# longbook\n', schemaText: () => '{}' }
    const init = { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26' } }
    const said = async (ctx: RpcContext) =>
      ((await handleRpc(init, ctx)) as { result: { instructions: string } }).result.instructions
    assert.match(await said({ ...base, hints: () => data.hints }), /people “Cook”/)
    assert.equal(await said({ ...base, hints: () => [], toFillIn: () => [] }), INSTRUCTIONS)
  })

  it('whoami lists them by name and kind', () => {
    const data = parseVault(JSON.stringify(VAULT))
    const ctx = { loadData: () => data, llmsText: () => '# longbook\n', schemaText: () => '{}' }
    assert.deepEqual(whoami(ctx).hints, [
      { name: 'Cook', kind: 'person', tag: 'Cook' },
      { name: 'Savings account', kind: 'account', tag: 'bank account' },
      { name: 'Credit card', kind: 'account', tag: null },
    ])
    assert.deepEqual(whoami({ ...ctx, loadData: () => null }).hints, [])
  })
})
