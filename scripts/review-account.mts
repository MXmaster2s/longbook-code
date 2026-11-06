#!/usr/bin/env -S npx tsx
// The App Review account. Makes or refreshes appreview@longbook.app with a fresh eight-digit code
// as its password, holds no licence and no Cloud, and keeps the code in the keychain for asc:listing, which
// puts it in the review details. Run before each submission: npm run review:account
import { execFileSync } from 'node:child_process'
import { randomInt } from 'node:crypto'
import { existsSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const PROJECT_REF = 'xbrnijgctmovoqbbmgmb'
const API = `https://api.supabase.com/v1/projects/${PROJECT_REF}`
const AUTH = `https://${PROJECT_REF}.supabase.co/auth/v1`
/** Must match REVIEW_EMAIL in packages/swift-core AuthClient.swift. */
const EMAIL = 'appreview@longbook.app'
/** asc:listing reads the code from here; nothing else does. */
const KEYCHAIN_SERVICE = 'longbook App Review sign-in code'

const fail = (message: string): never => {
  console.error(message)
  process.exit(1)
}

function token(): string {
  const env = process.env.SUPABASE_ACCESS_TOKEN
  if (env) return env.trim()
  const cli = join(homedir(), '.supabase/access-token')
  if (existsSync(cli)) return readFileSync(cli, 'utf8').trim()
  return fail('No Supabase access token. Set SUPABASE_ACCESS_TOKEN, or run: npx supabase login')
}

const manage = async (path: string, init: RequestInit = {}): Promise<any> => {
  const res = await fetch(`${API}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    signal: AbortSignal.timeout(20_000),
  })
  if (!res.ok) fail(`${path}: ${res.status} ${(await res.text()).slice(0, 300)}`)
  return res.json()
}

const keys = (await manage('/api-keys?reveal=true')) as { name: string; api_key: string }[]
const service = keys.find((k) => k.name === 'service_role')?.api_key ?? fail('No service_role key on the project.')
const anon = keys.find((k) => k.name === 'anon')?.api_key ?? fail('No anon key on the project.')

const admin = async (path: string, method: string, body?: unknown): Promise<any> => {
  const res = await fetch(`${AUTH}/admin${path}`, {
    method,
    headers: { Authorization: `Bearer ${service}`, apikey: service, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(20_000),
  })
  if (!res.ok) fail(`auth admin ${path}: ${res.status} ${(await res.text()).slice(0, 300)}`)
  return res.json()
}

// The code is the password; eight digits, like the codes the app emails.
const code = String(randomInt(0, 100_000_000)).padStart(8, '0')

const found = (await manage('/database/query', {
  method: 'POST',
  body: JSON.stringify({ query: `select id from auth.users where email = '${EMAIL}'` }),
})) as { id: string }[]
let id = found[0]?.id
if (id) {
  await admin(`/users/${id}`, 'PUT', { password: code, email_confirm: true })
  console.log(`✓ ${EMAIL}: new code set`)
} else {
  id = (await admin('/users', 'POST', { email: EMAIL, password: code, email_confirm: true })).id as string
  console.log(`✓ ${EMAIL}: account made`)
}

// longbook is bought before it is used, and App Review must find both purchases (2.1(b), 23 Oct).
// The account holds nothing: sign-in opens on Buy longbook, and the sandbox purchase brings no
// Cloud months for this one account (licence-cloud.ts), so Subscribe to longbook Cloud shows next.
await manage('/database/query', {
  method: 'POST',
  body: JSON.stringify({ query: `delete from public.entitlements where user_id = '${id}';
    delete from public.cloud_grants where user_id = '${id}';
    delete from public.cloud_subscriptions where user_id = '${id}'` }),
})
console.log('✓ no licence, no Cloud: both purchases are reviewable')

// Read it back the way the app signs in, then keep the code where asc:listing finds it.
const check = await fetch(`${AUTH}/token?grant_type=password`, {
  method: 'POST',
  headers: { apikey: anon, 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: EMAIL, password: code }),
  signal: AbortSignal.timeout(20_000),
})
if (!check.ok) fail(`Signing in with the new code failed: ${check.status}. Is password sign-in on for email?`)
console.log('✓ signs in with the code')

execFileSync('security', ['add-generic-password', '-U', '-s', KEYCHAIN_SERVICE, '-a', EMAIL, '-w', code])
console.log(`✓ code kept in the keychain as "${KEYCHAIN_SERVICE}". Next: npm run asc:listing`)
