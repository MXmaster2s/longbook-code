#!/usr/bin/env -S npx tsx
// Deploys one Edge Function from the files on disk, then reads the deployed body back and
// diffs it byte for byte. Run: npm run function:deploy -- <slug>; `--verify` only reads.
// `verify_jwt` is false: each function checks its own token and answers the preflight.
import { readdirSync, readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { homedir } from 'node:os'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const PROJECT_REF = 'xbrnijgctmovoqbbmgmb'
const ALLOWED = ['share-report', 'apple-purchase', 'apple-notifications', 'statement-extract', 'account-notice', 'sessions', 'auth-email', 'review-sign-in', 'reorganise', 'seats', 'support', 'polar-webhook', 'polar-checkout', 'polar-claim']

const args = process.argv.slice(2).filter((a) => !a.startsWith('--'))
const SLUG = args[0]
if (!SLUG || !ALLOWED.includes(SLUG)) {
  console.error(`Name a function: ${ALLOWED.join(', ')}. The mcp and delete-account functions have their own scripts.`)
  process.exit(1)
}
const FN_DIR = join(ROOT, 'supabase/functions', SLUG)
const SHARED_DIR = join(ROOT, 'supabase/functions/_shared')
const OWN = readdirSync(FN_DIR).filter((n) => !n.startsWith('.')).sort()
const API = `https://api.supabase.com/v1/projects/${PROJECT_REF}/functions`

// A function may import from ../_shared; those files travel with it, and every path is then
// given from supabase/functions so the imports resolve where they run.
function sharedImports(): string[] {
  const found = new Set<string>()
  const scan = (dir: string, names: string[], pattern: RegExp): void => {
    for (const name of names) {
      for (const m of readFileSync(join(dir, name), 'utf8').matchAll(pattern)) {
        if (found.has(m[1]!)) continue
        found.add(m[1]!)
        scan(SHARED_DIR, [m[1]!], /from '\.\/([^']+)'/g)
      }
    }
  }
  scan(FN_DIR, OWN, /from '\.\.\/_shared\/([^']+)'/g)
  return [...found].sort()
}
const SHARED = sharedImports()
// A function may also import the hosted engine, ../mcp/engine.mjs; it travels the same way.
const ENGINE = OWN.some((n) => readFileSync(join(FN_DIR, n), 'utf8').includes("from '../mcp/engine.mjs'"))
const NESTED = SHARED.length > 0 || ENGINE
/** Each file as it is uploaded: its name there, and where it is read from here. */
const FILES = [
  ...OWN.map((n) => ({ name: NESTED ? `${SLUG}/${n}` : n, path: join(FN_DIR, n) })),
  ...SHARED.map((n) => ({ name: `_shared/${n}`, path: join(SHARED_DIR, n) })),
  ...(ENGINE ? [{ name: 'mcp/engine.mjs', path: join(ROOT, 'supabase/functions/mcp/engine.mjs') }] : []),
]
const ENTRYPOINT = NESTED ? `${SLUG}/index.ts` : 'index.ts'
const uploadedName = (partName: string): string =>
  FILES.find((f) => partName === f.name || partName.endsWith(`/${f.name}`))?.name ?? partName

function token(): string {
  const env = process.env.SUPABASE_ACCESS_TOKEN
  if (env) return env.trim()
  const cli = join(homedir(), '.supabase/access-token')
  if (existsSync(cli)) return readFileSync(cli, 'utf8').trim()
  console.error('No Supabase access token. Set SUPABASE_ACCESS_TOKEN, or run: npx supabase login')
  process.exit(1)
}
const auth = { Authorization: `Bearer ${token()}` }

/** The deployed files, name by name, against the folder they came from. */
async function verify(): Promise<void> {
  const details = await fetch(`${API}/${SLUG}`, { headers: auth })
  if (!details.ok) {
    console.error(`Could not read the deployed function: ${details.status} ${details.statusText}`)
    process.exit(1)
  }
  const fn = (await details.json()) as { version?: number; status?: string; verify_jwt?: boolean }
  const body = await fetch(`${API}/${SLUG}/body`, { headers: { ...auth, accept: 'multipart/form-data' } })
  const contentType = body.headers.get('content-type') ?? ''
  if (!body.ok || !contentType.includes('multipart/form-data')) {
    console.error(`The deployed body could not be read as source files (${body.status}, ${contentType || 'no type'}).`)
    process.exit(1)
  }
  const deployed = new Map<string, Buffer>()
  for (const part of (await body.formData()).values()) {
    if (typeof part === 'string') continue
    deployed.set(uploadedName(part.name), Buffer.from(await part.arrayBuffer()))
  }
  console.log(`${SLUG} — deployed version ${fn.version ?? '?'}, ${fn.status ?? 'status unknown'}, verify_jwt ${fn.verify_jwt}`)
  let drift = fn.status !== 'ACTIVE' || fn.verify_jwt !== false
  for (const name of deployed.keys()) {
    if (!FILES.some((f) => f.name === name)) {
      console.log(`  ${name} — deployed, but not in supabase/functions/${SLUG}`)
      drift = true
    }
  }
  for (const { name, path } of FILES) {
    const disk = readFileSync(path)
    const live = deployed.get(name)
    if (!live) {
      console.log(`  ${name} — on disk, not deployed`)
      drift = true
    } else if (!live.equals(disk)) {
      console.log(`  ${name} — differs (${live.length} deployed, ${disk.length} on disk)`)
      drift = true
    } else {
      console.log(`  ${name} — identical (${disk.length} bytes)`)
    }
  }
  if (drift) {
    console.error(`\n${SLUG} does not match the repo, or is not serving.`)
    process.exit(1)
  }
  console.log(`\nEvery file matches supabase/functions/${SLUG}, byte for byte.`)
}

if (process.argv.includes('--verify')) {
  await verify()
  process.exit(0)
}

const form = new FormData()
form.append('metadata', JSON.stringify({ name: SLUG, entrypoint_path: ENTRYPOINT, verify_jwt: false }))
for (const { name, path } of FILES) {
  const bytes = readFileSync(path)
  form.append('file', new File([bytes], name, { type: name.endsWith('.ts') ? 'application/typescript' : 'text/javascript' }))
  console.log(`packed ${name} (${bytes.length} bytes, from disk)`)
}
const res = await fetch(`${API}/deploy?slug=${SLUG}`, { method: 'POST', headers: auth, body: form })
if (!res.ok) {
  console.error(`deploy FAILED: ${res.status} ${await res.text()}`)
  process.exit(1)
}
const out = (await res.json()) as { version?: number }
console.log(`deployed ${SLUG} — version ${out.version ?? '?'}.`)
await verify()
