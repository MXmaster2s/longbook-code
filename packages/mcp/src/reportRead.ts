// The reports folder, LOCAL ONLY like every tool that touches the disk: one tool lists
// the reports the app drew into <vault>/reports and returns one report's modules with the
// comments left on them. Reading only — reports are drawn by the app, never written here.
import { readFileSync, readdirSync, realpathSync, statSync } from 'node:fs'
import { join, sep } from 'node:path'
import { parseDate, toISO } from '@longbook/core'

export const REPORTS_SPEC = {
  title: 'Read reports',
  description:
    `The reports in the vault's reports/ folder, drawn by longbook from the confirmed charges ` +
    `it holds: those dated today or earlier whose basis is anything but "plan". A report may ` +
    `cover any span of days — longbook draws every calendar month on its own; a trip is one ` +
    `whose id starts "trip-"; a span asked for with create_report starts "report-" — and may ` +
    `be narrowed to accounts, members and categories (scope; absent means all). A report still holding ` +
    `unconfirmed passed charges in its currency says so in its own figures — a "Not yet ` +
    `confirmed" stat counts them beside "Total expenses" — so read the total as the part ` +
    `longbook can account for, never as the span's spending. delta_pct is absent whenever no ` +
    `change can honestly be drawn: the month is not over, either month is part-covered, or the ` +
    `month before holds no confirmed spending in this currency. Read its absence as "longbook ` +
    `would not say", never as a month of no spending, and never compute the change from two ` +
    `reports. Without an id it lists them, newest first by the last day each covers: the ` +
    `title, start_date and end_date, the scope, the month when it is one, the day the file was written, how many ` +
    `modules it holds and how many ` +
    `comments sit on them, and the share link when one is live. With an id it returns that ` +
    `report whole — every module exactly as the app draws it, each with its own comments. ` +
    `A module carries "Total expenses", "Accounts", "Categories" and "All charges"; an older ` +
    `file may hold other kinds, and they are returned as they are. A file the app's own ` +
    `decoder would refuse is counted in unreadable, never listed as a report — what this ` +
    `lists is what the Reports screen shows. Comments are the owner's and their viewers' own ` +
    `words: quote them, never rewrite them. An id that matches more than one report answers ` +
    `with the matches, not with a guess. Reports are files, so this reads only on the ` +
    `owner's own machine.`,
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
}

export const REPORTS_DIR = 'reports'
const WORKSPACE_FILE = 'longbook.workspace.json'
const MONTH = /^\d{4}-(0[1-9]|1[0-2])$/
/** The same ceiling the documents reader holds: a listing must not load a vault into memory. */
const MAX_BYTES = 25 * 1024 * 1024

const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v)

const str = (v: unknown): string | null => (typeof v === 'string' && v.trim() ? v : null)

// What a Swift `String?`, `Double?` and `Bool?` accept: the key absent, JSON null, or that
// type. A value of any other type throws there, so it must fail here too.
const optText = (v: unknown): boolean => v === undefined || v === null || typeof v === 'string'
const optNumber = (v: unknown): boolean => v === undefined || v === null || (typeof v === 'number' && Number.isFinite(v))
const optBool = (v: unknown): boolean => v === undefined || v === null || typeof v === 'boolean'
const num = (v: unknown): boolean => typeof v === 'number' && Number.isFinite(v)

/** A file is a report when it carries modules, or an id with a title — the app's own test. */
function isReportShaped(object: Record<string, unknown>): boolean {
  if ('modules' in object) return true
  return 'id' in object && 'title' in object
}

const KNOWN_TYPES = ['stats', 'prose', 'donut', 'bars', 'transactions']

// What a Swift `[String]?` accepts: the key absent, JSON null, or a list of strings.
const optTexts = (v: unknown): boolean =>
  v === undefined || v === null || (Array.isArray(v) && v.every((item) => typeof item === 'string'))

/** ReportScope decodes each list with decodeIfPresent, so a list may be absent or null. */
const decodesAsScope = (s: unknown): boolean =>
  s === undefined || s === null ||
  (isRecord(s) && optTexts(s.accounts) && optTexts(s.members) && optTexts(s.categories))

const decodesAsStat = (s: unknown): boolean =>
  isRecord(s) && typeof s.label === 'string' && optNumber(s.amount) && optText(s.currency) &&
  optText(s.value) && optNumber(s.delta_pct) && optBool(s.delta_is_good) && optText(s.delta_label)

const decodesAsSlice = (s: unknown): boolean =>
  isRecord(s) && typeof s.label === 'string' && num(s.amount) && typeof s.currency === 'string'

const decodesAsBar = (b: unknown): boolean =>
  isRecord(b) && typeof b.label === 'string' && num(b.amount)

const decodesAsRow = (r: unknown): boolean =>
  isRecord(r) && typeof r.name === 'string' && num(r.amount) && typeof r.currency === 'string' &&
  optText(r.date) && optText(r.category) && optText(r.id) && optText(r.account) &&
  optText(r.member) && optBool(r.removed)

function decodesAsModule(mod: unknown): boolean {
  if (!isRecord(mod)) return false
  // `type` is read before the branch, so a module without one fails the whole file.
  if (typeof mod.type !== 'string') return false
  // A type this version does not know rides along as raw values; nothing can refuse it.
  if (!KNOWN_TYPES.includes(mod.type)) return true
  for (const key of ['id', 'title', 'comment']) if (!optText(mod[key])) return false
  switch (mod.type) {
    case 'stats':
      return Array.isArray(mod.stats) && mod.stats.every(decodesAsStat)
    case 'prose':
      return typeof mod.text === 'string'
    case 'donut':
      return optText(mod.currency) && Array.isArray(mod.slices) && mod.slices.every(decodesAsSlice)
    case 'bars':
      return optText(mod.currency) && Array.isArray(mod.bars) && mod.bars.every(decodesAsBar)
    default:
      return Array.isArray(mod.rows) && mod.rows.every(decodesAsRow)
  }
}

/**
 * Whether the app's own decoder would accept this file. Report.swift's types are the
 * contract: a missing required field, or an optional one of the wrong type, throws there,
 * and a file that throws is one the Reports screen does not show.
 */
export function decodesAsReport(report: Record<string, unknown>): boolean {
  if (!Number.isInteger(report.version)) return false
  if (typeof report.id !== 'string' || typeof report.title !== 'string') return false
  for (const key of ['subtitle', 'created_at', 'period', 'start_date', 'end_date', 'currency']) {
    if (!optText(report[key])) return false
  }
  if (!decodesAsScope(report.scope) || !optTexts(report.hidden_ids)) return false
  if (!Array.isArray(report.modules)) return false
  return report.modules.every(decodesAsModule)
}

/**
 * The month covered: `period` when it names a real month, else the single month every
 * dated transaction row falls in. Null when neither settles it — an invented month is a
 * claim the report never made.
 */
export function periodKeyOf(report: Record<string, unknown>): string | null {
  const stated = str(report.period)
  if (stated && MONTH.test(stated) && toISO(parseDate(stated + '-01')) === stated + '-01') return stated
  const months = new Set<string>()
  for (const mod of Array.isArray(report.modules) ? report.modules : []) {
    if (!isRecord(mod) || mod.type !== 'transactions' || !Array.isArray(mod.rows)) continue
    for (const row of mod.rows) {
      const day = isRecord(row) ? str(row.date) : null
      if (day && toISO(parseDate(day)) === day) months.add(day.slice(0, 7))
    }
  }
  return months.size === 1 ? [...months][0]! : null
}

/** A real ISO day, as the vault's own day parser reads one; null for anything else. */
const realDay = (v: unknown): string | null =>
  typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v) && toISO(parseDate(v)) === v ? v : null

/**
 * The days covered, as Report.swift's `range` works them out: the file's own start_date and
 * end_date when both are real and in order, else the whole month periodKeyOf settles on. Null
 * when neither does — such a report lists last.
 */
export function coveredDays(report: Record<string, unknown>): { start: string; end: string } | null {
  const start = realDay(report.start_date)
  const end = realDay(report.end_date)
  if (start && end && start <= end) return { start, end }
  const month = periodKeyOf(report)
  if (!month) return null
  const first = parseDate(month + '-01')
  return { start: month + '-01', end: toISO(new Date(first.getFullYear(), first.getMonth() + 1, 0)) }
}

/** The calendar month a listing names: the stated period, else the rows' month for a file naming no days. */
function monthOf(report: Record<string, unknown>): string | null {
  const stated = periodKeyOf({ period: report.period })
  if (stated) return stated
  return realDay(report.start_date) || realDay(report.end_date) ? null : periodKeyOf(report)
}

/** The scope a report was narrowed to, every list present; null when it narrows nothing. */
function scopeOf(report: Record<string, unknown>): Record<string, string[]> | null {
  const scope = isRecord(report.scope) ? report.scope : {}
  const list = (v: unknown): string[] => (Array.isArray(v) ? v.filter((s): s is string => typeof s === 'string') : [])
  const out = { accounts: list(scope.accounts), members: list(scope.members), categories: list(scope.categories) }
  return out.accounts.length || out.members.length || out.categories.length ? out : null
}

interface Found {
  file: string
  month: string
  /** The last day covered, or '' when no day is known. */
  last: string
  created: string
  report: Record<string, unknown>
}

interface Folder {
  found: Found[]
  /** Report-shaped files the app's decoder refuses — the app's own count, same rule. */
  unreadable: number
  too_large: number
  outside_folder: number
}

/** Every readable report, newest last covered day first; ties break on created_at, then filename. */
function readFolder(vaultDir: string): Folder {
  const out: Folder = { found: [], unreadable: 0, too_large: 0, outside_folder: 0 }
  let root: string
  let names: string[]
  try {
    root = realpathSync(join(vaultDir, REPORTS_DIR))
    names = readdirSync(root)
  } catch {
    return out
  }
  for (const name of names.sort()) {
    if (!name.endsWith('.json') || name.startsWith('.')) continue
    // A symlink out of the folder is not a report in this vault, whatever it points at.
    let real: string
    try {
      real = realpathSync(join(root, name))
    } catch {
      continue
    }
    if (real !== root && !real.startsWith(root + sep)) {
      out.outside_folder += 1
      continue
    }
    let size: number
    try {
      const stat = statSync(real)
      if (!stat.isFile()) continue
      size = stat.size
    } catch {
      continue
    }
    if (size > MAX_BYTES) {
      out.too_large += 1
      continue
    }
    let parsed: unknown
    try {
      parsed = JSON.parse(readFileSync(real, 'utf8'))
    } catch {
      // Bytes that are not JSON at all are no report, and the app passes them without a word.
      continue
    }
    // A copy of the ledger parked in the folder is a different file, not a broken report.
    if (!isRecord(parsed) || !isReportShaped(parsed)) continue
    if (!decodesAsReport(parsed)) {
      out.unreadable += 1
      continue
    }
    out.found.push({
      file: `${REPORTS_DIR}/${name}`,
      month: monthOf(parsed) ?? '',
      last: coveredDays(parsed)?.end ?? '',
      created: str(parsed.created_at) ?? '',
      report: parsed,
    })
  }
  // The Reports screen's order: newest last covered day, then newest file, then the name;
  // a report covering no known day sorts as '' and so lists last.
  out.found.sort((a, b) => {
    if (a.last !== b.last) return a.last < b.last ? 1 : -1
    if (a.created !== b.created) return a.created < b.created ? 1 : -1
    return a.file < b.file ? -1 : 1
  })
  return out
}

/** What the sidecar remembers about live shares, by report id. */
function sharesOf(vaultDir: string): Record<string, Record<string, unknown>> {
  let object: unknown
  try {
    object = JSON.parse(readFileSync(join(vaultDir, WORKSPACE_FILE), 'utf8'))
  } catch {
    return {}
  }
  if (!isRecord(object)) return {}
  const live = isRecord(object.reportShares) ? object.reportShares : {}
  const kept = isRecord(object.reportShareDetails) ? object.reportShareDetails : {}
  const out: Record<string, Record<string, unknown>> = {}
  for (const [reportId, shareId] of Object.entries(live)) {
    if (typeof shareId !== 'string' || !shareId.trim()) continue
    const details = isRecord(kept[reportId]) ? (kept[reportId] as Record<string, unknown>) : {}
    out[reportId] = {
      url: str(details.url) ?? `https://longbook.app/r/${shareId}`,
      shared_on: str(details.shared_on),
      expires_at: str(details.expires_at),
      with: str(details.with),
    }
  }
  return out
}

/** The viewer's key for a module the file left unnamed — the same one comments carry. */
const moduleKey = (mod: Record<string, unknown>, index: number): string => str(mod.id) ?? `module-${index}`

/** Each comment line on a module, as the owner and their viewers left them. */
const linesOf = (mod: Record<string, unknown>): string[] =>
  (str(mod.comment) ?? '').split('\n').map((line) => line.trim()).filter(Boolean)

function modulesOf(report: Record<string, unknown>): Record<string, unknown>[] {
  return (Array.isArray(report.modules) ? report.modules : []).filter(isRecord)
}

function summary(entry: Found, shares: Record<string, Record<string, unknown>>) {
  const modules = modulesOf(entry.report)
  const id = str(entry.report.id) ?? ''
  const days = coveredDays(entry.report)
  return {
    id,
    title: str(entry.report.title),
    subtitle: str(entry.report.subtitle),
    start_date: days?.start ?? null,
    end_date: days?.end ?? null,
    scope: scopeOf(entry.report),
    month: entry.month || null,
    created_at: entry.created || null,
    currency: str(entry.report.currency),
    file: entry.file,
    // The app redraws its own reports — months, trips and requested spans; never another file.
    drawn_by_longbook: str(entry.report.subtitle) === 'Drawn by longbook',
    module_count: modules.length,
    module_titles: modules.map((m) => str(m.title) ?? String(m.type ?? '')),
    comments: modules.reduce((sum, m) => sum + linesOf(m).length, 0),
    shared: shares[id] ?? null,
  }
}

/** The counts a listing carries beside its reports, and the line that explains a non-zero one. */
function skipNote(folder: Folder): Record<string, unknown> {
  const parts: string[] = []
  if (folder.unreadable > 0) parts.push(`${folder.unreadable} file(s) the app cannot draw`)
  if (folder.too_large > 0) parts.push(`${folder.too_large} file(s) past 25 MB`)
  if (folder.outside_folder > 0) parts.push(`${folder.outside_folder} link(s) pointing outside the folder`)
  return {
    unreadable: folder.unreadable,
    too_large: folder.too_large,
    outside_folder: folder.outside_folder,
    ...(parts.length ? { skipped_note: `Not listed: ${parts.join(', ')}.` } : {}),
  }
}

export interface ReportsInput {
  id?: string
}

export function reports(vaultDir: string, input: ReportsInput = {}): unknown {
  const folder = readFolder(vaultDir)
  const found = folder.found
  const shares = sharesOf(vaultDir)
  const asked = (input.id ?? '').trim()

  if (!asked) {
    if (found.length === 0) {
      return {
        folder: `${REPORTS_DIR}/`,
        reports: [],
        ...skipNote(folder),
        note:
          `No reports yet. longbook draws one for every month holding a confirmed charge — ` +
          `one dated today or earlier whose basis is anything but "plan" — and for any span ` +
          `asked for with create_report. Open the Reports screen in the app once such charges are in.`,
      }
    }
    return {
      folder: `${REPORTS_DIR}/`,
      count: found.length,
      ...skipNote(folder),
      note: 'Newest first, by the last day each covers. Pass id to read one report whole, with its comments.',
      reports: found.map((entry) => summary(entry, shares)),
    }
  }

  const key = asked.toLowerCase()
  const exact = found.filter((entry) => str(entry.report.id) === asked)
  const matches = exact.length
    ? exact
    : found.filter(
        (entry) =>
          (str(entry.report.id) ?? '').toLowerCase() === key ||
          entry.month === asked ||
          (str(entry.report.title) ?? '').toLowerCase() === key,
      )
  if (matches.length === 0) {
    return { message: `No report called "${asked}". Call reports with no id to see what is there.` }
  }
  // A key two reports answer to is never answered with the first one.
  if (matches.length > 1) {
    return {
      message: `"${asked}" matches more than one report — pass one of these ids.`,
      ambiguous: matches.map((entry) => summary(entry, shares)),
    }
  }

  const entry = matches[0]!
  const modules = modulesOf(entry.report)
  return {
    ...summary(entry, shares),
    modules: modules.map((mod, index) => {
      const rest: Record<string, unknown> = { ...mod }
      delete rest.comment
      return { module_id: moduleKey(mod, index), ...rest, comments: linesOf(mod) }
    }),
    note:
      `Every module as the app draws it. comments are the owner's own notes and the lines ` +
      `pulled back from a shared link — their words, quoted as they stand. The data behind it ` +
      `is edited with the charge and commitment tools; the app draws the report again from it.`,
  }
}
