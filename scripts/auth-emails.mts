#!/usr/bin/env -S npx tsx
// The two sign-in emails Supabase Auth sends, made from one design and kept in supabase/auth-emails.
// Run: npm run auth-emails, with --check, --preview, --verify, --deploy or --restore <file>;
// supabase/auth-emails/README.md says what each does.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { AUTH_EMAILS, CODE, LINK, htmlOf, type AuthEmail } from './auth-emails/templates.mts'
import { differences, lifetimeProblem, otherChanges, restoreFields, same, type Config } from './auth-emails/live.mts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const DIR = join(ROOT, 'supabase/auth-emails')
const PROJECT_REF = 'xbrnijgctmovoqbbmgmb'
const API = `https://api.supabase.com/v1/projects/${PROJECT_REF}/config/auth`

const arg = (name: string): boolean => process.argv.includes(name)
const after = (name: string): string | undefined => {
  const i = process.argv.indexOf(name)
  const next = process.argv[i + 1]
  return i >= 0 && next && !next.startsWith('--') ? next : undefined
}
const fail = (message: string): never => {
  console.error(message)
  process.exit(1)
}

/** The four settings the emails live in: a subject and a template for each. */
const FIELDS = AUTH_EMAILS.flatMap((e) => [`mailer_subjects_${e.key}`, `mailer_templates_${e.key}_content`])

/** Only Supabase's own placeholders may appear, each where the email expects it. */
function assertPlaceholders(email: AuthEmail, html: string): void {
  const found = html.match(/\{\{[^}]*\}\}/g) ?? []
  if (JSON.stringify(found) !== JSON.stringify(email.placeholders)) {
    throw new Error(`${email.file} holds ${JSON.stringify(found)}, expected ${JSON.stringify(email.placeholders)}`)
  }
  if (html.replace(/\{\{[^}]*\}\}/g, '').match(/\{\{|\}\}/)) throw new Error(`${email.file} holds a stray double brace`)
}

// Made only by the modes that need them, so putting the old ones back never depends on this.
function generate(): { email: AuthEmail; html: string }[] {
  return AUTH_EMAILS.map((email) => {
    const html = htmlOf(email)
    assertPlaceholders(email, html)
    return { email, html }
  })
}

const wantedOf = (made: { email: AuthEmail; html: string }[]): Record<string, string> =>
  Object.fromEntries(made.flatMap(({ email, html }) => [[`mailer_subjects_${email.key}`, email.subject], [`mailer_templates_${email.key}_content`, html]]))

function token(): string {
  const env = process.env.SUPABASE_ACCESS_TOKEN
  if (env) return env.trim()
  const cli = join(homedir(), '.supabase/access-token')
  if (existsSync(cli)) return readFileSync(cli, 'utf8').trim()
  return fail('No Supabase access token. Set SUPABASE_ACCESS_TOKEN, or run: npx supabase login')
}

const call = (init: RequestInit = {}): Promise<Response> =>
  fetch(API, {
    ...init,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    signal: AbortSignal.timeout(20_000),
  })

async function readLive(): Promise<Config> {
  const res = await call().catch((e: Error) => fail(`Could not reach the project: ${e.message}`))
  if (!res.ok) return fail(`Could not read the live auth settings: ${res.status} ${res.statusText}`)
  return (await res.json()) as Config
}

/** Sets the four settings. If the answer is lost or refused, the live state is not assumed. */
async function patch(fields: Record<string, string>, undo: string): Promise<void> {
  const res = await call({ method: 'PATCH', body: JSON.stringify(fields) }).catch((e: Error) =>
    fail(`The update got no answer (${e.message}), so it may or may not have applied. Check with: npm run auth-emails -- --verify\n${undo}`))
  if (!res.ok) fail(`The update was refused: ${res.status} ${(await res.text()).slice(0, 300)}\n${undo}`)
}

if (arg('--check')) {
  const drift = generate().filter(({ email, html }) => {
    const p = join(DIR, email.file)
    return !existsSync(p) || readFileSync(p, 'utf8') !== html
  })
  if (drift.length) fail(`auth emails — ${drift.map((d) => d.email.file).join(', ')} is not what the generator makes. Run: npm run auth-emails`)
  console.log(`auth emails — in sync: ${AUTH_EMAILS.length} templates.`)
} else if (arg('--preview')) {
  const out = resolve(after('--preview') ?? join(tmpdir(), 'longbook-auth-emails'))
  mkdirSync(out, { recursive: true })
  for (const { email, html } of generate()) {
    writeFileSync(join(out, email.file.replace('.html', '.preview.html')), html.replace(CODE, '48291057').replace(LINK, 'https://longbook.app/'))
  }
  console.log(`written to ${out} — open the .html files in a browser. Nothing was sent.`)
} else if (arg('--verify')) {
  const live = await readLive()
  const drift = differences(live, wantedOf(generate()))
  const problem = lifetimeProblem(live)
  if (problem) console.error(`  ${problem}`)
  if (drift.length) console.error(`  live differs from the generator in: ${drift.join(', ')}`)
  if (drift.length || problem) process.exit(1)
  console.log('auth emails — the live project holds exactly these subjects and templates.')
} else if (arg('--deploy')) {
  const wanted = wantedOf(generate())
  const before = await readLive()
  const problem = lifetimeProblem(before)
  if (problem) fail(`Not deploying: ${problem}.`)
  const drift = differences(before, wanted)
  if (!drift.length) {
    console.log('auth emails — nothing to change; the live project already holds these.')
    process.exit(0)
  }
  const saved = join(tmpdir(), `longbook-auth-emails-before-${Date.now()}.json`)
  writeFileSync(saved, JSON.stringify(Object.fromEntries(FIELDS.map((f) => [f, before[f]])), null, 1))
  const undo = `To undo: npm run auth-emails -- --restore ${saved}`
  console.log(`saved what is live now to ${saved}`)
  await patch(wanted, undo)
  const now = await readLive()
  const still = differences(now, wanted)
  if (still.length) fail(`Read back, the live project still differs in: ${still.join(', ')}.\n${undo}`)
  const strays = otherChanges(before, now, FIELDS)
  if (strays.length) fail(`Deployed, but these other settings changed too: ${strays.join(', ')}.\n${undo}`)
  console.log(`deployed: ${drift.join(', ')}. Read back, every one matches, and no other setting moved.`)
  console.log(undo)
} else if (arg('--restore')) {
  const file = after('--restore')
  if (!file) fail('Name the file --deploy saved: npm run auth-emails -- --restore <file>')
  const fields = restoreFields(JSON.parse(readFileSync(resolve(file!), 'utf8')), FIELDS)
  if (typeof fields === 'string') fail(fields)
  await patch(fields as Record<string, string>, 'The live project is unchanged by this attempt only if the answer was a refusal.')
  const live = await readLive()
  const bad = FIELDS.filter((f) => !same(live[f], (fields as Record<string, string>)[f]!))
  if (bad.length) fail(`Restored, but the live project still differs in: ${bad.join(', ')}`)
  console.log('restored: the live project holds what the file held.')
} else {
  mkdirSync(DIR, { recursive: true })
  let written = 0
  for (const { email, html } of generate()) {
    const p = join(DIR, email.file)
    if (existsSync(p) && readFileSync(p, 'utf8') === html) continue
    writeFileSync(p, html)
    written++
  }
  console.log(`auth emails — wrote ${written} file(s) in supabase/auth-emails.`)
}
