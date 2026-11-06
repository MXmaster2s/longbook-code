#!/usr/bin/env -S npx tsx
// Lists longbook in the MCP registry as app.longbook/mcp, proven ours by a TXT record on
// longbook.app holding our public key. --setup makes the key and adds the record once.
// Run: npm run registry:publish [-- --setup | --dry-run]
import { execFileSync } from 'node:child_process'
import { createPrivateKey, createPublicKey, generateKeyPairSync, sign } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import Ajv from 'ajv'
import addFormats from 'ajv-formats'
import { MCP_NAME, NPM_NAME, RELEASE_VERSION, ROOT } from './release.mts'

const REGISTRY = 'https://registry.modelcontextprotocol.io'
const DOMAIN = 'longbook.app'
const ZONE = '94a06b6e20cefc740f62bc5d58f72cc9'
const KEY_ITEM = 'longbook MCP registry key'
const SETUP = process.argv.includes('--setup')
const DRY = process.argv.includes('--dry-run')

const sh = (cmd: string, args: string[]): string => execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
const stop = (message: string): never => {
  console.error(message)
  process.exit(1)
}
const keychain = (service: string): string | null => {
  try { return sh('security', ['find-generic-password', '-s', service, '-w']).trim() } catch { return null }
}

// ---- the key: Ed25519, private half only in the keychain ------------------------------------
let stored = keychain(KEY_ITEM)
if (!stored) {
  if (!SETUP) stop(`No keychain item "${KEY_ITEM}". Run once: npm run registry:publish -- --setup`)
  const { privateKey } = generateKeyPairSync('ed25519')
  stored = privateKey.export({ format: 'der', type: 'pkcs8' }).toString('base64')
  sh('security', ['add-generic-password', '-s', KEY_ITEM, '-a', DOMAIN, '-w', stored])
  console.log(`Made a new signing key and kept it in the keychain as "${KEY_ITEM}".`)
}
const privateKey = createPrivateKey({ key: Buffer.from(stored, 'base64'), format: 'der', type: 'pkcs8' })
const publicRaw = createPublicKey(privateKey).export({ format: 'der', type: 'spki' }).subarray(-32)
const RECORD = `v=MCPv1; k=ed25519; p=${publicRaw.toString('base64')}`

// ---- the record on longbook.app --------------------------------------------------------------
const published = (): boolean => sh('dig', ['+short', 'TXT', DOMAIN, '@keira.ns.cloudflare.com']).includes(RECORD)
if (!published()) {
  if (!SETUP) stop(`${DOMAIN} has no TXT record "${RECORD}". Run: npm run registry:publish -- --setup`)
  const token = keychain('Cloudflare API Token') ?? stop('No keychain item "Cloudflare API Token".')
  const response = await fetch(`https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records`, {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'TXT', name: DOMAIN, content: `"${RECORD}"`, ttl: 1, comment: 'MCP registry: proves app.longbook/* is ours' }),
  })
  const body = (await response.json()) as { success?: boolean; errors?: unknown }
  if (!body.success) stop(`Cloudflare refused the record: ${JSON.stringify(body.errors)}`)
  console.log(`Added the TXT record to ${DOMAIN}.`)
  for (let i = 0; i < 20 && !published(); i++) await new Promise((r) => setTimeout(r, 3000))
  if (!published()) stop('The record is not visible yet. Run again in a minute.')
}

// ---- the entry ----------------------------------------------------------------------------
const server = JSON.parse(readFileSync(join(ROOT, 'packages/mcp/server.json'), 'utf8'))
if (server.name !== MCP_NAME || server.version !== RELEASE_VERSION) stop('packages/mcp/server.json is not stamped. Run: npm run release')
const schema = await (await fetch(server.$schema)).json()
const ajv = new Ajv({ strict: false, allErrors: true })
addFormats(ajv)
const valid = ajv.compile(schema)
if (!valid(server)) stop(`server.json does not match the registry's schema: ${JSON.stringify(valid.errors)}`)
const npmVersion = (() => { try { return sh('npm', ['view', `${NPM_NAME}@${RELEASE_VERSION}`, 'version']).trim() } catch { return '' } })()
if (npmVersion !== RELEASE_VERSION && !DRY) stop(`${NPM_NAME}@${RELEASE_VERSION} is not on npm yet. Run npm run npm:publish first.`)

// ---- sign in and publish ---------------------------------------------------------------------
const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')
const login = await fetch(`${REGISTRY}/v0/auth/dns`, {
  method: 'POST',
  headers: { 'content-type': 'application/json', accept: 'application/json' },
  body: JSON.stringify({ domain: DOMAIN, timestamp, signed_timestamp: sign(null, Buffer.from(timestamp), privateKey).toString('hex') }),
})
if (!login.ok) stop(`The registry refused the sign-in (${login.status}): ${await login.text()}`)
const { registry_token: registryToken } = (await login.json()) as { registry_token: string }
console.log(`Signed in to the MCP registry as ${DOMAIN}; server.json matches the schema.`)

if (DRY) {
  console.log(`Dry run: ${MCP_NAME}@${RELEASE_VERSION} was not published.`)
  process.exit(0)
}
const publish = await fetch(`${REGISTRY}/v0/publish`, {
  method: 'POST',
  headers: { 'content-type': 'application/json', authorization: `Bearer ${registryToken}` },
  body: JSON.stringify(server),
})
if (!publish.ok) stop(`The registry refused ${MCP_NAME}@${RELEASE_VERSION} (${publish.status}): ${await publish.text()}`)
console.log(`Published ${MCP_NAME}@${RELEASE_VERSION} to the MCP registry.`)
