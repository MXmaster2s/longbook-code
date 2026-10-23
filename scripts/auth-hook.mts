#!/usr/bin/env -S npx tsx
// Turns Supabase Auth's Send Email hook on or off for the auth-email function, and shows its
// state. Run: npm run auth-hook -- --status | --on | --off. --on makes a fresh secret, gives it
// to the function and to Auth, and reads both back; --off returns Auth to its own sending.
import { randomBytes } from 'node:crypto'
import { existsSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const PROJECT_REF = 'xbrnijgctmovoqbbmgmb'
const API = `https://api.supabase.com/v1/projects/${PROJECT_REF}`
const HOOK_URI = `https://${PROJECT_REF}.supabase.co/functions/v1/auth-email`
/** The function reads the secret under this name; Auth signs every request with the same value. */
const SECRET_NAME = 'AUTH_EMAIL_HOOK_SECRET'

type Config = Record<string, unknown>

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

const call = (path: string, init: RequestInit = {}): Promise<Response> =>
  fetch(`${API}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    signal: AbortSignal.timeout(20_000),
  }).catch((e: Error) => fail(`Could not reach the project: ${e.message}`))

async function config(): Promise<Config> {
  const res = await call('/config/auth')
  if (!res.ok) return fail(`Could not read the auth settings: ${res.status} ${res.statusText}`)
  return (await res.json()) as Config
}

const describe = (c: Config): string =>
  `hook ${c.hook_send_email_enabled ? 'on' : 'off'}; uri ${c.hook_send_email_uri ?? 'none'}; secret ${c.hook_send_email_secrets ? 'set' : 'none'}`

async function patch(fields: Config, then: string): Promise<void> {
  const res = await call('/config/auth', { method: 'PATCH', body: JSON.stringify(fields) })
  if (!res.ok) fail(`The update was refused: ${res.status} ${(await res.text()).slice(0, 300)}\n${then}`)
}

/** Whether the counter the function calls is in the database; without it every code would go uncounted. */
async function counterInPlace(): Promise<boolean> {
  const res = await call('/database/query', {
    method: 'POST',
    body: JSON.stringify({ query: "select 1 from pg_proc where proname = 'count_auth_email' and pronamespace = 'public'::regnamespace" }),
  })
  return res.ok && ((await res.json()) as unknown[]).length > 0
}

const arg = (name: string): boolean => process.argv.includes(name)

if (arg('--status')) {
  const fn = await call('/functions/auth-email')
  const state = fn.ok ? ((await fn.json()) as { status?: string; version?: number }) : {}
  console.log(`auth-email function: ${fn.ok ? `${state.status}, version ${state.version}` : 'not deployed'}`)
  console.log(`auth: ${describe(await config())}`)
} else if (arg('--off')) {
  await patch({ hook_send_email_enabled: false }, 'Check with: npm run auth-hook -- --status')
  const now = await config()
  if (now.hook_send_email_enabled !== false) fail('Read back, the hook is still on.')
  console.log(`auth: ${describe(now)} — Auth sends its own templates again.`)
} else if (arg('--on')) {
  // Never a new secret under a running hook: Auth would sign with the old one while the function
  // holds the new, and every sign-in would fail. To replace it: --off, then --on.
  const before = await config()
  if (before.hook_send_email_enabled === true && before.hook_send_email_uri === HOOK_URI && before.hook_send_email_secrets) {
    console.log(`auth: ${describe(before)} — already on. To replace the secret: --off, then --on.`)
    process.exit(0)
  }
  const fn = await call('/functions/auth-email')
  const state = fn.ok ? ((await fn.json()) as { status?: string }) : {}
  if (state.status !== 'ACTIVE') fail('The auth-email function is not serving. Deploy it first: npm run function:deploy -- auth-email')
  if (!(await counterInPlace())) fail('The counter is not in the database. Apply supabase/migrations/20260930100000_auth_email_limit.sql first.')
  const secret = `v1,whsec_${randomBytes(32).toString('base64')}`
  const set = await call('/secrets', { method: 'POST', body: JSON.stringify([{ name: SECRET_NAME, value: secret }]) })
  if (!set.ok) fail(`The function secret was refused: ${set.status} ${(await set.text()).slice(0, 300)}\nThe hook is still off, so Auth sends its own templates; nothing is broken.`)
  await patch(
    { hook_send_email_enabled: true, hook_send_email_uri: HOOK_URI, hook_send_email_secrets: secret },
    'The hook is still off, so Auth sends its own templates; nothing is broken. Run --on again when the project answers.',
  )
  const now = await config()
  if (now.hook_send_email_enabled !== true || now.hook_send_email_uri !== HOOK_URI) fail(`Read back, the hook is not as set: ${describe(now)}\nTo be safe: npm run auth-hook -- --off`)
  console.log(`auth: ${describe(now)} — every sign-in email now goes through the function.`)
  console.log('To undo: npm run auth-hook -- --off')
} else {
  fail('Say what to do: npm run auth-hook -- --status | --on | --off')
}
