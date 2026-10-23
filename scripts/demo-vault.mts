#!/usr/bin/env -S npx tsx
// A demo folder for screenshots: one invented household, dated around the day it runs, every
// name and amount made up, written into an empty or earlier demo folder. India in rupees by
// default; `--household us` is the US in dollars.
// Run: npm run demo:vault -- <folder> [--today 2026-09-24] [--household us]
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const argv = process.argv.slice(2)
const todayAt = argv.indexOf('--today')
const TODAY = todayAt >= 0 ? argv[todayAt + 1] : new Date().toLocaleDateString('en-CA')
const householdAt = argv.indexOf('--household')
const US = householdAt >= 0 && argv[householdAt + 1] === 'us'
const target = argv.find((a, i) => !a.startsWith('--') && (todayAt < 0 || i !== todayAt + 1) && (householdAt < 0 || i !== householdAt + 1))
if (!target || !/^\d{4}-\d{2}-\d{2}$/.test(TODAY ?? '')) {
  console.error('Usage: npm run demo:vault -- <folder> [--today YYYY-MM-DD] [--household us]')
  process.exit(2)
}
const folder = resolve(target)
// Never over a real folder: only an empty one, or one this script wrote before.
if (existsSync(folder) && readdirSync(folder).length && !existsSync(join(folder, '.demo-vault'))) {
  console.error(`${folder} holds files this script did not write. Name an empty folder.`)
  process.exit(1)
}

// ---- days, as YYYY-MM-DD in no time zone ---------------------------------------------------

const parse = (d: string): Date => new Date(`${d}T00:00:00Z`)
const iso = (d: Date): string => d.toISOString().slice(0, 10)
const daysIn = (y: number, m: number): number => new Date(Date.UTC(y, m + 1, 0)).getUTCDate()
const addDays = (d: string, n: number): string => iso(new Date(parse(d).getTime() + n * 86_400_000))
const addMonths = (d: string, n: number, anchor = parse(d).getUTCDate()): string => {
  const t = parse(d)
  const y = t.getUTCFullYear() + Math.floor((t.getUTCMonth() + n) / 12)
  const m = (((t.getUTCMonth() + n) % 12) + 12) % 12
  return iso(new Date(Date.UTC(y, m, Math.min(anchor, daysIn(y, m)))))
}
/** This month's day `n`, or last month's when that is still ahead of today. */
const recent = (n: number): string => {
  const here = addMonths(TODAY, 0, n)
  return here <= TODAY ? here : addMonths(TODAY, -1, n)
}
const YEAR_AGO = addMonths(TODAY, -12)
const YEAR_AHEAD = addMonths(TODAY, 12)

// ---- the household ------------------------------------------------------------------------

type Basis = 'statement' | 'email' | 'user' | 'mark_paid'
interface Spec {
  id: string
  name: string
  amount: number | ((i: number) => number)
  currency?: string
  cycle: 'monthly' | 'yearly' | 'custom' | 'once'
  every?: number
  first: string
  until?: string
  tag?: string
  member?: string
  account?: string
  notes?: string
  direction?: 'in' | 'transfer'
  basis?: Basis
  status?: 'active' | 'paused' | 'cancelled'
  ends?: string
}

/** A monthly line's first charge, a year back on its day of the month. */
const monthly = (n: number): string => addMonths(recent(n), -12)

const inSpecs: Spec[] = [
  { id: 'c-rent', name: 'House rent', amount: 42000, cycle: 'monthly', first: monthly(1), tag: 'rent',
    member: 'm-mehta', account: 'a-hdfc', notes: 'Landlord: Mehta Properties\nLease ends: March 2027' },
  { id: 'c-maint', name: 'Society maintenance', amount: 3500, cycle: 'monthly', first: monthly(5), tag: 'home',
    account: 'a-hdfc', notes: 'Society: Greenwood Residency' },
  { id: 'c-cook', name: 'Sunita, cook', amount: 12000, cycle: 'monthly', first: monthly(5), tag: 'salary',
    member: 'm-sunita', account: 'a-hdfc' },
  { id: 'c-netflix', name: 'Netflix', amount: 649, cycle: 'monthly', first: monthly(6), tag: 'streaming',
    account: 'a-axis', basis: 'email' },
  { id: 'c-spotify', name: 'Spotify', amount: 119, cycle: 'monthly', first: monthly(11), tag: 'streaming',
    member: 'm-asha', account: 'a-axis', basis: 'email' },
  { id: 'c-airtel', name: 'Airtel Digital TV', amount: 899, cycle: 'monthly', first: monthly(3), tag: 'telecom',
    account: 'a-hdfc' },
  { id: 'c-jio', name: 'Jio postpaid', amount: 599, cycle: 'monthly', first: monthly(18), tag: 'telecom',
    member: 'm-asha', account: 'a-axis' },
  { id: 'c-adobe', name: 'Adobe Creative Cloud', amount: 1699, cycle: 'monthly', first: monthly(2), tag: 'software',
    member: 'm-dev', account: 'a-axis', basis: 'email', until: addMonths(TODAY, 3) },
  { id: 'c-claude', name: 'Claude Pro', amount: 20, currency: 'USD', cycle: 'monthly', first: monthly(2), tag: 'ai',
    member: 'm-dev', account: 'a-axis', basis: 'email' },
  { id: 'c-school', name: 'School fees, Kabir', amount: 15000, cycle: 'monthly', first: monthly(10), tag: 'education',
    member: 'm-kabir', account: 'a-icici', notes: 'School: Oakridge Public School\nTerm: April to March' },
  { id: 'c-gym', name: 'Fitlane gym', amount: 2500, cycle: 'monthly', first: monthly(15), tag: 'health & fitness',
    member: 'm-asha', account: 'a-icici' },
  { id: 'c-power', name: 'Electricity', amount: (i) => [2140, 2310, 2890, 3420, 3180, 2760, 2230, 2080, 2450, 2960, 3310, 2870][i % 12]!,
    cycle: 'monthly', first: monthly(20), tag: 'utility', account: 'a-hdfc' },
  { id: 'c-prime', name: 'Amazon Prime', amount: 1499, cycle: 'yearly', first: addMonths(recent(14), -7), tag: 'membership',
    account: 'a-axis', until: addMonths(TODAY, 24) },
  { id: 'c-ergo', name: 'HDFC ERGO health insurance', amount: 24500, cycle: 'yearly', first: addMonths(recent(12), -10),
    tag: 'insurance', member: 'm-dev', account: 'a-hdfc', until: addMonths(TODAY, 24),
    notes: 'Policy number: 88213\nCovers: Dev, Asha and Kabir\nRenews: every November' },
  { id: 'c-lic', name: 'LIC term plan', amount: 18200, cycle: 'yearly', first: addMonths(recent(28), -6), tag: 'insurance',
    member: 'm-dev', account: 'a-hdfc', until: addMonths(TODAY, 24), notes: 'Policy number: 51204776\nCover: 1 crore' },
  { id: 'c-star', name: 'Star Health, Asha', amount: 11800, cycle: 'custom', every: 182, first: addDays(recent(8), -182 * 2 + 30),
    tag: 'insurance', member: 'm-asha', account: 'a-icici', until: addMonths(TODAY, 18) },
  { id: 'c-domain', name: 'GoDaddy domain, three years', amount: 2850, cycle: 'custom', every: 1095, first: addDays(TODAY, -330),
    tag: 'domain & hosting', member: 'm-dev', account: 'a-axis', until: addDays(TODAY, 800) },
  { id: 'c-card', name: 'Axis card bill', amount: (i) => [9830, 11240, 12450, 10610, 13980, 9960, 12870, 11420, 10350, 12050, 11730, 12450][i % 12]!,
    cycle: 'monthly', first: monthly(24), account: 'a-hdfc', direction: 'transfer' },
  { id: 'c-salary', name: 'Salary, Vertex Labs', amount: 185000, cycle: 'monthly', first: monthly(1), member: 'm-dev',
    account: 'a-hdfc', direction: 'in', notes: 'Employer: Vertex Labs Pvt Ltd' },
  { id: 'c-swiggy', name: 'Swiggy', amount: 1340, cycle: 'once', first: addDays(TODAY, -9), account: 'a-axis' },
  { id: 'c-pharmacy', name: 'Apollo Pharmacy', amount: 862, cycle: 'once', first: addDays(TODAY, -16), tag: 'health & fitness',
    account: 'a-axis' },
  { id: 'c-train', name: 'IRCTC, Pune trip', amount: 4380, cycle: 'once', first: addDays(TODAY, -38), tag: 'travel',
    account: 'a-axis' },
  { id: 'c-gift', name: 'Tanishq, anniversary gift', amount: 28500, cycle: 'once', first: addDays(TODAY, -71), tag: 'gift',
    member: 'm-asha', account: 'a-axis' },
  { id: 'c-hotstar', name: 'JioHotstar', amount: 299, cycle: 'monthly', first: addMonths(monthly(21), 2), tag: 'streaming',
    account: 'a-axis', status: 'cancelled', ends: addMonths(recent(21), -3), until: addMonths(recent(21), -3) },
]

// The same household's shape in the US: the same days and kinds of line, in dollars.
const usSpecs: Spec[] = [
  { id: 'c-rent', name: 'Rent', amount: 2450, cycle: 'monthly', first: monthly(1), tag: 'rent',
    member: 'm-parkview', account: 'a-chase', notes: 'Landlord: Parkview Apartments\nLease ends: March 2027' },
  { id: 'c-internet', name: 'Xfinity internet', amount: 80, cycle: 'monthly', first: monthly(5), tag: 'telecom',
    account: 'a-chase' },
  { id: 'c-nanny', name: 'Rosa, nanny', amount: 1600, cycle: 'monthly', first: monthly(5), tag: 'salary',
    member: 'm-rosa', account: 'a-chase' },
  { id: 'c-netflix', name: 'Netflix', amount: 15.49, cycle: 'monthly', first: monthly(6), tag: 'streaming',
    account: 'a-amex', basis: 'email' },
  { id: 'c-spotify', name: 'Spotify Family', amount: 19.99, cycle: 'monthly', first: monthly(11), tag: 'streaming',
    member: 'm-maya', account: 'a-amex', basis: 'email' },
  { id: 'c-youtube', name: 'YouTube TV', amount: 82.99, cycle: 'monthly', first: monthly(3), tag: 'streaming',
    account: 'a-chase' },
  { id: 'c-verizon', name: 'Verizon', amount: 85, cycle: 'monthly', first: monthly(18), tag: 'telecom',
    member: 'm-maya', account: 'a-amex' },
  { id: 'c-adobe', name: 'Adobe Creative Cloud', amount: 59.99, cycle: 'monthly', first: monthly(2), tag: 'software',
    member: 'm-sam', account: 'a-amex', basis: 'email', until: addMonths(TODAY, 3) },
  { id: 'c-claude', name: 'Claude Pro', amount: 20, cycle: 'monthly', first: monthly(2), tag: 'ai',
    member: 'm-sam', account: 'a-amex', basis: 'email' },
  { id: 'c-school', name: 'Preschool, Leo', amount: 1250, cycle: 'monthly', first: monthly(10), tag: 'education',
    member: 'm-leo', account: 'a-ally', notes: 'School: Little Oaks Preschool\nTerm: September to June' },
  { id: 'c-gym', name: 'Peloton membership', amount: 44, cycle: 'monthly', first: monthly(15), tag: 'health & fitness',
    member: 'm-maya', account: 'a-ally' },
  { id: 'c-power', name: 'Electricity', amount: (i) => [96, 104, 131, 158, 149, 122, 99, 92, 108, 134, 152, 127][i % 12]!,
    cycle: 'monthly', first: monthly(20), tag: 'utility', account: 'a-chase' },
  { id: 'c-prime', name: 'Amazon Prime', amount: 139, cycle: 'yearly', first: addMonths(recent(14), -7), tag: 'membership',
    account: 'a-amex', until: addMonths(TODAY, 24) },
  { id: 'c-home', name: 'Home insurance', amount: 1280, cycle: 'yearly', first: addMonths(recent(12), -10),
    tag: 'insurance', member: 'm-sam', account: 'a-chase', until: addMonths(TODAY, 24),
    notes: 'Policy number: 88213\nCovers: apartment contents\nRenews: every November' },
  { id: 'c-life', name: 'Term life insurance', amount: 540, cycle: 'yearly', first: addMonths(recent(28), -6), tag: 'insurance',
    member: 'm-sam', account: 'a-chase', until: addMonths(TODAY, 24), notes: 'Policy number: 51204776\nCover: $1,000,000' },
  { id: 'c-car', name: 'Car insurance, Maya', amount: 684, cycle: 'custom', every: 182, first: addDays(recent(8), -182 * 2 + 30),
    tag: 'insurance', member: 'm-maya', account: 'a-ally', until: addMonths(TODAY, 18) },
  { id: 'c-domain', name: 'Namecheap domain, three years', amount: 54, cycle: 'custom', every: 1095, first: addDays(TODAY, -330),
    tag: 'domain & hosting', member: 'm-sam', account: 'a-amex', until: addDays(TODAY, 800) },
  { id: 'c-card', name: 'Amex card bill', amount: (i) => [612, 704, 781, 655, 868, 619, 803, 712, 641, 752, 733, 781][i % 12]!,
    cycle: 'monthly', first: monthly(24), account: 'a-chase', direction: 'transfer' },
  { id: 'c-salary', name: 'Salary, Vertex Labs', amount: 8200, cycle: 'monthly', first: monthly(1), member: 'm-sam',
    account: 'a-chase', direction: 'in', notes: 'Employer: Vertex Labs Inc.' },
  { id: 'c-doordash', name: 'DoorDash', amount: 42.8, cycle: 'once', first: addDays(TODAY, -9), account: 'a-amex' },
  { id: 'c-pharmacy', name: 'CVS Pharmacy', amount: 26.4, cycle: 'once', first: addDays(TODAY, -16), tag: 'health & fitness',
    account: 'a-amex' },
  { id: 'c-train', name: 'Amtrak, Boston trip', amount: 186, cycle: 'once', first: addDays(TODAY, -38), tag: 'travel',
    account: 'a-amex' },
  { id: 'c-gift', name: 'Anniversary gift', amount: 320, cycle: 'once', first: addDays(TODAY, -71), tag: 'gift',
    member: 'm-maya', account: 'a-amex' },
  { id: 'c-hulu', name: 'Hulu', amount: 17.99, cycle: 'monthly', first: addMonths(monthly(21), 2), tag: 'streaming',
    account: 'a-amex', status: 'cancelled', ends: addMonths(recent(21), -3), until: addMonths(recent(21), -3) },
]
const specs = US ? usSpecs : inSpecs
const CURRENCY = US ? 'USD' : 'INR'

// Past rows are confirmed, except the charges a household has not reconciled yet: this month's
// electricity bill, which keeps the month part-covered.
const unconfirmed = new Set([`c-power:${recent(20)}`])

const commitments: Record<string, unknown>[] = []
const charges: Record<string, unknown>[] = []
for (const s of specs) {
  const until = s.until ?? YEAR_AHEAD
  const dates: string[] = []
  const anchor = parse(s.first).getUTCDate()
  for (let d = s.first, i = 0; d <= until && i < 400; i++) {
    dates.push(d)
    if (s.cycle === 'once') break
    d = s.cycle === 'monthly' ? addMonths(s.first, i + 1, anchor)
      : s.cycle === 'yearly' ? addMonths(s.first, 12 * (i + 1), anchor)
      : addDays(s.first, (s.every ?? 30) * (i + 1))
  }
  const amountAt = (i: number): number => (typeof s.amount === 'function' ? s.amount(i) : s.amount)
  commitments.push({
    id: s.id,
    name: s.name,
    amount: amountAt(dates.length - 1),
    currency: s.currency ?? CURRENCY,
    billing_cycle: s.cycle,
    ...(s.every ? { custom_cycle_days: s.every } : {}),
    ...(s.tag ? { tag: s.tag } : {}),
    ...(s.notes ? { notes: s.notes } : {}),
    ...(s.member ? { member_id: s.member } : {}),
    ...(s.account ? { account_id: s.account } : {}),
    status: s.status ?? 'active',
    ...(s.ends ? { ends_on: s.ends } : {}),
    ...(s.direction ? { direction: s.direction } : {}),
    created_at: `${s.first < YEAR_AGO ? s.first : YEAR_AGO}T09:00:00Z`,
  })
  dates.forEach((date, i) => {
    const past = date <= TODAY && !unconfirmed.has(`${s.id}:${date}`)
    charges.push({
      commitment_id: s.id,
      date,
      amount: amountAt(i),
      ...(s.currency ? { currency: s.currency } : {}),
      paid: past,
      ...(past ? { paid_on: date } : {}),
      basis: past ? (s.basis ?? 'statement') : 'plan',
    })
  })
}
charges.sort((a, b) => String(a.date).localeCompare(String(b.date)))

const joined = addDays(TODAY, -115)
const inMembers = [
  { id: 'm-dev', name: 'Dev', name_key: 'dev', tag: 'family', created_at: `${joined}T09:00:00Z` },
  { id: 'm-asha', name: 'Asha', name_key: 'asha', tag: 'family', created_at: `${joined}T09:00:00Z` },
  { id: 'm-kabir', name: 'Kabir', name_key: 'kabir', tag: 'family', created_at: `${joined}T09:00:00Z` },
  { id: 'm-sunita', name: 'Sunita', name_key: 'sunita', tag: 'household help', created_at: `${joined}T09:00:00Z` },
  { id: 'm-mehta', name: 'Mehta Properties', name_key: 'mehta properties', tag: 'landlord', created_at: `${joined}T09:00:00Z` },
]
const inAccounts = [
  { id: 'a-hdfc', name: 'HDFC savings', name_key: 'hdfc savings', institution: 'HDFC Bank', last4: '5521', tag: 'bank account',
    member_id: 'm-dev', balance: 284512, balance_date: addDays(TODAY, -4), created_at: `${joined}T09:00:00Z` },
  { id: 'a-axis', name: 'Axis card', name_key: 'axis card', institution: 'Axis Bank', last4: '4402', tag: 'credit card',
    member_id: 'm-dev', parent_account_id: 'a-hdfc', notes: 'Card name: Ruby Rewards', balance: -12450,
    balance_date: recent(15), created_at: `${joined}T09:00:00Z` },
  { id: 'a-icici', name: 'ICICI savings', name_key: 'icici savings', institution: 'ICICI Bank', last4: '8130', tag: 'bank account',
    member_id: 'm-asha', balance: 112400, balance_date: addDays(TODAY, -10), created_at: `${joined}T09:00:00Z` },
]
const usMembers = [
  { id: 'm-sam', name: 'Sam', name_key: 'sam', tag: 'family', created_at: `${joined}T09:00:00Z` },
  { id: 'm-maya', name: 'Maya', name_key: 'maya', tag: 'family', created_at: `${joined}T09:00:00Z` },
  { id: 'm-leo', name: 'Leo', name_key: 'leo', tag: 'family', created_at: `${joined}T09:00:00Z` },
  { id: 'm-rosa', name: 'Rosa', name_key: 'rosa', tag: 'household help', created_at: `${joined}T09:00:00Z` },
  { id: 'm-parkview', name: 'Parkview Apartments', name_key: 'parkview apartments', tag: 'landlord', created_at: `${joined}T09:00:00Z` },
]
const usAccounts = [
  { id: 'a-chase', name: 'Chase checking', name_key: 'chase checking', institution: 'Chase', last4: '5521', tag: 'bank account',
    member_id: 'm-sam', balance: 18450, balance_date: addDays(TODAY, -4), created_at: `${joined}T09:00:00Z` },
  { id: 'a-amex', name: 'Amex Gold card', name_key: 'amex gold card', institution: 'American Express', last4: '1009', tag: 'credit card',
    member_id: 'm-sam', parent_account_id: 'a-chase', balance: -781, balance_date: recent(15), created_at: `${joined}T09:00:00Z` },
  { id: 'a-ally', name: 'Ally savings', name_key: 'ally savings', institution: 'Ally Bank', last4: '8130', tag: 'bank account',
    member_id: 'm-maya', balance: 9320, balance_date: addDays(TODAY, -10), created_at: `${joined}T09:00:00Z` },
]
const members = US ? usMembers : inMembers
const accounts = US ? usAccounts : inAccounts

// The library's own entries for every tag the household wears, as setup writes them.
const library = JSON.parse(readFileSync(join(ROOT, 'packages/core/contract/library.json'), 'utf8')) as {
  tags: { kind: string; name: string; name_key: string; icon?: string; sort?: number }[]
}
const worn = new Set([
  ...commitments.map((c) => `commitment:${c.tag}`),
  ...members.map((m) => `member:${m.tag}`),
  ...accounts.map((a) => `account:${a.tag}`),
])
const tags = library.tags
  .filter((t) => worn.has(`${t.kind}:${t.name}`))
  .map((t) => ({ id: `t-${t.kind}-${t.name_key.replace(/\W+/g, '-')}`, kind: t.kind, name: t.name, name_key: t.name_key,
    icon: t.icon, is_default: true, sort: t.sort, created_at: `${joined}T09:00:00Z` }))

const vault = { app: 'longbook', version: 3, commitments, members, accounts, tags, charges }

const usInsights = [
  { module: 'dashboard.next_payment', created_at: addDays(TODAY, -2),
    text: 'Rent and Rosa\'s pay leave Chase checking within five days of the 1st, about half of the salary that arrives the same day.' },
  { module: 'dashboard.by_category', created_at: addDays(TODAY, -2),
    text: 'Rent is most of every month. Of the rest, the home, life and car insurance premiums make a few months heavier.' },
  { module: 'dashboard.by_account', created_at: addDays(TODAY, -2),
    text: 'The Amex card carries the subscriptions and the one-off spending; its bill leaves Chase checking on the 24th.' },
  { module: 'account.a-amex', created_at: addDays(TODAY, -2),
    text: 'Every subscription on this card renews between the 2nd and the 18th, so each month\'s bill on the 24th holds them all.' },
  { module: 'member.m-maya', created_at: addDays(TODAY, -2),
    text: 'Peloton and the car insurance both leave Ally savings; everything else of Maya\'s is on the Amex card.' },
]
const insights = {
  version: 1,
  insights: US ? usInsights : [
    { module: 'dashboard.next_payment', created_at: addDays(TODAY, -2),
      text: 'Rent and Sunita\'s pay leave HDFC savings within five days of the 1st, a little under a third of the salary that arrives the same day.' },
    { module: 'dashboard.by_category', created_at: addDays(TODAY, -2),
      text: 'Rent is most of every month. Of the rest, the three insurance premiums fall in November, January and March, so those months run heavier.' },
    { module: 'dashboard.by_account', created_at: addDays(TODAY, -2),
      text: 'The Axis card carries the subscriptions and the one-off spending; its bill leaves HDFC savings on the 24th.' },
    { module: 'account.a-axis', created_at: addDays(TODAY, -2),
      text: 'Every subscription on this card renews between the 2nd and the 18th, so each month\'s bill on the 24th holds them all.' },
    { module: 'member.m-asha', created_at: addDays(TODAY, -2),
      text: 'The gym and Star Health both leave ICICI savings; everything else of Asha\'s is on the Axis card.' },
  ],
}

// The household's own currency; the workspace names it so no view has to guess.
const workspace = { homeCurrency: CURRENCY, commitmentsAsked: true }

mkdirSync(folder, { recursive: true })
writeFileSync(join(folder, 'financial_memory.json'), `${JSON.stringify(vault, null, 2)}\n`)
writeFileSync(join(folder, 'insights.json'), `${JSON.stringify(insights, null, 2)}\n`)
writeFileSync(join(folder, 'longbook.workspace.json'), `${JSON.stringify(workspace, null, 2)}\n`)
writeFileSync(join(folder, '.demo-vault'), 'Written by scripts/demo-vault.mts. Every name and amount is made up.\n')
console.log(`demo vault for ${TODAY}: ${commitments.length} commitments, ${charges.length} charges, ${members.length} members, ${accounts.length} accounts → ${folder}`)
