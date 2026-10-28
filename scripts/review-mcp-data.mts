#!/usr/bin/env -S npx tsx
// Fills appreview@longbook.app's hosted copy with the made-up demo household, for directory
// reviewers connecting https://longbook.app/mcp. Signs in with the code review:account keeps in
// the keychain, switches suggestions on, and reads the copy back. Never prints the code.

// The copy needs longbook Cloud, which review:account takes off. --grant-cloud gives 120 days;
// run this after review:account, since the copy is deleted 30 days after Cloud ends.
// Run: npm run review:mcp-data [-- --household us|in] [--grant-cloud] [--dry-run]
import { execFileSync } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const PROJECT_REF = 'xbrnijgctmovoqbbmgmb'
const SUPABASE = `https://${PROJECT_REF}.supabase.co`
// The public anon key every client ships (the app, the consent page); RLS and the account's own
// session are the boundary.
const ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhicm5pamdjdG1vdm9xYmJtZ21iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU3NzQ0NDQsImV4cCI6MjEwMTM1MDQ0NH0.ZamrPyf3UmAmbqzzAcce_Ocb1bKNq19wVxTtaC32a-g'
const MCP_URL = 'https://longbook.app/mcp'
/** Must match REVIEW_EMAIL in packages/swift-core AuthClient.swift and EMAIL in review-account.mts. */
const EMAIL = 'appreview@longbook.app'
/** Where review:account keeps the code, which is this account's password. */
const KEYCHAIN_SERVICE = 'longbook App Review sign-in code'
const GRANT_NOTE = 'MCP directory review account'
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

// ---- sign in as the review account ------------------------------------------------------------

let password = ''
try {
  password = execFileSync('security', ['find-generic-password', '-s', KEYCHAIN_SERVICE, '-a', EMAIL, '-w'], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  }).trim()
} catch {
  fail(`No code in the keychain under "${KEYCHAIN_SERVICE}". Run npm run review:account first.`)
}

const signIn = await fetch(`${SUPABASE}/auth/v1/token?grant_type=password`, {
  method: 'POST',
  headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: EMAIL, password }),
  signal: AbortSignal.timeout(20_000),
})
password = ''
if (!signIn.ok) fail(`Signing in as ${EMAIL} failed: ${signIn.status}. Run npm run review:account, then this again.`)
const session = (await signIn.json()) as { access_token: string; user: { id: string } }
const userId = session.user.id
const asUser = { apikey: ANON_KEY, Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' }
console.log(`✓ signed in as ${EMAIL}`)

// ---- Cloud, which the hosted memory needs ---------------------------------------------------

const rpc = async (fn: string, args: Record<string, unknown>): Promise<unknown> => {
  const res = await fetch(`${SUPABASE}/rest/v1/rpc/${fn}`, { method: 'POST', headers: asUser, body: JSON.stringify(args), signal: AbortSignal.timeout(20_000) })
  return res.ok ? res.json() : null
}

if (GRANT) {
  const env = process.env.SUPABASE_ACCESS_TOKEN?.trim()
  const cli = join(homedir(), '.supabase/access-token')
  const token = env || (existsSync(cli) ? readFileSync(cli, 'utf8').trim() : fail('No Supabase access token. Set SUPABASE_ACCESS_TOKEN, or run: npx supabase login'))
  const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      query: `insert into public.cloud_grants (user_id, until, note) values ('${userId}', now() + interval '${GRANT_DAYS} days', '${GRANT_NOTE}')
        on conflict (user_id) do update set until = excluded.until, note = excluded.note, granted_at = now()`,
    }),
    signal: AbortSignal.timeout(20_000),
  })
  if (!res.ok) fail(`Granting Cloud failed: ${res.status} ${(await res.text()).slice(0, 300)}`)
  console.log(`✓ Cloud granted for ${GRANT_DAYS} days ("${GRANT_NOTE}"); review:account takes it off again`)
}
// The database refuses a hosted copy for an account without Cloud, and the nightly expiry
// deletes one 30 days after Cloud ends, so nothing is written without it.
if ((await rpc('has_cloud', { uid: userId })) !== true) {
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
