// The curriculum as chapters: llms.txt splits on its "## " headings so a server can hand
// back one chapter by name, and every contract file names its revision so two copies
// can be ordered — the vault's against the bundle's.
import { PROMPTS, promptKey } from './prompts'

export interface GuideSection {
  id: string
  title: string
  text: string
}

/** "contract_revision": 9 in JSON, "contract revision 9" in text; null when unmarked. */
export function contractRevisionOf(text: string): number | null {
  const m = /"contract_revision":\s*(\d+)/.exec(text) ?? /contract revision (\d+)/i.exec(text)
  return m ? Number(m[1]) : null
}

/** "The working method" → working-method; the part before " — " or ":" names the chapter. */
export function guideSlug(title: string): string {
  return title
    .split(/ — |: /)[0]!
    .toLowerCase()
    .replace(/^the\s+/, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

export function guideSections(llms: string): GuideSection[] {
  const out: GuideSection[] = []
  const parts = llms.split(/^## /m)
  for (const part of parts.slice(1)) {
    const newline = part.indexOf('\n')
    const title = (newline === -1 ? part : part.slice(0, newline)).trim()
    const body = newline === -1 ? '' : part.slice(newline + 1)
    out.push({ id: guideSlug(title), title, text: `## ${title}\n${body}`.trimEnd() + '\n' })
  }
  return out
}

/**
 * Every word a prompt answers to — its id, title, phrases, template and aliases, keyed as
 * promptKey keys them — sent to the chapter it builds on. The legacy phrases ("setup my
 * longbook", "import my statements") are aliases in the catalogue.
 */
const PROMPT_CHAPTERS: ReadonlyMap<string, string> = (() => {
  const table = new Map<string, string>()
  for (const prompt of PROMPTS) {
    if (!prompt.chapter) continue
    const words = [prompt.id, prompt.title, ...prompt.phrases, ...(prompt.template ? [prompt.template] : []), ...(prompt.aliases ?? [])]
    for (const w of words) {
      const key = promptKey(w)
      if (key && !table.has(key)) table.set(key, prompt.chapter)
    }
  }
  return table
})()

/**
 * Exact id first, then a prompt's words, month name and all, then the first chapter whose id
 * or title contains the words asked for, then the first whose id the words contain.
 */
export function guideSection(llms: string, query: string): GuideSection | null {
  const sections = guideSections(llms)
  const slug = guideSlug(query)
  if (!slug) return null
  const wanted = sections.some((s) => s.id === slug) ? slug : (PROMPT_CHAPTERS.get(promptKey(query)) ?? slug)
  return (
    sections.find((s) => s.id === wanted) ??
    sections.find((s) => s.id.includes(wanted) || s.title.toLowerCase().includes(query.trim().toLowerCase())) ??
    sections.find((s) => wanted.includes(s.id)) ??
    null
  )
}

/** FNV-1a over the words, in base 36: short, the same on every door, and gone when a word changes. */
function wordsHash(text: string): string {
  let h = 0x811c9dc5
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 0x01000193)
  return (h >>> 0).toString(36)
}

/**
 * The key read_guide hands out with a chapter or a prompt, "importing-statements:44:1x9k2a":
 * what was read, the rulebook it was read in, and a hash of its words. A write passes it
 * back, so a write that skipped the guide can be told which chapter to read.
 */
export function guideKey(id: string, revision: number | null, words: string): string {
  return `${id}:${revision ?? 0}:${wordsHash(words)}`
}

/** A prompt's key: its procedure is what the owner's AI reads, from read_guide or the prompt itself. */
export function promptGuideKey(prompt: { id: string; procedure: string[] }, revision: number | null): string {
  return guideKey(prompt.id, revision, prompt.procedure.join('\n'))
}

/** The whole guide read at once counts for every chapter. */
export const WHOLE_GUIDE = 'guide'

/**
 * Every key this guide hands out, to the chapter each one counts for: a chapter's own, a
 * prompt's chapter (or the prompt itself when it builds on none), and the whole guide's.
 */
export function guideKeys(llms: string): Map<string, string> {
  const revision = contractRevisionOf(llms)
  const keys = new Map<string, string>([[guideKey(WHOLE_GUIDE, revision, llms), WHOLE_GUIDE]])
  for (const s of guideSections(llms)) keys.set(guideKey(s.id, revision, s.text), s.id)
  for (const p of PROMPTS) keys.set(promptGuideKey(p, revision), p.chapter ?? p.id)
  return keys
}
