// Sign in with Apple's server-to-server notices: a JWT Apple signs when a person turns Hide My
// Email forwarding off or on, stops using Apple with longbook, or deletes their Apple Account.
// Pure but for the injected parts, so a test runs it.

export const APPLE_ISSUER = 'https://appleid.apple.com'
export const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys'
/** The primary App ID Sign in with Apple is configured on; Apple names it as the audience. */
export const APPLE_AUDIENCES = ['app.longbook.longbook']
/** Clocks differ a little; a token is not refused for that. */
const SKEW_SECONDS = 300

export interface AppleKey {
  kty: string
  kid: string
  alg?: string
  n: string
  e: string
}

export interface AppleEvent {
  type: string
  sub: string
  email?: string
  eventTime?: number
}

export type AppleAction = 'relay_off' | 'relay_on' | 'end_sessions' | 'delete_account' | 'ignore'

const decodeSegment = (segment: string): Uint8Array => {
  const b64 = segment.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(segment.length / 4) * 4, '=')
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))
}
const json = (segment: string): Record<string, unknown> => JSON.parse(new TextDecoder().decode(decodeSegment(segment)))

/**
 * The event Apple signed, or a thrown reason it is refused: an RS256 signature by the key the
 * header names from Apple's published set, issued by Apple, for longbook, and not expired.
 * `keys(true)` asks for a fresh set, for a key Apple has newly rotated in.
 */
export async function verifyAppleNotice(
  token: string,
  opts: { keys: (fresh: boolean) => Promise<AppleKey[]>; now: Date; audiences?: string[] },
): Promise<AppleEvent> {
  const parts = token.split('.')
  if (parts.length !== 3) throw new Error('not a JWT')
  const [h, p, sig] = parts as [string, string, string]
  const header = json(h)
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') throw new Error('not signed the way Apple signs')
  let key = (await opts.keys(false)).find((k) => k.kid === header.kid)
  if (!key) key = (await opts.keys(true)).find((k) => k.kid === header.kid)
  if (!key || key.kty !== 'RSA') throw new Error('no Apple key by that id')
  const verifier = await crypto.subtle.importKey(
    'jwk', { kty: 'RSA', n: key.n, e: key.e, alg: 'RS256', ext: true },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify'],
  )
  const signed = new TextEncoder().encode(`${h}.${p}`)
  if (!(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', verifier, decodeSegment(sig), signed))) throw new Error('bad signature')

  const claims = json(p)
  const now = Math.floor(opts.now.getTime() / 1000)
  if (claims.iss !== APPLE_ISSUER) throw new Error('not issued by Apple')
  const audiences = opts.audiences ?? APPLE_AUDIENCES
  const aud = Array.isArray(claims.aud) ? claims.aud : [claims.aud]
  if (!aud.some((a) => typeof a === 'string' && audiences.includes(a))) throw new Error('not for longbook')
  if (typeof claims.exp === 'number' && claims.exp + SKEW_SECONDS < now) throw new Error('expired')
  if (typeof claims.iat === 'number' && claims.iat - SKEW_SECONDS > now) throw new Error('issued in the future')

  // Apple sends the events claim as a JSON string; its own examples show an object. Both read.
  const raw = typeof claims.events === 'string' ? JSON.parse(claims.events) : claims.events
  const events = (raw ?? {}) as Record<string, unknown>
  if (typeof events.type !== 'string' || typeof events.sub !== 'string' || !events.sub) throw new Error('no event')
  return {
    type: events.type,
    sub: events.sub,
    email: typeof events.email === 'string' ? events.email : undefined,
    eventTime: typeof events.event_time === 'number' ? events.event_time : undefined,
  }
}

/** What longbook does for each event type. account-delete is accepted as well as Apple's spelling. */
export function actionFor(type: string): AppleAction {
  switch (type) {
    case 'email-disabled': return 'relay_off'
    case 'email-enabled': return 'relay_on'
    case 'consent-revoked': return 'end_sessions'
    case 'account-deleted':
    case 'account-delete': return 'delete_account'
    default: return 'ignore'
  }
}

/** What the handler needs of the database, given by the function and faked by the test. */
export interface AccountStore {
  userForSub(sub: string): Promise<string | null>
  setRelayOff(userId: string, offAt: string | null): Promise<void>
  endSessions(userId: string): Promise<void>
  /** The same deletion as the app's Delete Account: the auth user, and every row cascading from it. */
  deleteAccount(userId: string): Promise<void>
}

/**
 * Acts on one verified event. An Apple user no longbook account signed in with is answered
 * and left, so Apple stops retrying. A failure throws, so the caller answers 500 and Apple
 * tries again later.
 */
export async function handleAppleEvent(event: AppleEvent, store: AccountStore, now: Date): Promise<{ action: AppleAction; matched: boolean }> {
  const action = actionFor(event.type)
  if (action === 'ignore') return { action, matched: false }
  const userId = await store.userForSub(event.sub)
  if (!userId) return { action, matched: false }
  const at = event.eventTime ? new Date(event.eventTime * (event.eventTime > 1e12 ? 1 : 1000)) : now
  if (action === 'relay_off') await store.setRelayOff(userId, at.toISOString())
  if (action === 'relay_on') await store.setRelayOff(userId, null)
  if (action === 'end_sessions') await store.endSessions(userId)
  if (action === 'delete_account') await store.deleteAccount(userId)
  return { action, matched: true }
}

/** The JWT out of Apple's POST: a JSON body with payload, or the same as a form. */
export function payloadOf(body: string, contentType: string | null): string | null {
  const text = body.trim()
  if ((contentType ?? '').includes('application/x-www-form-urlencoded') || text.startsWith('payload=')) {
    return new URLSearchParams(text).get('payload')
  }
  try {
    const parsed = JSON.parse(text) as { payload?: unknown }
    return typeof parsed.payload === 'string' ? parsed.payload : null
  } catch {
    return null
  }
}
