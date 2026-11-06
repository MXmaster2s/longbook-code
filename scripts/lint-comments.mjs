#!/usr/bin/env node
// lint-comments — no comment here may exceed 50 words.
//
// Flags: --staged, --report (longest first), --write-baseline.
//
// A comment is one contiguous run of line comments, or one block comment.
// Long rationale belongs in the vault; leave a pointer.
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { join, dirname, extname } from 'node:path'
import { fileURLToPath } from 'node:url'

const LIMIT = 50
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const BASELINE = join(ROOT, 'scripts', 'comment-length-baseline.json')

const args = process.argv.slice(2)
const staged = args.includes('--staged')
const report = args.includes('--report')
const writeBaseline = args.includes('--write-baseline')

const git = (a) => execFileSync('git', ['-C', ROOT, ...a], { encoding: 'utf8', maxBuffer: 64 << 20 })

const HASH = new Set(['.sh', '.bash', '.zsh', '.yml', '.yaml'])
const SLASH = new Set(['.ts', '.tsx', '.mts', '.js', '.jsx', '.mjs', '.cjs', '.swift', '.css'])
const ANGLE = new Set(['.html'])
const scannable = (f) => {
  const e = extname(f)
  return HASH.has(e) || SLASH.has(e) || ANGLE.has(e)
}

// Punctuation-only tokens are not words. An em dash between clauses should not cost the same as a
// sentence, and counting it does not make anything shorter — only harder to predict.
const words = (s) => s.split(/\s+/).filter((t) => /[\p{L}\p{N}]/u.test(t)).length

/**
 * Every comment in one file, as {line, words}.
 *
 * Block comments are found first and blanked out, so a slash-slash inside one is not counted twice.
 * A URL is one word however long it is, which is the point: the limit is about prose.
 */
function commentsIn(file, src) {
  const ext = extname(file)
  const found = []
  let rest = src

  if (!HASH.has(ext)) {
    const re = ANGLE.has(ext) ? /<!--([\s\S]*?)-->/g : /\/\*([\s\S]*?)\*\//g
    rest = src.replace(re, (whole, body, idx) => {
      const line = src.slice(0, idx).split('\n').length
      found.push({ line, words: words(body.replace(/^\s*\*/gm, ' ')) })
      return whole.replace(/[^\n]/g, ' ')
    })
  }

  // Contiguous line comments. A blank line, or any code, ends the run.
  const marker = HASH.has(ext) ? /^\s*#(?!!)(.*)$/ : /^\s*\/\/(.*)$/
  let run = null
  rest.split('\n').forEach((ln, i) => {
    const m = ln.match(marker)
    if (m) {
      if (!run) run = { line: i + 1, text: [] }
      run.text.push(m[1])
    } else if (run) {
      found.push({ line: run.line, words: words(run.text.join(' ')) })
      run = null
    }
  })
  if (run) found.push({ line: run.line, words: words(run.text.join(' ')) })

  return found.sort((a, b) => a.line - b.line)
}

// ---- which files ------------------------------------------------------------
let files = git(['ls-files']).split('\n').filter(Boolean).filter(scannable)
if (staged) {
  const s = new Set(
    git(['diff', '--cached', '--name-only', '--diff-filter=ACMR']).split('\n').filter(Boolean),
  )
  files = files.filter((f) => s.has(f))
}

const over = []
for (const f of files) {
  let src
  try {
    src = readFileSync(join(ROOT, f), 'utf8')
  } catch {
    continue
  }
  for (const c of commentsIn(f, src)) if (c.words > LIMIT) over.push({ file: f, ...c })
}

// ---- the ratchet ------------------------------------------------------------
//
// The baseline freezes whatever blocks exist when the rule tightens, so the limit binds
// immediately. It holds a COUNT per file, never a line number, because line numbers churn on
// every edit and a baseline that churns is one people stop trusting.
if (writeBaseline) {
  const counts = {}
  for (const o of over) counts[o.file] = (counts[o.file] ?? 0) + 1
  writeFileSync(BASELINE, `${JSON.stringify(counts, null, 2)}\n`)
  const total = Object.values(counts).reduce((a, b) => a + b, 0)
  console.log(`lint-comments — baseline written: ${total} blocks in ${Object.keys(counts).length} files.`)
  process.exit(0)
}

const baseline = existsSync(BASELINE) ? JSON.parse(readFileSync(BASELINE, 'utf8')) : {}

if (report) {
  for (const o of [...over].sort((a, b) => b.words - a.words)) {
    console.log(`${String(o.words).padStart(4)}w  ${o.file}:${o.line}`)
  }
  console.log(`\n${over.length} blocks over ${LIMIT} words.`)
  process.exit(0)
}

const byFile = {}
for (const o of over) (byFile[o.file] ??= []).push(o)

const fresh = []
for (const [file, list] of Object.entries(byFile)) {
  const allowed = baseline[file] ?? 0
  if (list.length > allowed) fresh.push({ file, allowed, now: list.length, at: list })
}

// A file that improved must not silently bank the credit — the baseline gets tightened instead.
const improved = Object.entries(baseline).filter(
  ([f, n]) => !staged && files.includes(f) && (byFile[f]?.length ?? 0) < n,
)

if (fresh.length === 0) {
  const scope = staged ? 'staged changes' : `${files.length} files`
  console.log(`lint-comments — clean (${scope}, limit ${LIMIT} words).`)
  if (improved.length) {
    console.log(`  ${improved.length} file(s) now have fewer — run --write-baseline to lock it in.`)
  }
  process.exit(0)
}

console.error(`\n  lint-comments — REFUSING. A comment may not exceed ${LIMIT} words.\n`)
for (const f of fresh) {
  const worst = f.at.filter((c) => c.words > LIMIT).sort((a, b) => b.words - a.words)
  console.error(`      ${f.file} — ${f.now} over-length block(s), ${f.allowed} allowed here`)
  for (const c of worst.slice(0, 5)) console.error(`        line ${c.line}: ${c.words} words`)
}
console.error(`
  Shorten it, or move the reasoning to the private vault and leave a pointer.
  Never pass --no-verify: that publishes the thing this refuses.
`)
process.exit(1)
