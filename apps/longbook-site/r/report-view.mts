// What the shared-report viewer says about a report, with no page in sight: the days, the
// scope, money, shares, the total's words, the charge split and the inks. The app's own
// rules (ReportDetailView.swift, Report.swift, Selectors.swift fmtMoney), copied so a link reads
// like the report screen.

export type Json = Record<string, unknown>

export const TITLE_CATEGORIES = 'Categories'
export const TITLE_CHARGES = 'All charges'
export const TITLE_REMOVED = 'Removed from this report'
export const NO_CATEGORY = 'No category'
// The fraction of a turn shaved off each arc, and offset by half of it. Keep it equal to the
// trim in the app's LBDonut or the two rings stop matching.
export const RING_GAP = 0.004
// How many identity inks tokens.css carries (--lb-data-0 to --lb-data-11).
export const RAMP_SIZE = 12

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December']
const MONTHS_SHORT = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

export const isObject = (value: unknown): value is Json =>
  typeof value === 'object' && value !== null && !Array.isArray(value)
const text = (value: unknown): string | undefined => (typeof value === 'string' ? value : undefined)
const finite = (value: unknown): number | undefined =>
  typeof value === 'number' && Number.isFinite(value) ? value : undefined
const objects = (value: unknown): Json[] => (Array.isArray(value) ? value.filter(isObject) : [])
const strings = (value: unknown): string[] =>
  Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : []

export const modulesOf = (report: Json): unknown[] => (Array.isArray(report.modules) ? report.modules : [])

// ---- days ------------------------------------------------------------------------------

// A calendar day, never a moment: "2026-08-01" read as UTC falls back a day west of
// Greenwich, so the parts build a local date. An invented day (31 February) is no day.
export function parseDay(value: unknown): Date | null {
  const parts = /^(\d{4})-(\d{2})-(\d{2})/.exec(text(value) ?? '')
  if (!parts) return null
  const [y, m, d] = [Number(parts[1]), Number(parts[2]), Number(parts[3])]
  const date = new Date(y, m - 1, d)
  return date.getFullYear() === y && date.getMonth() === m - 1 && date.getDate() === d ? date : null
}

const sameDay = (a: Date, b: Date): boolean =>
  a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
const isoMonth = (d: Date): string => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`

/** "7 August 2026". */
export const longDay = (d: Date): string => `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`
/** "7 Aug", the charge row's date. */
export const shortDay = (d: Date): string => `${d.getDate()} ${MONTHS_SHORT[d.getMonth()]}`

function monthKey(value: unknown): string | null {
  const key = text(value)
  return key && /^\d{4}-\d{2}$/.test(key) && parseDay(`${key}-01`) ? key : null
}

/** The month covered: a well-formed `period`, else the one month every dated charge row falls in. */
export function periodKey(report: Json): string | null {
  const stated = monthKey(report.period)
  if (stated) return stated
  const months = new Set<string>()
  for (const mod of modulesOf(report)) {
    if (!isObject(mod) || mod.type !== 'transactions') continue
    for (const row of objects(mod.rows)) {
      const day = parseDay(row.date)
      if (day) months.add(isoMonth(day))
    }
  }
  return months.size === 1 ? [...months][0] ?? null : null
}

/** The file's own first and last day, else the days of its month. */
export function reportRange(report: Json): { start: Date; end: Date } | null {
  const start = parseDay(report.start_date)
  const end = parseDay(report.end_date)
  if (start && end && start.getTime() <= end.getTime()) return { start, end }
  const key = periodKey(report)
  const first = key ? parseDay(`${key}-01`) : null
  if (!first) return null
  return { start: first, end: new Date(first.getFullYear(), first.getMonth() + 1, 0) }
}

/** "1 October 2026", "1–31 August 2026", "28 September – 3 October 2026", across years with both. */
export function rangeName(report: Json): string | null {
  const range = reportRange(report)
  if (!range) return null
  const { start, end } = range
  if (sameDay(start, end)) return longDay(start)
  const sameYear = start.getFullYear() === end.getFullYear()
  if (sameYear && start.getMonth() === end.getMonth()) {
    return `${start.getDate()}–${end.getDate()} ${MONTHS[start.getMonth()]} ${start.getFullYear()}`
  }
  if (sameYear) return `${start.getDate()} ${MONTHS[start.getMonth()]} – ${longDay(end)}`
  return `${longDay(start)} – ${longDay(end)}`
}

/** Said where no days settle: when the file was written, named as that. */
export function writtenNote(report: Json): string | null {
  const day = parseDay(report.created_at)
  return day ? `Written ${longDay(day)}` : null
}

/** "Accounts: HDFC, Cash · Members: Rohit", or nothing when the report covers everything. */
export function scopeLine(report: Json): string | null {
  const scope = report.scope
  if (!isObject(scope)) return null
  const parts = ([['Accounts', 'accounts'], ['Members', 'members'], ['Categories', 'categories']] as const)
    .map(([word, key]) => [word, key === 'categories' ? strings(scope[key]).map(categoryWord) : strings(scope[key])] as const)
    .filter(([, names]) => names.length > 0)
    .map(([word, names]) => `${word}: ${names.join(', ')}`)
  return parts.length ? parts.join(' · ') : null
}

/** "This link expires 4 Oct, 14:30", in the viewer's own time. */
export function expiryNote(expiresAt: unknown): string | null {
  const at = Date.parse(text(expiresAt) ?? '')
  if (!Number.isFinite(at)) return null
  const d = new Date(at)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `This link expires ${shortDay(d)}, ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

/** A comment's date line: "Asha · 4 Oct", or "Someone" when no name was given. */
export function commentMeta(comment: Json): string {
  const who = text(comment.author) || 'Someone'
  const at = Date.parse(text(comment.created_at) ?? '')
  return Number.isFinite(at) ? `${who} · ${shortDay(new Date(at))}` : who
}

// ---- money and words -------------------------------------------------------------------

const NO_DECIMALS = new Set(['INR', 'JPY'])
const LOCALES = new Map([
  ['INR', 'en-IN'], ['USD', 'en-US'], ['EUR', 'de-DE'], ['GBP', 'en-GB'], ['AED', 'ar-AE'],
  ['SGD', 'en-SG'], ['AUD', 'en-AU'], ['CAD', 'en-CA'], ['JPY', 'ja-JP'],
])

/** fmtMoney's twin: each currency in its own country's style; no cents on INR, JPY or a whole amount. */
export function money(amount: number, currency: string): string {
  if (!currency) return new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(amount)
  const digits = NO_DECIMALS.has(currency) || amount === Math.round(amount) ? 0 : 2
  try {
    return new Intl.NumberFormat(LOCALES.get(currency), {
      style: 'currency', currency, minimumFractionDigits: digits, maximumFractionDigits: digits,
    }).format(amount)
  } catch {
    return `${currency} ${amount}`
  }
}

/** An item's money in its own currency (else the fallback), else its free text. */
export function moneyOf(item: Json, fallbackCurrency = ''): string {
  const amount = finite(item.amount)
  if (amount !== undefined) return money(amount, text(item.currency) || fallbackCurrency)
  if (typeof item.value === 'string' || typeof item.value === 'number') return String(item.value)
  return ''
}

/** "62%" from a tenth up; "4.5%" below it. */
export function sharePct(share: number): string {
  const percent = share * 100
  return percent >= 10 ? `${Math.round(percent)}%` : `${(Math.round(percent * 10) / 10).toFixed(1)}%`
}

function firstCharacter(word: string): string {
  const code = word.codePointAt(0)
  return code === undefined ? '' : String.fromCodePoint(code)
}

// A tag as a screen shows it: the first letter up, the rest as written. Only a category: an
// account's name and a charge's name are the owner's own typing.
export function categoryWord(name: unknown): string {
  const word = name === undefined || name === null ? '' : String(name)
  const first = firstCharacter(word)
  return first.toUpperCase() + word.slice(first.length)
}

const lowerFirst = (word: string): string => {
  const first = firstCharacter(word)
  return first.toLowerCase() + word.slice(first.length)
}

// ---- the total -------------------------------------------------------------------------

const isMoneyStat = (stat: Json): boolean => finite(stat.amount) !== undefined && typeof stat.currency === 'string'

// One decimal as the app's String(format: "%.1f") prints it. The only exact halves a double
// holds at one decimal are x.25 and x.75; those go to the even digit, where toFixed rounds up.
function oneDecimal(x: number): string {
  if (Number.isInteger(x * 4) && !Number.isInteger(x * 2)) {
    const tenths = Math.floor(x * 10)
    return ((tenths % 2 === 0 ? tenths : tenths + 1) / 10).toFixed(1)
  }
  return x.toFixed(1)
}

/** "3 charges", "1 not yet confirmed", "Money in ₹1,50,000": a count wears its label after it. */
export function statWords(stat: Json): string {
  const label = text(stat.label) ?? ''
  if (isMoneyStat(stat)) return `${label} ${moneyOf(stat)}`.trim()
  if (typeof stat.value === 'string' || typeof stat.value === 'number') {
    return `${stat.value} ${lowerFirst(label)}`.trim()
  }
  return label
}

export interface StatsView {
  /** The first money stat, drawn large; its own label is left to the section heading. */
  lead: string | null
  /** The other money stats under the lead's label, "+$20 +€5". */
  companions: string | null
  delta: { text: string; good: boolean } | null
  /** Every other stat on one line. */
  line: string
}

export function statsView(mod: Json): StatsView {
  const stats = objects(mod.stats)
  const leadIndex = stats.findIndex(isMoneyStat)
  const lead = leadIndex >= 0 ? stats[leadIndex] : undefined
  const companion = (stat: Json, index: number): boolean =>
    lead !== undefined && index !== leadIndex && isMoneyStat(stat) && stat.label === lead.label
  const companions = stats.filter(companion).map((stat) => moneyOf(stat))
  const rest = stats.filter((stat, index) => index !== leadIndex && !companion(stat, index))
  const deltaPct = lead ? finite(lead.delta_pct) : undefined
  const deltaLabel = lead ? text(lead.delta_label) : undefined
  return {
    lead: lead ? moneyOf(lead) : null,
    companions: companions.length ? `+${companions.join(' +')}` : null,
    delta: lead && deltaPct !== undefined
      ? {
          text: `${deltaPct >= 0 ? '▲' : '▼'} ${oneDecimal(Math.abs(deltaPct))}%${deltaLabel ? ` ${deltaLabel}` : ''}`,
          good: lead.delta_is_good === true,
        }
      : null,
    line: rest.map(statWords).filter(Boolean).join(' · '),
  }
}

// ---- rings and tiles -------------------------------------------------------------------

/**
 * What a slice gives the ring: a real, positive number, or nothing. A negative, a text
 * amount and a blank keep their row and their ink and take no share. One rule for the
 * total, the arcs and the shares, so no two of them disagree.
 */
export function ringValue(slice: Json): number {
  const amount = finite(slice.amount)
  return amount !== undefined && amount > 0 ? amount : 0
}

export interface SliceRow { label: string; amountText: string; share: string | null; rank: number | null }
export interface DonutView {
  scope: string
  total: number
  /** Slices in the ring's currency, in file order; rank is their ink. */
  scoped: SliceRow[]
  /** Slices in any other currency: listed with their own sum, no share, no ink. */
  foreign: SliceRow[]
  centre: { title: string; note: string }
  /** Each arc as fractions of a turn, from twelve o'clock. */
  arcs: { rank: number; length: number; offset: number }[]
}

/** A ring is one currency; a slice in any other is listed beside it and never enters it. */
export function donutView(mod: Json, reportCurrency = ''): DonutView {
  const slices = objects(mod.slices)
  const scope = text(mod.currency) || reportCurrency || text(slices[0]?.currency) || ''
  const scoped = slices.filter((slice) => slice.currency === scope)
  const foreign = slices.filter((slice) => slice.currency !== scope)
  const total = scoped.reduce((sum, slice) => sum + ringValue(slice), 0)
  const shareOf = (slice: Json): number | null =>
    total > 0 && ringValue(slice) > 0 ? ringValue(slice) / total : null
  const row = (slice: Json, rank: number | null): SliceRow => {
    const share = rank === null ? null : shareOf(slice)
    return {
      label: text(slice.label) ?? '', amountText: moneyOf(slice, scope),
      share: share === null ? null : sharePct(share), rank,
    }
  }
  const arcs: DonutView['arcs'] = []
  let at = 0
  scoped.forEach((slice, rank) => {
    // Clamped to what is left of the turn: a dash longer than the circle comes out negative
    // and a browser drops the attribute, closing the ring over everything.
    const span = total > 0 ? Math.min(ringValue(slice) / total, 1 - at) : 0
    if (!(span > 0)) return
    const from = at
    at += span
    const length = Math.max(span - RING_GAP, 0)
    if (length > 0) arcs.push({ rank, length, offset: from + RING_GAP / 2 })
  })
  const top = scoped[0]
  const topShare = top ? shareOf(top) : null
  return {
    scope, total,
    scoped: scoped.map((slice, rank) => row(slice, rank)),
    foreign: foreign.map((slice) => row(slice, null)),
    centre: {
      title: topShare === null ? '—' : sharePct(topShare),
      note: top ? `From ${text(top.label) ?? ''}` : 'Nothing yet',
    },
    arcs,
  }
}

/** An ink by rank as a CSS value; a rank past the ramp, or none, folds to the neutral. */
export function inkVar(rank: number | null): string {
  return rank !== null && rank >= 0 && rank < RAMP_SIZE ? `var(--lb-data-${rank})` : 'var(--lb-neutral-fold)'
}

// ---- charges ---------------------------------------------------------------------------

/** A row's category as the app compares it: trimmed, empty when it has none. */
export const rowCategory = (row: Json): string => (text(row.category) ?? '').trim()

/** The object rows a list holds, less any the owner dropped for good (`hidden_ids`). */
export function listedRows(report: Json, mod: Json): Json[] {
  const hidden = new Set(strings(report.hidden_ids))
  return objects(mod.rows).filter((row) => !(typeof row.id === 'string' && hidden.has(row.id)))
}

/** The charges the report counts, and the ones taken out of it, each in file order. */
export function chargeSplit(report: Json, mod: Json): { kept: Json[]; removed: Json[] } {
  const rows = listedRows(report, mod)
  return { kept: rows.filter((row) => row.removed !== true), removed: rows.filter((row) => row.removed === true) }
}

/** Each category's place in the Categories donut, so a row and its tile wear one ink. */
export function categoryRanks(report: Json): Map<string, number> {
  const rank = new Map<string, number>()
  for (const mod of modulesOf(report)) {
    if (!isObject(mod) || mod.type !== 'donut' || mod.title !== TITLE_CATEGORIES) continue
    objects(mod.slices).forEach((slice, index) => {
      const label = text(slice.label)
      if (label !== undefined && !rank.has(label)) rank.set(label, index)
    })
  }
  return rank
}

/** A row's ink rank: its category's place in the donut, the no-category slice for none. */
export function rowInkRank(row: Json, ranks: Map<string, number>): number | null {
  const category = rowCategory(row)
  return ranks.get(category || NO_CATEGORY) ?? null
}

export interface RowFact { kind: 'date' | 'category' | 'member' | 'account'; text: string }

/** The line under a charge's name: its day, category, member and account. */
export function rowFacts(row: Json): RowFact[] {
  const facts: RowFact[] = []
  const day = parseDay(row.date)
  if (day) facts.push({ kind: 'date', text: shortDay(day) })
  const category = rowCategory(row)
  facts.push({ kind: 'category', text: category ? categoryWord(category) : NO_CATEGORY })
  const member = text(row.member)
  if (member) facts.push({ kind: 'member', text: member })
  const account = text(row.account)
  if (account) facts.push({ kind: 'account', text: account })
  return facts
}

export const rowName = (row: Json): string => text(row.name) ?? text(row.label) ?? ''

export interface Narrowing {
  search: string
  category: string | null
  account: string | null
  member: string | null
  currency: string | null
}

export const emptyNarrowing = (): Narrowing => ({ search: '', category: null, account: null, member: null, currency: null })
export const isNarrowed = (n: Narrowing): boolean =>
  n.category !== null || n.account !== null || n.member !== null || n.currency !== null

function names(values: unknown[]): string[] {
  const out: string[] = []
  for (const value of values) if (typeof value === 'string' && value && !out.includes(value)) out.push(value)
  return out
}

/** The choices the rows can answer, as [value, label]; each is offered only with two or more. */
export function filterOptions(rows: Json[]): {
  categories: [string, string][]; accounts: string[]; members: string[]; currencies: string[]
} {
  const named: string[] = []
  let bare = false
  for (const row of rows) {
    const category = rowCategory(row)
    if (!category) bare = true
    else if (!named.includes(category)) named.push(category)
  }
  const categories: [string, string][] = named.map((name) => [name, categoryWord(name)])
  if (bare) categories.push([NO_CATEGORY, NO_CATEGORY])
  return {
    categories,
    accounts: names(rows.map((row) => row.account)),
    members: names(rows.map((row) => row.member)),
    currencies: [...new Set(rows.map((row) => text(row.currency) ?? ''))].filter(Boolean).sort(),
  }
}

/** The rows a search and the chosen facts leave, in the order the file wrote them. */
export function narrow(rows: Json[], n: Narrowing): Json[] {
  const needle = n.search.trim().toLowerCase()
  return rows.filter((row) => {
    const category = rowCategory(row)
    if (n.category !== null && category !== (n.category === NO_CATEGORY ? '' : n.category)) return false
    if (n.account !== null && row.account !== n.account) return false
    if (n.member !== null && row.member !== n.member) return false
    if (n.currency !== null && (text(row.currency) ?? '') !== n.currency) return false
    if (!needle) return true
    const haystack = `${rowName(row)} ${category} ${text(row.account) ?? ''} ${text(row.member) ?? ''}`
    return haystack.toLowerCase().includes(needle)
  })
}

// ---- modules and the page --------------------------------------------------------------

/**
 * The key a viewer's comment is stored under: the module's own id, else `module-<index>` by
 * its place in report.modules. The app merges comments back by exactly this key, so it
 * must never change.
 */
export function moduleKey(mod: unknown, index: number): string {
  return isObject(mod) && typeof mod.id === 'string' && mod.id ? mod.id : `module-${index}`
}

/** A heading for a module this viewer draws generically: its title, else its type in words. */
export function genericHeading(mod: Json): string | null {
  const title = text(mod.title)
  if (title) return title
  const type = text(mod.type)
  return type ? type.replace(/_/g, ' ') : null
}

/** One JSON value as reading text: Yes and No, a dash for nothing, objects as "key value". */
export function genericWord(value: unknown): string {
  if (typeof value === 'string') return value
  if (typeof value === 'number') return String(value)
  if (typeof value === 'boolean') return value ? 'Yes' : 'No'
  if (value === null || value === undefined) return '—'
  if (Array.isArray(value)) return value.map(genericWord).join(', ')
  if (isObject(value)) {
    return Object.keys(value).sort()
      .map((key) => `${key.replace(/_/g, ' ')} ${genericWord(value[key])}`)
      .join(' · ')
  }
  return String(value)
}

/** The share id: the last part of /r/<id>. A bare /r/ names none. */
export function shareIdFrom(pathname: string): string | null {
  const last = pathname.split('/').filter(Boolean).pop()
  return last && last !== 'r' ? last : null
}

/** What a refusal means to the person reading, by the server's status, never its own words. */
export function errorWords(status: number, action: 'view' | 'comment'): string {
  if (status === 404) return 'No report is shared at this link. It may have ended.'
  if (status === 410) return 'This link has expired.'
  if (status === 403) return 'That password is not right. Check it and try again.'
  if (status === 400) {
    return action === 'comment'
      ? 'The comment could not be sent. Keep it to 2,000 characters, and a name to 80.'
      : 'This link could not be opened. Check the address and try again.'
  }
  if (status === 0) return 'The report could not be reached. Check the connection and try again.'
  return 'Something went wrong. Try again in a moment.'
}
