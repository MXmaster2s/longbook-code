#!/usr/bin/env -S npx tsx
// Deploys the account-deletion function from the file on disk, then proves the deployed copy
// refuses an unauthenticated caller. Run: npm run account:deploy.
//
// `verify_jwt` is false because the function verifies the token itself and answers the
// browser preflight; the platform gate would refuse OPTIONS before CORS could be sent.
import { readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { homedir } from 'node:os'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const PROJECT_REF = 'xbrnijgctmovoqbbmgmb'
const SLUG = 'delete-account'
const FN_DIR = join(ROOT, 'supabase/functions', SLUG)
const PUBLIC_URL = `https://${PROJECT_REF}.supabase.co/functions/v1/${SLUG}`

function token(): string {
  const env = process.env.SUPABASE_ACCESS_TOKEN
  if (env) return env.trim()
  const cli = join(homedir(), '.supabase/access-token')
  if (existsSync(cli)) return readFileSync(cli, 'utf8').trim()
  console.error('No Supabase access token. Set SUPABASE_ACCESS_TOKEN, or run: npx supabase login')
  process.exit(1)
}

/** Deletes nothing: a request with no token must be refused, and the preflight must answer. */
async function verify(): Promise<void> {
  const bare = await fetch(PUBLIC_URL, { method: 'POST' })
  if (bare.status !== 401) {
    console.error(`verify FAILED: a token-less POST answered ${bare.status}, expected 401.`)
    process.exit(1)
  }
  const pre = await fetch(PUBLIC_URL, { method: 'OPTIONS' })
  const allow = pre.headers.get('access-control-allow-origin')
  if (!allow) {
    console.error(`verify FAILED: the preflight sent no Access-Control-Allow-Origin (${pre.status}).`)
    process.exit(1)
  }
  console.log('verify — a token-less POST is refused 401, and the preflight answers with CORS.')
}

if (process.argv.includes('--check')) {
  await verify()
  process.exit(0)
}

const form = new FormData()
form.append(
  'metadata',
  JSON.stringify({ name: SLUG, entrypoint_path: 'index.ts', verify_jwt: false }),
)
const bytes = readFileSync(join(FN_DIR, 'index.ts'))
form.append('file', new File([bytes], 'index.ts', { type: 'application/typescript' }))
console.log(`packed index.ts (${bytes.length} bytes, from disk)`)

const res = await fetch(
  `https://api.supabase.com/v1/projects/${PROJECT_REF}/functions/deploy?slug=${SLUG}`,
  { method: 'POST', headers: { Authorization: `Bearer ${token()}` }, body: form },
)
if (!res.ok) {
  console.error(`deploy FAILED: ${res.status} ${await res.text()}`)
  process.exit(1)
}
const out = (await res.json()) as { version?: number }
console.log(`deployed ${SLUG} — version ${out.version ?? '?'}.`)
await verify()
