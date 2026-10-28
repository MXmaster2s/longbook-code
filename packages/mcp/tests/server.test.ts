// The whole server over a real MCP handshake — an in-memory transport pair standing in
// for stdio, a temp folder standing in for the vault.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { Client } from '@modelcontextprotocol/sdk/client/index.js'
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js'
import { CONTRACT_REVISION, PROMPTS, promptGuideKey, toISO, todayMid } from '@longbook/core'
import { TOOLS } from '../src/catalog.js'
import { WRITE_TOOLS, checkProposal } from '../src/proposal.js'
import { MCP_PROMPTS, mcpPromptMessage } from '../src/prompts.js'
import { buildServer } from '../src/server.js'
import { VaultReader } from '../src/vault.js'

function seededVaultDir(): string {
  const today = todayMid()
  const due = toISO(new Date(today.getFullYear(), today.getMonth(), today.getDate() + 3))
  const dir = mkdtempSync(join(tmpdir(), 'longbook-mcp-server-'))
  writeFileSync(
    join(dir, 'financial_memory.json'),
    JSON.stringify({
      app: 'longbook',
      version: 3,
      commitments: [
        { id: 's1', name: 'Netflix', amount: 649, currency: 'INR', billing_cycle: 'monthly', status: 'active' },
      ],
      charges: [{ commitment_id: 's1', date: due, amount: 649, paid: false, basis: 'plan' }],
      members: [],
      accounts: [],
    }),
  )
  writeFileSync(join(dir, 'llms.txt'), '# longbook\n\nthe contract text.')
  writeFileSync(join(dir, 'longbook.schema.json'), '{"title": "longbook financial memory"}')
  return dir
}

/** A key read_guide hands out, for writes that followed the guide. */
const KEY = promptGuideKey(PROMPTS[0]!, CONTRACT_REVISION)

async function connected() {
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair()
  await buildServer(new VaultReader(seededVaultDir())).connect(serverTransport)
  const client = new Client({ name: 'test-client', version: '0.0.0' })
  await client.connect(clientTransport)
  return client
}

const textOf = (result: Awaited<ReturnType<Client['callTool']>>): string => {
  const content = result.content as { type: string; text?: string }[]
  return content[0]?.text ?? ''
}

test('the server offers seventeen read tools, eighteen write tools, and the three contract resources', async () => {
  const client = await connected()
  const tools = (await client.listTools()).tools.map((t) => t.name).sort()
  assert.deepEqual(tools, [
    'accounts', 'add_account', 'add_charges', 'add_commitments', 'add_person', 'cancel_commitment', 'cashflow',
    'charges', 'commitments', 'create_report', 'delete_commitment', 'delete_tag', 'leave_insight', 'list_documents',
    'mark_paid', 'next_payment', 'people', 'promote_to_recurring', 'read_document', 'read_guide', 'remove_charges',
    'rename_tag', 'reports', 'search', 'set_planned_count', 'spending_by_account', 'spending_by_category',
    'spending_by_person', 'tags', 'upcoming', 'update_account', 'update_charge', 'update_commitment',
    'update_person', 'whoami',
  ])
  const resources = (await client.listResources()).resources.map((r) => r.uri).sort()
  assert.deepEqual(resources, [
    'longbook://vault/library.json',
    'longbook://vault/llms.txt',
    'longbook://vault/longbook.schema.json',
    'ui://longbook/cashflow.html',
    'ui://longbook/commitments.html',
    'ui://longbook/next-payment.html',
    'ui://longbook/upcoming.html',
  ])
})

test('next_payment answers with the real charge over the wire', async () => {
  const client = await connected()
  const result = await client.callTool({ name: 'next_payment', arguments: {} })
  const answer = JSON.parse(textOf(result))
  assert.equal(answer.charges[0].name, 'Netflix')
  assert.equal(answer.charges[0].amount_text, '₹649')
  assert.equal(answer.due, 'in 3 days')
})

test('upcoming validates its window and answers inside it', async () => {
  const client = await connected()
  const result = await client.callTool({ name: 'upcoming', arguments: { days: 10 } })
  const answer = JSON.parse(textOf(result))
  assert.equal(answer.count, 1)
  assert.equal(answer.window_days, 10)
  const bad = await client.callTool({ name: 'upcoming', arguments: { days: 0 } })
  assert.equal(bad.isError, true)
})

test('a call that omits arguments entirely still answers', async () => {
  const client = await connected()
  const noArgs = await client.callTool({ name: 'next_payment' })
  assert.notEqual(noArgs.isError, true)
  const defaulted = await client.callTool({ name: 'upcoming' })
  assert.notEqual(defaulted.isError, true)
  assert.equal(JSON.parse(textOf(defaulted)).window_days, 30)
})

test("an older vault's llms.txt is outranked by the bundled curriculum; a newer one is served", async () => {
  const client = await connected()
  const read = await client.readResource({ uri: 'longbook://vault/llms.txt' })
  const contents = read.contents as { text?: string }[]
  assert.match(contents[0]?.text ?? '', /^longbook llms\.txt — contract revision \d+\./)
  assert.doesNotMatch(contents[0]?.text ?? '', /^# longbook\n/)

  const dir = seededVaultDir()
  writeFileSync(join(dir, 'llms.txt'), 'longbook llms.txt — contract revision 99.\n\n## From the future\nnewer words.\n')
  const [ct, st] = InMemoryTransport.createLinkedPair()
  await buildServer(new VaultReader(dir)).connect(st)
  const newer = new Client({ name: 'test-client', version: '0.0.0' })
  await newer.connect(ct)
  const guide = await newer.callTool({ name: 'read_guide', arguments: { section: 'future' } })
  const answer = JSON.parse(textOf(guide))
  assert.equal(answer.revision, 99)
  assert.match(answer.text, /newer words/)
})

test('whoami on this machine names the vault and says writes go straight to the folder', async () => {
  const client = await connected()
  assert.equal(client.getServerVersion()?.name, 'longbook (this Mac)')
  const answer = JSON.parse(textOf(await client.callTool({ name: 'whoami' })))
  assert.equal(answer.server, 'longbook (this Mac)')
  assert.equal(answer.can_write, true)
  assert.equal(answer.write_mode, 'direct')
  // The owner's own folder is the first door already; it points nowhere else.
  assert.equal(answer.closer_door, undefined)
  assert.equal(answer.write_tools.length, 18)
  assert.equal(answer.cannot_write_because, undefined, 'this machine writes; nothing to explain')
  assert.equal(answer.connected_as, 'test-client')
  assert.ok(answer.memory.commitments >= 1)
  assert.deepEqual(answer.memory.stale_balances, [], 'no account holds a balance to be stale')
  assert.ok(answer.guide.read_guide.includes('importing-statements'))

  const vocabulary = JSON.parse(textOf(await client.callTool({ name: 'tags' })))
  assert.ok(vocabulary.library.some((t: { name: string }) => t.name === 'insurance'))
})

test('read_guide answers whole or by chapter, and lists the chapters when the name misses', async () => {
  const client = await connected()
  const whole = JSON.parse(textOf(await client.callTool({ name: 'read_guide' })))
  assert.ok(whole.sections.some((s: { id: string }) => s.id === 'importing-statements'))
  assert.match(whole.text, /## Importing statements/)

  const chapter = JSON.parse(textOf(await client.callTool({ name: 'read_guide', arguments: { section: 'import' } })))
  assert.equal(chapter.section, 'importing-statements')
  assert.match(chapter.text, /one-time row/)
  assert.doesNotMatch(chapter.text, /## Reading reports/)

  const miss = await client.callTool({ name: 'read_guide', arguments: { section: 'astrology' } })
  assert.equal(miss.isError, true)
  assert.match(textOf(miss), /Chapters: .*reading-reports/)

  const library = await client.readResource({ uri: 'longbook://vault/library.json' })
  const libraryText = (library.contents as { text?: string }[])[0]?.text ?? ''
  assert.match(libraryText, /"shield\.checkered"/)
})

test("this Mac lists the same prompt menu as the hosted door, and hands over a prompt's words and procedure", async () => {
  const client = await connected()
  assert.ok(client.getServerCapabilities()?.prompts, 'prompts are advertised')
  const listed = (await client.listPrompts()).prompts
  assert.deepEqual(listed.map((p) => p.name), MCP_PROMPTS.map((p) => p.name))
  assert.equal(listed.length, PROMPTS.length)
  const month = listed.find((p) => p.name === 'add-a-month-report-in-my-longbook')!
  assert.equal(month.title, 'Add a month report in my longbook')
  assert.deepEqual(month.arguments?.map((a) => [a.name, a.required ?? false]), [['month', false]])
  assert.equal(listed.find((p) => p.name === 'tidy-my-longbook')!.arguments?.length ?? 0, 0)

  const october = await client.getPrompt({ name: 'add-a-month-report-in-my-longbook', arguments: { month: 'October' } })
  const text = (october.messages[0]!.content as { text: string }).text
  assert.equal(text, mcpPromptMessage('add-a-month-report-in-my-longbook', 'October')!.messages[0]!.content.text, 'both doors say it alike')
  assert.ok(text.startsWith('Add October month report in my longbook\n'))
  assert.match(text, /The method in full: read_guide\("month-report"\)\n\nPass guide_key "add-a-month-report-in-my-longbook:\d+:[0-9a-z]+" with every write this procedure makes\.$/)
  const tidy = await client.getPrompt({ name: 'tidy-my-longbook' })
  assert.ok((tidy.messages[0]!.content as { text: string }).text.startsWith('Tidy my longbook\n'))

  await assert.rejects(client.getPrompt({ name: 'find-horoscopes' }), /find-horoscopes/)
  // A client that leaves the optional month out sends no arguments; the menu entry still answers.
  const bare = await client.getPrompt({ name: 'add-a-month-report-in-my-longbook' })
  assert.match((bare.messages[0]!.content as { text: string }).text, /^Add [A-Z][a-z]+ month report in my longbook\n/)

  // The guide answers the owner's words with the procedure, over the bundled curriculum.
  const guided = JSON.parse(textOf(await client.callTool({ name: 'read_guide', arguments: { section: 'Add my statement' } })))
  assert.equal(guided.prompt, 'add-my-statement')
  assert.equal(guided.chapter.id, 'importing-statements')
})

function seededDir(): string {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-mcp-server-v3-'))
  writeFileSync(
    join(dir, 'financial_memory.json'),
    JSON.stringify({
      app: 'longbook',
      version: 3,
      commitments: [
        { id: 'c1', name: 'Netflix', amount: 649, currency: 'INR', billing_cycle: 'monthly', status: 'active' },
      ],
      charges: [{ commitment_id: 'c1', date: '2026-09-01', amount: 649, paid: false, basis: 'plan' }],
    }),
  )
  return dir
}

async function connectedTo(dir: string, clientName: string) {
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair()
  await buildServer(new VaultReader(dir)).connect(serverTransport)
  const client = new Client({ name: clientName, version: '0.0.0' })
  await client.connect(clientTransport)
  return client
}

test('the write tools carry honest annotations: adds additive, cancel destructive', async () => {
  const client = await connected()
  const tools = (await client.listTools()).tools
  const add = tools.find((t) => t.name === 'add_commitments')
  const cancel = tools.find((t) => t.name === 'cancel_commitment')
  assert.deepEqual(add?.annotations, {
    title: 'Add commitments', readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false,
  })
  assert.deepEqual(cancel?.annotations, {
    title: 'Cancel a commitment', readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false,
  })
})

test('every tool lists the fields the hosted door lists, so a client can send them', async () => {
  const listed = (await (await connected()).listTools()).tools
  const fields = (schema: unknown) => Object.keys((schema as { properties?: object }).properties ?? {})
  for (const spec of [...TOOLS, ...WRITE_TOOLS]) {
    const tool = listed.find((t) => t.name === spec.name)
    if (!tool) continue
    const missing = fields(spec.inputSchema).filter((f) => f !== 'idempotency_key' && !fields(tool.inputSchema).includes(f))
    assert.deepEqual(missing, [], spec.name)
  }
})

test('every tool on this door names itself in annotations.title, as the directory reads it', async () => {
  const tools = (await (await connected()).listTools()).tools
  for (const tool of tools) assert.equal(tool.annotations?.title, tool.title, tool.name)
})

test("a wire write signs provenance with the client's own name, as given", async () => {
  const dir = seededDir()
  const client = await connectedTo(dir, 'Fixture-Client')
  const result = await client.callTool({
    name: 'add_commitments',
    arguments: { rows: [{ name: 'Claude', amount: 20, currency: 'USD', billing_cycle: 'monthly', first_charge: '2026-09-10', plan_months: 3 }] },
  })
  assert.notEqual(result.isError, true)
  const vault = JSON.parse(readFileSync(join(dir, 'financial_memory.json'), 'utf8'))
  const row = vault.commitments.find((c: { name: string }) => c.name === 'Claude')
  assert.equal(vault._provenance[row.id].edited_by, 'Fixture-Client')

  const cancelled = await client.callTool({ name: 'cancel_commitment', arguments: { name: 'Claude' } })
  assert.notEqual(cancelled.isError, true)
  const again = JSON.parse(readFileSync(join(dir, 'financial_memory.json'), 'utf8'))
  assert.equal(again.commitments.find((c: { name: string }) => c.name === 'Claude').status, 'cancelled')
})

test('a known AI signs by its display name, as the hosted door names it', async () => {
  for (const [given, signed] of <[string, string][]>[['claude-ai', 'Claude'], ['claude-code', 'Claude'], ['openai-mcp', 'ChatGPT'], ['Gemini CLI', 'Gemini'], ['cursor-vscode', 'Cursor']]) {
    const dir = seededDir()
    const client = await connectedTo(dir, given)
    const result = await client.callTool({
      name: 'add_commitments',
      arguments: { rows: [{ name: 'Claude', amount: 20, currency: 'USD', billing_cycle: 'monthly', first_charge: '2026-09-10', plan_months: 3 }] },
    })
    assert.notEqual(result.isError, true, textOf(result))
    const vault = JSON.parse(readFileSync(join(dir, 'financial_memory.json'), 'utf8'))
    const row = vault.commitments.find((c: { name: string }) => c.name === 'Claude')
    assert.equal(vault._provenance[row.id].edited_by, signed, given)
    assert.equal(JSON.parse(textOf(await client.callTool({ name: 'whoami' }))).connected_as, signed, given)
  }
})

test("a client wearing the app's own signing name signs as the door, not as the app", async () => {
  const dir = seededDir()
  const client = await connectedTo(dir, 'Longbook-Mac')
  const result = await client.callTool({
    name: 'add_commitments',
    arguments: { rows: [{ name: 'Claude', amount: 20, currency: 'USD', billing_cycle: 'monthly', first_charge: '2026-09-10', plan_months: 3 }] },
  })
  assert.notEqual(result.isError, true, textOf(result))
  const vault = JSON.parse(readFileSync(join(dir, 'financial_memory.json'), 'utf8'))
  const row = vault.commitments.find((c: { name: string }) => c.name === 'Claude')
  assert.equal(vault._provenance[row.id].edited_by, 'mcp')
  const answer = JSON.parse(textOf(await client.callTool({ name: 'whoami' })))
  assert.equal(answer.connected_as, 'mcp')
})

test('a direction is set and cleared over the wire: null is taken here as the hosted door takes it', async () => {
  const dir = seededDir()
  const client = await connectedTo(dir, 'fixture-client')
  const direction = () => JSON.parse(readFileSync(join(dir, 'financial_memory.json'), 'utf8')).commitments[0].direction
  const moved = await client.callTool({ name: 'update_commitment', arguments: { id: 'c1', set: { direction: 'transfer' } } })
  assert.notEqual(moved.isError, true, textOf(moved))
  assert.equal(direction(), 'transfer')
  const cleared = await client.callTool({ name: 'update_commitment', arguments: { id: 'c1', set: { direction: null } } })
  assert.notEqual(cleared.isError, true, textOf(cleared))
  assert.equal(direction(), null)
})

test('over the wire, a commitment write sending details is refused by name, in the hosted door\'s words', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-mcp-server-details-'))
  const path = join(dir, 'financial_memory.json')
  writeFileSync(path, JSON.stringify({
    app: 'longbook',
    version: 3,
    commitments: [
      { id: 'c1', name: 'Netflix', amount: 649, currency: 'INR', billing_cycle: 'monthly', status: 'active' },
      { id: 'p1', name: 'UPI-RAMESH', amount: 6000, currency: 'INR', billing_cycle: 'once', status: 'active' },
      { id: 'p2', name: 'UPI-RAMESH', amount: 6000, currency: 'INR', billing_cycle: 'once', status: 'active' },
    ],
    charges: [
      { commitment_id: 'c1', date: '2026-09-01', amount: 649, paid: false, basis: 'plan' },
      { commitment_id: 'p1', date: '2026-07-01', amount: 6000, paid: true, basis: 'statement' },
      { commitment_id: 'p2', date: '2026-08-01', amount: 6000, paid: true, basis: 'statement' },
    ],
  }))
  const client = await connectedTo(dir, 'fixture-client')
  const before = readFileSync(path, 'utf8')
  const row = { name: 'Term plan', amount: 24600, currency: 'INR', billing_cycle: 'yearly', first_charge: '2026-05-22', plan_months: 12, notes: 'Policy number: 88213' }
  const calls: [string, Record<string, unknown>][] = [
    ['add_commitments', { rows: [{ ...row, details: { insurer: 'LIC' } }] }],
    ['update_commitment', { id: 'c1', set: { notes: 'Plan: Premium', details: { plan: 'Premium' } } }],
    ['update_commitment', { id: 'c1', set: { details: { plan: 'Premium' } } }],
    ['promote_to_recurring', { ids: ['p1', 'p2'], billing_cycle: 'monthly', name: 'Ramesh', details: { role: 'cook' } }],
  ]
  for (const [name, args] of calls) {
    const local = await client.callTool({ name, arguments: args })
    assert.equal(local.isError, true, `${name} is refused`)
    assert.match(textOf(local), /details is longbook's own — write a commitment's details as lines of its notes\./)
    assert.throws(() => checkProposal(name, args), (error: Error) => error.message === textOf(local), `${name}: both doors word it alike`)
  }
  assert.equal(readFileSync(path, 'utf8'), before, 'nothing was written')

  // Without details, each of those writes lands: details alone was the reason.
  for (const [name, args] of [
    ['add_commitments', { rows: [row] }],
    ['update_commitment', { id: 'c1', set: { notes: 'Plan: Premium' } }],
    ['promote_to_recurring', { ids: ['p1', 'p2'], billing_cycle: 'monthly', name: 'Ramesh', plan_months: 1 }],
  ] as [string, Record<string, unknown>][]) {
    const landed = await client.callTool({ name, arguments: args })
    assert.notEqual(landed.isError, true, `${name}: ${textOf(landed)}`)
  }
})

test('neither door lists details as an input: the Mac door lets the key through to its refusal', async () => {
  const client = await connected()
  const listed = (await client.listTools()).tools
  const input = (name: string) => listed.find((t) => t.name === name)?.inputSchema as Record<string, any>
  const places: [string, Record<string, unknown>, string][] = [
    ['add_commitments rows', input('add_commitments').properties.rows.items.properties, 'notes'],
    ['update_commitment set', input('update_commitment').properties.set.properties, 'notes'],
    ['promote_to_recurring', input('promote_to_recurring').properties, 'notes'],
    ['update_account set', input('update_account').properties.set.properties, 'notes'],
    ['update_member set', input('update_person').properties.set.properties, 'email'],
  ]
  for (const [where, properties, beside] of places) {
    assert.ok(beside in properties, `${where}: the listing is read where ${beside} sits`)
    assert.equal('details' in properties, false, `${where}: the Mac door lists no details`)
    assert.equal('card_name' in properties, false, `${where}: the Mac door lists no card_name`)
  }
  for (const tool of WRITE_TOOLS) {
    assert.doesNotMatch(JSON.stringify(tool.inputSchema), /"(details|card_name)"\s*:/, `${tool.name}: the hosted door lists neither`)
  }
})

test('over the wire, an account or person write sending card_name or details is refused by name, in the hosted door\'s words', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-mcp-server-entity-details-'))
  const path = join(dir, 'financial_memory.json')
  writeFileSync(path, JSON.stringify({
    app: 'longbook',
    version: 3,
    commitments: [],
    members: [{ id: 'm1', name: 'Diya', name_key: 'diya' }],
    accounts: [{ id: 'a1', name: 'Coral 9292', name_key: 'coral 9292', details: { card_name: 'Coral' } }],
  }))
  const client = await connectedTo(dir, 'fixture-client')
  const before = readFileSync(path, 'utf8')
  const calls: [string, Record<string, unknown>, RegExp][] = [
    ['update_account', { id: 'a1', set: { card_name: 'Platinum Reserve' } }, /card_name and details are longbook's own — write an account's details as lines of its notes\./],
    ['update_account', { id: 'a1', set: { notes: 'Lounge access', details: { due_day: 5 } } }, /card_name and details are longbook's own — write an account's details as lines of its notes\./],
    ['update_person', { id: 'm1', set: { details: { relationship: 'sister' } } }, /details is longbook's own — a member carries a name, a tag, an email and linked accounts\./],
    ['update_person', { id: 'm1', set: { tag: 'family', card_name: 'Coral' } }, /details is longbook's own — a member carries a name, a tag, an email and linked accounts\./],
  ]
  for (const [name, args, words] of calls) {
    const local = await client.callTool({ name, arguments: args })
    assert.equal(local.isError, true, `${name} ${JSON.stringify(args)} is refused`)
    assert.match(textOf(local), words)
    assert.throws(() => checkProposal(name, args), (error: Error) => error.message === textOf(local), `${name}: both doors word it alike`)
  }
  assert.equal(readFileSync(path, 'utf8'), before, 'nothing was written')

  // Without them, each write lands: they alone were the reason.
  const landed = await client.callTool({ name: 'update_account', arguments: { id: 'a1', set: { notes: 'Card name: Platinum Reserve' } } })
  assert.notEqual(landed.isError, true, textOf(landed))
  assert.deepEqual(JSON.parse(textOf(landed)).fields, ['notes'])
  const account = JSON.parse(readFileSync(path, 'utf8')).accounts[0]
  assert.equal(account.notes, 'Card name: Platinum Reserve')
  assert.deepEqual(account.details, { card_name: 'Coral' }, 'what details held is kept as held')
  const person = await client.callTool({ name: 'update_person', arguments: { id: 'm1', set: { tag: 'family' } } })
  assert.notEqual(person.isError, true, textOf(person))

  // A key the tool does not take rides through to it, which names it rather than dropping it unseen.
  const typed = await client.callTool({ name: 'update_account', arguments: { id: 'a1', set: { notes: 'Shared card.', type: 'credit card', card_name: '' } } })
  assert.deepEqual(JSON.parse(textOf(typed)).ignored, ['type — the account type is tag', "card_name — a card's name is a line of notes"])
  const role = await client.callTool({ name: 'update_person', arguments: { id: 'm1', set: { tag: 'family', role: 'sister' }, guide_key: KEY } })
  assert.deepEqual(JSON.parse(textOf(role)), { updated: { id: 'm1', name: 'Diya' }, fields: ['tag'], ignored: ['role — their role is tag'] })
})

test('over the wire, an amount past the limit or below zero is refused on the Mac door in the hosted door\'s words', async () => {
  const dir = seededDir()
  const path = join(dir, 'financial_memory.json')
  const client = await connectedTo(dir, 'fixture-client')
  const before = readFileSync(path, 'utf8')
  const huge = 9.3e18
  const calls: [string, Record<string, unknown>][] = [
    ['add_commitments', { rows: [{ name: 'Slip', amount: huge, currency: 'INR', billing_cycle: 'once', date: '2026-09-01' }] }],
    ['add_commitments', { rows: [{ name: 'Slip', amount: -5, currency: 'INR', billing_cycle: 'once', date: '2026-09-01' }] }],
    ['update_commitment', { id: 'c1', set: { amount: huge } }],
    ['mark_paid', { id: 'c1', date: '2026-09-01', amount: huge }],
    ['add_charges', { id: 'c1', charges: [{ date: '2026-12-01', amount: huge }] }],
  ]
  for (const [name, args] of calls) {
    const local = await client.callTool({ name, arguments: args })
    assert.equal(local.isError, true, name)
    assert.throws(() => checkProposal(name, args), (error: Error) => error.message === textOf(local),
      `${name}: the hosted door says what the Mac door said: ${textOf(local)}`)
  }
  assert.equal(readFileSync(path, 'utf8'), before, 'nothing was written')

  // The Mac door's listing states the limit in words, where zod no longer enforces it first.
  const listed = (await client.listTools()).tools
  const input = (name: string) => listed.find((t) => t.name === name)?.inputSchema as Record<string, any>
  const stated = { type: 'number', description: 'A number, zero or more, up to 1,000,000,000,000,000.' }
  assert.deepEqual(input('add_commitments').properties.rows.items.properties.amount, stated)
  assert.deepEqual(input('update_commitment').properties.set.properties.amount, stated)
  assert.deepEqual(input('mark_paid').properties.amount, stated)
  assert.deepEqual(input('add_charges').properties.charges.items.properties.amount, stated)
  assert.ok(input('add_commitments').properties.rows.items.required.includes('amount'), 'a row still needs its amount')
})

test('over the wire, a custom cycle outside 1 to 36,500 days is refused on the Mac door in the hosted door\'s words', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-mcp-server-days-'))
  const path = join(dir, 'financial_memory.json')
  writeFileSync(path, JSON.stringify({
    app: 'longbook',
    version: 3,
    commitments: [
      { id: 'c1', name: 'Netflix', amount: 649, currency: 'INR', billing_cycle: 'monthly', status: 'active' },
      { id: 'p1', name: 'Water cans', amount: 300, currency: 'INR', billing_cycle: 'once', status: 'active' },
      { id: 'p2', name: 'Water cans', amount: 300, currency: 'INR', billing_cycle: 'once', status: 'active' },
    ],
    charges: [
      { commitment_id: 'c1', date: '2026-09-01', amount: 649, paid: false, basis: 'plan' },
      { commitment_id: 'p1', date: '2026-07-01', amount: 300, paid: true, basis: 'statement' },
      { commitment_id: 'p2', date: '2026-07-11', amount: 300, paid: true, basis: 'statement' },
    ],
  }))
  const client = await connectedTo(dir, 'fixture-client')
  const before = readFileSync(path, 'utf8')
  const row = { name: 'Gas', amount: 900, currency: 'INR', billing_cycle: 'custom', first_charge: '2026-07-01', plan_months: 1 }
  const words = {
    add_commitments: 'Nothing was written. Fix these and send the batch again — row 1 ("Gas"): custom_cycle_days is a whole number of days, 1 to 36,500.',
    update_commitment: 'Nothing was changed. Fix these — custom_cycle_days is a whole number of days, 1 to 36,500.',
    promote_to_recurring: 'custom_cycle_days is a whole number of days, 1 to 36,500.',
  }
  for (const days of [0, 1.5, 36_501, 99_999_999_999_999_999]) {
    const calls: [keyof typeof words, Record<string, unknown>][] = [
      ['add_commitments', { rows: [{ ...row, custom_cycle_days: days }] }],
      ['update_commitment', { id: 'c1', set: { billing_cycle: 'custom', custom_cycle_days: days } }],
      ['promote_to_recurring', { ids: ['p1', 'p2'], billing_cycle: 'custom', custom_cycle_days: days }],
    ]
    for (const [name, args] of calls) {
      const local = await client.callTool({ name, arguments: args })
      assert.equal(local.isError, true, `${name}, ${days} days`)
      assert.equal(textOf(local), words[name], `${name}, ${days} days`)
      assert.throws(() => checkProposal(name, args), (error: Error) => error.message === textOf(local),
        `${name}, ${days} days: the hosted door says what the Mac door said`)
    }
  }
  assert.equal(readFileSync(path, 'utf8'), before, 'nothing was written')

  // The limit itself is taken, and the Mac door's listing states the bounds in words.
  const landed = await client.callTool({ name: 'add_commitments', arguments: { rows: [{ ...row, custom_cycle_days: 36_500 }] } })
  assert.notEqual(landed.isError, true, textOf(landed))
  const listed = (await client.listTools()).tools
  const input = (name: string) => listed.find((t) => t.name === name)?.inputSchema as Record<string, any>
  const stated = { type: 'number', description: 'The days between charges of a custom cycle: a whole number, 1 to 36,500.' }
  assert.deepEqual(input('add_commitments').properties.rows.items.properties.custom_cycle_days, stated)
  assert.deepEqual(input('promote_to_recurring').properties.custom_cycle_days, stated)
  assert.equal(input('update_commitment').properties.set.properties.custom_cycle_days.description, stated.description)
})

// A key update_commitment does not take rides through to the tool, which names it rather
// than reporting it written.
test('over the wire, update_commitment names a key it does not take and writes the rest', async () => {
  const dir = seededDir()
  const client = await connectedTo(dir, 'fixture-client')
  const result = await client.callTool({ name: 'update_commitment', arguments: { id: 'c1', set: { notes: 'Plan: Premium', cancelling_on: '2026-12-31' }, guide_key: KEY } })
  assert.notEqual(result.isError, true, textOf(result))
  assert.deepEqual(JSON.parse(textOf(result)), {
    updated: { id: 'c1', name: 'Netflix' },
    fields: ['notes'],
    ignored: ['cancelling_on — the cancelling date is ends_on'],
  })
  const row = JSON.parse(readFileSync(join(dir, 'financial_memory.json'), 'utf8')).commitments[0]
  assert.equal(row.notes, 'Plan: Premium')
  assert.equal(row.ends_on, undefined)
})

test('a card reads as one self-contained HTML file with the real numbers', async () => {
  const client = await connected()
  const read = await client.readResource({ uri: 'ui://longbook/next-payment.html' })
  const html = (read.contents as { text?: string }[])[0]?.text ?? ''
  assert.ok(html.startsWith('<!doctype html>'))
  assert.match(html, /₹649/)
  assert.match(html, /Netflix/)
  assert.doesNotMatch(html, /https?:\/\//)
})

test('over the wire, the seven new writes land on this machine and refuse in the hosted door\'s words', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-mcp-server-r32-'))
  const path = join(dir, 'financial_memory.json')
  const today = todayMid()
  const tenth = (months: number) => toISO(new Date(today.getFullYear(), today.getMonth() + months, 10))
  writeFileSync(path, JSON.stringify({
    app: 'longbook',
    version: 3,
    commitments: [
      { id: 'c1', name: 'Netflix', amount: 649, currency: 'INR', billing_cycle: 'monthly', status: 'active', tag: 'Streaming' },
      { id: 'c2', name: 'Sofa', amount: 500, currency: 'INR', billing_cycle: 'once', status: 'active' },
    ],
    charges: [
      { commitment_id: 'c1', date: tenth(1), amount: 649, paid: false, basis: 'plan' },
      { commitment_id: 'c1', date: tenth(2), amount: 649, paid: false, basis: 'plan' },
      { commitment_id: 'c2', date: tenth(1), amount: 500, paid: false, basis: 'plan' },
    ],
    members: [{ id: 'm1', name: 'Diya', name_key: 'diya' }],
    accounts: [{ id: 'a1', name: 'HDFC', name_key: 'hdfc' }],
  }))
  const client = await connectedTo(dir, 'fixture-client')
  const vault = () => JSON.parse(readFileSync(path, 'utf8'))
  const landed = async (name: string, args: Record<string, unknown>) => {
    const result = await client.callTool({ name, arguments: { ...args, guide_key: KEY } })
    assert.notEqual(result.isError, true, `${name}: ${textOf(result)}`)
    return JSON.parse(textOf(result))
  }

  assert.deepEqual((await landed('update_charge', { id: 'c1', date: tenth(1), set: { paid: true, note: 'paid ahead' } })).fields, ['paid', 'note'])
  assert.equal(vault().charges[0].note, 'paid ahead')
  await landed('update_charge', { id: 'c1', date: tenth(1), set: { note: null } })
  assert.equal('note' in vault().charges[0], false, 'null is taken here as the hosted door takes it')
  assert.equal((await landed('set_planned_count', { name: 'Netflix', count: 4 })).ahead, 4)
  assert.equal((await landed('add_person', { name: 'Meera', tag: 'family' })).fields.join(), 'tag')
  assert.equal((await landed('add_account', { name: 'Coral 9292', linked_to: 'HDFC', member: 'Meera' })).fields.join(), 'linked_to,member')
  assert.deepEqual(await landed('rename_tag', { kind: 'commitment', from: 'streaming', to: 'Entertainment' }), { renamed: { from: 'streaming', to: 'Entertainment' }, kind: 'commitment', rows_moved: 1 })
  assert.deepEqual(await landed('delete_tag', { kind: 'commitment', name: 'Entertainment' }), { deleted: 'Entertainment', kind: 'commitment', rows_cleared: 1 })
  assert.equal(vault().commitments[0].tag, null)
  assert.deepEqual(await landed('delete_commitment', { id: 'c2' }), { deleted: { id: 'c2', name: 'Sofa' }, charges_removed: 1, paid_charges_removed: 0 })
  assert.equal(vault()._provenance['c1'].edited_by, 'fixture-client')

  // What the shared checks refuse, both doors refuse in one sentence; zod lets these keys through.
  const before = readFileSync(path, 'utf8')
  const calls: [string, Record<string, unknown>][] = [
    ['update_charge', { id: 'c1', date: tenth(1), set: { date: '2026-02-30' } }],
    ['update_charge', { id: 'c1', date: tenth(1), set: { and_later: true } }],
    ['add_person', { name: 'Arjun', details: { role: 'cook' } }],
    ['add_account', { name: 'Wallet', card_name: 'Coral' }],
    ['add_account', { name: 'Wallet', balance_date: '2026-09-01' }],
  ]
  for (const [name, args] of calls) {
    const local = await client.callTool({ name, arguments: args })
    assert.equal(local.isError, true, `${name} is refused`)
    assert.throws(() => checkProposal(name, args), (error: Error) => error.message === textOf(local), `${name}: both doors word it alike — ${textOf(local)}`)
  }
  assert.equal(readFileSync(path, 'utf8'), before, 'nothing was written')
  const twin = await client.callTool({ name: 'add_person', arguments: { name: 'diya' } })
  assert.equal(textOf(twin), "There's already a person called diya.")
  const taken = await client.callTool({ name: 'update_charge', arguments: { id: 'c1', date: tenth(1), set: { date: tenth(2) } } })
  assert.match(textOf(taken), /^A charge already sits on .*\. Move or remove it first\.$/)
})

test('on this Mac too, a write without a guide_key is answered with a guide_warning, and lands', async () => {
  const dir = seededDir()
  const client = await connectedTo(dir, 'fixture-client')
  const args = { rows: [{ name: 'Gym', amount: 2000, currency: 'INR', billing_cycle: 'monthly', first_charge: '2026-09-01', plan_months: 2 }] }
  const skipped = await client.callTool({ name: 'add_commitments', arguments: args })
  assert.notEqual(skipped.isError, true, textOf(skipped))
  assert.match(JSON.parse(textOf(skipped)).guide_warning, /^No guide_key/)
  const guide = JSON.parse(textOf(await client.callTool({ name: 'read_guide', arguments: { section: 'working-method' } })))
  const followed = await client.callTool({ name: 'add_commitments', arguments: { rows: [{ ...args.rows[0], name: 'Pool' }], guide_key: guide.guide_key } })
  assert.equal(JSON.parse(textOf(followed)).guide_warning, undefined)
})
