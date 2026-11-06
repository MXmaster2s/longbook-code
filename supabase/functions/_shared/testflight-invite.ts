// Invites a web buyer to the iPhone beta on TestFlight: their email joins the external group
// Early access, and Apple sends the invitation. The key is its own App Store Connect key with the
// App Manager role, held as function secrets. Every step may repeat safely.
import * as jose from 'npm:jose@5'

const API = 'https://api.appstoreconnect.apple.com'
const APP_ID = '6795070908'
export const BETA_GROUP = 'Early access'

export interface TestersKey {
  keyId: string
  issuerId: string
  /** The .p8 file's text. */
  privateKey: string
}

/** The testers key from ASC_TESTERS_KEY_ID, ASC_TESTERS_ISSUER_ID and ASC_TESTERS_PRIVATE_KEY, or
 *  null when any is missing. */
export function testersKeyFromEnv(read: (name: string) => string | undefined): TestersKey | null {
  const privateKey = read('ASC_TESTERS_PRIVATE_KEY'), keyId = read('ASC_TESTERS_KEY_ID'), issuerId = read('ASC_TESTERS_ISSUER_ID')
  return privateKey && keyId && issuerId ? { privateKey, keyId, issuerId } : null
}

async function token(key: TestersKey): Promise<string> {
  const signing = await jose.importPKCS8(key.privateKey, 'ES256')
  return await new jose.SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: key.keyId, typ: 'JWT' })
    .setIssuer(key.issuerId)
    .setIssuedAt()
    .setExpirationTime('10m')
    .setAudience('appstoreconnect-v1')
    .sign(signing)
}

type Linkage = { id: string; attributes?: { name?: string } }

/** Puts `email` in the Early access group. A tester already there, or Apple calling the request a
 *  duplicate, is success; anything else throws with the status alone, never the address. */
export async function inviteToBeta(key: TestersKey, email: string): Promise<void> {
  const headers = { Authorization: `Bearer ${await token(key)}`, 'Content-Type': 'application/json' }
  const call = async (path: string, body?: unknown, missing: Linkage[] | null = null): Promise<Linkage[]> => {
    const res = await fetch(`${API}${path}`, {
      method: body === undefined ? 'GET' : 'POST',
      headers,
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      signal: AbortSignal.timeout(10_000),
    })
    if (res.status === 409) return []
    if (res.status === 404 && missing) return missing
    if (!res.ok) throw new Error(`testflight invite: ${res.status}`)
    if (res.status === 204) return []
    const { data } = (await res.json().catch(() => ({}))) as { data?: Linkage[] | Linkage }
    return Array.isArray(data) ? data : []
  }
  const groups = await call(`/v1/apps/${APP_ID}/betaGroups?limit=200`)
  const group = groups.find((g) => g.attributes?.name === BETA_GROUP)
  if (!group) throw new Error('testflight invite: no group')
  const query = new URLSearchParams({ 'filter[email]': email, 'filter[apps]': APP_ID })
  const [tester] = await call(`/v1/betaTesters?${query}`)
  if (!tester) {
    await call('/v1/betaTesters', {
      data: {
        type: 'betaTesters',
        attributes: { email },
        relationships: { betaGroups: { data: [{ type: 'betaGroups', id: group.id }] } },
      },
    })
    return
  }
  // Apple answers 404 for a tester whose access was removed; adding them to the group invites them again.
  const memberOf = await call(`/v1/betaTesters/${encodeURIComponent(tester.id)}/relationships/betaGroups?limit=200`, undefined, [])
  if (memberOf.some((g) => g.id === group.id)) return
  await call(`/v1/betaGroups/${encodeURIComponent(group.id)}/relationships/betaTesters`, {
    data: [{ type: 'betaTesters', id: tester.id }],
  })
}
