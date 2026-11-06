#!/usr/bin/env -S npx tsx
// The website's films, re-encoded from images/videos by scripts/site-media.swift with a poster,
// as apps/longbook-site-content/media.json says. Kept out of git: built.json names each by hash,
// and the site deploy carries them. Run: npm run site:media
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync } from 'node:fs'
import { basename, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { readBuilt, writeBuilt } from './site-pages/built.mts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SITE = join(ROOT, 'apps/longbook-site')

interface Film { source: string; out: string; poster: string; posterAt: number; width: number; bitrate: number; gainDb?: number }
// A still is a finished image from the same folder, saved as JPEG for the site: a page's share
// image, or a blog post's picture at the width and height its page draws it.
interface Still { source: string; out: string; width?: number; height?: number }
// --stills builds the stills alone and keeps the films as built.json names them; --only=<path>
// builds the one film whose address contains <path> with the stills, and keeps the others.
const STILLS_ONLY = process.argv.includes('--stills')
const ONLY = process.argv.find((a) => a.startsWith('--only='))?.slice('--only='.length)
const { films, stills = [] } = JSON.parse(readFileSync(join(ROOT, 'apps/longbook-site-content/media.json'), 'utf8')) as { films: Film[]; stills?: Still[] }

function sources(): string {
  const here = join(ROOT, 'images/videos')
  if (existsSync(here)) return here
  const common = execFileSync('git', ['rev-parse', '--path-format=absolute', '--git-common-dir'], { cwd: ROOT, encoding: 'utf8' }).trim()
  const main = join(dirname(common), 'images/videos')
  if (existsSync(main)) return main
  throw new Error('no images/videos folder here or in the main checkout')
}

const from = sources()
const chosen = STILLS_ONLY ? [] : ONLY ? films.filter((f) => f.out.includes(ONLY)) : films
if (ONLY && !chosen.length) throw new Error(`media.json builds no film at "${ONLY}"`)
for (const f of chosen) {
  const src = join(from, f.source)
  if (!existsSync(src)) throw new Error(`${f.source} is not in ${from}`)
  execFileSync('swift', [join(ROOT, 'scripts/site-media.swift'), src, join(SITE, f.out), String(f.width), String(f.bitrate),
    join(SITE, f.poster), String(f.posterAt), String(f.gainDb ?? 0)], { stdio: 'inherit' })
  // AVAssetWriter leaves its working copy beside the file when it moves the index to the front.
  const dir = dirname(join(SITE, f.out))
  for (const name of readdirSync(dir)) if (name.startsWith(`${basename(f.out)}.sb-`)) rmSync(join(dir, name))
}
for (const s of stills) {
  const src = join(from, s.source)
  if (!existsSync(src)) throw new Error(`${s.source} is not in ${from}`)
  mkdirSync(dirname(join(SITE, s.out)), { recursive: true })
  execFileSync('sips', [...(s.width ? ['--resampleWidth', String(s.width)] : []), '-s', 'format', 'jpeg', '-s', 'formatOptions', '86',
    src, '--out', join(SITE, s.out)], { stdio: 'ignore' })
}
const filmPaths = films.flatMap((f) => [f.out, f.poster])
const builtNow = chosen.flatMap((f) => [f.out, f.poster])
writeBuilt(ROOT, 'media', [...builtNow, ...stills.map((s) => s.out)],
  readBuilt(ROOT).media.filter((m) => filmPaths.includes(m.path) && !builtNow.includes(m.path)))
console.log(`site media — ${chosen.length} film(s) and ${stills.length} still(s) built, named in apps/longbook-site-content/built.json.`)
