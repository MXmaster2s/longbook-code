// Website-only text in the help articles. An article whose first line is `<!-- website-only -->`,
// above its `# Title`, is website-only as a whole. Lines between `<!-- website-only -->` and
// `<!-- /website-only -->`, each marker on its own line, are a website-only block.
// App Store builds, and Support answering them, never see website-only text.

export const OPEN = '<!-- website-only -->'
export const CLOSE = '<!-- /website-only -->'

const isMarker = (line: string): boolean => line.trim() === OPEN || line.trim() === CLOSE

/** True when the article, as written, is website-only as a whole. */
export const wholeArticleWebsiteOnly = (text: string): boolean => text.split('\n')[0]!.trim() === OPEN

/** Checks the markers pair up and never nest; returns the problems, empty when sound. */
export function markerProblems(text: string, file: string): string[] {
  const lines = text.split('\n')
  const problems: string[] = []
  let open = -1
  lines.forEach((line, i) => {
    if (i === 0 && wholeArticleWebsiteOnly(text)) return
    if (line.trim() === OPEN) {
      if (open >= 0) problems.push(`${file}:${i + 1}: website-only block opened inside another`)
      open = i
    } else if (line.trim() === CLOSE) {
      if (open < 0) problems.push(`${file}:${i + 1}: website-only block closed without opening`)
      open = -1
    } else if (line.includes('website-only')) {
      problems.push(`${file}:${i + 1}: a website-only marker must sit alone on its line`)
    }
  })
  if (open >= 0) problems.push(`${file}:${open + 1}: website-only block never closed`)
  return problems
}

/** The full text, as the website shows it: every marker line removed, nothing else. */
export const fullText = (text: string): string => text.split('\n').filter((l) => !isMarker(l)).join('\n')

/** The text for App Store builds: website-only blocks removed, or null for a website-only article. */
export function restrictedText(text: string): string | null {
  if (wholeArticleWebsiteOnly(text)) return null
  const out: string[] = []
  let inside = false
  let removed = false
  for (const line of text.split('\n')) {
    if (line.trim() === OPEN) { inside = true; continue }
    if (line.trim() === CLOSE) { inside = false; removed = true; continue }
    if (inside) continue
    // A removed block between two blank lines leaves one blank line, not two.
    if (removed && line.trim() === '' && out.length && out[out.length - 1]!.trim() === '') { removed = false; continue }
    removed = false
    out.push(line)
  }
  return out.join('\n')
}
