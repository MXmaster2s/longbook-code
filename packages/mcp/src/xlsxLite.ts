// A small .xlsx reader of our own: unzip, then walk the sheet XML directly. Scoped to
// what a bank or card export actually uses — shared and inline strings, numbers,
// booleans — so the dependency surface stays a zip reader, not a spreadsheet suite.
import { unzipSync, strFromU8 } from 'fflate'

export class XlsxError extends Error {}

const ENTITIES: Record<string, string> = {
  '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'",
}

function unescape(xml: string): string {
  return xml
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex: string) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec: string) => String.fromCodePoint(parseInt(dec, 10)))
    .replace(/&(amp|lt|gt|quot|apos);/g, (m) => ENTITIES[m] ?? m)
}

/** Every <t> run inside one element, joined — a styled cell splits its text across runs. */
function textRuns(fragment: string): string {
  let out = ''
  const rx = /<t(?:\s[^>]*)?>([\s\S]*?)<\/t>|<t(?:\s[^>]*)?\/>/g
  for (let m = rx.exec(fragment); m; m = rx.exec(fragment)) out += unescape(m[1] ?? '')
  return out
}

/** A1 → 0, B7 → 1: the column index a cell reference names. */
function columnOf(ref: string): number {
  let n = 0
  for (const ch of ref) {
    if (ch < 'A' || ch > 'Z') break
    n = n * 26 + (ch.charCodeAt(0) - 64)
  }
  return Math.max(0, n - 1)
}

function csvCell(value: string): string {
  return /[",\n\r]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value
}

interface Sheet {
  name: string
  rows: string[][]
}

function parseSheet(xml: string, shared: string[]): string[][] {
  const rows: string[][] = []
  const rowRx = /<row(?:\s[^>]*)?>([\s\S]*?)<\/row>/g
  for (let rm = rowRx.exec(xml); rm; rm = rowRx.exec(xml)) {
    const cells: string[] = []
    const cellRx = /<c(\s[^>]*)?(?:\/>|>([\s\S]*?)<\/c>)/g
    for (let cm = cellRx.exec(rm[1]!); cm; cm = cellRx.exec(rm[1]!)) {
      const attrs = cm[1] ?? ''
      const body = cm[2] ?? ''
      const ref = /r="([A-Z]+\d+)"/.exec(attrs)?.[1]
      const type = /t="([^"]+)"/.exec(attrs)?.[1] ?? 'n'
      const column = ref ? columnOf(ref) : cells.length
      let value = ''
      if (type === 'inlineStr') {
        value = textRuns(body)
      } else {
        const v = /<v(?:\s[^>]*)?>([\s\S]*?)<\/v>/.exec(body)?.[1]
        if (v != null) {
          const raw = unescape(v)
          if (type === 's') value = shared[Number(raw)] ?? ''
          else if (type === 'b') value = raw === '1' ? 'TRUE' : 'FALSE'
          else value = raw
        }
      }
      while (cells.length < column) cells.push('')
      cells[column] = value
    }
    rows.push(cells)
  }
  return rows
}

/** Workbook order and names, resolved through the relationship ids the file declares. */
function sheetEntries(files: Record<string, Uint8Array>): { name: string; path: string }[] {
  const workbook = files['xl/workbook.xml']
  if (!workbook) throw new XlsxError('This file has no workbook inside — not an .xlsx.')
  const rels = files['xl/_rels/workbook.xml.rels']
  const targets: Record<string, string> = {}
  if (rels) {
    const rx = /<Relationship\s[^>]*Id="([^"]+)"[^>]*Target="([^"]+)"[^>]*\/?>/g
    const text = strFromU8(rels)
    for (let m = rx.exec(text); m; m = rx.exec(text)) {
      targets[m[1]!] = m[2]!.replace(/^\//, '').startsWith('xl/') ? m[2]!.replace(/^\//, '') : `xl/${m[2]}`
    }
  }
  const out: { name: string; path: string }[] = []
  const rx = /<sheet\s[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"[^>]*\/?>/g
  const text = strFromU8(workbook)
  for (let m = rx.exec(text); m; m = rx.exec(text)) {
    const path = targets[m[2]!] ?? `xl/worksheets/sheet${out.length + 1}.xml`
    out.push({ name: unescape(m[1]!), path })
  }
  if (out.length === 0) throw new XlsxError('This workbook names no sheets.')
  return out
}

/**
 * The whole workbook as readable text: one heading per sheet, rows as CSV lines.
 * Dates stored as Excel serial numbers stay numbers — the export's own text columns
 * carry the dates a statement reader needs.
 */
export function xlsxToText(bytes: Uint8Array): string {
  let files: Record<string, Uint8Array>
  try {
    files = unzipSync(bytes)
  } catch {
    throw new XlsxError('This file does not open as an .xlsx (it is not a zip archive).')
  }
  const sharedXml = files['xl/sharedStrings.xml']
  const shared: string[] = []
  if (sharedXml) {
    const rx = /<si(?:\s[^>]*)?>([\s\S]*?)<\/si>/g
    const text = strFromU8(sharedXml)
    for (let m = rx.exec(text); m; m = rx.exec(text)) shared.push(textRuns(m[1]!))
  }
  const sheets: Sheet[] = sheetEntries(files).map(({ name, path }) => {
    const xml = files[path]
    return { name, rows: xml ? parseSheet(strFromU8(xml), shared) : [] }
  })
  return sheets
    .map((sheet) => {
      const lines = sheet.rows.map((row) => row.map(csvCell).join(','))
      return `## Sheet: ${sheet.name}\n${lines.join('\n')}`
    })
    .join('\n\n')
}
