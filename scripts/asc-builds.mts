#!/usr/bin/env -S npx tsx
// Lists the app's TestFlight builds and expires every one older than the build named, so a
// tester can install only the current one. `--check` reports without writing; `--platform
// IOS|MAC_OS` confines the expiry to one platform. Run: npm run asc:builds -- --keep 15
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { createSign } from 'node:crypto'
import { homedir } from 'node:os'
import { join } from 'node:path'

const BUNDLE_ID = 'app.longbook.longbook'
const CHECK = process.argv.includes('--check')
const keepAt = process.argv.indexOf('--keep')
const KEEP = keepAt >= 0 ? Number(process.argv[keepAt + 1]) : NaN
if (!Number.isFinite(KEEP)) {
  console.error('Name the build number to keep: --keep <build>. Everything older expires.')
  process.exit(1)
}
const platformAt = process.argv.indexOf('--platform')
const PLATFORM = platformAt >= 0 ? process.argv[platformAt + 1] : null
if (PLATFORM && !['IOS', 'MAC_OS'].includes(PLATFORM)) {
  console.error('--platform takes IOS or MAC_OS.')
  process.exit(1)
}

const sh = (cmd: string, args: string[]): string =>
  execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
const keychain = (service: string): string => {
  try {
    return sh('security', ['find-generic-password', '-s', service, '-w']).trim()
  } catch {
    console.error(`No keychain item "${service}". See docs/releasing-ios.md.`)
    process.exit(1)
  }
}
const KEY_ID = keychain('App Store Connect Key ID')
const ISSUER = keychain('Apple App Store Connect Issuer ID')
const KEY_PATH = join(homedir(), `.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`)
if (!existsSync(KEY_PATH)) {
  console.error(`No key at ${KEY_PATH}.`)
  process.exit(1)
}
const b64u = (b: Buffer): string => b.toString('base64url')
const token = (): string => {
  const now = Math.floor(Date.now() / 1000)
  const header = b64u(Buffer.from(JSON.stringify({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' })))
  const payload = b64u(Buffer.from(JSON.stringify({ iss: ISSUER, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' })))
  const signer = createSign('SHA256')
  signer.update(`${header}.${payload}`)
  const sig = signer.sign({ key: readFileSync(KEY_PATH), dsaEncoding: 'ieee-p1363' })
  return `${header}.${payload}.${b64u(sig)}`
}
const API = 'https://api.appstoreconnect.apple.com'
const call = async (path: string, method = 'GET', body?: unknown): Promise<any> => {
  const res = await fetch(path.startsWith('http') ? path : `${API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await res.text()
  if (!res.ok) {
    console.error(`App Store Connect refused ${method} ${path}: ${res.status}`)
    console.error(text.slice(0, 600))
    process.exit(1)
  }
  return text ? JSON.parse(text) : {}
}

const apps = await call(`/v1/apps?filter[bundleId]=${BUNDLE_ID}`)
const app = apps.data?.[0]
if (!app) {
  console.error(`No App Store Connect record for ${BUNDLE_ID}.`)
  process.exit(1)
}
const listed = await call(`/v1/builds?filter[app]=${app.id}&sort=-uploadedDate&limit=50&include=preReleaseVersion`)
const platforms = new Map<string, string>()
for (const item of listed.included ?? []) {
  if (item.type === 'preReleaseVersions') platforms.set(item.id, item.attributes.platform)
}
const platformOf = (build: any): string =>
  platforms.get(build.relationships?.preReleaseVersion?.data?.id ?? '') ?? '?'
const word = (platform: string): string => (platform === 'MAC_OS' ? 'Mac' : platform === 'IOS' ? 'iPhone' : platform)
for (const build of listed.data ?? []) {
  const number = Number(build.attributes.version)
  const platform = platformOf(build)
  const state = build.attributes.processingState
  const expired = build.attributes.expired
  const older = number < KEEP && (!PLATFORM || platform === PLATFORM)
  if (!older || expired) {
    console.log(`  build ${number} ${word(platform)} — ${state}${expired ? ', expired' : ''}${older ? '' : ' (kept)'}`)
    continue
  }
  if (CHECK) {
    console.log(`· build ${number} ${word(platform)} — would expire`)
    continue
  }
  await call(`/v1/builds/${build.id}`, 'PATCH', {
    data: { type: 'builds', id: build.id, attributes: { expired: true } },
  })
  console.log(`✓ build ${number} ${word(platform)} — expired`)
}
