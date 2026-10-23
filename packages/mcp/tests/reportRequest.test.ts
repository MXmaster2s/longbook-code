// create_report on both doors: the shared check refuses what longbook draws itself, the
// target check names only rows the memory holds, and the local door leaves exactly one
// request file in requests/ — or, refused, nothing at all.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { existsSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { Client } from '@modelcontextprotocol/sdk/client/index.js'
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js'
import { DATA_POLICY_REFUSAL, toISO, todayMid } from '@longbook/core'
import {
  CREATE_REPORT_SPEC,
  EMPTY_NAME_REFUSAL,
  REPORT_DRAWN_REFUSAL,
  WRITE_TOOLS,
  checkProposal,
  checkReportRequest,
} from '../src/proposal.js'
import { TargetMiss, VAULT_PLACE, checkTargets } from '../src/targets.js'
import { REPORT_ASKED_NOTE, createReport } from '../src/reportRequest.js'
import { buildServer } from '../src/server.js'
import { VaultReader } from '../src/vault.js'
import { fixture } from './fixtures.js'

const TODAY = '2026-10-01'
const ASK = { title: 'Goa', start_date: '2026-09-28', end_date: '2026-10-01' }

const refusal = (body: Record<string, unknown>, today = TODAY): string => {
  try {
    checkReportRequest(body, today)
  } catch (error) {
    return (error as Error).message
  }
  return 'accepted'
}

test('a report request names its title, its days and its scope, and nothing longbook draws', () => {
  for (const key of ['id', 'currency', 'modules', 'hidden_ids', 'period', 'scope', 'subtitle']) {
    assert.equal(refusal({ ...ASK, [key]: key === 'modules' ? [] : 'x' }), REPORT_DRAWN_REFUSAL, key)
  }
  // A misspelt scope would widen the report to everything, so it is refused, never dropped.
  assert.equal(refusal({ ...ASK, account: ['HDFC'] }), REPORT_DRAWN_REFUSAL)
  assert.equal(REPORT_DRAWN_REFUSAL, 'longbook draws the report; name only title, start_date, end_date, accounts, members and categories.')
})

test('each refusal of the shape says what to fix', () => {
  assert.equal(refusal({ ...ASK, title: '   ' }), EMPTY_NAME_REFUSAL)
  assert.equal(refusal({ ...ASK, title: undefined }), EMPTY_NAME_REFUSAL)
  assert.equal(refusal({ ...ASK, title: 'x'.repeat(81) }), 'A report\'s name is 80 characters at most.')
  assert.equal(refusal({ ...ASK, title: ` ${'x'.repeat(80)} ` }), 'accepted', 'trimmed first, then counted')
  assert.equal(refusal({ ...ASK, start_date: '2026-02-30' }), 'start_date is the first day the report covers, a real YYYY-MM-DD day.')
  assert.equal(refusal({ ...ASK, start_date: undefined }), 'start_date is the first day the report covers, a real YYYY-MM-DD day.')
  assert.equal(refusal({ ...ASK, end_date: '2026-9-30' }), 'end_date is the last day the report covers, a real YYYY-MM-DD day.')
  assert.equal(refusal({ ...ASK, start_date: '2026-09-30', end_date: '2026-09-29' }), 'end_date comes on or after start_date.')
  assert.equal(
    refusal({ ...ASK, start_date: '2026-10-02', end_date: '2026-10-05' }),
    'start_date is after today, 2026-10-01: a report counts charges dated today or earlier, so it starts on a day that has come.',
  )
  // 366 days counting both ends is a leap year whole; one more is refused.
  assert.equal(refusal({ ...ASK, start_date: '2024-01-01', end_date: '2024-12-31' }), 'accepted')
  assert.equal(refusal({ ...ASK, start_date: '2025-01-01', end_date: '2026-01-02' }), 'A report covers 366 days at most, counting both start_date and end_date.')
  assert.equal(refusal({ ...ASK, start_date: '2025-10-01', end_date: '2026-10-01' }), 'accepted', 'a year and its last day is 366 days')
  assert.equal(refusal({ ...ASK, start_date: '2026-10-01', end_date: '2026-10-01' }), 'accepted', 'a single day is a span')
  // The end may lie ahead: a span still running counts what has happened so far.
  assert.equal(refusal({ ...ASK, end_date: '2026-10-20' }), 'accepted')
})

test('a scope is up to fifty trimmed names of up to eighty characters', () => {
  assert.equal(refusal({ ...ASK, accounts: 'HDFC' }), 'accounts lists up to 50 account names, each 1 to 80 characters.')
  assert.equal(refusal({ ...ASK, members: ['Rohit', '  '] }), 'members lists up to 50 people\'s names, each 1 to 80 characters.')
  assert.equal(refusal({ ...ASK, categories: ['x'.repeat(81)] }), 'categories lists up to 50 category names, each 1 to 80 characters.')
  assert.equal(refusal({ ...ASK, categories: [7] }), 'categories lists up to 50 category names, each 1 to 80 characters.')
  assert.equal(refusal({ ...ASK, accounts: Array.from({ length: 51 }, (_, i) => `A${i}`) }), 'accounts lists up to 50 account names, each 1 to 80 characters.')
  assert.equal(refusal({ ...ASK, accounts: Array.from({ length: 50 }, (_, i) => `A${i}`) }), 'accepted')
})

test('the payload is filed as the app reads it: trimmed, the no-row names written once, an empty list dropped', () => {
  const filed = checkReportRequest(
    { title: '  Goa  ', start_date: '2026-09-28', end_date: '2026-10-01', accounts: [' no account ', 'HDFC'], members: [], categories: ['NO CATEGORY'], source: 'chat' },
    TODAY,
  )
  assert.deepEqual(filed, {
    title: 'Goa', start_date: '2026-09-28', end_date: '2026-10-01', accounts: ['No account', 'HDFC'], categories: ['No category'], source: 'chat',
  })
  // "No account" stands for no row only among accounts.
  assert.deepEqual(checkReportRequest({ ...ASK, members: ['no account'] }, TODAY).members, ['no account'])
})

test('checkProposal judges against the server\'s own day and keeps the key and source apart', () => {
  const today = toISO(todayMid())
  const proposal = checkProposal('create_report', { title: 'Trip', start_date: today, end_date: today, idempotency_key: 'ask-1', source: 'chat:42' })
  assert.equal(proposal.kind, 'create_report')
  assert.equal(proposal.idempotency_key, 'ask-1')
  assert.equal(proposal.source_ref, 'chat:42')
  assert.deepEqual(proposal.payload, { title: 'Trip', start_date: today, end_date: today, source: 'chat:42' })
  assert.throws(() => checkProposal('create_report', { title: 'Later', start_date: '2999-01-01', end_date: '2999-01-02' }), /start_date is after today/)
  // The data-policy scan reaches a title too.
  assert.throws(() => checkProposal('create_report', { ...ASK, title: 'Card 4111 1111 1111 1111' }),
    (error: Error) => error.message.startsWith(DATA_POLICY_REFUSAL) && error.message.includes('a card number in title'))
})

test('the tool says what longbook does and what the owner is asked first', () => {
  const spec = WRITE_TOOLS.find((t) => t.name === 'create_report')!
  assert.equal(CREATE_REPORT_SPEC.title, 'Create a report')
  assert.match(spec.description, /draw a report from the ledger over the days and scope named/)
  assert.match(spec.description, /narrow it — left out or empty means all/)
  assert.doesNotMatch(spec.description, /Ask the owner/)
  assert.match(spec.description, /nothing waits in Changes/)
  assert.deepEqual(spec.annotations, { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false })
  assert.deepEqual((spec.inputSchema as { required: string[] }).required, ['title', 'start_date', 'end_date'])
})

const missOf = (fn: () => void): TargetMiss => {
  try {
    fn()
  } catch (error) {
    if (error instanceof TargetMiss) return error
    throw error
  }
  throw new Error('no miss')
}

test('a scope names accounts, people and categories the memory holds; a miss lists the real names', () => {
  const data = fixture()
  const ask = (scope: Record<string, unknown>) => checkProposal('create_report', { title: 'Q3', start_date: '2026-07-01', end_date: '2026-09-30', ...scope })
  // Any casing, an id, and the two no-row names all pass; nothing is created.
  checkTargets(ask({ accounts: ['hdfc current account', 'pm-icici', 'No account'], members: ['DIYA'], categories: ['travel', 'No category'] }), data)
  assert.equal(data.methods.length, 2)

  const account = missOf(() => checkTargets(ask({ accounts: ['Amex'] }), data))
  assert.equal(account.code, 'not_found')
  assert.equal(account.message, 'No account in the hosted copy is called "Amex". Accounts: "HDFC Current account" (id pm-hdfc), "ICICI Joint Account" (id pm-icici). Pass one of these names exactly, or its id.')
  const member = missOf(() => checkTargets(ask({ members: ['Meera'] }), data, '2026-09-17T08:00:00Z'))
  assert.equal(member.message, 'No person in the hosted copy (pushed 2026-09-17) is called "Meera". People: "Rohit" (id m-rohit), "Diya" (id m-diya). Pass one of these names exactly, or its id.')
  const category = missOf(() => checkTargets(ask({ categories: ['Pets'] }), data))
  assert.equal(category.message, 'No commitment tag in the hosted copy is called "Pets". commitment tags: "Entertainment", "Home", "Insurance", "Work", "Travel".')
  // On this machine the miss is said of the vault itself.
  const local = missOf(() => checkTargets(ask({ members: ['Meera'] }), { ...data, members: [] }, null, VAULT_PLACE))
  assert.equal(local.message, 'No person in the vault is called "Meera". The vault holds none.')
})

/** A vault folder holding one account, one person and one tagged commitment. */
function vault(): string {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-mcp-report-request-'))
  writeFileSync(join(dir, 'financial_memory.json'), JSON.stringify({
    app: 'longbook',
    version: 3,
    commitments: [{ id: 's1', name: 'Hotel', amount: 9000, currency: 'INR', billing_cycle: 'once', status: 'active', tag: 'Travel' }],
    charges: [{ commitment_id: 's1', date: '2026-09-28', amount: 9000, paid: true, basis: 'statement' }],
    members: [{ id: 'm1', name: 'Diya', name_key: 'diya' }],
    accounts: [{ id: 'a1', name: 'Coral 9292', name_key: 'coral 9292' }],
  }))
  return dir
}

test('the local door leaves exactly one request file, in the shape the app applies', () => {
  const dir = vault()
  const before = readFileSync(join(dir, 'financial_memory.json'), 'utf8')
  const out = createReport(dir, 'claude-desktop', {
    title: ' Goa ', start_date: '2026-09-28', end_date: '2026-09-30', accounts: ['coral 9292'], members: ['Diya'], categories: ['travel'], source: 'chat', idempotency_key: 'k1',
  }) as Record<string, unknown>
  assert.equal(out.note, REPORT_ASKED_NOTE)
  assert.equal(REPORT_ASKED_NOTE, 'Asked. longbook draws the report on its Reports screen the next time the app is open — tell the owner so, and stop here. Nothing waits in Changes.')

  const files = readdirSync(join(dir, 'requests'))
  assert.equal(files.length, 1, 'one file, no temp left behind')
  assert.match(files[0]!, /^create_report-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.json$/)
  const request = JSON.parse(readFileSync(join(dir, 'requests', files[0]!), 'utf8'))
  assert.deepEqual(Object.keys(request), ['id', 'kind', 'payload', 'source_ref', 'client', 'origin', 'created_at'])
  assert.equal(files[0], `create_report-${request.id}.json`)
  assert.equal(request.kind, 'create_report')
  assert.deepEqual(request.payload, {
    title: 'Goa', start_date: '2026-09-28', end_date: '2026-09-30', accounts: ['coral 9292'], members: ['Diya'], categories: ['travel'], source: 'chat',
  })
  assert.equal(request.source_ref, 'chat')
  assert.equal(request.client, 'claude-desktop')
  assert.equal(request.origin, 'local')
  assert.equal(new Date(request.created_at).toISOString(), request.created_at)
  assert.deepEqual(out.asked, request.payload)
  assert.equal(readFileSync(join(dir, 'financial_memory.json'), 'utf8'), before, 'the ledger is untouched')
  assert.equal(existsSync(join(dir, 'reports')), false, 'the app draws the report; nothing here writes one')

  // A request with no source says so in the file.
  createReport(dir, 'mcp', { title: 'Everything', start_date: '2026-09-01', end_date: '2026-09-30' })
  const second = readdirSync(join(dir, 'requests')).map((f) => JSON.parse(readFileSync(join(dir, 'requests', f), 'utf8')))
    .find((r) => r.payload.title === 'Everything')
  assert.equal(second.source_ref, null)
  assert.deepEqual(second.payload, { title: 'Everything', start_date: '2026-09-01', end_date: '2026-09-30' })
})

test('a refused request writes nothing at all', () => {
  const dir = vault()
  assert.throws(() => createReport(dir, 'mcp', { ...ASK, currency: 'INR' }), { message: REPORT_DRAWN_REFUSAL })
  assert.throws(() => createReport(dir, 'mcp', { ...ASK, start_date: '2026-13-01' }), /start_date is the first day/)
  assert.throws(() => createReport(dir, 'mcp', { title: 'Q3', start_date: '2026-07-01', end_date: '2026-09-30', accounts: ['Amex'] }),
    { message: 'No account in the vault is called "Amex". Accounts: "Coral 9292" (id a1). Pass one of these names exactly, or its id.' })
  assert.equal(existsSync(join(dir, 'requests')), false)
})

test('over the wire the Mac door registers create_report and signs the request with the client', async () => {
  const dir = vault()
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair()
  await buildServer(new VaultReader(dir)).connect(serverTransport)
  const client = new Client({ name: 'Claude-Desktop', version: '0.0.0' })
  await client.connect(clientTransport)

  const listed = (await client.listTools()).tools.find((t) => t.name === 'create_report')!
  assert.equal(listed.title, 'Create a report')
  assert.equal(listed.annotations?.idempotentHint, true)

  const refused = await client.callTool({ name: 'create_report', arguments: { ...ASK, period: '2026-09' } })
  assert.equal(refused.isError, true)
  assert.equal((refused.content as { text: string }[])[0]!.text, REPORT_DRAWN_REFUSAL, 'the hosted door\'s own words')
  assert.equal(existsSync(join(dir, 'requests')), false)

  const done = await client.callTool({ name: 'create_report', arguments: { title: 'Goa', start_date: '2026-09-28', end_date: '2026-09-30', members: ['diya'] } })
  assert.notEqual(done.isError, true)
  assert.equal(JSON.parse((done.content as { text: string }[])[0]!.text).note, REPORT_ASKED_NOTE)
  const [file] = readdirSync(join(dir, 'requests'))
  assert.equal(JSON.parse(readFileSync(join(dir, 'requests', file!), 'utf8')).client, 'Claude')
})

test('the hosted door allows a day for its UTC clock; the app checks the owner\'s own day', () => {
  const tomorrow = { ...ASK, start_date: '2026-10-02', end_date: '2026-10-02' }
  assert.match(refusal(tomorrow), /start_date is after today, 2026-10-01/)
  assert.equal(checkReportRequest(tomorrow, TODAY, 1).start_date, '2026-10-02')
  assert.throws(() => checkReportRequest({ ...ASK, start_date: '2026-10-03', end_date: '2026-10-03' }, TODAY, 1), /start_date is after today/)
})
