#!/usr/bin/env node
// history-guard — nothing shipped may read as "we changed X": no user has seen a prior
// version. Flags: --range A..B, --staged, or --full (every tracked file). Default
// origin/main..HEAD. Same shape as leak-check.mjs.
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const args = process.argv.slice(2)
const opt = (n) => {
  const i = args.indexOf(n)
  return i !== -1 ? args[i + 1] : undefined
}

const git = (a) => execFileSync('git', a, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })

// A rule's own pattern text necessarily contains its own trigger phrases — never scan this
// file against its own rules, in any mode.
const SELF = 'scripts/history-guard.mjs'

// The reserved former name has its own guard (name-guard.mjs) and is not repeated here.
const RULES = [
  {
    id: 'rename-narration',
    why: 'narrates a rename — invisible history to every reader',
    re: /\b(the rename|pre-rename|post-rename|renamed (it|the app|itself|from|to))\b/i,
  },
  {
    id: 'history-narration',
    why: 'implies the reader lived through a prior version — nobody has',
    re: /\b(used to be|no longer (called|named)|formerly (known as|named|called)|migrated from|the old (version|name)|previously (called|named|known as))\b/i,
  },
  {
    id: 'pricing-narration',
    why: 'narrates a price change — no reader has seen an earlier price',
    re: /\b(was \$\d+|used to cost \$?\d+|no longer \$\d+|the (old|previous|earlier) price|price (changed|moved|dropped|rose|went) (from|to))\b/i,
  },
  {
    id: 'model-narration',
    why: 'narrates a business-model switch — the product has always worked this way',
    re: /\b(used to be free|no longer free|moved (from|to) (a|the) (free|support|paid) model|switched (from|to) a (free|support|paid) model|introduced (a )?paywall|added (a )?paywall|now requires payment)\b/i,
  },
]

// ---- what are we scanning? -------------------------------------------------

let range = opt('--range')
const staged = args.includes('--staged')
const full = args.includes('--full')
if (!range && !staged && !full) {
  try {
    git(['rev-parse', '--verify', '--quiet', 'origin/main'])
    range = 'origin/main..HEAD'
  } catch {
    console.error('history-guard — no origin/main to compare against. Pass --range, --staged, or --full.')
    process.exit(2)
  }
}

const findings = []

if (full) {
  // Every tracked, non-binary file, ON DISK right now — including uncommitted edits, since a
  // sweep exists to be run mid-cleanup, not just against whatever HEAD happens to say. Not the
  // normal mode: slow and noisy is fine once, wrong for every commit.
  const files = git(['ls-files']).trim().split('\n').filter(Boolean)
  for (const file of files) {
    if (file === SELF) continue
    let text
    try {
      text = readFileSync(file, 'utf8')
    } catch {
      continue // deleted-but-still-listed race, or unreadable
    }
    if (text.includes('\x00')) continue // binary
    const lines = text.split('\n')
    lines.forEach((line, i) => {
      for (const r of RULES) {
        if (r.exempt?.includes(file)) continue
        if (r.re.test(line)) findings.push({ file, line: i + 1, rule: r, text: line.trim().slice(0, 120) })
      }
    })
  }
} else {
  const diff = staged ? git(['diff', '--cached']) : git(['diff', range])
  const scanTargetLabel = staged ? 'staged changes' : range
  if (!diff.trim()) {
    console.log(`history-guard — nothing to scan (${scanTargetLabel} is empty).`)
    process.exit(0)
  }
  let file = null
  for (const line of diff.split('\n')) {
    if (line.startsWith('+++ b/')) { file = line.slice(6); continue }
    if (!line.startsWith('+') || line.startsWith('+++')) continue
    if (file === SELF) continue
    const text = line.slice(1)
    for (const r of RULES) {
      if (r.exempt?.includes(file)) continue
      if (r.re.test(text)) findings.push({ file, rule: r, text: text.trim().slice(0, 120) })
    }
  }
}

// ---- commit messages, same as leak-check --------------------------------
const messageFindings = []
if (!staged && !full) {
  const log = git(['log', '--format=%H%x00%B%x01', range])
  for (const entry of log.split('\x01')) {
    if (!entry.trim()) continue
    const [sha, body] = entry.split('\0')
    for (const r of RULES) {
      if (r.re.test(body)) messageFindings.push({ sha: sha.trim().slice(0, 8), rule: r })
    }
  }
}

// ---- report ----------------------------------------------------------------
if (findings.length === 0 && messageFindings.length === 0) {
  console.log(`history-guard — clean (${full ? 'full tree' : staged ? 'staged changes' : range}).`)
  process.exit(0)
}

console.error(`\n  history-guard — REFUSING.\n`)

if (messageFindings.length) {
  console.error(`  ${messageFindings.length} commit MESSAGE(s) matched a rule:\n`)
  for (const m of messageFindings) console.error(`      ${m.sha}  [${m.rule.id}] ${m.rule.why}`)
  console.error('')
}

if (findings.length) {
  console.error(`  ${findings.length} line(s) matched a rule:\n`)
  for (const f of findings) {
    const where = f.line ? `${f.file}:${f.line}` : f.file
    console.error(`      ${where}`)
    console.error(`        [${f.rule.id}] ${f.rule.why}`)
    console.error(`        ${f.text}\n`)
  }
}

console.error('  Reword it so it reads as day one, not a change log. Never --no-verify.\n')
process.exit(1)
