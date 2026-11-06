// The documents folder over real temp vaults: listing with iCloud honesty, and the
// three readable formats — PDFs built object-by-object so the offsets are honest.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { zipSync, strToU8 } from 'fflate'
import { listDocuments, readDocument } from '../src/documents.js'
import { xlsxToText } from '../src/xlsxLite.js'

const vaultWithDocs = () => {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-mcp-docs-'))
  mkdirSync(join(dir, 'documents', 'statements 2026'), { recursive: true })
  return dir
}

/** A real PDF assembled with computed xref offsets — valid by construction. */
function pdf(contentStream: string): Buffer {
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    `<< /Length ${contentStream.length} >>\nstream\n${contentStream}\nendstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ]
  let body = '%PDF-1.4\n'
  const offsets: number[] = []
  objects.forEach((obj, i) => {
    offsets.push(body.length)
    body += `${i + 1} 0 obj\n${obj}\nendobj\n`
  })
  const xref = body.length
  let out = body + `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`
  for (const at of offsets) out += `${String(at).padStart(10, '0')} 00000 n \n`
  out += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`
  return Buffer.from(out, 'latin1')
}

const TEXT_PDF = pdf('BT /F1 12 Tf 50 700 Td (HDFC Bank statement 2026-07-01 NETFLIX 649.00) Tj ET')
const SCANNED_PDF = pdf('')

/** A real .xlsx zipped from its own XML: shared strings, inline, numbers, a gap, escapes. */
function xlsx(): Buffer {
  const files = {
    'xl/workbook.xml':
      '<workbook xmlns:r="rels"><sheets><sheet name="July &amp; August" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
      '<Relationships><Relationship Id="rId1" Type="ws" Target="worksheets/sheet1.xml"/></Relationships>',
    'xl/sharedStrings.xml':
      '<sst><si><t>Date</t></si><si><t>Narration</t></si><si><r><t>NET</t></r><r><t>FLIX</t></r></si></sst>',
    'xl/worksheets/sheet1.xml':
      '<worksheet><sheetData>' +
      '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>' +
      '<row r="2"><c r="A2" t="inlineStr"><is><t>2026-07-01</t></is></c><c r="B2" t="s"><v>2</v></c><c r="D2"><v>649</v></c></row>' +
      '<row r="3"><c r="A3" t="b"><v>1</v></c><c r="B3" t="inlineStr"><is><t>has, comma</t></is></c></row>' +
      '</sheetData></worksheet>',
  }
  return Buffer.from(zipSync(Object.fromEntries(Object.entries(files).map(([k, v]) => [k, strToU8(v)]))))
}

test('xlsxToText reads sheets, shared and inline strings, gaps, booleans, and quoting', () => {
  const text = xlsxToText(xlsx())
  assert.match(text, /## Sheet: July & August/)
  assert.match(text, /Date,Narration/)
  assert.match(text, /2026-07-01,NETFLIX,,649/)
  assert.match(text, /TRUE,"has, comma"/)
})

test('list walks subfolders, types every file, and speaks iCloud honestly', () => {
  const dir = vaultWithDocs()
  writeFileSync(join(dir, 'documents', 'hdfc-2026.pdf'), TEXT_PDF)
  writeFileSync(join(dir, 'documents', 'statements 2026', 'card.xlsx'), xlsx())
  writeFileSync(join(dir, 'documents', 'export.csv'), 'a,b\n1,2\n')
  writeFileSync(join(dir, 'documents', 'old.xls'), 'x')
  writeFileSync(join(dir, 'documents', 'notes.docx'), 'x')
  writeFileSync(join(dir, 'documents', '.icici-aug.pdf.icloud'), 'stub')

  const out = listDocuments(dir) as { files: { name: string; kind: string; note?: string }[] }
  const byName = Object.fromEntries(out.files.map((f) => [f.name, f]))
  assert.equal(byName['hdfc-2026.pdf']!.kind, 'pdf')
  assert.equal(byName[join('statements 2026', 'card.xlsx')]!.kind, 'excel')
  assert.equal(byName['export.csv']!.kind, 'csv')
  assert.match(byName['old.xls']!.note ?? '', /save it as .xlsx or CSV/i)
  assert.match(byName['notes.docx']!.note ?? '', /Only PDF/)
  assert.equal(byName['icici-aug.pdf']!.kind, 'not-downloaded')
  assert.match(byName['icici-aug.pdf']!.note ?? '', /Still in iCloud/)
})

test('an empty or missing documents folder answers with the invitation, never an error', () => {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-mcp-nodocs-'))
  const out = listDocuments(dir) as { files: unknown[]; note?: string }
  assert.equal(out.files.length, 0)
  assert.match(out.note ?? '', /statements go in the documents folder/)
})

test('a text PDF reads page by page; a scanned one refuses with the way out', async () => {
  const dir = vaultWithDocs()
  writeFileSync(join(dir, 'documents', 'hdfc.pdf'), TEXT_PDF)
  writeFileSync(join(dir, 'documents', 'scan.pdf'), SCANNED_PDF)

  const out = (await readDocument(dir, { name: 'hdfc.pdf' })) as { kind: string; text: string }
  assert.equal(out.kind, 'pdf')
  assert.match(out.text, /## Page 1/)
  assert.match(out.text, /NETFLIX 649\.00/)

  await assert.rejects(() => readDocument(dir, { name: 'scan.pdf' }), /carries no text/)
})

test('excel and csv read; long text pages through next_offset', async () => {
  const dir = vaultWithDocs()
  writeFileSync(join(dir, 'documents', 'card.xlsx'), xlsx())
  const rows = Array.from({ length: 3000 }, (_, i) => `2026-07-${String((i % 28) + 1).padStart(2, '0')},UPI-${i},${i}`)
  writeFileSync(join(dir, 'documents', 'big.csv'), `date,narration,amount\n${rows.join('\n')}\n`)

  const excel = (await readDocument(dir, { name: 'card.xlsx' })) as { text: string }
  assert.match(excel.text, /NETFLIX/)

  const first = (await readDocument(dir, { name: 'big.csv' })) as { next_offset: number | null; total_chars: number; text: string }
  assert.ok(first.next_offset != null && first.total_chars > first.text.length)
  const second = (await readDocument(dir, { name: 'big.csv', offset: first.next_offset! })) as { offset: number }
  assert.equal(second.offset, first.next_offset)
})

test('refusals: unsupported, legacy .xls, a name stepping outside, a missing name', async () => {
  const dir = vaultWithDocs()
  writeFileSync(join(dir, 'documents', 'notes.docx'), 'x')
  writeFileSync(join(dir, 'documents', 'old.xls'), 'x')
  await assert.rejects(() => readDocument(dir, { name: 'notes.docx' }), /Only PDF/)
  await assert.rejects(() => readDocument(dir, { name: 'old.xls' }), /\.xlsx or CSV/)
  await assert.rejects(() => readDocument(dir, { name: '../financial_memory.json' }), /stays inside/)
  await assert.rejects(() => readDocument(dir, { name: 'gone.pdf' }), /No document named/)
})
