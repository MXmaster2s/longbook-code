#!/usr/bin/env -S npx tsx
// Makes what an App Store build is signed with: the distribution and Mac installer
// certificates, and a profile per bundle id and platform, through App Store Connect's API.
// Nothing is created twice. Xcode never makes distribution certificates itself
// (docs/releasing-ios.md). Once a year: npm run asc:provision.
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { createSign } from 'node:crypto'
import { homedir, tmpdir } from 'node:os'
import { join } from 'node:path'

const TEAM = '27F9SH746V'
const API = 'https://api.appstoreconnect.apple.com/v1'
const PROFILES = [
  { bundleId: 'app.longbook.longbook', name: 'longbook App Store', type: 'IOS_APP_STORE', ext: 'mobileprovision' },
  { bundleId: 'app.longbook.longbook.widget', name: 'longbook Widget App Store', type: 'IOS_APP_STORE', ext: 'mobileprovision' },
  { bundleId: 'app.longbook.longbook', name: 'longbook Mac App Store', type: 'MAC_APP_STORE', ext: 'provisionprofile' },
]

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
  console.error(`No key at ${KEY_PATH}. xcodebuild reads it only from there — move it, do not point at it.`)
  process.exit(1)
}

// A short-lived ES256 token, the shape App Store Connect asks for. The key never leaves this
// process and is never written anywhere.
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

const call = async (path: string, body?: unknown): Promise<any> => {
  const res = await fetch(`${API}/${path}`, {
    method: body ? 'POST' : 'GET',
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await res.text()
  if (!res.ok) {
    console.error(`App Store Connect refused ${path}: ${res.status}`)
    console.error(text.slice(0, 600))
    process.exit(1)
  }
  return text ? JSON.parse(text) : {}
}

// ---- the certificate -------------------------------------------------------------------

const existing = await call('certificates?filter[certificateType]=DISTRIBUTION&limit=20')
let certId: string | undefined = existing.data?.[0]?.id
const installed = (() => {
  try {
    return sh('security', ['find-identity', '-v', '-p', 'codesigning']).includes('Apple Distribution')
  } catch {
    return false
  }
})()

if (certId && installed) {
  console.log(`✓ Apple Distribution certificate — already on the account and in the keychain.`)
} else {
  // The private half is generated here and imported straight into the keychain; the file it
  // passes through is shredded. A distribution key that also sits on disk is a second copy of
  // the thing that proves who built the app.
  const dir = sh('mktemp', ['-d', join(tmpdir(), 'lb-cert-XXXX')]).trim()
  sh('chmod', ['700', dir])
  try {
    sh('openssl', ['req', '-new', '-newkey', 'rsa:2048', '-nodes',
      '-keyout', join(dir, 'k.pem'), '-out', join(dir, 'c.csr'),
      '-subj', `/CN=longbook distribution/O=Rohit Kundliwal/C=IN`])
    const made = await call('certificates', {
      data: {
        type: 'certificates',
        attributes: { certificateType: 'DISTRIBUTION', csrContent: readFileSync(join(dir, 'c.csr'), 'utf8') },
      },
    })
    certId = made.data.id
    writeFileSync(join(dir, 'c.cer'), Buffer.from(made.data.attributes.certificateContent, 'base64'))
    const login = join(homedir(), 'Library/Keychains/login.keychain-db')
    for (const f of ['k.pem', 'c.cer']) {
      sh('security', ['import', join(dir, f), '-k', login, '-T', '/usr/bin/codesign', '-T', '/usr/bin/security', '-A'])
    }
    console.log(`✓ Apple Distribution certificate created and imported (expires ${made.data.attributes.expirationDate?.slice(0, 10)}).`)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
}

// ---- the installer certificate ---------------------------------------------------------
// A Mac App Store upload is an installer package, signed with its own certificate type.

const installers = await call('certificates?filter[certificateType]=MAC_INSTALLER_DISTRIBUTION&limit=20')
const installerInstalled = (() => {
  try {
    return sh('security', ['find-identity', '-v']).includes('3rd Party Mac Developer Installer')
  } catch {
    return false
  }
})()
if (installers.data?.[0] && installerInstalled) {
  console.log('✓ Mac Installer Distribution certificate — already on the account and in the keychain.')
} else {
  const dir = sh('mktemp', ['-d', join(tmpdir(), 'lb-inst-XXXX')]).trim()
  sh('chmod', ['700', dir])
  try {
    sh('openssl', ['req', '-new', '-newkey', 'rsa:2048', '-nodes',
      '-keyout', join(dir, 'k.pem'), '-out', join(dir, 'c.csr'),
      '-subj', `/CN=longbook installer/O=Rohit Kundliwal/C=IN`])
    const made = await call('certificates', {
      data: {
        type: 'certificates',
        attributes: { certificateType: 'MAC_INSTALLER_DISTRIBUTION', csrContent: readFileSync(join(dir, 'c.csr'), 'utf8') },
      },
    })
    writeFileSync(join(dir, 'c.cer'), Buffer.from(made.data.attributes.certificateContent, 'base64'))
    const login = join(homedir(), 'Library/Keychains/login.keychain-db')
    for (const f of ['k.pem', 'c.cer']) {
      sh('security', ['import', join(dir, f), '-k', login, '-T', '/usr/bin/codesign', '-T', '/usr/bin/security', '-T', '/usr/bin/productbuild', '-A'])
    }
    console.log(`✓ Mac Installer Distribution certificate created and imported (expires ${made.data.attributes.expirationDate?.slice(0, 10)}).`)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
}

// ---- the profiles ----------------------------------------------------------------------

const bundleIds = await call('bundleIds?limit=200')
const byIdentifier = new Map<string, string>(
  (bundleIds.data ?? []).map((b: any) => [b.attributes.identifier, b.id]),
)
const have = await call('profiles?limit=200')
const haveNames = new Set((have.data ?? []).map((p: any) => p.attributes.name))

const dest = join(homedir(), 'Library/Developer/Xcode/UserData/Provisioning Profiles')
mkdirSync(dest, { recursive: true })

for (const { bundleId, name, type, ext } of PROFILES) {
  const id = byIdentifier.get(bundleId)
  if (!id) {
    console.error(`No bundle id "${bundleId}" on the account. Register it before provisioning.`)
    process.exit(1)
  }
  let profile = (have.data ?? []).find((p: any) => p.attributes.name === name)
  if (!profile) {
    const made = await call('profiles', {
      data: {
        type: 'profiles',
        attributes: { name, profileType: type },
        relationships: {
          bundleId: { data: { id, type: 'bundleIds' } },
          certificates: { data: [{ id: certId, type: 'certificates' }] },
        },
      },
    })
    profile = made.data
  }
  const file = join(dest, `${profile.attributes.uuid}.${ext}`)
  writeFileSync(file, Buffer.from(profile.attributes.profileContent, 'base64'))
  console.log(`✓ ${name} — ${haveNames.has(name) ? 'already there' : 'created'}, installed for ${bundleId}`)
}

console.log(`\nThe names above are the ones scripts/ios-export-options.plist and scripts/mas-export-options.plist pin. Team ${TEAM}.`)
console.log('Now: npm run release:ios')
