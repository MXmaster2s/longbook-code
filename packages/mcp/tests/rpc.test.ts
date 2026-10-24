// The hosted dispatcher, tested where it's written: the same messages a remote client
// POSTs, against the shared fixture memory.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { HOW_TO_ENABLE, REPORT_FILED_NOTE, RpcFailure, WHY_READ_ONLY, handleRpc } from '../src/rpc.js'
import type { RpcContext } from '../src/rpc.js'
import type { Proposal } from '../src/proposal.js'
import { DATA_POLICY_REFUSAL, LLMS_TXT, PROMPTS } from '@longbook/core'

// A refusal's words before the reason it adds (what was found, where, how to file again).
const bare = (message: string): string => message.replace(/ Found what looks like [^.]+\. Remove it \(a card's last four digits are fine\) and file again\.$/, '')
import { fixture, TODAY, inDays, mkRow, mkSub } from './fixtures.js'
import { WRITE_TOOLS } from '../src/proposal.js'
import type { Account } from '@longbook/core'

const ctx = (data = fixture() as ReturnType<typeof fixture> | null): RpcContext => ({
  loadData: () => data,
  llmsText: () => 'the contract text',
  schemaText: () => '{"title":"schema"}',
  today: () => TODAY,
})

const call = async (method: string, params: Record<string, unknown> = {}, id: number | null = 1) =>
  (await handleRpc({ jsonrpc: '2.0', id, method, params }, ctx())) as Record<string, any>

test('initialize negotiates a known protocol and names the hosted server apart', async () => {
  const known = await call('initialize', { protocolVersion: '2025-03-26' })
  assert.equal(known.result.protocolVersion, '2025-03-26')
  const unknown = await call('initialize', { protocolVersion: '1999-01-01' })
  assert.equal(unknown.result.protocolVersion, '2025-06-18')
  assert.equal(known.result.serverInfo.name, 'longbook (hosted)', 'the two doors never introduce themselves alike')
})

test('notifications get no answer; unknown methods get -32601', async () => {
  assert.equal(await handleRpc({ jsonrpc: '2.0', method: 'notifications/initialized' }, ctx()), null)
  assert.equal((await call('completion/complete')).error.code, -32601)
})

test("initialize advertises prompts, and the menu is longbook's catalogue: every prompt once, by its id", async () => {
  const init = await call('initialize', { protocolVersion: '2025-06-18' })
  assert.deepEqual(init.result.capabilities.prompts, {})
  // The connect-time method names every prompt, and sets a repeat the statement proves.
  const said = (init.result.instructions as string).replace(/\s+/g, ' ')
  for (const prompt of PROMPTS) assert.ok(said.includes(`"${prompt.title}"`), prompt.title)
  assert.match(said, /promote_to_recurring a payee the statement shows at least three times, a steady month, quarter or year apart, still going at its end, and show it in the table; ask about the rest; plan 24 months unless the owner says otherwise\./)
  assert.doesNotMatch(said, /ask which repeat/)
  const listed = (await call('prompts/list')).result.prompts as { name: string; title: string; description: string; arguments?: { name: string; required: boolean }[] }[]
  assert.equal(listed.length, PROMPTS.length)
  assert.equal(new Set(listed.map((p) => p.name)).size, listed.length, 'names are unique')
  assert.deepEqual(listed.map((p) => p.name), PROMPTS.map((p) => p.id))
  const month = listed.find((p) => p.name === 'add-a-month-report-in-my-longbook')!
  assert.equal(month.title, 'Add a month report in my longbook')
  assert.deepEqual(month.arguments?.map((a) => [a.name, a.required]), [['month', false]])
  // Only a prompt whose words name a month takes one.
  assert.deepEqual(listed.filter((p) => p.arguments).map((p) => p.name), PROMPTS.filter((p) => p.template).map((p) => p.id))
  assert.equal(listed.find((p) => p.name === 'add-my-statement')!.description, PROMPTS.find((p) => p.id === 'add-my-statement')!.result)
})

test("prompts/get hands over the owner's words, then longbook's procedure and where the method lives", async () => {
  const got = await call('prompts/get', { name: 'add-my-statement' })
  assert.equal(got.result.messages.length, 1)
  assert.equal(got.result.messages[0].role, 'user')
  const text = got.result.messages[0].content.text as string
  assert.ok(text.startsWith('Add my statement in my longbook\n'), 'the first phrase opens the message')
  for (const step of PROMPTS.find((p) => p.id === 'add-my-statement')!.procedure) assert.ok(text.includes(step), step)
  assert.match(text, /The method in full: read_guide\("importing-statements"\)\n\nPass guide_key "add-my-statement:\d+:[0-9a-z]+" with every write this procedure makes\.$/)

  const october = (await call('prompts/get', { name: 'add-a-month-report-in-my-longbook', arguments: { month: 'october' } })).result
  assert.ok(october.messages[0].content.text.startsWith('Add October month report in my longbook\n'))
  const spent = (await call('prompts/get', { name: 'what-did-i-spend-in-a-month', arguments: { month: 'July' } })).result
  assert.ok(spent.messages[0].content.text.startsWith('What did I spend in July in my longbook?\n'))
  // A reading prompt builds on no chapter, so it points at none.
  const next = (await call('prompts/get', { name: 'what-do-i-pay-next' })).result
  assert.doesNotMatch(next.messages[0].content.text, /read_guide\(/)

  const unknown = await call('prompts/get', { name: 'find-horoscopes' })
  assert.equal(unknown.error.code, -32602)
  assert.match(unknown.error.message, /unknown prompt: find-horoscopes/)
})

test("read_guide given a prompt's name or the owner's words answers with its procedure and the chapter it builds on", async () => {
  const guided: RpcContext = { ...ctx(null), llmsText: () => LLMS_TXT }
  const read = async (section: string) => JSON.parse(((await handleRpc(
    { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'read_guide', arguments: { section } } },
    guided,
  )) as Record<string, any>).result.content[0].text)
  const prompt = PROMPTS.find((p) => p.id === 'find-subscriptions-from-my-email')!
  for (const asked of [prompt.id, prompt.phrases[0]!]) {
    const answer = await read(asked)
    assert.equal(answer.prompt, prompt.id, asked)
    assert.equal(answer.title, prompt.title)
    assert.deepEqual(answer.says, prompt.phrases)
    assert.equal(answer.result, prompt.result)
    assert.deepEqual(answer.needs, ['mail'])
    assert.equal(answer.procedure, prompt.procedure.join('\n'))
    assert.equal(answer.chapter.id, 'daily-email-round')
    assert.match(answer.chapter.text, /^## The daily email round/)
  }
  // A month's name finds its prompt; a prompt that builds on no chapter carries none.
  assert.equal((await read('Add March month report in my longbook')).chapter.id, 'month-report')
  assert.equal((await read('What do I pay next?')).chapter, null)
  // A chapter that is no prompt still answers as a chapter.
  assert.equal((await read('importing-statements')).section, 'importing-statements')
})

/** The eighteen write tools, as both doors list them. */
const WRITE_NAMES = [
  'add_commitments', 'update_commitment', 'mark_paid', 'add_charges', 'remove_charges', 'cancel_commitment',
  'promote_to_recurring', 'leave_insight', 'update_account', 'update_person', 'update_charge', 'set_planned_count',
  'add_person', 'add_account', 'rename_tag', 'delete_tag', 'delete_commitment', 'create_report',
]

test('tools list and answer with the same arithmetic the stdio server uses', async () => {
  const list = await call('tools/list')
  assert.equal(list.result.tools.length, 14 + WRITE_NAMES.length, 'fourteen reads and the eighteen writes, listed even where refused')
  const answer = await call('tools/call', { name: 'upcoming', arguments: { days: 30 } })
  const parsed = JSON.parse(answer.result.content[0].text)
  assert.equal(parsed.count, 7, 'the same seven rows the tools test counts')
})

test('bad arguments refuse with -32602, not a wrong answer', async () => {
  assert.equal((await call('tools/call', { name: 'upcoming', arguments: { days: 0 } })).error.code, -32602)
  assert.equal((await call('tools/call', { name: 'search', arguments: {} })).error.code, -32602)
  assert.equal((await call('tools/call', { name: 'nonsense', arguments: {} })).error.code, -32602)
})

test('without a hosted copy, tools answer with the way to make one', async () => {
  const answer = await handleRpc(
    { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'next_payment' } },
    ctx(null),
  ) as Record<string, any>
  assert.match(answer.result.content[0].text, /MCP server switch in the longbook app/)
})

test('read_guide answers on the hosted door too, before any copy exists', async () => {
  const guide = await handleRpc(
    { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'read_guide', arguments: {} } },
    ctx(null),
  ) as Record<string, any>
  assert.match(guide.result.content[0].text, /the contract text/)
  const listed = (await call('tools/list')).result.tools.map((t: { name: string }) => t.name)
  assert.ok(listed.includes('read_guide'))
  const library = await call('resources/read', { uri: 'longbook://vault/library.json' })
  assert.match(library.result.contents[0].text, /"contract_revision"/)
  // The library served: every kind is there, and no tag of any kind carries a template.
  const served = JSON.parse(library.result.contents[0].text) as { tags: Record<string, unknown>[] }
  assert.deepEqual([...new Set(served.tags.map((t) => t.kind))], ['commitment', 'member', 'account'])
  assert.deepEqual(served.tags.filter((t) => 'template' in t).map((t) => t.name), [])
})

test('the contract travels: resources read back the embedded llms and schema', async () => {
  const list = await call('resources/list')
  assert.equal(list.result.resources.length, 7)
  const read = await call('resources/read', { uri: 'longbook://vault/llms.txt' })
  assert.equal(read.result.contents[0].text, 'the contract text')
  assert.equal((await call('resources/read', { uri: 'longbook://vault/nowhere' })).error.code, -32002)
})

test('cards render over the wire shape, and say so when no copy exists', async () => {
  const card = await call('resources/read', { uri: 'ui://longbook/next-payment.html' })
  assert.equal(card.result.contents[0].mimeType, 'text/html;profile=mcp-app')
  assert.match(card.result.contents[0].text, /^<!doctype html>/)
  assert.match(card.result.contents[0].text, /₹42,000/)
  const empty = await handleRpc(
    { jsonrpc: '2.0', id: 9, method: 'resources/read', params: { uri: 'ui://longbook/cashflow.html' } },
    ctx(null),
  ) as Record<string, any>
  assert.match(empty.result.contents[0].text, /MCP server switch in the longbook app/)
})

test('tool descriptions state what a tool does and never instruct the model, as the directory asks', async () => {
  const instruct = /\b(before calling|read it before|call it (first|before)|ask the owner|never (write|state)|then stop|tell the owner|say so plainly|pass (source|idempotency_key|amount))\b/i
  for (const tool of (await call('tools/list')).result.tools) {
    assert.doesNotMatch(tool.description, instruct, `${tool.name} instructs the model`)
  }
})

test('every read tool wears its read-only annotations; card tools carry their ui meta', async () => {
  const writes = new Set(WRITE_NAMES)
  const tools = (await call('tools/list')).result.tools.filter((t: { name: string }) => !writes.has(t.name))
  for (const tool of tools) {
    assert.equal(tool.annotations.readOnlyHint, true, `${tool.name} says read-only`)
    assert.equal(tool.annotations.destructiveHint, false)
  }
  for (const tool of (await call('tools/list')).result.tools) {
    assert.equal(tool.annotations.title, tool.title, `${tool.name} names itself in annotations.title`)
  }
  const next = tools.find((t: any) => t.name === 'next_payment')
  assert.equal(next._meta.ui.resourceUri, 'ui://longbook/next-payment.html')
  assert.equal(next._meta['openai/outputTemplate'], 'ui://longbook/next-payment.html')
})

// ---------------------------------------------------------------------------------------------
// The proposal door (W47): writes exist only where a door does, and every refusal is typed.

const filed: Proposal[] = []
const writingCtx = (propose?: RpcContext['propose'], data?: ReturnType<typeof fixture> | null): RpcContext => ({
  ...ctx(data),
  identity: () => ({ key_name: 'claude-daily-brief', scopes: ['memory:read', 'memory:propose'], hosted_copy: { pushed_at: '2026-09-17T08:00:00+00:00' } }),
  propose:
    propose ??
    ((proposal) => {
      filed.push(proposal)
      return { entry_id: `entry-${filed.length}`, created: true, pending_count: filed.length }
    }),
})

const callWith = async (context: RpcContext, name: string, args: Record<string, unknown> = {}) =>
  (await handleRpc({ jsonrpc: '2.0', id: 7, method: 'tools/call', params: { name, arguments: args } }, context)) as Record<string, any>

const ROW = { name: 'Gym', amount: 2000, currency: 'INR', billing_cycle: 'monthly', first_charge: '2026-09-01' }

test('a read-only door still LISTS the writes, and its refusal says how to switch them on', async () => {
  // Listed on purpose: a tool that is merely absent teaches an agent nothing, and it
  // cannot then tell the owner what to enable.
  const listed = (await call('tools/list')).result.tools.map((t: { name: string }) => t.name)
  assert.ok(listed.includes('add_commitments'))

  const refused = await callWith(ctx(), 'add_commitments', { rows: [ROW] })
  const error = JSON.parse(refused.result.content[0].text).error
  assert.equal(error.code, 'insufficient_scope')
  assert.equal(error.advice, 'stop')
  assert.equal(error.scope, 'memory:propose')
  assert.match(error.how_to_enable, /Automations screen/)

  // And the door's own words travel: a signed-in web session is told about the switch,
  // a key is told about the key.
  const web = await callWith(
    { ...ctx(), whyReadOnly: () => WHY_READ_ONLY.oauth, howToEnable: () => HOW_TO_ENABLE.oauth },
    'add_commitments',
    { rows: [ROW] },
  )
  const webError = JSON.parse(web.result.content[0].text).error
  assert.match(webError.message, /switched off/)
  assert.match(webError.how_to_enable, /Let signed-in AIs suggest changes/)
})

test('no hosted copy is a refusal, not an empty ledger', async () => {
  const cold = (await handleRpc(
    { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'commitments', arguments: {} } },
    ctx(null),
  )) as Record<string, any>
  assert.equal(cold.result.isError, true)
  const error = JSON.parse(cold.result.content[0].text).error
  assert.equal(error.code, 'not_found')
  assert.equal(error.advice, 'stop')
  assert.match(error.message, /MCP server switch/)
})

test('a proposing door lists all eighteen writes and files one, carrying its key and source', async () => {
  const names = (await handleRpc({ jsonrpc: '2.0', id: 1, method: 'tools/list' }, writingCtx()) as Record<string, any>)
    .result.tools.map((t: { name: string }) => t.name)
  for (const write of WRITE_NAMES) {
    assert.ok(names.includes(write), `${write} is offered`)
  }
  const out = await callWith(writingCtx(), 'add_commitments', {
    rows: [ROW],
    source: 'gmail:18c2a',
    idempotency_key: 'brief:2026-08-21:18c2a',
  })
  const answer = JSON.parse(out.result.content[0].text)
  assert.equal(answer.created, true)
  assert.match(answer.note, /Changes screen/)
  const proposal = filed.at(-1)!
  assert.equal(proposal.kind, 'add_commitments')
  assert.equal(proposal.idempotency_key, 'brief:2026-08-21:18c2a')
  assert.equal(proposal.source_ref, 'gmail:18c2a')
  assert.equal((proposal.payload.rows as unknown[]).length, 1)
  assert.equal(proposal.payload.idempotency_key, undefined, 'the key rides beside the payload, not inside it')
})

// details is longbook's own on a commitment. A write sending it is refused by name and never
// filed, so no write that sends details is answered as a success that dropped them.
const DETAILS = "details is longbook's own — write a commitment's details as lines of its notes"

test('a commitment write sending details is refused by name, and never filed', async () => {
  const before = filed.length
  const added = JSON.parse((await callWith(writingCtx(), 'add_commitments', {
    rows: [ROW, { ...ROW, name: 'Term plan', tag: 'insurance', notes: 'Policy number: 88213', details: { insurer: 'HDFC ERGO' } }],
  })).result.content[0].text).error
  assert.equal(added.code, 'validation_failed')
  assert.equal(added.message, `Nothing was written. Fix these and send the batch again — row 2 ("Term plan"): ${DETAILS}.`)

  // Beside a field update_commitment takes, or alone: the same words, never "names none of".
  for (const set of [{ notes: 'Plan: Premium', details: { plan: 'Premium' } }, { details: { plan: 'Premium' } }]) {
    const updated = JSON.parse((await callWith(writingCtx(), 'update_commitment', { name: 'Netflix', set })).result.content[0].text).error
    assert.equal(updated.code, 'validation_failed')
    assert.equal(updated.message, `Nothing was changed. Fix these — ${DETAILS}.`)
  }

  const promoted = JSON.parse((await callWith(writingCtx(), 'promote_to_recurring', {
    ids: ['s-bill', 's-bill-2'], billing_cycle: 'monthly', details: { role: 'cook' },
  })).result.content[0].text).error
  assert.equal(promoted.code, 'validation_failed')
  assert.equal(promoted.message, `${DETAILS}.`)
  assert.equal(filed.length, before, 'nothing was filed')

  // Details that say nothing refuse nothing; the rest of the write is filed.
  const empty = JSON.parse((await callWith(writingCtx(), 'update_commitment', { name: 'Netflix', set: { notes: 'Plan: Premium', details: {} } })).result.content[0].text)
  assert.equal(empty.created, true)
})

// The guide promises the validator names the row: a batch row by its place and name, any
// other write by the row it addresses — never by the value it refused.
test('a secret is refused naming its row, and the refusal never repeats the secret', async () => {
  const refusal = (args: Record<string, unknown>, name = 'add_commitments') =>
    callWith(writingCtx(), name, args).then((out) => JSON.parse(out.result.content[0].text).error)
  const before = filed.length

  const batch = await refusal({ rows: [ROW, { ...ROW, name: 'Visa bill', notes: 'Card 4111 1111 1111 1111' }, { ...ROW, name: 'Rent' }] })
  assert.equal(batch.code, 'validation_failed')
  assert.equal(bare(batch.message), `${DATA_POLICY_REFUSAL} (row 2: "Visa bill")`)
  const numbered = await refusal({ rows: [ROW, { ...ROW, name: 'Visa bill', amount: 10, notes: 'Plan: Premium', memo: 4111111111111111 }] })
  assert.equal(bare(numbered.message), `${DATA_POLICY_REFUSAL} (row 2: "Visa bill")`, 'a number is a digit run, whatever key holds it')
  const itself = await refusal({ rows: [ROW, { ...ROW, name: 'Visa 4111 1111 1111 1111' }] })
  assert.equal(bare(itself.message), `${DATA_POLICY_REFUSAL} (row 2)`, 'a name that is the secret is named by its place')

  assert.equal(bare((await refusal({ name: 'Netflix', set: { notes: 'CVV 123' } }, 'update_commitment')).message), `${DATA_POLICY_REFUSAL} (row: "Netflix")`)
  assert.equal(bare((await refusal({ id: 's-rent', set: { notes: 'pin: 4821' } }, 'update_commitment')).message), `${DATA_POLICY_REFUSAL} (row: "s-rent")`)
  assert.equal(bare((await refusal({ name: 'Netflix', charges: [{ date: '2026-09-01', note: 'paid by 4111 1111 1111 1111' }] }, 'add_charges')).message),
    `${DATA_POLICY_REFUSAL} (row: "Netflix")`)
  assert.equal(bare((await refusal({ ids: ['s-bill', 's-bill-2'], billing_cycle: 'monthly', name: 'Card bill', notes: 'Expires: 03/27' }, 'promote_to_recurring')).message),
    `${DATA_POLICY_REFUSAL} (row: "Card bill")`)
  assert.equal(bare((await refusal({ name: 'HDFC Current account', set: { notes: 'password: hunter2' } }, 'update_account')).message),
    `${DATA_POLICY_REFUSAL} (row: "HDFC Current account")`)
  // An insight is no row; its refusal is the policy alone, as on the local door.
  assert.equal(bare((await refusal({ module: 'dashboard.this_month', text: 'paid with 4111 1111 1111 1111' }, 'leave_insight')).message), DATA_POLICY_REFUSAL)
  assert.equal(filed.length, before, 'nothing was filed')
})

test('a bad payload is refused before the door, naming every offender', async () => {
  const bad = await callWith(writingCtx(), 'add_commitments', { rows: [{ ...ROW, first_charge: '2026-02-30', currency: 'rupees' }] })
  const error = JSON.parse(bad.result.content[0].text).error
  assert.equal(error.code, 'validation_failed')
  assert.match(error.message, /real calendar day/)
  assert.match(error.message, /three-letter/)

  const leak = await callWith(writingCtx(), 'leave_insight', { module: 'dashboard.this_month', text: 'paid with 4111 1111 1111 1111' })
  assert.equal(JSON.parse(leak.result.content[0].text).error.code, 'validation_failed')
})

test('a door that knows why it refused says so, typed — and an already-filed write is success', async () => {
  const revoked = writingCtx(() => {
    throw new RpcFailure('key_revoked', 'This key was revoked in the longbook app.')
  })
  const error = JSON.parse((await callWith(revoked, 'cancel_commitment', { name: 'Netflix' })).result.content[0].text).error
  assert.equal(error.code, 'key_revoked')
  assert.equal(error.advice, 'stop')

  const repeat = writingCtx(() => ({ entry_id: 'entry-1', created: false, pending_count: 1 }))
  const answer = JSON.parse((await callWith(repeat, 'mark_paid', { name: 'Netflix', date: '2026-09-01' })).result.content[0].text)
  assert.equal(answer.created, false)
  assert.match(answer.note, /already filed/)
})

test('whoami answers before any copy exists, and says plainly whether it can write', async () => {
  const cold = await handleRpc({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'whoami' } }, ctx(null)) as Record<string, any>
  const answer = JSON.parse(cold.result.content[0].text)
  assert.equal(answer.can_write, false)
  assert.equal(answer.write_tools.length, WRITE_NAMES.length, 'named even when refused')
  assert.match(answer.how_to_enable, /Automations screen/)
  assert.ok(answer.cannot_write_because)
  assert.equal(answer.memory, null)
  assert.equal(answer.guide.llms_txt, 'https://longbook.app/llms.txt')

  // Served the real curriculum, whoami hands back the chapter names read_guide answers to.
  const taught = await handleRpc(
    { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'whoami' } },
    { ...ctx(null), llmsText: () => LLMS_TXT },
  ) as Record<string, any>
  assert.ok(JSON.parse(taught.result.content[0].text).guide.read_guide.includes('unattended-runs'))
  assert.ok(JSON.parse(taught.result.content[0].text).guide.read_guide.includes('daily-email-round'))

  const warm = JSON.parse((await callWith(writingCtx(), 'whoami')).result.content[0].text)
  assert.equal(warm.key_name, 'claude-daily-brief')
  assert.equal(warm.can_write, true)
  assert.equal(warm.write_mode, 'proposal')
  assert.equal(warm.write_tools.length, WRITE_NAMES.length)
  assert.ok(warm.memory.commitments > 0)
  // The morning round reads accounts and people by name from this one call.
  assert.equal(warm.memory.account_names.length, warm.memory.accounts)
  assert.equal(warm.memory.member_names.length, warm.memory.members)
  assert.match(warm.closer_door, /prefer their longbook folder/)
  assert.ok(warm.tags.library.some((t: { name: string }) => t.name === 'insurance'))
})

test('the tags tool answers the vault first, then the library, counting what wears each', async () => {
  const answer = JSON.parse((await callWith(ctx(), 'tags')).result.content[0].text)
  assert.ok(Array.isArray(answer.in_vault))
  assert.ok(answer.library.some((t: { name: string }) => t.name === 'streaming'))
  assert.match(answer.note, /Invent one only when nothing fits/)
})

// ---------------------------------------------------------------------------------------------
// Targets (owner point 4): what the app would refuse at apply time is refused before filing.

const errorOf = (out: Record<string, any>) => JSON.parse(out.result.content[0].text).error
const bodyOf = (out: Record<string, any>) => JSON.parse(out.result.content[0].text)

test('an account the copy does not hold is refused with the real names, ids and the push date', async () => {
  const out = await callWith(writingCtx(), 'update_account', { name: 'Fi Money', set: { tag: 'bank account' } })
  assert.equal(out.result.isError, true)
  const error = errorOf(out)
  assert.equal(error.code, 'not_found')
  assert.equal(error.advice, 'stop')
  assert.match(error.message, /No account in the hosted copy \(pushed 2026-09-17\) is called "Fi Money"/)
  assert.match(error.message, /"HDFC Current account" \(id pm-hdfc\)/)
  assert.match(error.message, /"ICICI Joint Account" \(id pm-icici\)/)
  assert.match(error.message, /Pass one of these names exactly, or its id\./)
  assert.deepEqual(error.candidates, [
    { name: 'HDFC Current account', id: 'pm-hdfc' },
    { name: 'ICICI Joint Account', id: 'pm-icici' },
  ])
  assert.equal(error.hosted_copy_pushed_at, '2026-09-17T08:00:00+00:00')
  assert.equal(filed.some((p) => p.kind === 'update_account'), false, 'nothing was filed')

  const byId = errorOf(await callWith(writingCtx(), 'update_account', { id: 'a-none', set: { tag: 'cash' } }))
  assert.equal(byId.code, 'not_found')
  assert.match(byId.message, /has the id a-none/)
})

test('the exact name files; so does a whitespace and case variant, by the name key', async () => {
  const exact = bodyOf(await callWith(writingCtx(), 'update_account', { name: 'HDFC Current account', set: { tag: 'bank account' } }))
  assert.equal(exact.created, true)
  const loose = bodyOf(await callWith(writingCtx(), 'update_account', { name: '  hdfc  CURRENT account ', set: { balance: 1200 } }))
  assert.equal(loose.created, true)
  const person = bodyOf(await callWith(writingCtx(), 'update_person', { name: 'diya', set: { email: 'diya@example.com' } }))
  assert.equal(person.created, true)
})

test('two accounts under one key refuse as ambiguous, naming both ids', async () => {
  const data = fixture()
  const twin: Account = { ...data.methods[0]!, id: 'pm-hdfc-2', name: 'HDFC current account', name_key: 'hdfc current account' }
  data.methods = [...data.methods, twin]
  const error = errorOf(await callWith(writingCtx(undefined, data), 'update_account', { name: 'HDFC Current account', set: { tag: 'cash' } }))
  assert.equal(error.code, 'validation_failed')
  assert.match(error.message, /matches more than one account/)
  assert.match(error.message, /pm-hdfc\b/)
  assert.match(error.message, /pm-hdfc-2/)
  assert.equal(error.candidates.length, 2)
})

test('a rename onto a name another row wears is refused before filing', async () => {
  const account = errorOf(await callWith(writingCtx(), 'update_account', { id: 'pm-icici', set: { name: 'hdfc current account' } }))
  assert.equal(account.code, 'validation_failed')
  assert.match(account.message, /There's already an account called "hdfc current account" in the hosted copy \(pushed 2026-09-17\) \(id pm-hdfc\)/)
  const person = errorOf(await callWith(writingCtx(), 'update_person', { id: 'm-rohit', set: { name: 'Diya' } }))
  assert.equal(person.code, 'validation_failed')
  assert.match(person.message, /already a person called "Diya"/)
})

test('a parent the copy does not hold is refused at proposal time, with the accounts', async () => {
  const error = errorOf(await callWith(writingCtx(), 'update_account', { id: 'pm-icici', set: { parent_account: 'Nobody' } }))
  assert.equal(error.code, 'not_found')
  assert.match(error.message, /No account in the hosted copy \(pushed 2026-09-17\) is called "Nobody"/)
  assert.match(error.message, /"HDFC Current account" \(id pm-hdfc\)/)

  const self = errorOf(await callWith(writingCtx(), 'update_account', { id: 'pm-icici', set: { parent_account: 'ICICI Joint Account' } }))
  assert.equal(self.code, 'validation_failed')
  assert.match(self.message, /can't be linked to itself/)

  const ok = bodyOf(await callWith(writingCtx(), 'update_account', { id: 'pm-icici', set: { parent_account: 'pm-hdfc' } }))
  assert.equal(ok.created, true)
})

test('linked_to and member are held to the copy like every other name', async () => {
  const link = errorOf(await callWith(writingCtx(), 'update_account', { id: 'pm-icici', set: { linked_to: 'Nobody' } }))
  assert.equal(link.code, 'not_found')
  assert.match(link.message, /No account in the hosted copy \(pushed 2026-09-17\) is called "Nobody"/)

  const owner = errorOf(await callWith(writingCtx(), 'update_account', { id: 'pm-icici', set: { member: 'Grandma' } }))
  assert.equal(owner.code, 'not_found')
  assert.match(owner.message, /No person in the hosted copy \(pushed 2026-09-17\) is called "Grandma"\. People: "Rohit" \(id m-rohit\), "Diya" \(id m-diya\)/)
  assert.deepEqual(owner.candidates, [{ name: 'Rohit', id: 'm-rohit' }, { name: 'Diya', id: 'm-diya' }])

  const before = filed.length
  const ok = bodyOf(await callWith(writingCtx(), 'update_account', {
    id: 'pm-icici', set: { linked_to: 'hdfc current account', member: 'm-diya', notes: 'Card name: Coral\nShared card.' },
  }))
  assert.equal(ok.created, true)
  assert.deepEqual(filed.at(-1)!.payload.set, { linked_to: 'hdfc current account', member: 'm-diya', notes: 'Card name: Coral\nShared card.' })
  const cleared = bodyOf(await callWith(writingCtx(), 'update_account', { id: 'pm-icici', set: { member: null, linked_to: null } }))
  assert.equal(cleared.created, true, 'clearing names nobody, so there is nothing to look up')
  const role = bodyOf(await callWith(writingCtx(), 'update_person', { name: 'Diya', set: { tag: 'family' } }))
  assert.equal(role.created, true)
  assert.equal(filed.length, before + 3)
})

// An account's card name and details are longbook's own, and so are a person's details: refused
// by name and never filed, so no write is answered as a success that dropped them.
test('an account or person write sending card_name or details is refused by name, and never filed', async () => {
  const before = filed.length
  const account = "card_name and details are longbook's own — write an account's details as lines of its notes"
  for (const set of [{ card_name: 'Coral' }, { notes: 'Shared card.', card_name: 'Coral' }, { details: { due_day: 5 } }]) {
    const refused = errorOf(await callWith(writingCtx(), 'update_account', { id: 'pm-icici', set }))
    assert.equal(refused.code, 'validation_failed')
    assert.equal(refused.message, `Nothing was changed. Fix these — ${account}.`)
  }
  const member = "details is longbook's own — a member carries a name, a tag, an email and linked accounts"
  for (const set of [{ details: { relationship: 'sister' } }, { tag: 'family', details: { role: 'cook' } }, { card_name: 'Coral' }]) {
    const refused = errorOf(await callWith(writingCtx(), 'update_person', { name: 'Diya', set }))
    assert.equal(refused.code, 'validation_failed')
    assert.equal(refused.message, `Nothing was changed. Fix these — ${member}.`)
  }
  assert.equal(filed.length, before, 'nothing was filed')
})

// A key update_account or update_member does not take is filed and never applied, so the answer
// names it, with the key meant where one is, in the words the Mac door answers with.
test('update_account and update_person file what they take and name the keys they do not', async () => {
  const account = bodyOf(await callWith(writingCtx(), 'update_account', {
    id: 'pm-icici', set: { notes: 'Shared card.', type: 'credit card', belongs_to: 'Diya', card_name: '', details: {}, colour: 'red' },
  }))
  assert.equal(account.created, true)
  assert.deepEqual(account.ignored, [
    'type — the account type is tag',
    'belongs_to — the person is member',
    "card_name — a card's name is a line of notes",
    "details — an account's details are lines of its notes",
    'colour',
  ])
  const linked = bodyOf(await callWith(writingCtx(), 'update_account', { id: 'pm-icici', set: { linked_to: 'pm-hdfc', parent: 'Nobody' } }))
  assert.equal(linked.created, true, 'the older name is never looked up beside linked_to')
  assert.deepEqual(linked.ignored, ['parent — linked_to wins'])
  const person = bodyOf(await callWith(writingCtx(), 'update_person', {
    name: 'Diya', set: { tag: 'family', role: 'sister', notes: 'Role: cook', details: null },
  }))
  assert.equal(person.created, true)
  assert.deepEqual(person.ignored, [
    'role — their role is tag',
    'notes — what is said about a person goes in the notes of the commitment it is about',
    'details — a member carries a name, a tag, an email and linked accounts',
  ])
  assert.equal(bodyOf(await callWith(writingCtx(), 'update_account', { id: 'pm-icici', set: { notes: 'Shared card.' } })).ignored, undefined)
  assert.equal(bodyOf(await callWith(writingCtx(), 'update_person', { name: 'Diya', set: { email: 'diya@example.com' } })).ignored, undefined)
})

test('the hosted door says when the rows just filed outrun an account\'s balance, and whoami names every stale one', async () => {
  const data = fixture()
  Object.assign(data.methods[1]!, { balance: 31250, balance_date: inDays(-10) })
  const context = writingCtx(undefined, data)
  const once = { name: 'Taxi', amount: 900, currency: 'INR', billing_cycle: 'once', date: inDays(-2), paid: true, basis: 'statement', account: 'ICICI Joint Account' }
  const { paid: _paid, basis: _basis, ...bare } = once

  // The card's statement row in the fixture is a month old: the balance is not yet stale.
  assert.deepEqual(bodyOf(await callWith(context, 'whoami')).memory.stale_balances, [])

  const stale = bodyOf(await callWith(context, 'add_commitments', { rows: [once, { ...ROW, account: 'ICICI Joint Account' }] }))
  assert.equal(stale.created, true)
  assert.equal(
    stale.balance_note,
    `ICICI Joint Account: balance as of ${inDays(-10)} is older than the newest charge written, ${inDays(-2)} — when the statement prints a closing balance, update_account with balance and balance_date its last day.`,
  )
  // Older than the balance, unconfirmed, still ahead, or billed to a name the copy lacks: nothing to say.
  const quiet = bodyOf(await callWith(context, 'add_commitments', { rows: [
    { ...once, date: inDays(-12) }, { ...bare, date: inDays(-1) }, { ...once, date: inDays(1) }, { ...once, account: 'Fi Money' },
  ] }))
  assert.equal(quiet.balance_note, undefined)

  // Netflix is billed to the card: a statement row on it says the same; a plan row says nothing.
  const proved = bodyOf(await callWith(context, 'add_charges', { name: 'Netflix', charges: [{ date: inDays(-4), paid: true, basis: 'statement' }] }))
  assert.match(proved.balance_note, new RegExp(`^ICICI Joint Account: balance as of ${inDays(-10)} is older than the newest charge written, ${inDays(-4)} —`))
  const planned = bodyOf(await callWith(context, 'add_charges', { name: 'Netflix', charges: [{ date: inDays(-4) }] }))
  assert.equal(planned.balance_note, undefined)

  // Once the copy holds a newer confirmed charge, whoami names the account with both days.
  data.charges!.push(mkRow('s-netflix', inDays(-5), 649, { paid: true, basis: 'statement' }))
  assert.deepEqual(bodyOf(await callWith(context, 'whoami')).memory.stale_balances, [
    { account: 'ICICI Joint Account', balance_date: inDays(-10), newest_charge: inDays(-5) },
  ])
  assert.equal(bodyOf(await callWith(context, 'accounts')).accounts[1].balance_note.startsWith(`Balance as of ${inDays(-10)}, older than`), true)
})

test('accounts and members answer over the wire with what the memory holds', async () => {
  const accounts = bodyOf(await callWith(ctx(), 'accounts'))
  assert.deepEqual(accounts.accounts.map((a: { name: string }) => a.name), ['HDFC Current account', 'ICICI Joint Account'])
  const people = bodyOf(await callWith(ctx(), 'people'))
  assert.deepEqual(people.members.map((m: { name: string }) => m.name), ['Rohit', 'Diya'])
  const cold = await callWith(ctx(null), 'accounts')
  assert.equal(errorOf(cold).code, 'not_found', 'no copy is said plainly, never an empty list')
})

test('a commitment miss lists the nearest names, else the most recent, and points at the reads', async () => {
  const near = errorOf(await callWith(writingCtx(), 'mark_paid', { name: 'Net', date: inDays(3) }))
  assert.equal(near.code, 'not_found')
  assert.match(near.message, /No commitment in the hosted copy \(pushed 2026-09-17\) is called "Net"\. Nearest by name: "Netflix" \(id s-netflix, active\)\./)
  assert.match(near.message, /Read commitments \(status "all"\) or search for the rest/)
  assert.deepEqual(near.candidates, [{ name: 'Netflix', id: 's-netflix', status: 'active' }])

  const far = errorOf(await callWith(writingCtx(), 'add_charges', { name: 'Spotify', charges: [{ date: inDays(3) }] }))
  assert.equal(far.code, 'not_found')
  assert.match(far.message, /Most recent: /)
  assert.equal(far.candidates.length, 8, 'every fixture commitment, fewer than ten')

  const cancelled = errorOf(await callWith(writingCtx(), 'cancel_commitment', { name: 'Hotstar' }))
  assert.equal(cancelled.code, 'validation_failed')
  assert.match(cancelled.message, /"Hotstar" \(id s-old\) is already cancelled/)

  const removed = bodyOf(await callWith(writingCtx(), 'remove_charges', { id: 's-rent', dates: [inDays(3)] }))
  assert.equal(removed.created, true)
})

test('promote_to_recurring needs every id to be a one-time row the copy holds', async () => {
  const unknown = errorOf(await callWith(writingCtx(), 'promote_to_recurring', { ids: ['s-flight', 's-nope'], billing_cycle: 'monthly' }))
  assert.equal(unknown.code, 'not_found')
  assert.match(unknown.message, /No commitment in the hosted copy \(pushed 2026-09-17\) has the id s-nope/)

  const monthly = errorOf(await callWith(writingCtx(), 'promote_to_recurring', { ids: ['s-netflix'], billing_cycle: 'monthly' }))
  assert.equal(monthly.code, 'validation_failed')
  assert.match(monthly.message, /"Netflix" \(id s-netflix\) is monthly, not a one-time commitment/)

  const ok = bodyOf(await callWith(writingCtx(), 'promote_to_recurring', { ids: ['s-flight'], billing_cycle: 'yearly' }))
  assert.equal(ok.created, true)
})

test('a promotion that mixes directions is refused before filing, naming each row', async () => {
  const data = fixture()
  data.subs.push(
    mkSub({ id: 's-bill', name: 'Coral card bill', amount: 31250, billing_cycle: 'once', direction: 'transfer' }),
    mkSub({ id: 's-bill-2', name: 'Coral card bill', amount: 28900, billing_cycle: 'once', direction: 'transfer' }),
    mkSub({ id: 's-refund', name: 'Refund', amount: 900, billing_cycle: 'once', direction: 'in' }),
  )
  const door = writingCtx(undefined, data)
  const before = filed.length
  const spend = errorOf(await callWith(door, 'promote_to_recurring', { ids: ['s-flight', 's-bill'], billing_cycle: 'monthly' }))
  assert.equal(spend.code, 'validation_failed')
  assert.match(spend.message, /These rows do not share a direction: promote spending, money in and transfers separately/)
  assert.match(spend.message, /"Flight to Goa" is spending, "Coral card bill" is a transfer/)
  assert.deepEqual(spend.candidates.map((c: { id: string }) => c.id), ['s-flight', 's-bill'])
  const credit = errorOf(await callWith(door, 'promote_to_recurring', { ids: ['s-refund', 's-bill'], billing_cycle: 'monthly' }))
  assert.match(credit.message, /"Refund" is money in, "Coral card bill" is a transfer/)
  assert.equal(filed.length, before, 'nothing was filed')

  const ok = bodyOf(await callWith(door, 'promote_to_recurring', { ids: ['s-bill', 's-bill-2'], billing_cycle: 'monthly' }))
  assert.equal(ok.created, true, 'one direction across the ids files')
})

test('update_commitment takes direction null on the hosted door, and its schema says so', async () => {
  const schema = WRITE_TOOLS.find((t) => t.name === 'update_commitment')!.inputSchema as Record<string, any>
  const direction = schema.properties.set.properties.direction
  assert.deepEqual(direction.type, ['string', 'null'])
  assert.deepEqual(direction.enum, ['in', 'out', 'transfer', null])
  const ok = bodyOf(await callWith(writingCtx(), 'update_commitment', { id: 's-rent', set: { direction: null } }))
  assert.equal(ok.created, true)
  assert.deepEqual(filed.at(-1)!.payload.set, { direction: null })
})

test('an amount past the limit is refused before filing, on every write that takes one', async () => {
  const before = filed.length
  const huge = 9.3e18
  const calls: [string, Record<string, unknown>][] = [
    ['add_commitments', { rows: [{ ...ROW, amount: huge }] }],
    ['update_commitment', { id: 's-rent', set: { amount: huge } }],
    ['mark_paid', { id: 's-rent', date: inDays(3), amount: huge }],
    ['add_charges', { id: 's-rent', charges: [{ date: inDays(90), amount: huge }] }],
  ]
  for (const [name, args] of calls) {
    const refused = errorOf(await callWith(writingCtx(), name, args))
    assert.equal(refused.code, 'validation_failed', name)
    assert.match(refused.message, /the amount can't be more than 1,000,000,000,000,000/i, name)
  }
  assert.equal(filed.length, before, 'nothing was filed')
})

test('a commitment holding several charges is not made one-time: refused before filing, in the app\'s words', async () => {
  const before = filed.length
  const refused = errorOf(await callWith(writingCtx(), 'update_commitment', { id: 's-rent', set: { billing_cycle: 'once' } }))
  assert.equal(refused.code, 'validation_failed')
  assert.equal(refused.message, 'One-time holds a single charge, and this has 12. Cancel it instead to stop its plan.')
  assert.equal(filed.length, before, 'nothing was filed')
  const single = bodyOf(await callWith(writingCtx(), 'update_commitment', { id: 's-carins', set: { billing_cycle: 'once' } }))
  assert.equal(single.created, true, 'one charge is a one-time commitment\'s own')
})

test('a date for a one-time commitment holding several charges is refused before filing, in the app\'s words', async () => {
  const data = fixture()
  data.subs.push(mkSub({ id: 's-sofa', name: 'Sofa', amount: 500, billing_cycle: 'once' }))
  data.charges = [...(data.charges ?? []),
    mkRow('s-sofa', inDays(-20), 500, { paid: true, basis: 'statement' }), mkRow('s-sofa', inDays(20), 500, { basis: 'user' })]
  const door = writingCtx(undefined, data)
  const before = filed.length
  const refused = errorOf(await callWith(door, 'update_commitment', { id: 's-sofa', set: { date: inDays(30), notes: 'Two parts' } }))
  assert.equal(refused.code, 'validation_failed')
  assert.equal(refused.message, 'This one-time commitment has 2 charges. Move the one you mean from the charge itself.')
  assert.equal(filed.length, before, 'nothing was filed')
  assert.equal(bodyOf(await callWith(door, 'update_commitment', { id: 's-sofa', set: { notes: 'Two parts' } })).created, true)
  assert.equal(bodyOf(await callWith(door, 'update_commitment', { id: 's-flight', set: { date: inDays(61) } })).created, true,
    'a one-time commitment holding one charge moves it')
})

// A key the tool does not take is filed and never applied, so the answer names it, with the
// key meant where one is, in the words the Mac door answers with.
test('update_commitment files what it takes and names the keys it does not, with the key meant', async () => {
  const out = bodyOf(await callWith(writingCtx(), 'update_commitment', {
    id: 's-rent', set: { notes: 'Lease: 11 months', cancelling_on: '2026-12-31', colour: 'red' },
  }))
  assert.equal(out.created, true)
  assert.deepEqual(out.ignored, ['cancelling_on — the cancelling date is ends_on', 'colour'])
  const dated = bodyOf(await callWith(writingCtx(), 'update_commitment', { id: 's-rent', set: { amount: 43000, date: inDays(4) } }))
  assert.deepEqual(dated.ignored, ["date — only a one-time commitment's charge moves by date"])
  assert.equal(bodyOf(await callWith(writingCtx(), 'update_commitment', { id: 's-rent', set: { notes: 'Lease: 11 months' } })).ignored, undefined)
  assert.equal(bodyOf(await callWith(writingCtx(), 'update_commitment', { id: 's-flight', set: { date: inDays(61) } })).ignored, undefined)
  assert.equal(bodyOf(await callWith(writingCtx(), 'update_commitment', { id: 's-carins', set: { billing_cycle: 'once', date: inDays(41) } })).ignored,
    undefined, 'made one-time in the same set, its date moves its charge')
})

// The app writes days only onto a custom cycle, and a date moves a one-time commitment's
// charge only when it holds one: each other one is named, as the Mac door names it.
test('update_commitment names days off a custom cycle and a date with no charge to move as ignored', async () => {
  const data = fixture()
  data.subs.push(mkSub({ id: 's-deposit', name: 'Deposit', amount: 5000, billing_cycle: 'once' }),
    mkSub({ id: 's-gym', name: 'Gym', amount: 1500 }))
  const door = writingCtx(undefined, data)
  const ignored = async (id: string, set: Record<string, unknown>) => {
    const out = bodyOf(await callWith(door, 'update_commitment', { id, set }))
    assert.equal(out.created, true, `${id} files`)
    return out.ignored
  }
  const days = 'custom_cycle_days — custom_cycle_days goes with billing_cycle custom'
  assert.deepEqual(await ignored('s-rent', { custom_cycle_days: 14, notes: 'Lease: 11 months' }), [days])
  assert.deepEqual(await ignored('s-water', { billing_cycle: 'monthly', custom_cycle_days: 7 }), [days])
  assert.equal(await ignored('s-water', { custom_cycle_days: 14 }), undefined)
  assert.equal(await ignored('s-rent', { billing_cycle: 'custom', custom_cycle_days: 14 }), undefined)
  assert.equal(await ignored('s-rent', { custom_cycle_days: null }), undefined, 'clearing the days is what a monthly cycle holds')

  const date = 'date — the commitment holds no charge to move; add_charges writes one'
  assert.deepEqual(await ignored('s-deposit', { date: inDays(30), notes: 'Refundable' }), [date])
  assert.deepEqual(await ignored('s-gym', { billing_cycle: 'once', date: inDays(30) }), [date])
  assert.equal(await ignored('s-flight', { date: inDays(61) }), undefined, 'a sole charge moves')
})

test('add_commitments with a new member or account name files — the app makes the placeholder', async () => {
  const out = bodyOf(await callWith(writingCtx(), 'add_commitments', { rows: [{ ...ROW, member: 'Grandma', account: 'Fi Money' }] }))
  assert.equal(out.created, true)
  assert.equal(filed.at(-1)!.kind, 'add_commitments')
})

test('without a copy, a write that addresses a row is refused, not filed blind', async () => {
  const cold = writingCtx(undefined, null)
  const error = errorOf(await callWith(cold, 'update_account', { name: 'HDFC Current account', set: { tag: 'cash' } }))
  assert.equal(error.code, 'not_found')
  assert.match(error.message, /No hosted copy of your financial memory exists yet/)
  const create = bodyOf(await callWith(cold, 'add_commitments', { rows: [ROW] }))
  assert.equal(create.created, true, 'a write that only creates still files')
})

test('the copy date is left out of the refusal when the door does not state one', async () => {
  const bare: RpcContext = { ...writingCtx(), identity: () => ({ key_name: 'k', scopes: ['memory:read', 'memory:propose'] }) }
  const error = errorOf(await callWith(bare, 'update_person', { name: 'Nobody', set: { email: 'x@y' } }))
  assert.match(error.message, /No person in the hosted copy is called "Nobody"\. People: "Rohit" \(id m-rohit\), "Diya" \(id m-diya\)/)
  assert.equal(error.hosted_copy_pushed_at, null)
})

// ---------------------------------------------------------------------------------------------
// The seven writes of revision 32, filed or refused against the copy as the app would refuse.

test('update_charge files against a charge the copy holds, and refuses a missing one or a day already taken', async () => {
  const data = fixture()
  const planned = data.charges!.filter((c) => c.commitment_id === 's-netflix' && !c.paid).map((c) => c.date).sort()
  const [first, second] = planned as [string, string]
  const before = filed.length
  const out = await callWith(writingCtx(), 'update_charge', { name: 'Netflix', date: first, set: { amount: 699, and_later: true }, idempotency_key: 'k:1' })
  assert.equal(JSON.parse(out.result.content[0].text).created, true)
  assert.equal(filed.at(-1)!.kind, 'update_charge')
  assert.deepEqual(filed.at(-1)!.payload, { name: 'Netflix', date: first, set: { amount: 699, and_later: true } })

  const missing = errorOf(await callWith(writingCtx(), 'update_charge', { name: 'Netflix', date: '2031-01-01', set: { paid: true } }))
  assert.equal(missing.code, 'not_found')
  assert.match(missing.message, /^No charge on 2031-01-01 is written for "Netflix"\. Its charges in the hosted copy \(pushed 2026-09-17\): /)
  const taken = errorOf(await callWith(writingCtx(), 'update_charge', { name: 'Netflix', date: first, set: { date: second } }))
  assert.equal(taken.code, 'validation_failed')
  assert.match(taken.message, /^A charge already sits on .*\. Move or remove it first\.$/)
  const run = await callWith(writingCtx(), 'update_charge', { name: 'Netflix', date: first, set: { date: second, and_later: true } })
  assert.equal(JSON.parse(run.result.content[0].text).created, true, 'with the rows after it, the app judges each landing')
  const empty = errorOf(await callWith(writingCtx(), 'update_charge', { name: 'Netflix', date: first, set: { and_later: true } }))
  assert.equal(empty.code, 'validation_failed')
  assert.equal(empty.message, 'Nothing was changed. Fix these — set names none of date, amount, paid, paid_on, note.')
  assert.equal(filed.length, before + 2)
})

test('set_planned_count files for a recurring commitment and refuses a one-time one in the app\'s words', async () => {
  const before = filed.length
  const out = await callWith(writingCtx(), 'set_planned_count', { name: 'Netflix', count: 24 })
  assert.equal(JSON.parse(out.result.content[0].text).created, true)
  assert.deepEqual(filed.at(-1)!.payload, { name: 'Netflix', count: 24 })
  const once = errorOf(await callWith(writingCtx(), 'set_planned_count', { name: 'Flight to Goa', count: 3 }))
  assert.equal(once.code, 'validation_failed')
  assert.equal(once.message, 'A one-time commitment has its one charge; there is nothing to plan.')
  const high = errorOf(await callWith(writingCtx(), 'set_planned_count', { name: 'Netflix', count: 241 }))
  assert.equal(high.message, 'count is a whole number of charges, 1 to 240.')
  const cancelled = errorOf(await callWith(writingCtx(), 'set_planned_count', { name: 'Hotstar', count: 12 }))
  assert.equal(cancelled.code, 'validation_failed')
  assert.equal(cancelled.message, '"Hotstar" is cancelled; set its status to active first, then plan.', 'the local door\'s words, and the app\'s')
  assert.equal(filed.length, before + 1)
})

test('add_person and add_account file a new row, refuse a twin by its id, and resolve a link and an owner', async () => {
  const before = filed.length
  const person = await callWith(writingCtx(), 'add_person', { name: 'Meera', tag: 'family', email: 'meera@example.com' })
  assert.equal(JSON.parse(person.result.content[0].text).created, true)
  assert.equal(filed.at(-1)!.kind, 'add_person')
  const twin = errorOf(await callWith(writingCtx(), 'add_person', { name: 'rohit' }))
  assert.equal(twin.code, 'validation_failed')
  assert.equal(twin.message, 'There\'s already a person called "rohit" in the hosted copy (pushed 2026-09-17) (id m-rohit). Adding a twin is refused; update_person changes it.')
  assert.deepEqual(twin.candidates, [{ name: 'Rohit', id: 'm-rohit' }])

  const account = await callWith(writingCtx(), 'add_account', { name: 'Coral 9292', tag: 'credit card', linked_to: 'HDFC Current account', member: 'Diya', balance: 100 })
  assert.equal(JSON.parse(account.result.content[0].text).created, true)
  assert.equal(filed.at(-1)!.kind, 'add_account')
  const held = errorOf(await callWith(writingCtx(), 'add_account', { name: 'hdfc current account' }))
  assert.equal(held.code, 'validation_failed')
  assert.match(held.message, /^There's already an account called "hdfc current account" in the hosted copy \(pushed 2026-09-17\) \(id pm-hdfc\)\. Adding a twin is refused; update_account changes it\.$/)
  const nobody = errorOf(await callWith(writingCtx(), 'add_account', { name: 'Coral', member: 'Nobody' }))
  assert.equal(nobody.code, 'not_found')
  assert.match(nobody.message, /No person in the hosted copy .* is called "Nobody"\. People: "Rohit"/)
  const unlinked = errorOf(await callWith(writingCtx(), 'add_account', { name: 'Coral', linked_to: 'Nowhere' }))
  assert.equal(unlinked.code, 'not_found')
  assert.match(unlinked.message, /No account in the hosted copy .* is called "Nowhere"/)
  // The link under an older name is the link here too, checked against the copy the same way.
  const byParent = await callWith(writingCtx(), 'add_account', { name: 'Reef', parent: 'HDFC Current account' })
  assert.equal(JSON.parse(byParent.result.content[0].text).created, true)
  assert.deepEqual(filed.at(-1)!.payload, { name: 'Reef', parent: 'HDFC Current account' })
  const strayParent = errorOf(await callWith(writingCtx(), 'add_account', { name: 'Reef', parent_account: 'Nowhere' }))
  assert.equal(strayParent.code, 'not_found')
  const blankParent = errorOf(await callWith(writingCtx(), 'add_account', { name: 'Reef', parent: '  ' }))
  assert.equal(blankParent.message, 'Nothing was changed. Fix these — parent is an account name or id, or null to clear it.')
  const linked: Account = { ...fixture().methods[1]!, parent_account_id: 'pm-hdfc' }
  const chained = errorOf(await callWith(writingCtx(undefined, { ...fixture(), methods: [fixture().methods[0]!, linked] }), 'add_account', { name: 'Coral', linked_to: 'ICICI Joint Account' }))
  assert.equal(chained.code, 'validation_failed')
  assert.match(chained.message, /already linked to another account — one level only/)
  const refused = errorOf(await callWith(writingCtx(), 'add_account', { name: 'Coral', card_name: 'Platinum' }))
  assert.equal(refused.message, "Nothing was changed. Fix these — card_name and details are longbook's own — write an account's details as lines of its notes.")
  assert.equal(filed.length, before + 3)
})

test('rename_tag and delete_tag file against a tag the copy holds or wears, and refuse a twin or a stranger', async () => {
  const before = filed.length
  const worn = await callWith(writingCtx(), 'rename_tag', { kind: 'commitment', from: 'entertainment', to: 'Streaming' })
  assert.equal(JSON.parse(worn.result.content[0].text).created, true, 'worn but never registered is still a tag')
  assert.deepEqual(filed.at(-1)!.payload, { kind: 'commitment', from: 'entertainment', to: 'Streaming' })
  const stranger = errorOf(await callWith(writingCtx(), 'rename_tag', { kind: 'commitment', from: 'Pets', to: 'Pet care' }))
  assert.equal(stranger.code, 'not_found')
  assert.equal(stranger.message, 'No commitment tag in the hosted copy (pushed 2026-09-17) is called "Pets". commitment tags: "Entertainment", "Home", "Insurance", "Work", "Travel".')
  const none = errorOf(await callWith(writingCtx(), 'delete_tag', { kind: 'member', name: 'family' }))
  assert.equal(none.message, 'No member tag in the hosted copy (pushed 2026-09-17) is called "family". The copy holds no member tag.')

  const registry = { ...fixture(), tags: [
    { id: 't-home', kind: 'commitment' as const, name: 'Home', name_key: 'home', icon: 'house', is_default: true, sort: 0, created_at: '' },
    { id: 't-work', kind: 'commitment' as const, name: 'Work', name_key: 'work', icon: null, is_default: false, sort: 1, created_at: '' },
  ] }
  const twin = errorOf(await callWith(writingCtx(undefined, registry), 'rename_tag', { kind: 'commitment', from: 'Home', to: 'work' }))
  assert.equal(twin.code, 'validation_failed')
  assert.equal(twin.message, 'There\'s already one called "work".')
  const cased = await callWith(writingCtx(undefined, registry), 'rename_tag', { kind: 'commitment', from: 'Home', to: 'HOME' })
  assert.equal(JSON.parse(cased.result.content[0].text).created, true, 'only the case changes: no twin')

  const gone = await callWith(writingCtx(), 'delete_tag', { kind: 'commitment', name: 'Travel' })
  assert.equal(JSON.parse(gone.result.content[0].text).created, true)
  const kind = errorOf(await callWith(writingCtx(), 'delete_tag', { kind: 'thing', name: 'Travel' }))
  assert.equal(kind.message, 'kind is commitment, member, account — which list the tag belongs to.')
  assert.equal(filed.length, before + 3)
})

test('delete_commitment files by id alone, and refuses a name or an id the copy lacks', async () => {
  const before = filed.length
  const out = await callWith(writingCtx(), 'delete_commitment', { id: 's-old', source: 'the owner said delete' })
  assert.equal(JSON.parse(out.result.content[0].text).created, true)
  assert.equal(filed.at(-1)!.kind, 'delete_commitment')
  assert.equal(filed.at(-1)!.source_ref, 'the owner said delete')
  const named = errorOf(await callWith(writingCtx(), 'delete_commitment', { name: 'Hotstar' }))
  assert.equal(named.code, 'validation_failed')
  assert.equal(named.message, 'Say which commitment: pass its id. delete_commitment takes no name.')
  const gone = errorOf(await callWith(writingCtx(), 'delete_commitment', { id: 's-nope' }))
  assert.equal(gone.code, 'not_found')
  assert.match(gone.message, /No commitment in the hosted copy .* has the id s-nope/)
  assert.equal(filed.length, before + 1)
})

test('both doors make a placeholder for a member or account update_commitment names: the hosted door files it', async () => {
  const before = filed.length
  const out = await callWith(writingCtx(), 'update_commitment', { name: 'Netflix', set: { member: 'Nobody', account: 'Nowhere' } })
  const answer = JSON.parse(out.result.content[0].text)
  assert.equal(answer.created, true)
  assert.equal(answer.ignored, undefined)
  assert.equal(filed.length, before + 1)
})

test('the new kinds wear honest annotations and schemas: deletes destructive, every clearable field nullable', () => {
  const tool = (name: string) => WRITE_TOOLS.find((t) => t.name === name)!
  assert.equal(tool('delete_commitment').annotations.destructiveHint, true)
  assert.equal(tool('delete_tag').annotations.destructiveHint, true)
  for (const name of ['update_charge', 'set_planned_count', 'add_person', 'add_account', 'rename_tag']) {
    assert.equal(tool(name).annotations.destructiveHint, false, name)
  }
  const props = (name: string, path: string[]) => path.reduce<any>((at, key) => at.properties[key], tool(name).inputSchema)
  assert.deepEqual(props('update_charge', ['set']).properties.paid_on.type, ['string', 'null'])
  assert.deepEqual(props('update_charge', ['set']).properties.note.type, ['string', 'null'])
  assert.deepEqual(props('mark_paid', []).properties.paid_on.type, ['string', 'null'])
  assert.deepEqual(props('mark_paid', []).properties.note.type, ['string', 'null'])
  assert.deepEqual(props('add_charges', ['charges']).items.properties.note.type, ['string', 'null'])
  assert.equal(props('set_planned_count', []).properties.count.maximum, 240)
  assert.equal(props('add_commitments', ['rows']).items.properties.plan_count.maximum, 240)
  assert.equal(props('update_commitment', ['set']).properties.free_trial.type, 'boolean')
  assert.deepEqual(tool('delete_commitment').inputSchema.required, ['id'])
  assert.equal('name' in (tool('delete_commitment').inputSchema as any).properties, false, 'by id only')
})

test('create_report files for the app to draw, says nothing waits in Changes, and refuses a name the copy lacks', async () => {
  const before = filed.length
  const out = await callWith(writingCtx(), 'create_report', {
    title: 'Goa', start_date: '2026-09-28', end_date: '2026-09-30', accounts: ['icici joint account'], members: ['Diya'], categories: ['Travel'], idempotency_key: 'report:goa',
  })
  const answer = JSON.parse(out.result.content[0].text)
  assert.equal(answer.created, true)
  assert.equal(answer.note, REPORT_FILED_NOTE)
  assert.equal(REPORT_FILED_NOTE, 'Filed. longbook draws the report on its Reports screen the next time the owner opens the app — tell them so, and stop here. A report is drawn from the rows; nothing waits in Changes.')
  const proposal = filed.at(-1)!
  assert.equal(proposal.kind, 'create_report')
  assert.equal(proposal.idempotency_key, 'report:goa')
  assert.deepEqual(proposal.payload, { title: 'Goa', start_date: '2026-09-28', end_date: '2026-09-30', accounts: ['icici joint account'], members: ['Diya'], categories: ['Travel'] })

  const drawn = errorOf(await callWith(writingCtx(), 'create_report', { title: 'Goa', start_date: '2026-09-28', end_date: '2026-09-30', currency: 'INR' }))
  assert.equal(drawn.code, 'validation_failed')
  assert.equal(drawn.message, 'longbook draws the report; name only title, start_date, end_date, accounts, members and categories.')
  const stranger = errorOf(await callWith(writingCtx(), 'create_report', { title: 'Goa', start_date: '2026-09-28', end_date: '2026-09-30', members: ['Meera'] }))
  assert.equal(stranger.code, 'not_found')
  assert.equal(stranger.message, 'No person in the hosted copy (pushed 2026-09-17) is called "Meera". People: "Rohit" (id m-rohit), "Diya" (id m-diya). Pass one of these names exactly, or its id.')
  assert.equal(filed.length, before + 1)
})

test('a write says beside its filing when it skipped the guide, and says nothing once it read it', async () => {
  const guided = (): RpcContext => ({ ...writingCtx(), llmsText: () => LLMS_TXT })
  const read = async (section: string) =>
    JSON.parse((await callWith(guided(), 'read_guide', { section })).result.content[0].text)
  const statements = await read('importing-statements')
  assert.match(statements.guide_key, /^importing-statements:\d+:[0-9a-z]+$/)
  assert.match((await read('Add my statement')).guide_key, /^add-my-statement:\d+:[0-9a-z]+$/)
  const tags = (await read('tags')).guide_key

  const skipped = JSON.parse((await callWith(guided(), 'add_commitments', { rows: [ROW] })).result.content[0].text)
  assert.match(skipped.guide_warning, /^No guide_key: call read_guide/)
  const followed = JSON.parse((await callWith(guided(), 'add_commitments', { rows: [ROW], guide_key: statements.guide_key })).result.content[0].text)
  assert.equal(followed.guide_warning, undefined)
  assert.equal('guide_key' in filed.at(-1)!.payload, false, 'the key is checked, never filed')

  const stale = JSON.parse((await callWith(guided(), 'add_commitments', { rows: [ROW], guide_key: 'tags:43:abc' })).result.content[0].text)
  assert.match(stale.guide_warning, /^This guide_key is not from rulebook \d+'s guide/)
  const line = { ...ROW, billing_cycle: 'once', date: '2026-09-01', paid: true, basis: 'statement' }
  const wrongChapter = JSON.parse((await callWith(guided(), 'add_commitments', { rows: [line], guide_key: tags })).result.content[0].text)
  assert.match(wrongChapter.guide_warning, /^Rows with basis "statement" follow read_guide\("importing-statements"\)/)
  const rightChapter = JSON.parse((await callWith(guided(), 'add_commitments', { rows: [line], guide_key: statements.guide_key })).result.content[0].text)
  assert.equal(rightChapter.guide_warning, undefined)
})

test('every write lists guide_key', async () => {
  const listed = (await call('tools/list')).result.tools as { name: string; inputSchema: { properties: object } }[]
  for (const name of WRITE_NAMES) assert.ok('guide_key' in listed.find((t) => t.name === name)!.inputSchema.properties, name)
})
