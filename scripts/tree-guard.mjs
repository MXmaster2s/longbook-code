#!/usr/bin/env node
// tree-guard — refuse to work in a tree with somebody else's changes in it.
//   node scripts/tree-guard.mjs [--scope path] [--repo path]
// Uncommitted work has twice been swept into an unrelated commit. `--scope` says
// "dirt here is mine." EXIT: 0 clean, 1 dirty outside scope, 2 not a git repo.
import { execFileSync } from 'node:child_process'
import { resolve } from 'node:path'

const args = process.argv.slice(2)
const scopes = []
let repo = process.cwd()
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--scope' && args[i + 1]) scopes.push(args[++i].replace(/\/+$/, ''))
  else if (args[i] === '--repo' && args[i + 1]) repo = resolve(args[++i])
}

const git = (a) => execFileSync('git', a, { cwd: repo, encoding: 'utf8' }).trim()

let porcelain
try {
  // -z and NUL splitting: a filename with a space in it is not exotic here — this workspace has
  // "my project" in its own path — and line-splitting `git status` would mangle one silently.
  porcelain = execFileSync('git', ['status', '--porcelain', '-z'], { cwd: repo, encoding: 'utf8' })
} catch {
  console.error(`tree-guard — ${repo} is not a git repository.`)
  process.exit(2)
}

/** Parse `--porcelain -z`. Renames/copies emit TWO NUL-terminated fields: status+new, then old. */
function parse(z) {
  const out = []
  const parts = z.split('\0')
  for (let i = 0; i < parts.length; i++) {
    const entry = parts[i]
    if (!entry) continue
    const code = entry.slice(0, 2)
    const path = entry.slice(3)
    out.push({ code, path })
    // A rename carries its source path in the next field; consume it so it is never read as an entry.
    if (code[0] === 'R' || code[0] === 'C') i++
  }
  return out
}

const entries = parse(porcelain)
const inScope = (p) => scopes.some((s) => p === s || p.startsWith(`${s}/`))
const foreign = entries.filter((e) => !inScope(e.path))

const label = scopes.length ? ` outside ${scopes.join(', ')}` : ''

if (foreign.length === 0) {
  const mine = entries.length - foreign.length
  console.log(
    `tree-guard — clean${label}.${mine ? ` ${mine} change(s) inside scope, which are yours.` : ''}`,
  )
  process.exit(0)
}

console.error(`\n  tree-guard — REFUSING: ${foreign.length} change(s)${label} you did not make.\n`)
for (const e of foreign) console.error(`      ${e.code}  ${e.path}`)
console.error(`
  These are somebody else's in-progress work. Committing them would put their changes inside a
  commit whose message describes yours — which has happened here before, and shipped.

  What to do:
    · Leave them alone and stage YOUR files by explicit path — never 'git add -A'.
    · If you are a scheduled run: stop, and report the dirty tree. Do not guess whose it is.
    · If they are genuinely yours: re-run with --scope <path>, or commit them separately first.
`)
process.exit(1)
