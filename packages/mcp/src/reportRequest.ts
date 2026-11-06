// Report requests — LOCAL ONLY. create_report asks longbook to draw a report: held to the
// shared checks against the vault, then left as one file in requests/, longbook's own
// folder, which the app applies like a hosted proposal and deletes once the report is drawn.
import { mkdirSync, renameSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { randomUUID } from 'node:crypto'
import { checkProposal } from './proposal.js'
import { VAULT_PLACE, checkTargets } from './targets.js'
import { VaultReader } from './vault.js'

export { CREATE_REPORT_SPEC, REPORT_END_DESCRIPTION, REPORT_START_DESCRIPTION, REPORT_TITLE_DESCRIPTION } from './proposal.js'

export const REQUESTS_DIR = 'requests'

/** What the local door answers once the request is left for the app. */
export const REPORT_ASKED_NOTE =
  'Asked. longbook draws the report on its Reports screen the next time the app is open — tell the owner so, and stop here. Nothing waits in Proposals.'

export function createReport(dir: string, editedBy: string, input: Record<string, unknown>): unknown {
  const proposal = checkProposal('create_report', input)
  // The same names the hosted door would refuse, refused here against the folder itself.
  checkTargets(proposal, new VaultReader(dir).load(), null, VAULT_PLACE)

  const id = randomUUID()
  const request = {
    id,
    kind: proposal.kind,
    payload: proposal.payload,
    source_ref: proposal.source_ref ?? null,
    client: editedBy,
    origin: 'local',
    created_at: new Date().toISOString(),
  }
  const folder = join(dir, REQUESTS_DIR)
  mkdirSync(folder, { recursive: true })
  const name = `${proposal.kind}-${id}.json`
  // A dot name the app's *.json read never matches, renamed into place whole.
  const tmp = join(folder, `.${name}.tmp`)
  try {
    writeFileSync(tmp, JSON.stringify(request, null, 2))
    renameSync(tmp, join(folder, name))
  } catch (error) {
    rmSync(tmp, { force: true })
    throw error
  }
  return { asked: proposal.payload, note: REPORT_ASKED_NOTE }
}
