// The features screenshots, share images and films are built on a Mac and kept out of git. This
// list names each one by size and hash; the check reads it and the site deploy carries exactly it.
import { createHash } from 'node:crypto'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

export interface BuiltFile {
  path: string
  bytes: number
  sha256: string
}

export interface Built {
  images: BuiltFile[]
  shares: BuiltFile[]
  media: BuiltFile[]
}

export const BUILT_LIST = 'apps/longbook-site-content/built.json'

export const sha256 = (bytes: Buffer): string => createHash('sha256').update(bytes).digest('hex')

export function readBuilt(root: string): Built {
  const p = join(root, BUILT_LIST)
  if (!existsSync(p)) return { images: [], shares: [], media: [] }
  const raw = JSON.parse(readFileSync(p, 'utf8')) as Partial<Built>
  return { images: raw.images ?? [], shares: raw.shares ?? [], media: raw.media ?? [] }
}

// One section is rewritten at a time: site:images owns images, site:og shares, site:media media.
// Entries in keep are carried over as they are, for files this run did not build.
export function writeBuilt(root: string, section: keyof Built, sitePaths: string[], keep: BuiltFile[] = []): void {
  const built = readBuilt(root)
  built[section] = [...keep, ...sitePaths.map((path) => {
    const bytes = readFileSync(join(root, 'apps/longbook-site', path))
    return { path, bytes: bytes.length, sha256: sha256(bytes) }
  })].sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0))
  writeFileSync(join(root, BUILT_LIST), `${JSON.stringify(built, null, 2)}\n`)
}
