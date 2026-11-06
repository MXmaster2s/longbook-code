#!/usr/bin/env -S npx tsx
// The statement fixtures the import proof runs on: a household's year in the shapes a
// bank hands out, plus two that must be refused. Invented household, invented numbers;
// the SHAPE is real. Same bytes every run. Regenerate: npm run fixtures:statements.
import { writeFileSync, mkdirSync, readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { zipSync, strToU8 } from 'fflate'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
// Byte-identical copies in both places: the server's proof reads one, the app's reader
// the other, and a shape that defeats either is caught where it happens.
const OUTS = [
  join(ROOT, 'packages/mcp/tests/fixtures/statements'),
  join(ROOT, 'packages/swift-core/Tests/LongbookCoreTests/Fixtures/statements'),
]
const CHECK = process.argv.includes('--check')

interface Line {
  date: string
  narration: string
  debit?: number
  credit?: number
}

/** Twelve months of one household's savings account, as HDFC prints it. */
function savingsLines(): Line[] {
  const lines: Line[] = []
  const months = [
    ['2025-09', '2025-10', '2025-11', '2025-12'],
    ['2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07', '2026-08'],
  ].flat()

  for (const month of months) {
    // The rhythms: rent, the cook, the phone plan, a streaming subscription, society dues.
    lines.push({ date: `${month}-01`, narration: 'NEFT-DR-HOUSE RENT-MEHTA PROPERTIES', debit: 42000 })
    lines.push({ date: `${month}-01`, narration: 'UPI-SUNITA D-cook salary', debit: 9000 })
    lines.push({ date: `${month}-03`, narration: 'ACH-D- AIRTEL DIGITAL TV', debit: 899 })
    lines.push({ date: `${month}-05`, narration: 'UPI/NETFLIX.COM/6492001/subscription', debit: 649 })
    lines.push({ date: `${month}-07`, narration: 'NEFT-DR-GREENWOOD SOCIETY MAINT', debit: 3500 })
    // Money in, written apart with direction "in"; then two movements an importer skips.
    lines.push({ date: `${month}-28`, narration: 'SALARY CREDIT - VERTEX LABS PVT LTD', credit: 214000 })
    lines.push({ date: `${month}-15`, narration: 'ATM WDL SELF', debit: 10000 })
    lines.push({ date: `${month}-20`, narration: 'CREDIT CARD PAYMENT AXIS 4402', debit: 38000 })
  }

  // A streaming subscription that ENDED — the case that must import as once rows.
  for (const month of ['2025-09', '2025-10', '2025-11', '2025-12', '2026-01', '2026-02']) {
    lines.push({ date: `${month}-12`, narration: 'UPI/SPOTIFY INDIA/plan', debit: 119 })
  }
  // Yearly premiums, one insurer per month, each seen once in the year.
  lines.push({ date: '2026-03-15', narration: 'HDFC ERGO HEALTH PREMIUM POLICY 88213', debit: 18450 })
  lines.push({ date: '2026-05-22', narration: 'LIC OF INDIA TERM PLAN PREMIUM', debit: 24600 })
  // Half-yearly: the custom-cycle case.
  lines.push({ date: '2026-01-12', narration: 'STAR HEALTH PREMIUM HALF YEARLY', debit: 9200 })
  lines.push({ date: '2026-07-12', narration: 'STAR HEALTH PREMIUM HALF YEARLY', debit: 9200 })
  // One-time spends: no rhythm, no proof of repetition.
  lines.push({ date: '2026-06-10', narration: 'IRCTC RAIL CONNECT BOOKING', debit: 4560 })
  lines.push({ date: '2026-04-08', narration: 'APOLLO PHARMACY', debit: 1240 })
  lines.push({ date: '2026-02-14', narration: 'TANISHQ JEWELLERY', debit: 32000 })

  return lines.sort((a, b) => a.date.localeCompare(b.date))
}

/** A card statement: the charges the savings account only shows as one bill payment. */
function cardLines(): Line[] {
  const lines: Line[] = []
  for (const month of ['2026-05', '2026-06', '2026-07', '2026-08']) {
    lines.push({ date: `${month}-02`, narration: 'ADOBE SYSTEMS SOFTWARE SUBSCRIPTION', debit: 1699 })
    lines.push({ date: `${month}-09`, narration: 'AMAZON PRIME MEMBERSHIP', debit: 179 })
    lines.push({ date: `${month}-18`, narration: 'SWIGGY ORDER', debit: 640 })
  }
  lines.push({ date: '2026-07-21', narration: 'GODADDY.COM 3 YEAR DOMAIN', debit: 3597 })
  lines.push({ date: '2026-08-02', narration: 'CLAUDE.AI SUBSCRIPTION USD 20.00', debit: 1760 })
  return lines.sort((a, b) => a.date.localeCompare(b.date))
}

const ddmmyyyy = (iso: string): string => {
  const [y, m, d] = iso.split('-')
  return `${d}/${m}/${y}`
}

const money = (n?: number): string => (n == null ? '' : n.toFixed(2))

// ---------------------------------------------------------------------------------------------
// PDF: assembled object by object with computed xref offsets, so it is a real file.

function pdf(pages: string[][]): Buffer {
  const contents = pages.map(
    (rows) =>
      'BT /F1 9 Tf 40 780 Td 11 TL\n' +
      rows.map((row) => `(${row.replace(/[()\\]/g, '')}) Tj T*`).join('\n') +
      '\nET',
  )
  const objects: string[] = []
  const pageIds = contents.map((_, i) => 4 + i * 2)
  objects.push('<< /Type /Catalog /Pages 2 0 R >>')
  objects.push(`<< /Type /Pages /Kids [${pageIds.map((id) => `${id} 0 R`).join(' ')}] /Count ${pages.length} >>`)
  objects.push('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>')
  contents.forEach((stream, i) => {
    objects.push(
      `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents ${pageIds[i]! + 1} 0 R ` +
        '/Resources << /Font << /F1 3 0 R >> >> >>',
    )
    objects.push(`<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`)
  })

  let body = '%PDF-1.4\n'
  const offsets: number[] = []
  objects.forEach((object, i) => {
    offsets.push(body.length)
    body += `${i + 1} 0 obj\n${object}\nendobj\n`
  })
  const xref = body.length
  let out = `${body}xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`
  for (const at of offsets) out += `${String(at).padStart(10, '0')} 00000 n \n`
  out += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`
  return Buffer.from(out, 'latin1')
}

function savingsPdf(): Buffer {
  const lines = savingsLines()
  const header = [
    'HDFC BANK LTD',
    'Statement of account 01/09/2025 to 31/08/2026',
    'Account holder: A HOUSEHOLD    Account no: XXXXXXXX4417    Branch: KORAMANGALA',
    '',
    'Date        Narration                                   Debit       Credit',
  ]
  const rows = lines.map(
    (line) =>
      `${ddmmyyyy(line.date)}  ${line.narration.padEnd(42).slice(0, 42)}  ` +
      `${money(line.debit).padStart(10)}  ${money(line.credit).padStart(10)}`,
  )
  const pages: string[][] = []
  for (let i = 0; i < rows.length; i += 55) {
    pages.push([...(i === 0 ? header : ['Date        Narration                                   Debit       Credit']), ...rows.slice(i, i + 55)])
  }
  return pdf(pages)
}

/** A scanned statement: a real PDF whose page carries an image, and no text at all. */
function scannedPdf(): Buffer {
  return pdf([[]])
}

// ---------------------------------------------------------------------------------------------
// xlsx: the workbook a bank's "export to Excel" produces — inline strings, real numbers.

function cardXlsx(): Buffer {
  const lines = cardLines()
  const cell = (ref: string, value: string | number): string =>
    typeof value === 'number'
      ? `<c r="${ref}"><v>${value}</v></c>`
      : `<c r="${ref}" t="inlineStr"><is><t>${value.replace(/&/g, '&amp;')}</t></is></c>`
  const rows = [
    `<row r="1">${cell('A1', 'Transaction Date')}${cell('B1', 'Description')}${cell('C1', 'Amount (INR)')}</row>`,
    ...lines.map(
      (line, i) =>
        `<row r="${i + 2}">${cell(`A${i + 2}`, ddmmyyyy(line.date))}${cell(`B${i + 2}`, line.narration)}${cell(`C${i + 2}`, line.debit ?? 0)}</row>`,
    ),
  ]
  // The parts a workbook really carries, namespaces and all: a reader that walks the
  // package from _rels/.rels — as the app's does — must find its way here too.
  const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
  const rels = 'http://schemas.openxmlformats.org/package/2006/relationships'
  const doc = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
  const files: Record<string, Uint8Array> = {
    '[Content_Types].xml': strToU8(
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
        '<Default Extension="xml" ContentType="application/xml"/>' +
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
        '</Types>',
    ),
    '_rels/.rels': strToU8(
      `<Relationships xmlns="${rels}"><Relationship Id="rId1" Type="${doc}/officeDocument" Target="xl/workbook.xml"/></Relationships>`,
    ),
    'xl/workbook.xml': strToU8(
      `<workbook xmlns="${ns}" xmlns:r="${doc}"><sheets><sheet name="Axis Credit Card 4402" sheetId="1" r:id="rId1"/></sheets></workbook>`,
    ),
    'xl/_rels/workbook.xml.rels': strToU8(
      `<Relationships xmlns="${rels}"><Relationship Id="rId1" Type="${doc}/worksheet" Target="worksheets/sheet1.xml"/></Relationships>`,
    ),
    'xl/worksheets/sheet1.xml': strToU8(`<worksheet xmlns="${ns}"><sheetData>${rows.join('')}</sheetData></worksheet>`),
  }
  // A fixed timestamp inside the zip epoch: the bytes must not change run to run.
  return Buffer.from(zipSync(files, { mtime: new Date('2026-08-01T00:00:00Z') }))
}

// ---------------------------------------------------------------------------------------------
// csv: the plainest export, and the one a spreadsheet writes.

function savingsCsv(): string {
  const lines = savingsLines()
  const rows = lines.map(
    (line) => `${ddmmyyyy(line.date)},"${line.narration}",${money(line.debit)},${money(line.credit)}`,
  )
  return ['Date,Narration,Debit,Credit', ...rows].join('\n') + '\n'
}

// ---------------------------------------------------------------------------------------------

const files: Record<string, Buffer | string> = {
  'hdfc-savings-2025-2026.pdf': savingsPdf(),
  'hdfc-savings-2025-2026.csv': savingsCsv(),
  'axis-card-2026.xlsx': cardXlsx(),
  'icici-scanned-june.pdf': scannedPdf(),
  // Refused politely, each for its own stated reason.
  'policy-note.docx': Buffer.from('PK not really a document either', 'latin1'),
  'old-export.xls': Buffer.from('\xD0\xCF\x11\xE0 legacy workbook', 'latin1'),
}

let drift = false
for (const OUT of OUTS) {
  mkdirSync(OUT, { recursive: true })
  for (const [name, body] of Object.entries(files)) {
    const path = join(OUT, name)
    const bytes = typeof body === 'string' ? Buffer.from(body, 'utf8') : body
    const existing = existsSync(path) ? readFileSync(path) : null
    if (existing && existing.equals(bytes)) continue
    if (CHECK) {
      console.error(`drift: ${path}`)
      drift = true
      continue
    }
    writeFileSync(path, bytes)
  }
}

if (CHECK) {
  if (drift) {
    console.error('statement fixtures drifted — run: npm run fixtures:statements')
    process.exit(1)
  }
  console.log('statement fixtures — in sync.')
} else {
  console.log(`wrote ${Object.keys(files).length} statement fixtures to ${OUTS.map((o) => o.slice(ROOT.length)).join(' and ')}`)
}
