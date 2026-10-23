// The documents folder, LOCAL ONLY like every tool that touches the disk: two tools list
// and read the statements in <vault>/documents (PDF, .xlsx, CSV; the app's importer also
// reads .xls). Text leaves the machine only into the owner's own conversation.
import { execFile } from 'node:child_process'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, relative, resolve, sep } from 'node:path'
import { xlsxToText, XlsxError } from './xlsxLite.js'
import { VaultWriteError } from './vaultWrite.js'

export const LIST_DOCUMENTS_SPEC = {
  title: 'List documents',
  description:
    `Lists the files in the vault's documents/ folder — bank and card statements the owner ` +
    `dropped in, and source files referenced by rows. Reads PDF (text-bearing), Excel ` +
    `(.xlsx) and CSV; anything else is listed as unsupported. A file still in iCloud is ` +
    `named so, with its download nudged. Start an import here, then read_guide ` +
    `"importing-statements" for the method.`,
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
}

export const READ_DOCUMENT_SPEC = {
  title: 'Read a document',
  description:
    `Returns a document's text: PDFs page by page, Excel sheets as CSV lines under sheet ` +
    `headings, CSV as it is. Long files page through offset/next_offset — keep asking until ` +
    `next_offset is null. Only for files in the vault's documents folder; a statement pasted ` +
    `into the chat is already in front of you. The text stays on this machine and in this ` +
    `conversation; never copy an account or card number out of it into the vault — the ` +
    `validator refuses them. Debit lines are charges; credit lines are money in, written ` +
    `with direction "in"; only movements between the owner's own accounts are skipped.`,
  annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
}

export const DOCUMENTS_DIR = 'documents'
const PAGE_CHARS = 40_000
const MAX_BYTES = 25 * 1024 * 1024

type Kind = 'pdf' | 'excel' | 'csv' | 'legacy-excel' | 'unsupported' | 'not-downloaded'

interface Entry {
  name: string
  kind: Kind
  size?: number
  modified?: string
  note?: string
}

function kindOf(name: string): Kind {
  const lower = name.toLowerCase()
  if (lower.endsWith('.pdf')) return 'pdf'
  if (lower.endsWith('.xlsx')) return 'excel'
  if (lower.endsWith('.xls')) return 'legacy-excel'
  if (lower.endsWith('.csv')) return 'csv'
  return 'unsupported'
}

/** Nudge iCloud to bring a dataless file down; quietly nothing off-macOS. */
function nudgeDownload(path: string): void {
  try {
    execFile('/usr/bin/brctl', ['download', path], () => {})
  } catch {
    // Best effort only: the listing already tells the owner what to do.
  }
}

function walk(dir: string, root: string, out: Entry[]): void {
  let names: string[]
  try {
    names = readdirSync(dir)
  } catch {
    return
  }
  for (const name of names.sort()) {
    const full = join(dir, name)
    // An evicted iCloud file lists as .name.icloud until it is downloaded again.
    const stub = /^\.(.+)\.icloud$/.exec(name)
    if (stub) {
      nudgeDownload(full)
      out.push({
        name: relative(root, join(dir, stub[1]!)),
        kind: 'not-downloaded',
        note: 'Still in iCloud — its download was just nudged; ask again in a moment, or open the folder in Finder.',
      })
      continue
    }
    if (name.startsWith('.')) continue
    let stat
    try {
      stat = statSync(full)
    } catch {
      continue
    }
    if (stat.isDirectory()) {
      walk(full, root, out)
      continue
    }
    out.push({
      name: relative(root, full),
      kind: kindOf(name),
      size: stat.size,
      modified: stat.mtime.toISOString().slice(0, 10),
    })
  }
}

export function listDocuments(vaultDir: string): unknown {
  const root = join(vaultDir, DOCUMENTS_DIR)
  const files: Entry[] = []
  walk(root, root, files)
  for (const f of files) {
    if (f.kind === 'legacy-excel') f.note = 'Legacy .xls is not read here — save it as .xlsx or CSV, or import it in the app, which reads .xls.'
    if (f.kind === 'unsupported') f.note = 'Only PDF, .xlsx and CSV are read.'
  }
  if (files.length === 0) {
    return {
      folder: `${DOCUMENTS_DIR}/`,
      files,
      note:
        `No documents yet. Bank and card statements go in the ${DOCUMENTS_DIR} folder inside ` +
        `the longbook folder — PDF, .xlsx or CSV.`,
    }
  }
  return { folder: `${DOCUMENTS_DIR}/`, files }
}

/** The document resolved inside documents/ — a name may not step outside it. */
function resolveDocument(vaultDir: string, name: string): string {
  const root = resolve(vaultDir, DOCUMENTS_DIR)
  const full = resolve(root, name)
  if (full !== root && !full.startsWith(root + sep)) {
    throw new VaultWriteError('A document name stays inside the documents folder.')
  }
  return full
}

async function pdfToText(bytes: Uint8Array): Promise<string> {
  const { extractText, getDocumentProxy } = await import('unpdf')
  const pdf = await getDocumentProxy(new Uint8Array(bytes))
  const { text } = await extractText(pdf, { mergePages: false })
  const pages = (text as string[]).map((page, i) => `## Page ${i + 1}\n${page.trim()}`)
  return pages.join('\n\n').trim()
}

export interface ReadDocumentInput {
  name: string
  offset?: number
}

export async function readDocument(vaultDir: string, input: ReadDocumentInput): Promise<unknown> {
  const name = input.name?.trim()
  if (!name) throw new VaultWriteError('name says which document — as list_documents lists it.')
  const full = resolveDocument(vaultDir, name)
  const kind = kindOf(name)
  if (kind === 'legacy-excel') {
    throw new VaultWriteError('Legacy .xls is not read here — save the statement as .xlsx or CSV and try again, or import it in the app, which reads .xls.')
  }
  if (kind === 'unsupported') {
    throw new VaultWriteError('Only PDF, .xlsx and CSV documents are read.')
  }

  let bytes: Buffer
  try {
    bytes = readFileSync(full)
  } catch {
    const stubName = join(full, '..', `.${name.split(sep).pop()}.icloud`)
    try {
      statSync(stubName)
      nudgeDownload(full)
      throw new VaultWriteError(
        `"${name}" is still in iCloud. Its download was just nudged — ask again in a moment, or open the folder in Finder to download it.`,
      )
    } catch (error) {
      if (error instanceof VaultWriteError) throw error
      throw new VaultWriteError(`No document named "${name}" — list_documents shows what is there.`)
    }
  }
  if (bytes.length > MAX_BYTES) {
    throw new VaultWriteError('This file is larger than 25 MB — export a smaller statement.')
  }

  let text: string
  if (kind === 'pdf') {
    try {
      text = await pdfToText(bytes)
    } catch {
      throw new VaultWriteError(`"${name}" does not open as a PDF.`)
    }
    if (text.replace(/## Page \d+/g, '').trim() === '') {
      throw new VaultWriteError(
        `"${name}" carries no text — it is likely a scanned image. Export a text, .xlsx or CSV statement instead.`,
      )
    }
  } else if (kind === 'excel') {
    try {
      text = xlsxToText(bytes)
    } catch (error) {
      if (error instanceof XlsxError) throw new VaultWriteError(`"${name}": ${error.message}`)
      throw new VaultWriteError(`"${name}" does not open as an .xlsx workbook.`)
    }
  } else {
    text = bytes.toString('utf8')
  }

  const offset = Math.max(0, Math.trunc(input.offset ?? 0))
  const slice = text.slice(offset, offset + PAGE_CHARS)
  const next = offset + PAGE_CHARS < text.length ? offset + PAGE_CHARS : null
  return {
    name,
    kind,
    total_chars: text.length,
    offset,
    next_offset: next,
    ...(next != null ? { note: 'More follows — ask again with offset set to next_offset.' } : {}),
    text: slice,
  }
}
