// The one-prompt import, proved without an agent: real readers over the fixture
// statements, the decisions a correct import makes applied through the real write tools,
// and the whole vault compared against a golden the Swift suite decodes too.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { cpSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { chargesOf, spendSeriesRange, todayMid } from '@longbook/core'
import { listDocuments, readDocument } from '../src/documents.js'
import { addCommitments, promoteToRecurring } from '../src/writeTools.js'
import { parseVault } from '../src/parse.js'
import { CHECKS } from './importChecks.js'

const STATEMENTS = join(import.meta.dirname, 'fixtures/statements')
const GOLDEN = join(import.meta.dirname, '../../core/tests/fixtures/import-golden-vault.json')
const DECISIONS = JSON.parse(
  readFileSync(join(import.meta.dirname, 'fixtures/import-decisions.json'), 'utf8'),
) as {
  facts: Record<string, unknown>[]
  repeats: { name: string; billing_cycle: 'monthly' | 'yearly' | 'custom'; custom_cycle_days?: number; plan_months: number; ends_on?: string; notes?: string }[]
}

/** A vault folder holding the statements, and an empty memory beside them. */
function vaultWithStatements(): string {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-import-'))
  mkdirSync(join(dir, 'documents'), { recursive: true })
  cpSync(STATEMENTS, join(dir, 'documents'), { recursive: true })
  writeFileSync(
    join(dir, 'financial_memory.json'),
    JSON.stringify({ app: 'longbook', version: 3, commitments: [] }, null, 2),
  )
  return dir
}

/** Ids and timestamps are made fresh every run; the shape underneath them is the subject. */
function normalise(vault: Record<string, any>): Record<string, unknown> {
  const ids = new Map<string, string>()
  const label = (id: string, kind: string): string => {
    if (!ids.has(id)) ids.set(id, `${kind}-${ids.size + 1}`)
    return ids.get(id)!
  }
  const rows = [...(vault.commitments ?? [])].sort((a, b) => String(a.name).localeCompare(String(b.name)))
  const members = [...(vault.members ?? [])].sort((a, b) => String(a.name).localeCompare(String(b.name)))
  const accounts = [...(vault.accounts ?? [])].sort((a, b) => String(a.name).localeCompare(String(b.name)))
  for (const row of members) label(row.id, 'member')
  for (const row of accounts) label(row.id, 'account')
  for (const row of rows) label(row.id, 'commitment')

  const clean = (row: Record<string, any>, kind: string) => {
    const out: Record<string, unknown> = { ...row, id: label(row.id, kind) }
    delete out.created_at
    delete out.updated_at
    if (out.member_id) out.member_id = ids.get(String(out.member_id))
    if (out.account_id) out.account_id = ids.get(String(out.account_id))
    return out
  }

  return {
    app: vault.app,
    version: vault.version,
    commitments: rows.map((row) => clean(row, 'commitment')),
    members: members.map((row) => clean(row, 'member')),
    accounts: accounts.map((row) => clean(row, 'account')),
    tags: [...(vault.tags ?? [])]
      .sort((a, b) => String(a.name_key).localeCompare(String(b.name_key)))
      .map((tag) => {
        const out = { ...tag, id: `tag-${tag.name_key}` }
        delete out.created_at
        return out
      }),
    // The real shape, minus the moment it was stamped: the Swift suite decodes this file too.
    charges: [...(vault.charges ?? [])]
      .map((row) => {
        const out = { ...row, commitment_id: ids.get(String(row.commitment_id)) }
        delete out.written_at
        return out
      })
      .sort((a, b) => String(a.commitment_id).localeCompare(String(b.commitment_id)) || String(a.date).localeCompare(String(b.date))),
    // The signatures themselves, under the labelled ids: the moment is dropped, the
    // hand and the source are the point. A tombstone for a merged row has no label and is left out.
    _provenance: Object.fromEntries(
      Object.entries(vault._provenance ?? {})
        .filter(([id]) => ids.has(id))
        .map(([id, entry]: [string, any]) => [ids.get(id) ?? id, { edited_by: entry.edited_by, source: entry.source }])
        .sort(([a], [b]) => String(a).localeCompare(String(b))),
    ),
  }
}

test('the statements read as themselves: four readable shapes, two refused with the way out', async () => {
  const dir = vaultWithStatements()
  const listed = listDocuments(dir) as { files: { name: string; kind: string; note?: string }[] }
  const byName = Object.fromEntries(listed.files.map((f) => [f.name, f]))
  assert.equal(byName['hdfc-savings-2025-2026.pdf']!.kind, 'pdf')
  assert.equal(byName['hdfc-savings-2025-2026.csv']!.kind, 'csv')
  assert.equal(byName['axis-card-2026.xlsx']!.kind, 'excel')
  assert.match(byName['old-export.xls']!.note ?? '', /\.xlsx or CSV/)
  assert.match(byName['policy-note.docx']!.note ?? '', /Only PDF/)

  const pdf = (await readDocument(dir, { name: 'hdfc-savings-2025-2026.pdf' })) as { text: string }
  // The rhythms an importer must see, the money in it writes apart, and the movements it
  // skips are all really there.
  for (const payee of ['NETFLIX', 'HOUSE RENT', 'SUNITA D', 'GREENWOOD SOCIETY', 'SPOTIFY', 'STAR HEALTH', 'HDFC ERGO', 'IRCTC']) {
    assert.match(pdf.text, new RegExp(payee), `${payee} is in the statement`)
  }
  assert.match(pdf.text, /SALARY CREDIT/, 'the salary is there to be written as money in')
  for (const skip of ['ATM WDL', 'CREDIT CARD PAYMENT']) {
    assert.match(pdf.text, new RegExp(skip), `${skip} is there to be skipped`)
  }
  assert.equal((pdf.text.match(/NETFLIX/g) ?? []).length, 12, 'twelve monthly charges')
  assert.equal((pdf.text.match(/SPOTIFY/g) ?? []).length, 6, 'six charges, then it stops')

  const csv = (await readDocument(dir, { name: 'hdfc-savings-2025-2026.csv' })) as { text: string }
  assert.equal((csv.text.match(/NETFLIX/g) ?? []).length, 12, 'the CSV export carries the same year')

  const excel = (await readDocument(dir, { name: 'axis-card-2026.xlsx' })) as { text: string }
  assert.match(excel.text, /## Sheet: Axis Credit Card 4402/)
  assert.match(excel.text, /ADOBE SYSTEMS/)
  assert.match(excel.text, /GODADDY\.COM 3 YEAR DOMAIN/)

  await assert.rejects(() => readDocument(dir, { name: 'icici-scanned-june.pdf' }), /carries no text/)
  await assert.rejects(() => readDocument(dir, { name: 'old-export.xls' }), /\.xlsx or CSV/)
  await assert.rejects(() => readDocument(dir, { name: 'policy-note.docx' }), /Only PDF/)
})

test("a year of statements becomes the golden vault: facts first, then what repeats, nobody's numbers invented", (t) => {
  // Imported on the last day of the statements' last month; a plan never lands on or before
  // today, so the day is fixed and the golden holds whenever the suite runs.
  t.mock.timers.enable({ apis: ['Date'], now: new Date(2026, 7, 31, 12) })
  const dir = vaultWithStatements()
  const source = 'documents/hdfc-savings-2025-2026.pdf'

  // Step two of the owner's flow: every line that is a charge, as a fact — the agent's
  // judgement about what each line was, frozen as a fixture.
  const report = addCommitments(dir, 'claude', { rows: DECISIONS.facts as never, source }) as Record<string, any>
  assert.equal(report.added, DECISIONS.facts.length)
  assert.equal(report.charges_written, DECISIONS.facts.length, 'a one-time row is one charge')

  // Step six: which of them repeat. Each yes keeps every fact and plans ahead.
  for (const repeat of DECISIONS.repeats) {
    const vault = JSON.parse(readFileSync(join(dir, 'financial_memory.json'), 'utf8'))
    const ids = (vault.commitments as any[]).filter((c) => c.name === repeat.name && c.billing_cycle === 'once').map((c) => c.id)
    const { name, ...rest } = repeat
    promoteToRecurring(dir, 'claude', { ids, name, ...rest, source })
  }

  const vault = JSON.parse(readFileSync(join(dir, 'financial_memory.json'), 'utf8'))
  const actual = normalise(vault)
  if (process.env.UPDATE_GOLDEN) writeFileSync(GOLDEN, JSON.stringify(actual, null, 2) + '\n')
  assert.deepEqual(actual, JSON.parse(readFileSync(GOLDEN, 'utf8')))
})

test('the imported vault reads the history the statements actually show — from rows, nothing computed', () => {
  const golden = JSON.parse(readFileSync(GOLDEN, 'utf8'))
  const data = parseVault(JSON.stringify({ ...golden, app: 'longbook', version: 3 }))
  const today = todayMid()

  const netflix = data.subs.find((s) => s.name === 'Netflix')!
  assert.equal(netflix.billing_cycle, 'monthly')
  const netflixRows = chargesOf(netflix, data.charges)
  assert.equal(netflixRows[0]!.row.date, '2025-09-05', 'history is the first charge the statement showed')
  assert.equal(netflixRows.filter((c) => c.row.paid && c.row.basis === 'statement').length, 12)
  assert.equal(netflixRows.filter((c) => !c.row.paid && c.row.basis === 'plan').length, 12, 'and the plan continues for the year asked')
  assert.equal(netflixRows[12]!.row.date, '2026-09-05')

  const star = data.subs.find((s) => s.name === 'Star Health premium')!
  assert.equal(star.billing_cycle, 'custom')
  assert.equal(star.custom_cycle_days, 183)

  const domain = data.subs.find((s) => s.name!.startsWith('GoDaddy'))!
  assert.equal(domain.custom_cycle_days, 1095)
  assert.equal(chargesOf(domain, data.charges).length, 1, 'three years out is past a 24-month plan')

  // The ended repeat: one commitment, six charges on record, nothing planned past its end.
  const spotify = data.subs.filter((s) => s.name === 'Spotify')
  assert.equal(spotify.length, 1)
  assert.equal(spotify[0]!.ends_on, '2026-02-12')
  assert.equal(chargesOf(spotify[0]!, data.charges).length, 6)

  // A one-time spend is one commitment with its one charge, at its real date.
  const irctc = data.subs.find((s) => s.name === 'IRCTC booking')!
  assert.equal(irctc.billing_cycle, 'once')
  assert.deepEqual(chargesOf(irctc, data.charges).map((c) => c.row.date), ['2026-06-10'])

  // The months the statement covers, read from the rows rather than computed from anything.
  const monthsBack = (year: number, month: number) =>
    (today.getFullYear() - year) * 12 + (today.getMonth() - month)
  const series = spendSeriesRange(data.subs, data.charges, 'INR', monthsBack(2025, 8), 0, today)
  const month = (year: number, index: number) =>
    series.find((point) => point.year === year && point.month === index)!.total

  // September 2025: rent, cook, Airtel, Netflix, society, Spotify.
  assert.equal(month(2025, 8), 42000 + 9000 + 899 + 649 + 3500 + 119)

  // March 2026 carries the yearly health premium on top of the same monthly floor.
  assert.equal(month(2026, 2), 42000 + 9000 + 899 + 649 + 3500 + 18450)

  // June 2026: the monthly floor, the card's own three, the train booking, and lunch.
  assert.equal(month(2026, 5), 42000 + 9000 + 899 + 649 + 3500 + 1699 + 179 + 4560 + 640)

  // Money in is in, apart: the salary is one monthly commitment with direction "in", its
  // twelve credits on record, and none of it in any spending total above.
  const salary = data.subs.filter((s) => /vertex/i.test(s.name!))
  assert.equal(salary.length, 1)
  assert.equal(salary[0]!.direction, 'in')
  assert.equal(salary[0]!.billing_cycle, 'monthly', 'a repeating credit is promoted like any other')
  assert.equal(chargesOf(salary[0]!, data.charges).filter((c) => c.row.paid && c.row.basis === 'statement').length, 12)

  // Movements between the owner's own accounts never became rows.
  for (const row of data.subs) {
    assert.doesNotMatch(row.name!, /atm|card payment/i)
  }
})

test('the import refuses what it must, and the file is untouched when it does', () => {
  const dir = vaultWithStatements()
  const before = readFileSync(join(dir, 'financial_memory.json'), 'utf8')

  // An account number copied out of a statement — the one thing the file cannot hold.
  assert.throws(
    () =>
      addCommitments(dir, 'claude', {
        rows: [
          { name: 'Rent', amount: 42000, currency: 'INR', billing_cycle: 'monthly', first_charge: '2026-09-01' },
          { name: 'Card', amount: 100, currency: 'INR', billing_cycle: 'once', date: '2026-09-01', notes: 'billed to 4111 1111 1111 1111' },
        ],
      }),
    /\(row 2: "Card"\)/,
  )
  assert.equal(readFileSync(join(dir, 'financial_memory.json'), 'utf8'), before, 'nothing was written')

  // A date the statement could not have shown, named row by row.
  assert.throws(
    () =>
      addCommitments(dir, 'claude', {
        rows: [{ name: 'Netflix', amount: 649, currency: 'INR', billing_cycle: 'monthly', first_charge: '2026-02-30' }],
      }),
    /row 1 \("Netflix"\).*real calendar day/,
  )
  assert.equal(readFileSync(join(dir, 'financial_memory.json'), 'utf8'), before)
})

test('the agent judgement is real: the golden vault passes every check, and a lazy one does not', () => {
  const golden = JSON.parse(readFileSync(GOLDEN, 'utf8'))
  const failed = CHECKS.filter((check) => !check.ok(golden)).map((check) => check.what)
  assert.deepEqual(failed, [], 'a correct import passes every check')

  // The mistakes the curriculum exists to prevent, each caught by the check that names it.
  const caught = (mutate: (vault: any) => void): string[] => {
    const spoiled = JSON.parse(JSON.stringify(golden))
    mutate(spoiled)
    return CHECKS.filter((check) => !check.ok(spoiled)).map((check) => check.what)
  }

  // The ended repeat kept as a live monthly row with a plan — the shape that quietly bills forever.
  assert.ok(
    caught((v) => {
      const record = v.commitments.find((row: any) => row.name === 'Spotify')
      delete record.ends_on
      v.charges.push({ commitment_id: record.id, date: '2026-09-12', amount: 119, paid: false, basis: 'plan' })
    }).some((what) => /did not become an active monthly row/.test(what)),
  )

  // A salary credit written as spending — no direction — and a card payment written at all.
  assert.ok(
    caught((v) =>
      v.commitments.push({
        id: 'x', name: 'Salary credit', amount: 42000, currency: 'INR',
        billing_cycle: 'monthly', status: 'active',
      }),
    ).some((what) => /money in was written apart/i.test(what)),
  )
  assert.ok(
    caught((v) =>
      v.commitments.push({
        id: 'y', name: 'Credit card payment', amount: 38000, currency: 'INR',
        billing_cycle: 'once', status: 'active',
      }),
    ).some((what) => /money in was written apart/i.test(what)),
  )

  // A monthly row with no charge in the months the statement covered: its history is missing.
  assert.ok(caught((v) => { v.charges = v.charges.filter((r: any) => !(r.commitment_id === v.commitments.find((c: any) => c.name === 'Netflix').id && r.date < '2026-09-01')) })
    .some((what) => /history/.test(what)))

  // An invented amount, and an invented tag.
  assert.ok(caught((v) => { v.charges.find((r: any) => r.date === '2025-09-05').amount = 699 })
    .some((what) => /no amount was invented/.test(what)))
  assert.ok(caught((v) => { v.commitments.find((row: any) => row.name === 'Netflix').tag = 'entertainment' })
    .some((what) => /tags come from the library/i.test(what)))
})
