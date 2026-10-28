#!/usr/bin/env -S npx tsx
// Fills review@longbook.app's hosted copy with the made-up demo household, for directory
// reviewers connecting https://longbook.app/mcp. Signs in through review-sign-in with the code in
// the keychain, switches suggestions on, and reads the copy back. Never prints the code.

// This account is the directory reviewers' alone: review:account never touches it or its Cloud.
// review-sign-in opens only while its grant stands, so --grant-cloud keeps that grant.
// Run: npm run review:mcp-data [-- --household us|in] [--grant-cloud] [--dry-run]
import { execFileSync } from 'node:child_process'
import { randomInt } from 'node:crypto'
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { REVIEW_GRANT_NOTE } from '../supabase/functions/review-sign-in/check.ts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const PROJECT_REF = 'xbrnijgctmovoqbbmgmb'
const SUPABASE = `https://${PROJECT_REF}.supabase.co`
// The public anon key every client ships (the app, the consent page); RLS and the account's own
// session are the boundary.
const ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhicm5pamdjdG1vdm9xYmJtZ21iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU3NzQ0NDQsImV4cCI6MjEwMTM1MDQ0NH0.ZamrPyf3UmAmbqzzAcce_Ocb1bKNq19wVxTtaC32a-g'
const MCP_URL = 'https://longbook.app/mcp'
/** Must match the REVIEW_EMAIL secret review-sign-in reads, and REVIEW_ADDRESS on the consent page. */
const EMAIL = 'review@longbook.app'
/** The fixed sign-in code; the REVIEW_CODE secret holds the same value. */
const KEYCHAIN_SERVICE = 'longbook directory review sign-in code'
const GRANT_DAYS = 120

const argv = process.argv.slice(2)
const DRY = argv.includes('--dry-run')
const GRANT = argv.includes('--grant-cloud')
const householdAt = argv.indexOf('--household')
const HOUSEHOLD = householdAt >= 0 ? argv[householdAt + 1] : 'us'

const fail = (message: string): never => {
  console.error(message)
  process.exit(1)
}
if (HOUSEHOLD !== 'us' && HOUSEHOLD !== 'in') fail('--household is us or in.')

// ---- the household, from the same script the screenshots use --------------------------------

const folder = mkdtempSync(join(tmpdir(), 'longbook-review-household-'))
rmSync(folder, { recursive: true })
execFileSync('npx', ['tsx', join(ROOT, 'scripts/demo-vault.mts'), folder, ...(HOUSEHOLD === 'us' ? ['--household', 'us'] : [])], {
  cwd: ROOT,
  stdio: ['ignore', 'ignore', 'inherit'],
})
const memory = JSON.parse(readFileSync(join(folder, 'financial_memory.json'), 'utf8')) as {
  commitments: unknown[]
  charges: unknown[]
  members: unknown[]
  accounts: unknown[]
}
rmSync(folder, { recursive: true, force: true })
const counts = `${memory.commitments.length} commitments, ${memory.charges.length} charges, ${memory.members.length} people, ${memory.accounts.length} accounts`
console.log(`✓ demo household (${HOUSEHOLD}): ${counts}; every name and amount is made up`)
if (DRY) {
  console.log('dry run: nothing signed in to, nothing written.')
  process.exit(0)
}

// ---- the code, and Cloud, which both the sign-in and the hosted copy need -------------------

const keychain = (): string | null => {
  try {
    return execFileSync('security', ['find-generic-password', '-s', KEYCHAIN_SERVICE, '-a', EMAIL, '-w'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim()
  } catch {
    return null
  }
}
let code = keychain()
if (!code) {
  execFileSync('security', ['add-generic-password', '-s', KEYCHAIN_SERVICE, '-a', EMAIL, '-w', String(randomInt(0, 100_000_000)).padStart(8, '0')])
  fail(
    `A new code is in the keychain as "${KEYCHAIN_SERVICE}". Give it to review-sign-in, then run this again:\n` +
      `  npx supabase secrets set --project-ref ${PROJECT_REF} REVIEW_CODE="$(security find-generic-password -s '${KEYCHAIN_SERVICE}' -w)"`,
  )
}

const rpc = async (fn: string, args: Record<string, unknown>, headers: Record<string, string>): Promise<unknown> => {
  const res = await fetch(`${SUPABASE}/rest/v1/rpc/${fn}`, { method: 'POST', headers, body: JSON.stringify(args), signal: AbortSignal.timeout(20_000) })
  return res.ok ? res.json() : null
}

if (GRANT) {
  const env = process.env.SUPABASE_ACCESS_TOKEN?.trim()
  const cli = join(homedir(), '.supabase/access-token')
  const token = env || (existsSync(cli) ? readFileSync(cli, 'utf8').trim() : fail('No Supabase access token. Set SUPABASE_ACCESS_TOKEN, or run: npx supabase login'))
  // A longer grant already in place is kept; the note is the one review-sign-in asks for.
  const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      query: `insert into public.cloud_grants (user_id, until, note)
          select id, now() + interval '${GRANT_DAYS} days', '${REVIEW_GRANT_NOTE}' from auth.users where email = '${EMAIL}'
        on conflict (user_id) do update set until = greatest(public.cloud_grants.until, excluded.until), note = excluded.note
        returning until`,
    }),
    signal: AbortSignal.timeout(20_000),
  })
  if (!res.ok) fail(`Granting Cloud failed: ${res.status} ${(await res.text()).slice(0, 300)}`)
  const rows = (await res.json()) as { until: string }[]
  if (!rows.length) fail(`✗ ${EMAIL} has no account yet. Nothing was written.`)
  console.log(`✓ Cloud granted until ${rows[0].until.slice(0, 10)} ("${REVIEW_GRANT_NOTE}")`)
}

// ---- sign in as the review account, as a reviewer does on the consent page -----------------

const door = await fetch(`${SUPABASE}/functions/v1/review-sign-in`, {
  method: 'POST',
  headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: EMAIL, code }),
  signal: AbortSignal.timeout(20_000),
})
code = ''
const answer = (await door.json().catch(() => ({}))) as { token_hash?: string; error?: string }
if (!door.ok || !answer.token_hash) {
  fail(
    door.status === 404
      ? `✗ review-sign-in is shut for ${EMAIL}: REVIEW_EMAIL or REVIEW_CODE is unset, or the account has no grant. Run again with --grant-cloud.`
      : door.status === 401
        ? `✗ review-sign-in refused the code: REVIEW_CODE differs from "${KEYCHAIN_SERVICE}".`
        : `✗ review-sign-in answered ${door.status}: ${answer.error ?? ''}`,
  )
}
const verify = await fetch(`${SUPABASE}/auth/v1/verify`, {
  method: 'POST',
  headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' },
  body: JSON.stringify({ type: 'magiclink', token_hash: answer.token_hash }),
  signal: AbortSignal.timeout(20_000),
})
if (!verify.ok) fail(`Signing in as ${EMAIL} failed: ${verify.status}.`)
const session = (await verify.json()) as { access_token: string; user: { id: string } }
const userId = session.user.id
const asUser = { apikey: ANON_KEY, Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' }
console.log(`✓ signed in as ${EMAIL}`)

// The database refuses a hosted copy for an account without Cloud, and the nightly expiry
// deletes one 30 days after Cloud ends, so nothing is written without it.
if ((await rpc('has_cloud', { uid: userId }, asUser)) !== true) {
  await fetch(`${SUPABASE}/auth/v1/logout?scope=local`, { method: 'POST', headers: asUser, signal: AbortSignal.timeout(20_000) }).catch(() => null)
  fail(
    `✗ ${EMAIL} has no longbook Cloud: the hosted copy cannot be written, and ${MCP_URL} would refuse its ` +
      'memory (entitlement_required). Run again with --grant-cloud. Nothing was written.',
  )
}

// ---- the hosted copy, written as the app writes it ------------------------------------------

const upsert = await fetch(`${SUPABASE}/rest/v1/hosted_memories`, {
  method: 'POST',
  headers: { ...asUser, Prefer: 'resolution=merge-duplicates,return=minimal' },
  body: JSON.stringify({ user_id: userId, memory, pushed_at: new Date().toISOString() }),
  signal: AbortSignal.timeout(30_000),
})
if (!upsert.ok) fail(`Writing the hosted copy failed: ${upsert.status} ${(await upsert.text()).slice(0, 300)}`)
console.log('✓ hosted copy written')

// The owner's switch for suggestions, on, so the write tools file proposals instead of refusing.
const propose = await fetch(`${SUPABASE}/rest/v1/hosted_memories?user_id=eq.${userId}`, {
  method: 'PATCH',
  headers: { ...asUser, Prefer: 'return=minimal' },
  body: JSON.stringify({ web_propose: true }),
  signal: AbortSignal.timeout(20_000),
})
if (!propose.ok) fail(`Switching suggestions on failed: ${propose.status}`)
console.log('✓ suggestions from the web switched on')

// ---- read it back through the hosted server -------------------------------------------------

const call = await fetch(MCP_URL, {
  method: 'POST',
  headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream' },
  body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'whoami', arguments: {} } }),
  signal: AbortSignal.timeout(30_000),
})
const text = await call.text()
const held = text.match(/\\"commitments\\":\s*(\d+)/)?.[1] ?? text.match(/"commitments":\s*(\d+)/)?.[1]

// This script's own session ends here; the reviewer signs in on their own.
await fetch(`${SUPABASE}/auth/v1/logout?scope=local`, { method: 'POST', headers: asUser, signal: AbortSignal.timeout(20_000) }).catch(() => null)

if (!call.ok || !held) fail(`✗ the hosted server did not read the copy back (${call.status}).`)
console.log(`✓ ${MCP_URL} reads ${held} commitments for ${EMAIL}. The copy expires after 90 days unrefreshed; run this again before then.`)
