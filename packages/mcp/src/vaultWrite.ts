// The stdio server's safe write path — LOCAL ONLY. rpc.ts and catalog.ts never import
// this module, so the hosted engine stays read-only by construction. Every save is
// validated, policy-scanned, provenance-stamped, conflict-checked, and written atomically.
import { createHash, randomUUID } from 'node:crypto'
import { readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { DATA_POLICY_REFUSAL, policyFix, scanText } from '@longbook/core'
import { VAULT_FORMAT_VERSION, parseVault } from './parse.js'
import { DATA_FILE } from './vault.js'

import { VaultWriteError } from './errors.js'

export { VaultWriteError }

export const CAS_MESSAGE = 'The file changed while I was writing. Read it again and retry.'

export type RawVault = Record<string, unknown>

/** One row the mutation touched: its id (for provenance) and every free-text value on it. */
export interface TouchedRow {
  id: string
  fields: Record<string, string | null | undefined>
  /** Its place in a batch the caller sent, from 1 — how a refusal names a row it cannot quote. */
  place?: number
}

/** What a call named: a row by id or name, or a promotion's ids. */
export interface Addressed {
  id?: string
  name?: string
  ids?: string[]
}

/**
 * The row a refusal names, as the hosted door's refusedRow names it: a batch row by its place
 * and clean name; any other by the name or id the call gave, else a promotion's ids. Never
 * what the scan refused, nor an id the refused write would have made.
 */
function refusedRow(row: TouchedRow, addressed: Addressed | undefined): string {
  const clean = (value: unknown): string => {
    const text = typeof value === 'string' ? value.trim() : ''
    return text && !scanText(text) ? text : ''
  }
  if (row.place !== undefined) {
    const name = clean(row.fields.name)
    return name ? ` (row ${row.place}: "${name}")` : ` (row ${row.place})`
  }
  const named = clean(addressed?.name) || clean(addressed?.id)
  if (named) return ` (row: "${named}")`
  const ids = (addressed?.ids ?? []).map(clean).filter(Boolean)
  return ids.length > 0 ? ` (ids: ${ids.join(', ')})` : ''
}

export interface Mutated {
  touched: TouchedRow[]
  report: unknown
  /** Where the data came from — a document path, a mail id — kept in _provenance. */
  source?: string
  /** What the call named, for a refusal that no batch place names. */
  addressed?: Addressed
}

const sha256 = (bytes: Buffer): string => createHash('sha256').update(bytes).digest('hex')

const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v)

/**
 * The app's tag decoder is strict — one malformed entry makes the whole vault unreadable
 * there — so every registry entry is held to its required shape before a byte lands. A
 * template is read by no one, so its shape is never judged.
 */
function validateTags(vault: RawVault): void {
  if (vault.tags == null) return
  if (!Array.isArray(vault.tags)) throw new VaultWriteError('tags must be a list.')
  vault.tags.forEach((t, i) => {
    const bad = (what: string): never => {
      throw new VaultWriteError(`Nothing was written — tags[${i}] ${what}.`)
    }
    if (!isRecord(t)) bad('must be an object')
    const e = t as Record<string, unknown>
    for (const key of ['id', 'kind', 'name', 'name_key']) {
      if (typeof e[key] !== 'string' || !(e[key] as string).trim()) bad(`needs ${key}`)
    }
    if (e.icon != null && typeof e.icon !== 'string') bad('carries a non-text icon')
    if (e.sort != null && !Number.isInteger(e.sort)) bad('carries a non-integer sort')
    if (e.is_default != null && typeof e.is_default !== 'boolean') bad('carries a non-boolean is_default')
  })
}

/** A source reference is short and never carries what the file refuses. */
function checkSource(source: unknown): string | undefined {
  if (source === undefined || source === null) return undefined
  if (typeof source !== 'string' || !source.trim()) throw new VaultWriteError('source, when given, is a short reference like "documents/hdfc-2026.pdf".')
  const ref = source.trim()
  if (ref.length > 200) throw new VaultWriteError('source stays under 200 characters — a path or an id, not the content.')
  if (scanText(ref)) throw new VaultWriteError(`${DATA_POLICY_REFUSAL} (source)`)
  return ref
}

/**
 * Read → validate → mutate → scan → stamp → conflict-check → write atomically. The file
 * must already exist and parse: this path never creates a vault and never overwrites one
 * it cannot read. A concurrent edit refuses with CAS_MESSAGE; nothing is lost either way.
 */
export function writeVault(dir: string, editedBy: string, mutate: (vault: RawVault) => Mutated): unknown {
  const path = join(dir, DATA_FILE)
  let bytes: Buffer
  try {
    bytes = readFileSync(path)
  } catch {
    throw new VaultWriteError(
      `No financial memory at ${path} — this server never creates one. Point --vault (or LONGBOOK_VAULT_PATH) at an existing longbook folder.`,
    )
  }
  const hashAtRead = sha256(bytes)
  const text = bytes.toString('utf8')

  // parseVault refuses invalid JSON and foreign files, so a broken vault is reported
  // and preserved, never overwritten.
  parseVault(text)
  const vault = JSON.parse(text) as RawVault
  // parseVault already refused any other format; said again here so a write can never
  // land on a file this server does not understand.
  if (vault.version !== VAULT_FORMAT_VERSION) {
    throw new VaultWriteError(`This file is format ${String(vault.version)}; this server writes format ${VAULT_FORMAT_VERSION}.`)
  }

  const { touched, report, source, addressed } = mutate(vault)
  validateTags(vault)
  const sourceRef = checkSource(source)

  // The mandated data-policy scan: any free text a touched row carries, or the save
  // refuses — naming the row, so a 200-row batch is fixable without guessing.
  for (const row of touched) {
    for (const [field, value] of Object.entries(row.fields)) {
      const hit = value ? scanText(value) : null
      if (hit) throw new VaultWriteError(`${DATA_POLICY_REFUSAL}${refusedRow(row, addressed)}${policyFix(hit, field)}`)
    }
  }

  // Sign the work, as llms.txt asks of every outside editor.
  const provenance = isRecord(vault._provenance) ? vault._provenance : {}
  const editedAt = new Date().toISOString()
  for (const row of touched) {
    provenance[row.id] = { edited_by: editedBy, edited_at: editedAt, ...(sourceRef ? { source: sourceRef } : {}) }
  }
  vault._provenance = provenance

  // The mutated vault must itself parse before it may replace the file.
  const next = JSON.stringify(vault, null, 2)
  parseVault(next)

  // Compare-and-swap: another device or the app may have written since the read above.
  let current: Buffer
  try {
    current = readFileSync(path)
  } catch {
    throw new VaultWriteError(CAS_MESSAGE)
  }
  if (sha256(current) !== hashAtRead) throw new VaultWriteError(CAS_MESSAGE)

  // Atomic replace: a temp file beside the target, then one rename.
  const tmp = join(dir, `.${DATA_FILE}.${randomUUID()}.tmp`)
  try {
    writeFileSync(tmp, next)
    renameSync(tmp, path)
  } catch (error) {
    rmSync(tmp, { force: true })
    throw error
  }
  return report
}
