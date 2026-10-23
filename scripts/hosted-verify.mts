#!/usr/bin/env -S npx tsx
// Byte-compares the deployed MCP function against supabase/functions/mcp on disk. The
// deploy's own check only proves the function boots and challenges, which a stale engine
// passes just as happily — one sat deployed for days behind that 401.

// Needs a Supabase access token, exactly as the deploy does: set SUPABASE_ACCESS_TOKEN,
// or run `npx supabase login` once. Run: npm run hosted:verify.
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { basename, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const PROJECT_REF = 'xbrnijgctmovoqbbmgmb'
const SLUG = 'mcp'
const FN_DIR = join(ROOT, 'supabase/functions/mcp')
const FN_PATH = 'supabase/functions/mcp'
// Read from the folder rather than listed here: a third file added to the deploy would
// otherwise be published and never verified.
const FILES = readdirSync(FN_DIR).filter((n) => !n.startsWith('.')).sort()
const API = `https://api.supabase.com/v1/projects/${PROJECT_REF}/functions/${SLUG}`

function token(): string {
  const env = process.env.SUPABASE_ACCESS_TOKEN
  if (env) return env.trim()
  const cli = join(homedir(), '.supabase/access-token')
  if (existsSync(cli)) return readFileSync(cli, 'utf8').trim()
  console.error('No Supabase access token. Set SUPABASE_ACCESS_TOKEN, or run: npx supabase login')
  process.exit(1)
}

const auth = { Authorization: `Bearer ${token()}` }

const details = await fetch(API, { headers: auth })
if (!details.ok) {
  console.error(`Could not read the deployed function: ${details.status} ${details.statusText}`)
  console.error(`Check the token has access to project ${PROJECT_REF}, then run this again.`)
  process.exit(1)
}
const fn = (await details.json()) as { version?: number; status?: string }

// Asked for by name: unasked, this endpoint answers with an eszip archive, which is the
// deployed bundle rather than the files that went into it and cannot be compared with them.
const body = await fetch(`${API}/body`, { headers: { ...auth, accept: 'multipart/form-data' } })
if (!body.ok) {
  console.error(`Could not read the deployed function body: ${body.status} ${body.statusText}`)
  process.exit(1)
}

// The deploy packs the files as multipart, and the body comes back the same way. A bundled
// answer cannot be compared byte for byte here, so say so rather than pass on a guess.
const contentType = body.headers.get('content-type') ?? ''
if (!contentType.includes('multipart/form-data')) {
  console.error(`The deployed body came back as ${contentType || 'an unnamed type'}, not the source files.`)
  console.error(`Download and diff it instead: npx supabase functions download ${SLUG} --project-ref ${PROJECT_REF}`)
  process.exit(1)
}

const deployed = new Map<string, Buffer>()
for (const part of (await body.formData()).values()) {
  if (typeof part === 'string') continue
  deployed.set(basename(part.name), Buffer.from(await part.arrayBuffer()))
}

console.log(`${SLUG} — deployed version ${fn.version ?? 'unknown'}${fn.status ? `, ${fn.status}` : ''}`)
let drift = false
// Byte-identical and not serving is still not deployed.
if (fn.status && fn.status !== 'ACTIVE') {
  console.log(`  status is ${fn.status}, not ACTIVE — the bytes below are not answering`)
  drift = true
}
// A file deployed that the repo does not have is drift in the other direction, and only
// comparing the repo's own list would never see it.
for (const name of deployed.keys()) {
  if (!FILES.includes(name)) {
    console.log(`  ${name} — deployed, but not in ${FN_PATH}`)
    drift = true
  }
}
for (const name of FILES) {
  const onDisk = readFileSync(join(FN_DIR, name))
  const live = deployed.get(name)
  if (!live) {
    console.log(`  ${name} — missing from the deployed function`)
    drift = true
  } else if (live.equals(onDisk)) {
    console.log(`  ${name} — identical (${onDisk.length} bytes)`)
  } else {
    console.log(`  ${name} — differs: ${live.length} bytes deployed, ${onDisk.length} bytes on disk`)
    drift = true
  }
}

if (drift) {
  console.error(`\nThe deployed function is not what ${FN_PATH} holds.`)
  console.error('Run: npm run hosted:deploy')
  process.exit(1)
}
// Says what it checked, not more: these bytes are the repo's, and whether the repo's own
// generated engine is current is what hosted:engine:check answers.
console.log(`\nEvery file matches ${FN_PATH}, byte for byte. Run hosted:engine:check for whether that engine is itself current.`)
