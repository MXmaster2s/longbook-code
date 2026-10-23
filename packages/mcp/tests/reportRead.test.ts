// Reports and insights over real temp folders: the reader finds the files the app drew,
// returns the four modules with the comments left on them, and never writes a byte. The
// golden report is the Swift suite's fixture too, so one file has two readers in step.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdirSync, mkdtempSync, readFileSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { REPORTS_SPEC, coveredDays, decodesAsReport, periodKeyOf, reports } from '../src/reportRead.js'
import { leaveInsight } from '../src/insightWrite.js'
import { LEAVE_INSIGHT_SPEC, insightNote } from '../src/proposal.js'

const vaultDir = () => mkdtempSync(join(tmpdir(), 'longbook-mcp-report-'))

const GOLDEN = JSON.parse(
  readFileSync(join(import.meta.dirname, '../../core/tests/fixtures/report-golden.json'), 'utf8'),
) as Record<string, any>

/** A vault folder with the given reports already in it, as the app writes them. */
function seeded(files: Record<string, unknown>): string {
  const dir = vaultDir()
  mkdirSync(join(dir, 'reports'), { recursive: true })
  for (const [name, body] of Object.entries(files)) {
    writeFileSync(join(dir, 'reports', `${name}.json`), JSON.stringify(body, null, 2))
  }
  return dir
}

test('the golden report reads back module for module, in the order it was drawn', () => {
  const dir = seeded({ 'august-2026': GOLDEN })
  const out = reports(dir, { id: 'august-2026' }) as Record<string, any>

  assert.equal(out.id, 'august-2026')
  assert.equal(out.month, '2026-08')
  assert.equal(out.created_at, '2026-08-20')
  assert.equal(out.currency, 'INR')
  assert.equal(out.drawn_by_longbook, true)
  assert.equal(out.file, 'reports/august-2026.json')

  const titles = out.modules.map((m: Record<string, unknown>) => [m.type, m.title])
  assert.deepEqual(titles, [
    ['stats', 'Total expenses'],
    ['donut', 'Accounts'],
    ['donut', 'Categories'],
    ['transactions', 'All charges'],
    // Past the four: kinds no draw produces, which a file may still hold.
    ['donut', 'Where it went'],
    ['prose', undefined],
    ['bars', 'Monthly spend'],
  ])
  assert.equal(out.module_count, 7)

  // Every field the app draws from travels through untouched.
  assert.equal(out.modules[0].stats.length, 3)
  assert.equal(out.modules[1].slices[0].label, 'HDFC savings')
  // A draw derives both rings from one currency; only a written donut mixes them.
  assert.ok(out.modules[2].slices.every((s: Record<string, unknown>) => s.currency === 'INR'))
  assert.equal(out.modules[4].slices.at(-1).currency, 'USD')
  assert.equal(out.modules[3].rows.length, 4)
  assert.equal(out.modules[3].rows[0].name, 'House rent')
  assert.equal(out.modules[3].rows[1].category, undefined)
})

test('a module without an id carries the key a viewer comment is filed under', () => {
  const dir = seeded({ 'august-2026': GOLDEN })
  const out = reports(dir, { id: 'august-2026' }) as Record<string, any>
  assert.deepEqual(
    out.modules.map((m: Record<string, unknown>) => m.module_id),
    ['module-0', 'module-1', 'module-2', 'module-3', 'module-4', 'module-5', 'module-6'],
  )
})

test('comments come back as lines, on the module they were left on and nowhere else', () => {
  const dir = seeded({
    'august-2026': {
      ...GOLDEN,
      modules: GOLDEN.modules.map((m: Record<string, unknown>, i: number) =>
        i === 3 ? { ...m, comment: 'Meera: the rent went up\nRohit: ask about the deposit' } : m,
      ),
    },
  })
  const out = reports(dir, { id: 'august-2026' }) as Record<string, any>
  assert.deepEqual(out.modules[3].comments, ['Meera: the rent went up', 'Rohit: ask about the deposit'])
  assert.deepEqual(out.modules[2].comments, ['The rent is the whole of it.'])
  assert.deepEqual(out.modules[0].comments, [])
  // The raw field is not carried twice.
  assert.equal(out.modules[3].comment, undefined)
})

test('the listing is newest month first, and passes what is no report at all', () => {
  const dir = seeded({
    'june-2026': { ...GOLDEN, id: 'june-2026', period: '2026-06' },
    'august-2026': GOLDEN,
    'july-2026': { ...GOLDEN, id: 'july-2026', period: '2026-07' },
  })
  // Bytes that are not JSON are no report, and the app passes them without a word — its
  // shape test cannot read them either, so they are never counted as a broken report.
  writeFileSync(join(dir, 'reports', 'half-written.json'), '{"modules":[')
  // A ledger parked in the folder is a different file, not a broken report.
  writeFileSync(join(dir, 'reports', 'ledger-copy.json'), JSON.stringify({ subscriptions: [], charges: [] }))

  const out = reports(dir) as Record<string, any>
  assert.equal(out.count, 3)
  assert.equal(out.unreadable, 0)
  assert.equal(out.skipped_note, undefined)
  assert.deepEqual(out.reports.map((r: Record<string, unknown>) => r.id), ['august-2026', 'july-2026', 'june-2026'])
  assert.deepEqual(out.reports[0].module_titles, [
    'Total expenses', 'Accounts', 'Categories', 'All charges', 'Where it went', 'prose', 'Monthly spend',
  ])
  assert.equal(out.reports[0].module_count, 7)
  // One key, one type: a listing entry names no `modules`, and a read gives an array.
  assert.equal(out.reports[0].modules, undefined)
  assert.equal(out.reports[0].comments, 1)
  assert.equal(out.reports[0].shared, null)
})

/**
 * What Report.swift needs non-optional. Each of these is report-shaped, so the app counts
 * it, and each fails that decoder — so it must never be listed here as a report the Reports
 * screen would show.
 */
const REFUSED: Record<string, unknown>[] = [
  { ...GOLDEN, version: undefined },
  { ...GOLDEN, version: '1' },
  { ...GOLDEN, id: undefined },
  { ...GOLDEN, title: 42 },
  { ...GOLDEN, subtitle: 7 },
  { ...GOLDEN, modules: { type: 'stats' } },
  { ...GOLDEN, modules: [{ title: 'no type' }] },
  { ...GOLDEN, modules: [{ type: 'stats', stats: [{ amount: 1, currency: 'INR' }] }] },
  { ...GOLDEN, modules: [{ type: 'prose' }] },
  { ...GOLDEN, modules: [{ type: 'donut', slices: [{ label: 'home', amount: 90 }] }] },
  { ...GOLDEN, modules: [{ type: 'donut', slices: [{ label: 'home', amount: '90', currency: 'INR' }] }] },
  { ...GOLDEN, modules: [{ type: 'bars', bars: [{ label: 'Jun' }] }] },
  { ...GOLDEN, modules: [{ type: 'transactions', rows: [{ name: 'Rent', amount: 1 }] }] },
  { ...GOLDEN, modules: [{ type: 'transactions', rows: [{ name: 'Rent', amount: 1, currency: 'INR', date: 5 }] }] },
  { ...GOLDEN, modules: [{ type: 'stats', stats: [{ label: 'Total' }], title: 9 }] },
  // The version 2 envelope, held to the same decoder: days are text, a scope's lists are text.
  { ...GOLDEN, start_date: 20260901 },
  { ...GOLDEN, end_date: false },
  { ...GOLDEN, scope: 'everything' },
  { ...GOLDEN, scope: { accounts: 'HDFC savings' } },
  { ...GOLDEN, scope: { members: [7] } },
  { ...GOLDEN, hidden_ids: 'rent-2026-08-01' },
  { ...GOLDEN, hidden_ids: [1] },
  { ...GOLDEN, modules: [{ type: 'stats', stats: [{ label: 'Total expenses', delta_label: 5 }] }] },
  { ...GOLDEN, modules: [{ type: 'transactions', rows: [{ name: 'Rent', amount: 1, currency: 'INR', removed: 'yes' }] }] },
  { ...GOLDEN, modules: [{ type: 'transactions', rows: [{ name: 'Rent', amount: 1, currency: 'INR', account: 9 }] }] },
  { ...GOLDEN, modules: [{ type: 'transactions', rows: [{ name: 'Rent', amount: 1, currency: 'INR', id: 3 }] }] },
]

test('a file the app cannot decode is counted, never listed as a report', () => {
  for (const [i, refused] of REFUSED.entries()) {
    assert.equal(decodesAsReport(refused), false, `case ${i} should fail the app's decoder`)
    const out = reports(seeded({ broken: refused })) as Record<string, any>
    assert.deepEqual(out.reports, [], `case ${i} should not be listed`)
    assert.equal(out.unreadable, 1, `case ${i} should be counted`)
    assert.match(out.skipped_note, /cannot draw/)
  }
})

test('an unknown module type rides along whole — nothing can refuse it', () => {
  const report = { ...GOLDEN, id: 'rpt-gauge', modules: [{ type: 'gauge', title: 'runway', months: 8, nested: { a: [1, null] } }] }
  assert.equal(decodesAsReport(report), true)
  const out = reports(seeded({ 'rpt-gauge': report }), { id: 'rpt-gauge' }) as Record<string, any>
  assert.equal(out.modules[0].type, 'gauge')
  assert.equal(out.modules[0].months, 8)
  assert.deepEqual(out.modules[0].nested, { a: [1, null] })
})

test('a file past the size cap is skipped and named, never read whole', () => {
  const dir = seeded({ 'august-2026': GOLDEN })
  // Valid JSON, and far past the ceiling: the cap must decide before the read.
  writeFileSync(join(dir, 'reports', 'huge.json'), `{"modules":[],"pad":"${'x'.repeat(26 * 1024 * 1024)}"}`)
  const out = reports(dir) as Record<string, any>
  assert.equal(out.count, 1)
  assert.equal(out.too_large, 1)
  assert.equal(out.unreadable, 0)
  assert.match(out.skipped_note, /past 25 MB/)
})

test('a link out of the folder is refused, whatever it points at', () => {
  const dir = seeded({ 'august-2026': GOLDEN })
  const outside = mkdtempSync(join(tmpdir(), 'longbook-elsewhere-'))
  writeFileSync(join(outside, 'secret.json'), JSON.stringify({ ...GOLDEN, id: 'secret', title: 'Not in this vault' }))
  symlinkSync(join(outside, 'secret.json'), join(dir, 'reports', 'sneaky.json'))

  const out = reports(dir) as Record<string, any>
  assert.deepEqual(out.reports.map((r: Record<string, unknown>) => r.id), ['august-2026'])
  assert.equal(out.outside_folder, 1)
  assert.match(out.skipped_note, /outside the folder/)
  assert.equal((reports(dir, { id: 'secret' }) as Record<string, any>).message, 'No report called "secret". Call reports with no id to see what is there.')
})

test('a live share is named with its link, and its details when the sidecar kept them', () => {
  const dir = seeded({ 'august-2026': GOLDEN, 'july-2026': { ...GOLDEN, id: 'july-2026', period: '2026-07' } })
  writeFileSync(
    join(dir, 'longbook.workspace.json'),
    JSON.stringify({
      reportShares: { 'august-2026': 'sh_abc123', 'july-2026': 'sh_def456' },
      reportShareDetails: { 'august-2026': { url: 'https://longbook.app/r/sh_abc123', with: 'Meera', expires_at: '2026-08-23T09:00:00Z' } },
    }),
  )
  const out = reports(dir) as Record<string, any>
  assert.equal(out.reports[0].shared.with, 'Meera')
  assert.equal(out.reports[0].shared.expires_at, '2026-08-23T09:00:00Z')
  // A share made before details were kept still has the link its id names.
  assert.equal(out.reports[1].shared.url, 'https://longbook.app/r/sh_def456')
  assert.equal(out.reports[1].shared.with, null)
})

test('a key two reports answer to lists them, and an unknown one says so', () => {
  const dir = seeded({
    'august-2026': GOLDEN,
    'august-2026-mine': { ...GOLDEN, id: 'august-2026-mine', subtitle: 'Mine' },
  })
  const clash = reports(dir, { id: '2026-08' }) as Record<string, any>
  assert.match(clash.message, /matches more than one report/)
  // One month, one created_at: the filename is what breaks the tie, as it does in the app.
  assert.deepEqual(clash.ambiguous.map((r: Record<string, unknown>) => r.id), ['august-2026-mine', 'august-2026'])
  // An exact id still answers with one report, never with the clash.
  assert.equal((reports(dir, { id: 'august-2026' }) as Record<string, any>).drawn_by_longbook, true)
  assert.match((reports(dir, { id: 'may-2026' }) as Record<string, any>).message, /No report called "may-2026"/)
})

test('an empty vault says where reports come from, and never throws', () => {
  const out = reports(vaultDir()) as Record<string, any>
  assert.deepEqual(out.reports, [])
  assert.equal(out.unreadable, 0)
  assert.match(out.note, /No reports yet/)
})

test('the month is the period when it names one, else the one month every row falls in', () => {
  assert.equal(periodKeyOf(GOLDEN), '2026-08')
  const { period, ...noPeriod } = GOLDEN
  void period
  assert.equal(periodKeyOf(noPeriod), '2026-08')
  assert.equal(periodKeyOf({ ...GOLDEN, period: '2026-13' }), '2026-08')
  assert.equal(periodKeyOf({ ...noPeriod, modules: [] }), null)
})

test('the reports tool only reads — it is declared so, and it says where reports live', () => {
  assert.equal(REPORTS_SPEC.annotations.readOnlyHint, true)
  assert.match(REPORTS_SPEC.description, /reports\// )
  assert.match(REPORTS_SPEC.description, /owner's own machine/)
})

test('an insight appends to insights.json, creating it once and keeping what was there', () => {
  const dir = vaultDir()
  leaveInsight(dir, { module: 'dashboard.next_payment', text: 'Rent lands three days after salary.' })
  leaveInsight(dir, { module: 'dashboard.by_category', text: 'Home is two-thirds of the year.' })
  const file = JSON.parse(readFileSync(join(dir, 'insights.json'), 'utf8'))
  assert.equal(file.version, 1)
  assert.equal(file.insights.length, 2)
  assert.equal(file.insights[0].module, 'dashboard.next_payment')
  assert.match(file.insights[1].created_at, /^\d{4}-\d{2}-\d{2}T/)
})

const RETIRED = ['reports.summary', 'reports.cash_flow', 'reports.spendings', 'reports.by_account', 'reports.top_charges']

test('no reports module is offered, and a note left on one says it has no screen', () => {
  assert.ok(LEAVE_INSIGHT_SPEC.description.includes('There are no reports.* modules'))
  for (const id of RETIRED) {
    assert.ok(!LEAVE_INSIGHT_SPEC.description.includes(`, ${id},`), `${id} is still offered as a choice`)
    assert.match(insightNote(id) ?? '', /no longer a module in the app/)
  }
  assert.equal(insightNote('dashboard.this_month'), undefined)
  assert.equal(insightNote('account.7f1c'), undefined)
  assert.match(insightNote('calendar.month') ?? '', /shows when a version does/)
})

test('a note already written on a retired module is kept exactly as it was', () => {
  const dir = vaultDir()
  const out = leaveInsight(dir, { module: 'reports.spendings', text: 'Home is two-thirds of the year.' }) as Record<string, any>
  assert.match(out.note, /the months longbook drew/)
  const file = JSON.parse(readFileSync(join(dir, 'insights.json'), 'utf8'))
  assert.equal(file.insights[0].module, 'reports.spendings')
  assert.equal(file.insights[0].text, 'Home is two-thirds of the year.')
})

/** A version 2 report as longbook draws it: a month, a trip or a requested span. */
const drawn = (id: string, title: string, start: string, end: string, extra: Record<string, unknown> = {}) => ({
  version: 2, id, title, subtitle: 'Drawn by longbook', start_date: start, end_date: end, created_at: '2026-10-01', currency: 'INR',
  modules: [{ type: 'stats', title: 'Total expenses', stats: [{ label: 'Total expenses', amount: 100, currency: 'INR' }] }],
  ...extra,
})

test('the listing is newest last covered day first, as the Reports screen orders it; no days list last', () => {
  const dir = seeded({
    'august-2026': GOLDEN,
    'september-2026': drawn('september-2026', 'September 2026', '2026-09-01', '2026-09-30', { period: '2026-09' }),
    'trip-goa-2026-09-28': drawn('trip-goa-2026-09-28', 'Goa', '2026-09-28', '2026-10-03', { scope: { accounts: ['Amex 1007'] } }),
    'report-school-fees-2026-07-01': drawn('report-school-fees-2026-07-01', 'School fees', '2026-07-01', '2026-09-15', {
      scope: { members: ['Diya'], categories: ['education'] },
    }),
    // Days out of order are no days of their own: the rows' month stands in, as Report.swift's range does.
    'backwards': drawn('backwards', 'Backwards', '2026-06-30', '2026-06-01', {
      modules: [{ type: 'transactions', rows: [{ name: 'Rent', date: '2026-05-01', amount: 1, currency: 'INR' }] }],
    }),
    'undated': { version: 1, id: 'undated', title: 'Notes', modules: [{ type: 'prose', text: 'no days at all' }] },
  })
  const out = reports(dir) as Record<string, any>
  assert.deepEqual(out.reports.map((r: Record<string, unknown>) => r.id), [
    'trip-goa-2026-09-28', 'september-2026', 'report-school-fees-2026-07-01', 'august-2026', 'backwards', 'undated',
  ])
  assert.match(out.note, /^Newest first, by the last day each covers\./)

  const [trip, september, span, august, backwards, undated] = out.reports
  assert.deepEqual([trip.start_date, trip.end_date, trip.month], ['2026-09-28', '2026-10-03', null])
  assert.deepEqual(trip.scope, { accounts: ['Amex 1007'], members: [], categories: [] })
  assert.equal(trip.drawn_by_longbook, true)
  assert.deepEqual([september.start_date, september.end_date, september.month, september.scope], ['2026-09-01', '2026-09-30', '2026-09', null])
  assert.deepEqual(span.scope, { accounts: [], members: ['Diya'], categories: ['education'] })
  // A version 1 month names only its period; its days are the month's.
  assert.deepEqual([august.start_date, august.end_date, august.month], ['2026-08-01', '2026-08-31', '2026-08'])
  assert.deepEqual([backwards.start_date, backwards.end_date, backwards.month], ['2026-05-01', '2026-05-31', null])
  assert.deepEqual([undated.start_date, undated.end_date, undated.month, undated.scope], [null, null, null, null])
})

test('one last day breaks on the newer file, then on the name', () => {
  const dir = seeded({
    'b-older': drawn('b-older', 'Older', '2026-09-01', '2026-09-30', { created_at: '2026-09-30' }),
    'c-newer': drawn('c-newer', 'Newer', '2026-09-20', '2026-09-30', { created_at: '2026-10-01' }),
    'a-same': drawn('a-same', 'Same', '2026-09-10', '2026-09-30', { created_at: '2026-09-30' }),
  })
  const out = reports(dir) as Record<string, any>
  assert.deepEqual(out.reports.map((r: Record<string, unknown>) => r.id), ['c-newer', 'a-same', 'b-older'])
})

test('the days covered are the file\'s own when in order, else the month the report settles on', () => {
  assert.deepEqual(coveredDays(drawn('x', 'X', '2026-10-01', '2026-10-01')), { start: '2026-10-01', end: '2026-10-01' })
  assert.deepEqual(coveredDays({ ...GOLDEN }), { start: '2026-08-01', end: '2026-08-31' })
  assert.deepEqual(coveredDays({ ...GOLDEN, period: '2024-02' }), { start: '2024-02-01', end: '2024-02-29' })
  assert.deepEqual(coveredDays({ ...GOLDEN, start_date: '2026-08-05' }), { start: '2026-08-01', end: '2026-08-31' }, 'one day alone is no range')
  assert.equal(coveredDays({ version: 2, id: 'x', title: 'X', modules: [] }), null)
})

test('the reports tool says a report may cover any span, and names trips and requested spans by their ids', () => {
  assert.match(REPORTS_SPEC.description, /may cover any span of days/)
  assert.match(REPORTS_SPEC.description, /"trip-"/)
  assert.match(REPORTS_SPEC.description, /create_report starts "report-"/)
  assert.doesNotMatch(REPORTS_SPEC.description, /one per calendar month/)
})
