// A regression tripwire: no stylesheet may re-case our own words. ALL CAPS chrome is a
// violation, not typography — no `text-transform: uppercase|capitalize`.
//
// A RATCHET: existing violations are frozen in text-transform-baseline.json; a NEW
// transform not in the baseline fails the build.
//
// `lowercase` is out of scope — user data is never transformed.
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = fileURLToPath(new URL('..', import.meta.url))
const SKIP = new Set(['node_modules', '.next', 'dist-electron', 'dist-renderer', 'dist', '.git', 'build', 'out', '.expo'])
const EXT = /\.(css|ts|tsx|js|jsx|mjs)$/

const BASELINE_PATH = join(ROOT, 'scripts/text-transform-baseline.json')
const baseline = JSON.parse(readFileSync(BASELINE_PATH, 'utf8'))
// key "file::site" → how many times that site is tolerated in that file. See `siteOf`.
const tolerated = new Map(baseline.map((b) => [`${b.file}::${b.site}`, b.count ?? 1]))

/**
 * What identifies a tolerated violation: the rule, not the whole line it sits on.
 * Started as the trimmed line, which made the baseline lie on an unrelated contrast
 * fix. Now a single-line rule's site is its SELECTOR, stable across nearby edits.
 */
function siteOf(line) {
  const brace = line.indexOf('{')
  const selector = brace > 0 ? line.slice(0, brace).trim() : ''
  return selector || line
}

const files = []
;(function walk(dir) {
  for (const e of readdirSync(dir)) {
    if (SKIP.has(e)) continue
    const p = join(dir, e)
    if (statSync(p).isDirectory()) walk(p)
    else if (EXT.test(e)) files.push(p)
  }
})(ROOT)

/** Replace a comment with blanks, keeping newlines so line numbers still mean something. */
const blank = (m) => m.replace(/[^\n]/g, ' ')

const RE = [
  /text-transform\s*:\s*(uppercase|capitalize)/g, // CSS and CSS modules
  /textTransform\s*:\s*['"](uppercase|capitalize)['"]/g, // React Native style objects
]

const found = new Map() // "file::site" → { count, lines[] }
for (const file of files) {
  if (file === fileURLToPath(new URL('./lint-transform.mjs', import.meta.url))) continue
  const src = readFileSync(file, 'utf8')
  const code = src
    .replace(/\/\*[\s\S]*?\*\//g, blank) // block comments (CSS and JS alike) discuss the rule; they are not the rule being broken
    .replace(/(^|[^:])(\/\/[^\n]*)/g, (_, pre, c) => pre + blank(c))

  for (const re of RE) {
    for (const m of code.matchAll(re)) {
      const line = code.slice(0, m.index).split('\n').length
      const key = `${relative(ROOT, file)}::${siteOf((code.split('\n')[line - 1] ?? '').trim())}`
      const entry = found.get(key) ?? { count: 0, lines: [] }
      entry.count += 1
      entry.lines.push(line)
      found.set(key, entry)
    }
  }
}

let fresh = 0
for (const [key, { count, lines }] of [...found].sort()) {
  const allowed = tolerated.get(key) ?? 0
  if (count > allowed) {
    fresh += count - allowed
    const [file, site] = key.split('::')
    console.error(`${file}:${lines.join(',')}  NEW transform on our own words  ${site}`)
  }
}
for (const key of tolerated.keys()) {
  if (!found.has(key)) console.error(`stale baseline entry (violation fixed — shrink the baseline): ${key}`)
}

const frozen = [...found.values()].reduce((a, e) => a + e.count, 0) - fresh
console.error(`\nlint:transform — ${fresh} new violation(s); ${frozen} frozen in baseline awaiting the deferred cleanup pass.`)
process.exit(fresh ? 1 : 0)
