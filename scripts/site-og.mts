#!/usr/bin/env -S npx tsx
// Renders each page's share card (share-card.mts): its headline, one line and its own screens,
// photographed at 1200×630 by headless Chrome from a local copy of the site and saved as JPEG
// with its description inside. macOS with Google Chrome. Regenerate: npm run site:og.
import { execFileSync, spawn } from 'node:child_process'
import { createServer } from 'node:http'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, extname, join, normalize } from 'node:path'
import { fileURLToPath } from 'node:url'
import type { AddressInfo } from 'node:net'
import { loadAutomations, loadFeatures } from './site-pages/content.mts'
import { shareTargets, shareAlt } from './site-pages/seo.mts'
import { shareCardHtml } from './site-pages/share-card.mts'
import { withMetadata } from './site-pages/jpeg.mts'
import { writeBuilt } from './site-pages/built.mts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SITE = join(ROOT, 'apps/longbook-site')
const CHROME = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.woff2': 'font/woff2',
  '.jpg': 'image/jpeg', '.png': 'image/png', '.svg': 'image/svg+xml', '.md': 'text/markdown',
}

if (!existsSync(CHROME)) throw new Error(`no Chrome at ${CHROME}; set CHROME to its binary`)

const features = loadFeatures(join(ROOT, 'apps/longbook-site-content/features'))
const targets = shareTargets(features, loadAutomations(join(ROOT, 'apps/longbook-site-content/automations.md')))

const built = (key: string | null): string | null => (key && existsSync(join(SITE, 'features/img', `${key}.jpg`)) ? key : null)

const server = createServer((req, res) => {
  const card = /^\/__card\/(\d+)$/.exec(req.url ?? '')
  const t = card ? targets[Number(card[1])] : undefined
  if (t) {
    res.writeHead(200, { 'Content-Type': TYPES['.html']! }).end(shareCardHtml(t, built(t.iphone), built(t.mac)))
    return
  }
  let path = normalize(decodeURIComponent((req.url ?? '/').split('?')[0]!))
  if (path.includes('..')) path = '/'
  let file = join(SITE, path)
  if (existsSync(file) && statSync(file).isDirectory()) file = join(file, 'index.html')
  if (!existsSync(file)) {
    res.writeHead(404).end()
    return
  }
  res.writeHead(200, { 'Content-Type': TYPES[extname(file)] ?? 'application/octet-stream' })
  res.end(readFileSync(file))
})
await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
const port = (server.address() as AddressInfo).port

// Chrome writes the screenshot and can then stay running while a page's timers tick, so the
// file is watched and the browser stopped once it has settled.
async function shoot(url: string, png: string, profile: string): Promise<void> {
  rmSync(png, { force: true })
  const chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--hide-scrollbars', '--force-device-scale-factor=2', '--window-size=1200,630',
    `--user-data-dir=${profile}`, '--virtual-time-budget=6000', `--screenshot=${png}`, url], { stdio: 'ignore' })
  let exited = false
  chrome.on('exit', () => { exited = true })
  const wait = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms))
  let last = -1
  for (let i = 0; i < 300; i++) {
    await wait(200)
    const size = existsSync(png) ? statSync(png).size : -1
    if (size > 0 && size === last) break
    last = size
    if (exited && size <= 0) break
  }
  if (!exited) chrome.kill()
  await wait(300)
  if (!existsSync(png) || statSync(png).size === 0) throw new Error(`no screenshot of ${url}`)
}

const work = mkdtempSync(join(tmpdir(), 'longbook-site-og-'))
try {
  for (const [i, t] of targets.entries()) {
    const png = join(work, 'shot.png')
    const jpg = join(work, 'shot.jpg')
    // A fresh profile each time: no stored appearance, so the page shows as a first visit does.
    const profile = mkdtempSync(join(work, 'profile-'))
    await shoot(`http://127.0.0.1:${port}/__card/${i}`, png, profile)
    execFileSync('sips', ['--resampleWidth', '1200', '-s', 'format', 'jpeg', '-s', 'formatOptions', '86', png, '--out', jpg],
      { stdio: 'ignore' })
    const buf = withMetadata(readFileSync(jpg), {
      title: t.title,
      description: `The share card of ${t.page}: ${shareAlt(t)}`,
      keywords: ['longbook', 'share image'],
      pageUrl: t.page,
    })
    const out = join(SITE, t.out)
    mkdirSync(dirname(out), { recursive: true })
    writeFileSync(out, buf)
    rmSync(profile, { recursive: true, force: true })
    const missing = [t.iphone, t.mac].filter((k) => k && !built(k))
    console.log(`${t.out} ← ${t.path}${missing.length ? ` (no built ${missing.join(', ')}: left out)` : ''}`)
  }
  writeBuilt(ROOT, 'shares', targets.map((t) => t.out))
} finally {
  rmSync(work, { recursive: true, force: true })
  server.close()
}
