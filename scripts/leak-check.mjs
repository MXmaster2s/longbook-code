#!/usr/bin/env node
// leak-check — scan what you're about to push to PUBLIC for things that must never be in
// it. Flags: --range A..B, --staged; default origin/main..HEAD.
//
// This repo is public; `team/` is private. THE TRAP: hardcoding forbidden strings IS the
// leak. Every pattern is STRUCTURAL or DERIVED AT RUNTIME.
import { execFileSync } from 'node:child_process'
import { homedir } from 'node:os'
import { basename } from 'node:path'

const args = process.argv.slice(2)
const opt = (n) => {
  const i = args.indexOf(n)
  return i !== -1 ? args[i + 1] : undefined
}

const git = (a) => execFileSync('git', a, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })

/** The pseudonymous identity every public commit must carry. Not a secret — it is already on every
 *  commit in the public history — so unlike the patterns below, this one may be a literal. */
const EXPECTED_EMAIL = '56468426+MXmaster2s@users.noreply.github.com'

// The account name, derived from the home directory rather than written down. On this machine it is
// also a recognisable form of the owner's real name, which is precisely why it must not appear in a
// public file — including this one.
const ACCOUNT = basename(homedir())

const RULES = [
  {
    id: 'home-path',
    why: 'an absolute path from this machine — it names the account, and it breaks on anyone else’s',
    // Built at runtime from ACCOUNT, so the string never appears in this file.
    re: new RegExp(`/Users/${ACCOUNT.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i'),
  },
  { id: 'any-user-path', why: 'an absolute /Users/ path — machine-specific, and usually a name', re: /\/Users\/[A-Za-z0-9._-]+\//, },
  // NOT a rule: the iCloud container identifier, derived from the public bundle id and
  // shipped in main.ts and VaultContainer.swift. An earlier version flagged it and caught
  // ITSELF — a guard firing on correct code teaches --no-verify. The ACCOUNT rules above
  // catch what's actually sensitive.
  { id: 'home-tilde-path', why: 'a ~/ path into a personal Library — a real location on someone’s machine', re: /~\/Library\/(Mobile Documents|Application Support)/i },
  { id: 'private-repo', why: 'a path inside the PRIVATE team vault', re: /(^|[\s"'`(/])team\/(CTO|CMO|CDO|CSO|Product Analyst|Release Manager|Handoffs)\//, },
  {
    id: 'ai-trailer',
    why: 'an AI attribution line, a session link included — the owner’s identity alone goes on commits and pull requests',
    re: /Co-Authored-By:\s*(Claude|Anthropic|GPT|Copilot)|Claude-Session\s*:|Generated (with|by) \[?Claude Code|claude\.ai\/code\/session_/i,
  },
  { id: 'private-key', why: 'a private key block', re: /-----BEGIN [A-Z ]*PRIVATE KEY-----/ },
  { id: 'token', why: 'something shaped like a live credential', re: /\b(gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|phx_[A-Za-z0-9]{20,})\b/ },
  {
    id: 'team-register',
    why: 'internal team vocabulary — comments and commit messages describe the code, never the process',
    // Role acronyms are case-sensitive and word-bounded; "owner" alone is never flagged.
    // This file is exempt since the patterns must name what they refuse; the generated
    // server bundles are exempt because minified pdf.js carries operator tokens like RM.
    re: /\bhandoffs?\b|\b(CTO|CDO|CMO|CSO|RM|PA)\b|owner['’]s (rule|ruling|call|decision|instruction)/,
    exempt: [
      'scripts/leak-check.mjs',
      'apps/longbook/Resources/longbook-mcp.mjs',
      'packages/mcp/bin/longbook-mcp.mjs',
    ],
  },
  {
    id: 'internal-reference',
    why: 'a bare #NN — in a message that is always a reference to an internal document',
    // MESSAGES ONLY. In code, `#NN` is legitimate: `&#39;` is an apostrophe, `#000` a
    // colour — refusing those teaches --no-verify. In commit messages there is no such
    // use, so the rule applies exactly where the evidence supports it.
    messageOnly: true,
    re: /(^|\s)#\d{1,3}\b/,
  },
]

/** GitHub's own auto-generated merge-commit preamble: "Merge pull request #NN from
 *  owner/branch". Always carries a bare #NN — the exact shape internal-reference exists to
 *  catch — but it names a PR, not an internal document. Structural, not a hardcoded exception. */
const GITHUB_MERGE_PREAMBLE = /^Merge pull request #\d+ from \S+\n?/

// ---- what are we scanning? -------------------------------------------------

let range = opt('--range')
const staged = args.includes('--staged')
if (!range && !staged) {
  try {
    git(['rev-parse', '--verify', '--quiet', 'origin/main'])
    range = 'origin/main..HEAD'
  } catch {
    console.error('leak-check — no origin/main to compare against. Pass --range or --staged.')
    process.exit(2)
  }
}

const diff = staged ? git(['diff', '--cached']) : git(['diff', range])
const scanTargetLabel = staged ? 'staged changes' : range

const prText = [
  ['title', process.env.PR_TITLE],
  ['description', process.env.PR_BODY],
].filter(([, text]) => text)

if (!diff.trim() && !prText.length) {
  console.log(`leak-check — nothing to scan (${scanTargetLabel} is empty).`)
  process.exit(0)
}

// ---- scan the ADDED lines only ---------------------------------------------
//
// Removed lines are already public — flagging them would fail every commit that DELETES a leak,
// which is the one commit you most want to be able to make.
const findings = []
let file = null
for (const line of diff.split('\n')) {
  if (line.startsWith('+++ b/')) { file = line.slice(6); continue }
  if (!line.startsWith('+') || line.startsWith('+++')) continue
  const text = line.slice(1)
  for (const r of RULES) {
    if (r.messageOnly || r.exempt?.includes(file)) continue
    if (r.re.test(text)) findings.push({ file, rule: r, text: text.trim().slice(0, 120) })
  }
}

// ---- scan the COMMIT MESSAGES too ------------------------------------------
//
// A message publishes exactly like a file, but no diff contains it — without this a clean
// tree could still push a message breaking every rule above. Same rules, no exemptions.
const messageFindings = []
if (!staged) {
  const log = git(['log', '--format=%H%x00%B%x01', range])
  for (const entry of log.split('\x01')) {
    if (!entry.trim()) continue
    const [sha, body] = entry.split('\0')
    for (const r of RULES) {
      const text = r.id === 'internal-reference' ? body.replace(GITHUB_MERGE_PREAMBLE, '') : body
      if (r.re.test(text)) messageFindings.push({ sha: sha.trim().slice(0, 8), rule: r })
    }
  }
}

// ---- and the PULL REQUEST's title and description --------------------------
//
// CI passes them in as PR_TITLE and PR_BODY. They publish like a message, and a merge carries the
// title into history. Same rules, except internal-reference: there GitHub links a #NN to a PR.
const prFindings = []
for (const [label, text] of prText) {
  for (const r of RULES) {
    if (r.id !== 'internal-reference' && r.re.test(text)) prFindings.push({ label, rule: r })
  }
}

// ---- and check the messages are not essays ---------------------------------
//
// 50 words, same limit as a comment. Enforced at commit time by the commit-msg hook; repeated here
// because that hook is skippable and this runs on the range a push would send.
const MESSAGE_WORD_LIMIT = 50
const countWords = (s) =>
  s
    .split('\n')
    .filter((l) => !l.startsWith('#'))
    .join(' ')
    .split(/\s+/)
    .filter((t) => /[\p{L}\p{N}]/u.test(t)).length

const longMessages = []
if (!staged) {
  const log = git(['log', '--format=%H%x00%B%x01', range])
  for (const entry of log.split('\x01')) {
    if (!entry.trim()) continue
    const [sha, body] = entry.split('\0')
    const n = countWords(body ?? '')
    if (n > MESSAGE_WORD_LIMIT) longMessages.push({ sha: sha.trim().slice(0, 8), n })
  }
}

// ---- and check who authored and committed them -----------------------------
//
// GitHub commits the merges it makes itself, under its own no-reply address.
const GITHUB_COMMITTER = 'noreply@github.com'
const authorProblems = []
if (!staged) {
  const rows = git(['log', '--format=%H%x00%an%x00%ae%x00%cn%x00%ce', range]).trim()
  for (const row of rows ? rows.split('\n') : []) {
    const [sha, name, email, committer, committerEmail] = row.split('\0')
    const short = sha.slice(0, 8)
    if (email !== EXPECTED_EMAIL) authorProblems.push({ sha: short, role: 'author', name, email })
    if (committerEmail !== EXPECTED_EMAIL && committerEmail !== GITHUB_COMMITTER) {
      authorProblems.push({ sha: short, role: 'committer', name: committer, email: committerEmail })
    }
  }
}

// ---- report ----------------------------------------------------------------
if (
  findings.length === 0 &&
  messageFindings.length === 0 &&
  prFindings.length === 0 &&
  longMessages.length === 0 &&
  authorProblems.length === 0
) {
  console.log(`leak-check — clean (${scanTargetLabel}).`)
  process.exit(0)
}

console.error(`\n  leak-check — REFUSING (${scanTargetLabel}).\n`)

if (messageFindings.length) {
  console.error(`  ${messageFindings.length} commit MESSAGE(s) matched a rule:\n`)
  for (const m of messageFindings) {
    console.error(`      ${m.sha}  [${m.rule.id}] ${m.rule.why}`)
  }
  console.error(`        (messages withheld — git log will show them; reword with git commit --amend / rebase)\n`)
}

if (prFindings.length) {
  console.error(`  The pull request's text matched a rule:\n`)
  for (const p of prFindings) console.error(`      ${p.label}  [${p.rule.id}] ${p.rule.why}`)
  console.error(`        (text withheld — edit the pull request on GitHub)\n`)
}

if (findings.length) {
  console.error(`  ${findings.length} line(s) matched a rule:\n`)
  for (const f of findings) {
    console.error(`      ${f.file}`)
    console.error(`        [${f.rule.id}] ${f.rule.why}`)
    // The matching line is NOT printed. It is the thing we are trying not to publish, and this
    // output ends up in terminal scrollback, CI logs and pasted screenshots.
    console.error(`        (line withheld — open the file and look)\n`)
  }
}

if (longMessages.length) {
  console.error(`  ${longMessages.length} commit MESSAGE(s) over ${MESSAGE_WORD_LIMIT} words:\n`)
  for (const m of longMessages) console.error(`      ${m.sha}  ${m.n} words`)
  console.error('        (reword with git commit --amend, or rebase for older ones)\n')
}

if (authorProblems.length) {
  console.error(`  ${authorProblems.length} author or committer identities that are not the pseudonymous one:\n`)
  for (const a of authorProblems) console.error(`      ${a.sha}  ${a.role} ${a.name} <${a.email}>`)
  console.error('')
}

console.error(`  Nothing has been pushed. Fix the tree, or rewrite the commits, then run again.\n`)
process.exit(1)
