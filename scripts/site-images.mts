#!/usr/bin/env -S npx tsx
// Turns the app screenshots the features pages show into web images: the newest version of each
// screen in images/screenshots, in sRGB, resized and saved as JPEG by macOS's sips, with its
// description and copyright written into the file. macOS only. Regenerate: npm run site:images.
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { loadFeatures, loadScreens, ORIGIN, type Screen } from './site-pages/content.mts'
import { jpegSize, withMetadata } from './site-pages/jpeg.mts'
import { writeBuilt } from './site-pages/built.mts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SITE = join(ROOT, 'apps/longbook-site')
const CONTENT = join(ROOT, 'apps/longbook-site-content')
const OUT = join(SITE, 'features/img')
const WIDTHS = { iphone: [720, 400], mac: [1280, 640] } as const
const QUALITY = '82'
// A generic profile, so a file carries no trace of the display it was captured on.
const SRGB = '/System/Library/ColorSync/Profiles/sRGB Profile.icc'
if (!existsSync(SRGB)) throw new Error(`no sRGB profile at ${SRGB}`)

// The screenshots are gitignored, so a worktree has none; the main checkout holds them.
function shots(): string {
  const here = join(ROOT, 'images/screenshots')
  if (existsSync(here)) return here
  const common = execFileSync('git', ['rev-parse', '--path-format=absolute', '--git-common-dir'], { cwd: ROOT, encoding: 'utf8' }).trim()
  const main = join(dirname(common), 'images/screenshots')
  if (existsSync(main)) return main
  throw new Error('no images/screenshots folder here or in the main checkout')
}

// "ios/02-all-commitments" names every version of that screen; the highest -vN wins.
function newest(dir: string, source: string): string | null {
  const [folder, name] = source.split('/') as [string, string]
  const versions = readdirSync(join(dir, folder)).flatMap((file) => {
    if (file === `${name}.png`) return [{ file, v: 0 }]
    const m = new RegExp(`^${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}-v(\\d+)\\.png$`).exec(file)
    return m ? [{ file, v: Number(m[1]) }] : []
  })
  if (!versions.length) return null
  return `${folder}/${versions.sort((a, b) => b.v - a.v)[0]!.file}`
}

const dir = shots()
const screens = loadScreens(join(CONTENT, 'screens.json'))
const features = loadFeatures(join(CONTENT, 'features'))
const usedBy = (key: string): string[] => features
  .filter((f) => (f.platforms.includes('iphone') && f.iphone === key) || (f.platforms.includes('mac') && f.mac === key))
  .map((f) => f.slug)

const lockPath = join(CONTENT, 'screens.lock.json')
const before = (existsSync(lockPath) ? JSON.parse(readFileSync(lockPath, 'utf8')) : {}) as Record<string, object>
const tmp = mkdtempSync(join(tmpdir(), 'longbook-site-images-'))
const lock: Record<string, object> = {}
const kept = new Set<string>()
const missing: string[] = []
try {
  mkdirSync(OUT, { recursive: true })
  for (const s of [...screens.values()].sort((a, b) => a.key.localeCompare(b.key))) {
    const pages = usedBy(s.key)
    if (!s.source || !pages.length) continue
    const found = newest(dir, s.source)
    if (!found) {
      // Keep what was built before rather than take a picture off a page.
      missing.push(`${s.key} (${s.source})`)
      if (before[s.key]) {
        lock[s.key] = before[s.key]!
        for (const name of [`${s.key}.jpg`, `${s.key}-sm.jpg`]) if (existsSync(join(OUT, name))) kept.add(name)
      }
      continue
    }
    const sizes = render(s, join(dir, found), pages)
    lock[s.key] = { source: found, ...sizes }
    console.log(`${s.key} ← ${found}`)
  }
  for (const file of readdirSync(OUT)) {
    if (!kept.has(file)) rmSync(join(OUT, file))
  }
  writeFileSync(lockPath, `${JSON.stringify(lock, null, 2)}\n`)
  writeBuilt(ROOT, 'images', [...kept].map((f) => `features/img/${f}`))
} finally {
  rmSync(tmp, { recursive: true, force: true })
}
if (missing.length) {
  console.error(`no screenshot found for: ${missing.join(', ')} — the earlier images were kept.`)
  process.exitCode = 1
}

function render(s: Screen, src: string, pages: string[]): object {
  const [large, small] = WIDTHS[s.platform]
  const meta = {
    title: s.title,
    description: s.description,
    keywords: ['longbook', s.platform === 'iphone' ? 'iPhone' : 'Mac', 'app screenshot', s.title],
    pageUrl: `${ORIGIN}/features/${pages[0]}/`,
  }
  const out: Record<string, number> = {}
  for (const [width, suffix] of [[large, ''], [small, '-sm']] as const) {
    const staged = join(tmp, `${s.key}${suffix}.jpg`)
    execFileSync('sips', ['--matchTo', SRGB, '--resampleWidth', String(width), '-s', 'format', 'jpeg',
      '-s', 'formatOptions', QUALITY, src, '--out', staged], { stdio: 'ignore' })
    const buf = withMetadata(readFileSync(staged), meta)
    const name = `${s.key}${suffix}.jpg`
    writeFileSync(join(OUT, name), buf)
    kept.add(name)
    const size = jpegSize(buf)
    out[suffix ? 'smallWidth' : 'width'] = size.width
    out[suffix ? 'smallHeight' : 'height'] = size.height
  }
  return out
}
