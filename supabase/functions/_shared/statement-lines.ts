// A statement the device read, asked of the model as numbered lines: what a head, a batch
// and a look-over carry, checked before anything is spent, and the rows that come back.
// Pure, so `npm run statement:serve` asks the same questions from a Mac.
import { tidyCounterparts } from './statement-counterpart.ts'

/** The most one batch carries; the app sends far fewer. */
export const MAX_LINES_PER_CALL = 120
export const MAX_LINE_CHARS = 400
export const MAX_HEADER_CHARS = 4_000
export const MAX_REPEATS_CHARS = 150_000

export interface LineIn {
  n: number
  date: string
  amount: number
  direction: 'in' | 'out'
  text: string
}

export interface LineRow {
  n: number
  name: string
  kind: string
  category: string | null
  member: string | null
  counterpart: string | null
  counterpart_kind: string | null
  counterpart_bank: string | null
}

/** The lines as sent, each proved a line, or null when any is not. */
export function readLines(raw: unknown): LineIn[] | null {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > MAX_LINES_PER_CALL) return null
  const lines: LineIn[] = []
  for (const item of raw) {
    const { n, date, amount, direction, text } = (item ?? {}) as Record<string, unknown>
    if (!Number.isInteger(n) || typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return null
    if (typeof amount !== 'number' || !Number.isFinite(amount)) return null
    if ((direction !== 'in' && direction !== 'out') || typeof text !== 'string') return null
    lines.push({ n: n as number, date, amount, direction, text: text.replace(/\s+/g, ' ').trim().slice(0, MAX_LINE_CHARS) })
  }
  return lines
}

/** The lines as the model reads them: number | day | way | amount | line. */
export function linesText(lines: LineIn[]): string {
  return lines.map((l) => `${l.n} | ${l.date} | ${l.direction} | ${l.amount.toFixed(2)} | ${l.text}`).join('\n')
}

/** The top of the file and its first lines, for the head's look. */
export function headText(fileName: string, header: string, lines: LineIn[]): string {
  return `Statement file "${fileName}". The top of the file:\n${header.slice(0, MAX_HEADER_CHARS)}\n\nIts first lines (number | day | way | amount | line):\n${linesText(lines)}`
}

/** The answer's rows, each counterpart tidied. A row for a line not asked about, or a second
 *  row for one, is dropped: the app asks again or names that line itself. */
export function parseRows(rows: unknown, asked: LineIn[]): LineRow[] {
  if (!Array.isArray(rows)) return []
  const open = new Set(asked.map((l) => l.n))
  const kept = rows.filter((row) => open.delete(Number((row as { n?: unknown } | null)?.n)) && typeof (row as { name?: unknown }).name === 'string' && (row as { name: string }).name.trim() !== '')
  return tidyCounterparts({ charges: kept }).charges as LineRow[]
}

/** The shape to answer in; for a plain task, working down a list, thinking off at low effort,
 *  because thinking is where the time goes. Sonnet spells thinking off another way. */
export function answerMode(shape: unknown, model: string, plain: boolean): Record<string, unknown> {
  const format = { type: 'json_schema', schema: shape }
  if (!plain) return { output_config: { format } }
  return { output_config: { format, effort: 'low' }, thinking: { type: model.includes('sonnet') ? 'between_tools' : 'disabled' } }
}
