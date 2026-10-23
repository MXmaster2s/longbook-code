#!/usr/bin/env -S npx tsx
// Deploys the hosted MCP function from the files on disk — byte-faithful by construction,
// after two deploys nearly shipped a placeholder where the engine belonged.
//
// Needs a Supabase access token: set SUPABASE_ACCESS_TOKEN, or run `npx supabase login`
// once (the token lands in ~/.supabase/access-token). Run: npm run hosted:deploy.
import { readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { homedir } from 'node:os'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const PROJECT_REF = 'xbrnijgctmovoqbbmgmb'
const SLUG = 'mcp'
const FN_DIR = join(ROOT, 'supabase/functions/mcp')
const PUBLIC_URL = 'https://longbook.app/mcp'

function token(): string {
  const env = process.env.SUPABASE_ACCESS_TOKEN
  if (env) return env.trim()
  const cli = join(homedir(), '.supabase/access-token')
  if (existsSync(cli)) return readFileSync(cli, 'utf8').trim()
  console.error('No Supabase access token. Set SUPABASE_ACCESS_TOKEN, or run: npx supabase login')
  process.exit(1)
}

/** The deployed function must answer; a broken engine fails at module load and 503s. */
async function verify(): Promise<void> {
  const res = await fetch(PUBLIC_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'ping' }),
  })
  const authHeader = res.headers.get('www-authenticate') ?? ''
  if (res.status !== 401 || !authHeader.includes('oauth-protected-resource')) {
    console.error(`verify FAILED: expected 401 with WWW-Authenticate, got ${res.status}`)
    process.exit(1)
  }
  console.log('verify — the function boots and challenges: 401 + WWW-Authenticate.')
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
for (const name of ['index.ts', 'engine.mjs']) {
  const bytes = readFileSync(join(FN_DIR, name))
  form.append('file', new File([bytes], name, { type: 'application/typescript' }))
  console.log(`packed ${name} (${bytes.length} bytes, from disk)`)
}

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
