// Insight notes — LOCAL ONLY. Appends to the vault's insights.json, the file the app's
// Insights screen reads; append-only, last note per module wins, unknown modules kept.
import { readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { randomUUID } from 'node:crypto'
import { DATA_POLICY_REFUSAL, scanFields } from '@longbook/core'
import { VaultWriteError } from './errors.js'
import { insightNote } from './proposal.js'

export { LEAVE_INSIGHT_SPEC } from './proposal.js'

export interface LeaveInsightInput {
  module: string
  text: string
}

const INSIGHTS_FILE = 'insights.json'

const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v)

export function leaveInsight(dir: string, input: LeaveInsightInput): unknown {
  const module = input.module?.trim()
  const text = input.text?.trim()
  if (!module) throw new VaultWriteError('module names where the note sits, e.g. dashboard.next_payment.')
  if (!text) throw new VaultWriteError('text carries the note itself.')
  if (scanFields({ text }).length > 0) throw new VaultWriteError(DATA_POLICY_REFUSAL)

  const path = join(dir, INSIGHTS_FILE)
  let file: Record<string, unknown> = { version: 1, insights: [] }
  try {
    const parsed: unknown = JSON.parse(readFileSync(path, 'utf8'))
    if (isRecord(parsed)) file = parsed
  } catch {
    // A missing or unreadable file starts fresh; existing notes are never guessed at.
  }
  const insights = Array.isArray(file.insights) ? file.insights : []
  insights.push({ module, text, created_at: new Date().toISOString() })
  file.version = typeof file.version === 'number' ? file.version : 1
  file.insights = insights

  const tmp = join(dir, `.${INSIGHTS_FILE}.${randomUUID()}.tmp`)
  try {
    writeFileSync(tmp, JSON.stringify(file, null, 2))
    renameSync(tmp, path)
  } catch (error) {
    rmSync(tmp, { force: true })
    throw error
  }
  const warned = insightNote(module)
  return { left: { module, text }, ...(warned ? { note: warned } : {}) }
}
