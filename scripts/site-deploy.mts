#!/usr/bin/env -S npx tsx
// Publishes longbook.app from a clean export of the committed tree, then reads the live
// site back: the page byte for byte, and the edge function that serves /mcp.

// Deploys through the Netlify CLI's own sign-in, or NETLIFY_AUTH_TOKEN when it is set; the
// site is named below, and NETLIFY_SITE_ID overrides it. Run: npm run site:deploy; --dry-run
// checks without deploying; --draft publishes a draft at its own address and reads it back;
// --verify only reads the live site back.
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { eachLimited, fetchWithRetry, uncached } from './site-fetch.mts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SITE_DIR = join(ROOT, 'apps/longbook-site')
const REDIRECTS_PATH = 'apps/longbook-site/_redirects'
const SITE_ORIGIN = 'https://longbook.app'
// The site this repository publishes, by id: the CLI resolves --site by name but not by id, and
// an unlinked directory asks which site this is — a wrong answer creates a second one.
const SITE_ID = process.env.NETLIFY_SITE_ID ?? '08129536-6d49-4c7c-b344-6597b92172cc'
const DRY_RUN = process.argv.includes('--dry-run')
const DRAFT = process.argv.includes('--draft')
const VERIFY = process.argv.includes('--verify')

// The apex sits behind Cloudflare, which rewrites the HTML on its way out: email obfuscation
// encodes every address, Bot Fight Mode appends a challenge script, and AI Labyrinth adds a
// hidden link. The last two carry a per-response token, so they are removed rather than decoded.
const plainHtml = (html: string): string => {
  const decode = (hex: string): string => {
    const key = parseInt(hex.slice(0, 2), 16)
    let out = ''
    for (let i = 2; i < hex.length; i += 2) out += String.fromCharCode(parseInt(hex.slice(i, i + 2), 16) ^ key)
    return out
  }
  return html
    .replace(/<script data-cfasync="false" src="\/cdn-cgi\/scripts\/[^"]*\/email-decode\.min\.js"><\/script>/g, '')
    .replace(/<a href="\/cdn-cgi\/l\/email-protection" class="__cf_email__" data-cfemail="([0-9a-f]+)">\[email&#160;protected\]<\/a>/g, (_, h) => decode(h))
    .replace(/<span class="__cf_email__" data-cfemail="([0-9a-f]+)">\[email&#160;protected\]<\/span>/g, (_, h) => decode(h))
    .replace(/href="\/cdn-cgi\/l\/email-protection#([0-9a-f]+)"/g, (_, h) => `href="mailto:${decode(h)}"`)
    .replace(/<script>\(function\(\)\{function c\(\)\{var b=a\.contentDocument[\s\S]*?<\/script>/g, '')
    .replace(/<a href="https:\/\/[^"]*\/cdn-cgi\/content\?id=[^"]*"[^>]*>[\s\S]*?<\/a>/g, '')
}

const sh = (cmd: string, args: string[], opts: { cwd?: string } = {}): string =>
  execFileSync(cmd, args, { encoding: 'utf8', cwd: opts.cwd, stdio: ['ignore', 'pipe', 'pipe'] })

// The deploy carries the committed tree, so a redirect rule that is only in the working tree
// would be checked here and never published.
const redirects = readFileSync(join(SITE_DIR, '_redirects'), 'utf8')
let committedRedirects = ''
try {
  committedRedirects = sh('git', ['show', `HEAD:${REDIRECTS_PATH}`], { cwd: ROOT })
} catch {
  committedRedirects = ''
}
if (committedRedirects !== redirects) {
  console.error(`${REDIRECTS_PATH} differs from the committed copy, and the deploy publishes the commit.`)
  console.error(`Commit it first: git add ${REDIRECTS_PATH} && git commit`)
  process.exit(1)
}

// git archive, not a copy of the working tree: the tree carries edits that are not ready,
// and a deploy is the one place where publishing them cannot be taken back.
const stage = mkdtempSync(join(tmpdir(), 'longbook-site-'))
const clean = () => rmSync(stage, { recursive: true, force: true })
// Anything that throws between here and the deploy would otherwise leave a copy of the
// whole site in the temporary directory.
process.on('exit', clean)
const tarball = join(stage, 'site.tar')
sh('git', ['archive', '--format=tar', '-o', tarball, 'HEAD', '--', 'apps/longbook-site'], { cwd: ROOT })
sh('tar', ['-x', '-f', tarball, '-C', stage])
rmSync(tarball)
const deployDir = join(stage, 'apps/longbook-site')

// The deploy runs with this directory as its root, so the base the site's own build settings
// name would resolve one level too deep. Written here rather than committed: the repository's
// netlify.toml describes the build image, which reads it from the base directory instead.
writeFileSync(join(deployDir, 'netlify.toml'), [
  '[build]',
  '  base = "."',
  '  publish = "."',
  '  edge_functions = "netlify/edge-functions"',
  '',
].join('\n'))

// The media kit's images and the features screenshots, share images and films are built on a Mac and
// never committed; media-kit/files.json and apps/longbook-site-content/built.json name each by size
// and hash. The deploy carries exactly those: this checkout's build where it matches, else the live copy.
type Carried = { at: string; bytes: number; sha256: string; list: string; build: string }
const sha256 = (bytes: Buffer): string => createHash('sha256').update(bytes).digest('hex')
const kitListPath = join(deployDir, 'media-kit/files.json')
const kitList = existsSync(kitListPath) ? JSON.parse(readFileSync(kitListPath, 'utf8')) : { files: [], preview: [] }
const kitFiles: Carried[] = [...kitList.files, ...kitList.preview].map((f: { path: string; bytes: number; sha256: string }) =>
  ({ at: `media-kit/files/${f.path}`, bytes: f.bytes, sha256: f.sha256, list: 'media-kit/files.json', build: 'npm run site:media-kit' }))
let builtList: { images: Carried[]; shares: Carried[]; media?: Carried[] } = { images: [], shares: [] }
try {
  builtList = JSON.parse(execFileSync('git', ['show', 'HEAD:apps/longbook-site-content/built.json'], { cwd: ROOT, encoding: 'utf8' }))
} catch {
  // A commit from before the features section has no list.
}
const siteFiles: Carried[] = [
  ...[...builtList.images, ...builtList.shares].map((f) => ({ f, build: 'npm run site:images && npm run site:og' })),
  ...(builtList.media ?? []).map((f) => ({ f, build: 'npm run site:media' })),
].map(({ f, build }) => ({ at: (f as unknown as { path: string }).path, bytes: f.bytes, sha256: f.sha256,
  list: 'apps/longbook-site-content/built.json', build }))
const carried = [...kitFiles, ...siteFiles]
let kitFromLive = 0
let siteFromLive = 0
await eachLimited(carried, 6, async (file) => {
  const built = join(SITE_DIR, file.at)
  let bytes: Buffer | null = existsSync(built) ? readFileSync(built) : null
  if (!bytes || sha256(bytes) !== file.sha256) {
    const live = await fetchWithRetry(uncached(`${SITE_ORIGIN}/${file.at}`), { headers: { 'cache-control': 'no-cache' } })
    bytes = live.ok ? live.bytes : null
    if (file.list === 'media-kit/files.json') kitFromLive += 1
    else siteFromLive += 1
  }
  if (!bytes || sha256(bytes) !== file.sha256) {
    console.error(`${file.at} matches neither this checkout's build nor the live copy.`)
    console.error(`Build it first: ${file.build}`)
    process.exit(1)
  }
  const into = join(deployDir, file.at)
  mkdirSync(dirname(into), { recursive: true })
  writeFileSync(into, bytes)
})

// Without a token the CLI deploys with its own sign-in — and with neither it opens a browser and
// waits, which no script may start on anyone's behalf. `status` answers without prompting, but
// only from a linked directory, so the link is written first, the way `netlify link` writes it.
function cliSignIn(): string {
  mkdirSync(join(deployDir, '.netlify'), { recursive: true })
  writeFileSync(join(deployDir, '.netlify/state.json'), JSON.stringify({ siteId: SITE_ID }) + '\n')
  let answer = ''
  try {
    answer = sh('npx', ['-y', 'netlify', 'status', '--json'], { cwd: deployDir })
  } catch (error) {
    answer = String((error as { stderr?: string }).stderr ?? error)
  }
  let signedIn = false
  try {
    signedIn = typeof JSON.parse(answer).account === 'object'
  } catch {
    signedIn = false
  }
  if (signedIn) return 'the Netlify CLI, signed in'
  console.error('\nNETLIFY_AUTH_TOKEN is not set and the Netlify CLI is not signed in, so it would open a browser.')
  console.error(`The CLI said: ${answer.trim().split('\n')[0]}`)
  console.error('Sign in once with npx netlify login, or pipe a token in: NETLIFY_AUTH_TOKEN="$(…)" npm run site:deploy')
  process.exit(1)
}

console.log('site deploy')
console.log(`  content     HEAD, exported clean to ${deployDir}`)
console.log(`  site        ${SITE_ID}`)
console.log(`  sign-in     ${process.env.NETLIFY_AUTH_TOKEN ? 'NETLIFY_AUTH_TOKEN' : cliSignIn()}`)
console.log(`  command     npx netlify link --id …, then npx netlify deploy ${DRAFT ? '(a draft)' : '--prod'}, from that directory`)
console.log(`  media kit   ${kitFiles.length} files, ${kitFiles.length - kitFromLive} from this checkout's build, ${kitFromLive} from the live site`)
console.log(`  features    ${siteFiles.length} images, ${siteFiles.length - siteFromLive} from this checkout's build, ${siteFromLive} from the live site`)
console.log(`  then reads  ${DRAFT ? 'the draft' : SITE_ORIGIN} back: /mcp, /, and every carried image`)

if (DRY_RUN) {
  console.log('\n--dry-run: every check passed and nothing was deployed.')
  process.exit(0)
}

// A draft answers at its own address, so every read-back below goes there instead.
let origin = SITE_ORIGIN
if (VERIFY) {
  console.log(`\nreading ${SITE_ORIGIN} back against HEAD; nothing deployed.`)
} else {
  // Linked by id, so the CLI never asks which site this is.
  console.log('\nlinking…')
  execFileSync('npx', ['-y', 'netlify', 'link', '--id', SITE_ID], { cwd: deployDir, stdio: 'inherit' })
  console.log('\ndeploying…')
}
// No --dir: run from the directory itself so the edge functions are found and bundled. Passing
// --dir from a parent deploys the files and silently drops them, which takes the browser page
// at /mcp off the site while every other check still passes.
if (VERIFY) {
  // nothing to deploy
} else if (DRAFT) {
  const answer = sh('npx', ['-y', 'netlify', 'deploy', '--json'], { cwd: deployDir })
  const draftUrl = JSON.parse(answer.slice(answer.indexOf('{'), answer.lastIndexOf('}') + 1)).deploy_url as string | undefined
  if (!draftUrl) {
    console.error('The CLI reported no deploy_url for the draft.')
    process.exit(1)
  }
  origin = draftUrl
  console.log(`draft at ${draftUrl} — nothing live has changed.`)
} else {
  execFileSync('npx', ['-y', 'netlify', 'deploy', '--prod'], { cwd: deployDir, stdio: 'inherit' })
}

// Reading the deploy back is the point: the failure this guards against is invisible in the
// deploy's own output. The edge functions are what a file listing cannot see; without them
// longbook.app/mcp answers a browser with a JSON-RPC error instead of the page.
const explainer = await fetchWithRetry(origin + '/mcp', { headers: { accept: 'text/html' }, retry404: true })
const explainerBody = explainer.ok ? explainer.bytes.toString('utf8') : ''
if (!explainerBody.startsWith('<!doctype html')) {
  console.error(`\n${origin}/mcp answered ${explainer.status} without the explainer page.`)
  console.error('The edge functions did not deploy. Deploy again from the site directory itself.')
  process.exit(1)
}

// The page itself, byte for byte against the export, so what was checked is what was published.
const home = await fetchWithRetry(uncached(origin + '/'), { headers: { 'cache-control': 'no-cache' }, retry404: true })
// Cloudflare strips the email_off markers it honours, and a draft on Netlify keeps them, so both
// sides are compared without them.
const unmarked = (html: string): string => html.replace(/<!--\/?email_off-->/g, '')
const homeBody = unmarked(plainHtml(home.bytes.toString('utf8')))
const homeFile = unmarked(readFileSync(join(deployDir, 'index.html'), 'utf8'))
if (home.status !== 200 || homeBody !== homeFile) {
  console.error(`\n${origin}/ answered ${home.status} and does not match the exported index.html.`)
  process.exit(1)
}

console.log(`\nverified ${origin}/mcp — the explainer page is served, so the edge functions are live.`)
console.log(`verified ${origin}/ — byte-identical to the exported index.html.`)

await eachLimited(carried, 6, async (file) => {
  const served = await fetchWithRetry(uncached(`${origin}/${file.at}`), { headers: { 'cache-control': 'no-cache' }, retry404: true })
  const bytes = served.ok ? served.bytes : Buffer.alloc(0)
  if (sha256(bytes) !== file.sha256) {
    console.error(`\n${origin}/${file.at} answered ${served.status} and does not match ${file.list}.`)
    process.exit(1)
  }
})
if (kitFiles.length) console.log(`verified ${origin}/media-kit/files — all ${kitFiles.length} match media-kit/files.json.`)
if (siteFiles.length) console.log(`verified ${origin}/features/img and /og — all ${siteFiles.length} match built.json.`)
if (DRAFT) console.log(`\nDraft: ${origin} — live longbook.app is unchanged.`)
