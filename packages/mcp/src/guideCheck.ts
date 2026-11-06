// Whether a write followed the guide: the guide_key read_guide handed out comes back with
// the write. This rulebook warns; the next one refuses a write without it.
import { contractRevisionOf, guideKeys, LLMS_TXT } from '@longbook/core'

/** The chapters a charge read from a statement is written by. */
const STATEMENT_CHAPTERS = new Set(['importing-statements', 'first-run', 'month-report', 'guide'])

export const GUIDE_KEY_SCHEMA = {
  type: 'string',
  maxLength: 200,
  description: 'The guide_key read_guide returned with the prompt or chapter this write follows.',
}

/** What to say beside a write whose guide_key is missing, stale or from the wrong chapter; null when it is right. */
export function guideWarning(llms: string, payload: Record<string, unknown>): string | null {
  const key = typeof payload.guide_key === 'string' ? payload.guide_key.trim() : ''
  const then = ' From the next rulebook, a write without the right guide_key is refused.'
  if (!key) {
    return 'No guide_key: call read_guide with the owner\'s prompt or this task\'s chapter, follow it, and pass the guide_key it returns with every write.' + then
  }
  // The guide this door serves, and the one bundled with it, which a prompt's own message keys from.
  const known = new Map([...guideKeys(LLMS_TXT), ...guideKeys(llms)])
  const chapter = known.get(key)
  if (!chapter) {
    return `This guide_key is not from rulebook ${contractRevisionOf(llms) ?? ''}'s guide: read the chapter again with read_guide and pass the key it returns.` + then
  }
  if (!STATEMENT_CHAPTERS.has(chapter) && JSON.stringify(payload).includes('"basis":"statement"')) {
    return 'Rows with basis "statement" follow read_guide("importing-statements") or a prompt built on it; this guide_key is from "' + chapter + '".' + then
  }
  return null
}
