// What must hold before a disk image that was already built and tried by hand is published as
// it is: the file is the one tried, Gatekeeper accepts it, and the appcast entry was made from
// these bytes. Used by `release:mac-direct --publish-built`.
import { createHash } from 'node:crypto'
import { readFileSync, statSync } from 'node:fs'

export const sha256Of = (path: string): string => createHash('sha256').update(readFileSync(path)).digest('hex')

export interface PublishCheck {
  dmgPath: string
  dmgName: string
  tag: string
  repo: string
  /** The sha-256 the tried file had, as the tester reported it. */
  expectedSha: string
  appcast: string
}

/** The reasons this file may not be published, empty when it may. */
export function publishProblems(c: PublishCheck): string[] {
  const problems: string[] = []
  const actual = sha256Of(c.dmgPath)
  if (!/^[0-9a-f]{64}$/.test(c.expectedSha)) problems.push('--sha256 must be the 64 hex characters of the file that was tried.')
  else if (actual !== c.expectedSha) problems.push(`The file is not the one that was tried: its sha-256 is ${actual}, not ${c.expectedSha}.`)
  const url = `https://github.com/${c.repo}/releases/download/${c.tag}/${c.dmgName}`
  const entry = c.appcast.split('<enclosure').find((part) => part.includes(`url="${url}"`))
  if (!entry) problems.push(`The appcast has no entry for ${url}.`)
  else {
    if (!entry.includes('sparkle:edSignature=')) problems.push('The appcast entry has no EdDSA signature.')
    const length = /length="(\d+)"/.exec(entry)?.[1]
    if (length !== String(statSync(c.dmgPath).size)) problems.push(`The appcast entry's length ${length ?? 'is missing'} is not this file's ${statSync(c.dmgPath).size} bytes.`)
  }
  return problems
}
