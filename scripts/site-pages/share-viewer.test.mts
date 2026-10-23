// The shared-report viewer's words and numbers, held to the app's report screen. Dates are
// built from local parts, so the expectations hold in any time zone.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  categoryRanks, categoryWord, chargeSplit, commentMeta, donutView, emptyNarrowing, errorWords,
  expiryNote, filterOptions, genericHeading, inkVar, moduleKey, modulesOf, money, narrow, rangeName,
  rowFacts, rowInkRank, scopeLine, shareIdFrom, sharePct, statsView, writtenNote, type Json,
} from '../../apps/longbook-site/r/report-view.mts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..')
const GOLDEN = JSON.parse(readFileSync(join(ROOT, 'packages/core/tests/fixtures/report-golden.json'), 'utf8')) as Json
const NBSP = ' '

const SAMPLE: Json = {
  version: 2,
  id: 'trip-goa-2026-09-28',
  title: 'Goa',
  subtitle: 'Drawn by longbook',
  start_date: '2026-09-28',
  end_date: '2026-10-03',
  scope: { accounts: ['HDFC savings', 'Amex 1007'], members: [], categories: ['travel', 'rent'] },
  hidden_ids: ['hidden-1'],
  created_at: '2026-10-01',
  currency: 'INR',
  modules: [
    { type: 'stats', title: 'Total expenses', stats: [
      { label: 'Total expenses', amount: 43849, currency: 'INR', delta_pct: 9.6, delta_is_good: false, delta_label: 'vs June' },
      { label: 'Total expenses', amount: 20, currency: 'USD' },
      { label: 'Charges', value: '3' },
      { label: 'Not yet confirmed', value: '1' },
      { label: 'Money in', amount: 150000, currency: 'INR' },
    ] },
    { type: 'donut', title: 'Accounts', currency: 'INR', slices: [
      { label: 'HDFC savings', amount: 42000, currency: 'INR' },
      { label: 'Amex 1007', amount: 1849, currency: 'INR' },
    ] },
    { type: 'donut', title: 'Categories', currency: 'INR', slices: [
      { label: 'rent', amount: 42000, currency: 'INR' },
      { label: 'No category', amount: 1849, currency: 'INR' },
    ] },
    { type: 'transactions', title: 'All charges', rows: [
      { id: 'rent-2026-09-28', name: 'House rent', date: '2026-09-28', amount: 42000, currency: 'INR',
        category: 'rent', account: 'HDFC savings', member: 'Rohit' },
      { id: 'shop-2026-10-01', name: 'Corner shop', date: '2026-10-01', amount: 1849, currency: 'INR', account: 'Amex 1007' },
      { id: 'claude-2026-09-30', name: 'Claude', date: '2026-09-30', amount: 20, currency: 'USD',
        category: 'ai subscription', account: 'Amex 1007' },
      { id: 'hidden-1', name: 'Dropped for good', date: '2026-09-29', amount: 99, currency: 'INR' },
      { id: 'hotel-2026-09-29', name: 'Taj Holiday Village', date: '2026-09-29', amount: 18000, currency: 'INR',
        category: 'travel', account: 'Amex 1007', removed: true },
    ] },
  ],
}

const mod = (report: Json, index: number): Json => modulesOf(report)[index] as Json

test('rangeName names a single day, a month, a span across months and one across years', () => {
  const days = (start: string, end: string, extra: Json = {}) => rangeName({ start_date: start, end_date: end, ...extra })
  assert.equal(days('2026-10-01', '2026-10-01'), '1 October 2026')
  assert.equal(days('2026-08-01', '2026-08-31'), '1–31 August 2026')
  assert.equal(days('2026-09-28', '2026-10-03'), '28 September – 3 October 2026')
  assert.equal(days('2025-12-30', '2026-01-02'), '30 December 2025 – 2 January 2026')
  assert.equal(rangeName(SAMPLE), '28 September – 3 October 2026')
})

test('rangeName falls back to the period, then to the one month of every dated row', () => {
  assert.equal(rangeName({ start_date: '2026-03-09', end_date: '2026-03-01', period: '2026-02' }), '1–28 February 2026')
  assert.equal(rangeName({ start_date: '2026-02-31', end_date: '2026-03-04', period: '2026-02' }), '1–28 February 2026')
  assert.equal(rangeName(GOLDEN), '1–31 August 2026')
  const rows = (dates: string[]): Json => ({ modules: [{ type: 'transactions', rows: dates.map((date) => ({ name: 'x', date, amount: 1, currency: 'INR' })) }] })
  assert.equal(rangeName(rows(['2026-07-03', '2026-07-20'])), '1–31 July 2026')
  assert.equal(rangeName(rows(['2026-07-03', '2026-08-20'])), null)
  assert.equal(rangeName({ period: '2026-13' }), null)
})

test('writtenNote says when the file was written, only from a real day', () => {
  assert.equal(writtenNote({ created_at: '2026-08-07' }), 'Written 7 August 2026')
  assert.equal(writtenNote(GOLDEN), 'Written 20 August 2026')
  assert.equal(writtenNote({ created_at: 'soon' }), null)
  assert.equal(writtenNote({}), null)
})

test('scopeLine lists what the report was narrowed to, skipping empty lists', () => {
  assert.equal(scopeLine(SAMPLE), 'Accounts: HDFC savings, Amex 1007 · Categories: Travel, Rent', 'categories read as the tiles name them')
  assert.equal(scopeLine({ scope: { accounts: [], members: ['Rohit', 'Asha'] } }), 'Members: Rohit, Asha')
  assert.equal(scopeLine({ scope: { accounts: ['Cash'], members: ['Rohit'], categories: ['No category'] } }),
    'Accounts: Cash · Members: Rohit · Categories: No category')
  assert.equal(scopeLine({ scope: { accounts: [], members: [], categories: [] } }), null)
  assert.equal(scopeLine(GOLDEN), null)
})

test('money follows fmtMoney: each currency in its own style, no cents on INR, JPY or whole amounts', () => {
  assert.equal(money(43849, 'INR'), '₹43,849')
  assert.equal(money(150000, 'INR'), '₹1,50,000')
  assert.equal(money(1234.5, 'INR'), '₹1,235')
  assert.equal(money(20, 'USD'), '$20')
  assert.equal(money(19.5, 'USD'), '$19.50')
  assert.equal(money(1500, 'JPY'), '￥1,500')
  assert.equal(money(1500.4, 'JPY'), '￥1,500')
  assert.equal(money(5.5, 'EUR'), `5,50${NBSP}€`)
  assert.equal(money(5, 'EUR'), `5${NBSP}€`)
})

test('sharePct rounds from a tenth up and keeps one decimal below it', () => {
  assert.equal(sharePct(0.62), '62%')
  assert.equal(sharePct(0.1), '10%')
  assert.equal(sharePct(1), '100%')
  assert.equal(sharePct(0.045), '4.5%')
  assert.equal(sharePct(0.004), '0.4%')
  assert.equal(sharePct(0.0996), '10.0%')
})

test('a v2 total: the figure, its other-currency sums, the change, then one line', () => {
  assert.deepEqual(statsView(mod(SAMPLE, 0)), {
    lead: '₹43,849',
    companions: '+$20',
    delta: { text: '▲ 9.6% vs June', good: false },
    line: '3 charges · 1 not yet confirmed · Money in ₹1,50,000',
  })
  const two = statsView({ stats: [
    { label: 'Total expenses', amount: 649, currency: 'INR', delta_pct: -4.25, delta_is_good: true },
    { label: 'Total expenses', amount: 20, currency: 'USD' },
    { label: 'Total expenses', amount: 5, currency: 'EUR' },
  ] })
  assert.equal(two.companions, `+$20 +5${NBSP}€`)
  // An exact half goes to the even digit, as the app's String(format: "%.1f") prints it.
  assert.deepEqual(two.delta, { text: '▼ 4.2%', good: true })
  assert.equal(two.line, '')
  assert.equal(statsView({ stats: [{ label: 'T', amount: 1, currency: 'INR', delta_pct: 0.15 }] }).delta?.text, '▲ 0.1%')
  assert.equal(statsView({ stats: [{ label: 'T', amount: 1, currency: 'INR', delta_pct: 2.75 }] }).delta?.text, '▲ 2.8%')
})

test('the v1 golden total reads with no suffix on its change and counts as words', () => {
  assert.deepEqual(statsView(mod(GOLDEN, 0)), {
    lead: '₹46,528',
    companions: null,
    delta: { text: '▲ 8.4%', good: false },
    line: '4 charges · Money in ₹1,80,000',
  })
  const confirmed = statsView({ stats: [
    { label: 'Confirmed in August', amount: 649, currency: 'INR' },
    { label: 'Charges', value: '1 of 3' },
  ] })
  assert.equal(confirmed.lead, '₹649')
  assert.equal(confirmed.line, '1 of 3 charges')
  assert.equal(statsView({ stats: [{ label: 'Charges', value: '2' }] }).lead, null)
})

test('the charge list drops hidden ids and splits kept from removed, in file order', () => {
  const { kept, removed } = chargeSplit(SAMPLE, mod(SAMPLE, 3))
  assert.deepEqual(kept.map((row) => row.id), ['rent-2026-09-28', 'shop-2026-10-01', 'claude-2026-09-30'])
  assert.deepEqual(removed.map((row) => row.id), ['hotel-2026-09-29'])
  const golden = chargeSplit(GOLDEN, mod(GOLDEN, 3))
  assert.equal(golden.kept.length, 4)
  assert.equal(golden.removed.length, 0)
})

test('a row wears its category ink by the Categories donut order; unknown folds to neutral', () => {
  const ranks = categoryRanks(GOLDEN)
  assert.deepEqual([...ranks], [['rent', 0], ['No category', 1], ['streaming', 2]])
  const rows = mod(GOLDEN, 3).rows as Json[]
  assert.deepEqual(rows.map((row) => rowInkRank(row, ranks)), [0, 1, 2, null])
  assert.equal(inkVar(0), 'var(--lb-data-0)')
  assert.equal(inkVar(11), 'var(--lb-data-11)')
  assert.equal(inkVar(12), 'var(--lb-neutral-fold)')
  assert.equal(inkVar(null), 'var(--lb-neutral-fold)')
  assert.equal(rowInkRank({ category: '  rent ' }, ranks), 0)
})

test('a charge row lists its day, category, member and account', () => {
  const rows = mod(SAMPLE, 3).rows as Json[]
  assert.deepEqual(rowFacts(rows[0] as Json).map((fact) => fact.text), ['28 Sep', 'Rent', 'Rohit', 'HDFC savings'])
  assert.deepEqual(rowFacts(rows[1] as Json).map((fact) => fact.text), ['1 Oct', 'No category', 'Amex 1007'])
  const golden = mod(GOLDEN, 3).rows as Json[]
  assert.deepEqual(rowFacts(golden[1] as Json).map((fact) => fact.kind), ['date', 'category'])
})

test('search and filters answer from the rows alone', () => {
  const { kept } = chargeSplit(SAMPLE, mod(SAMPLE, 3))
  const options = filterOptions(kept)
  assert.deepEqual(options.categories, [['rent', 'Rent'], ['ai subscription', 'Ai subscription'], ['No category', 'No category']])
  assert.deepEqual(options.accounts, ['HDFC savings', 'Amex 1007'])
  assert.deepEqual(options.members, ['Rohit'])
  assert.deepEqual(options.currencies, ['INR', 'USD'])
  const names = (n: Partial<ReturnType<typeof emptyNarrowing>>) => narrow(kept, { ...emptyNarrowing(), ...n }).map((row) => row.name)
  assert.deepEqual(names({ category: 'No category' }), ['Corner shop'])
  assert.deepEqual(names({ search: ' AMEX ' }), ['Corner shop', 'Claude'])
  assert.deepEqual(names({ currency: 'USD' }), ['Claude'])
  assert.deepEqual(names({ account: 'Amex 1007', category: 'rent' }), [])
})

test('a ring is one currency: other slices list with no share, and the centre names the top slice', () => {
  const ring = donutView(mod(GOLDEN, 4), 'INR')
  assert.deepEqual(ring.scoped.map((row) => row.share), ['95%', '4.5%'])
  assert.deepEqual(ring.foreign.map((row) => [row.label, row.share, row.amountText]), [['ai subscription', null, '$20']])
  assert.deepEqual(ring.centre, { title: '95%', note: 'From home and bills' })
  const halves = donutView({ currency: 'INR', slices: [
    { label: 'a', amount: 50, currency: 'INR' }, { label: 'b', amount: 50, currency: 'INR' }, { label: 'c', amount: -5, currency: 'INR' },
  ] })
  assert.deepEqual(halves.arcs.map((arc) => [arc.rank, +arc.length.toFixed(4), +arc.offset.toFixed(4)]), [[0, 0.496, 0.002], [1, 0.496, 0.502]])
  assert.equal(halves.scoped[2]?.share, null)
  assert.deepEqual(donutView({ slices: [] }).centre, { title: '—', note: 'Nothing yet' })
})

test('only a category is re-cased', () => {
  assert.equal(categoryWord('ai subscription'), 'Ai subscription')
  assert.equal(categoryWord('éclairs'), 'Éclairs')
  assert.equal(categoryWord(''), '')
})

test('comment keys are the module id, else module-<index> into report.modules', () => {
  assert.deepEqual(modulesOf(GOLDEN).map((m, i) => moduleKey(m, i)),
    ['module-0', 'module-1', 'module-2', 'module-3', 'module-4', 'module-5', 'module-6'])
  assert.equal(moduleKey({ id: 'spend', type: 'stats' }, 3), 'spend')
  assert.equal(moduleKey({ id: '', type: 'stats' }, 3), 'module-3')
  assert.equal(moduleKey({ id: 7, type: 'stats' }, 2), 'module-2')
})

test('the page parts: share id, headings, expiry, comment names and error words', () => {
  assert.equal(shareIdFrom('/r/5b1c2f9e-0000-4000-8000-000000000000'), '5b1c2f9e-0000-4000-8000-000000000000')
  assert.equal(shareIdFrom('/r/'), null)
  assert.equal(genericHeading({ type: 'monthly_summary' }), 'monthly summary')
  assert.equal(genericHeading({ type: 'x', title: 'Mine' }), 'Mine')
  assert.equal(expiryNote(new Date(2026, 9, 4, 14, 5).toISOString()), 'This link expires 4 Oct, 14:05')
  assert.equal(expiryNote(undefined), null)
  assert.equal(commentMeta({ author: '', created_at: new Date(2026, 9, 2, 9).toISOString() }), 'Someone · 2 Oct')
  assert.equal(commentMeta({ author: 'Asha' }), 'Asha')
  for (const status of [404, 410, 403, 400, 500, 0]) {
    for (const action of ['view', 'comment'] as const) {
      const said = errorWords(status, action)
      assert.match(said, /^[A-Z]/)
      assert.ok(!['not found', 'this link has expired', 'wrong password'].includes(said))
    }
  }
})

test('the page is built by its generator and stays out of search', () => {
  const page = readFileSync(join(ROOT, 'apps/longbook-site/r/index.html'), 'utf8')
  assert.match(page, /<meta name="robots" content="noindex, nofollow">/)
  assert.match(page, /<!-- viewer:begin -->\n<script>\n\/\/ generated by scripts\/gen-share-viewer\.mts/)
  assert.match(page, /href="\/tokens\.css\?v=[0-9a-f]{10}"/)
})
