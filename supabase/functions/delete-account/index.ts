// Deletes the caller's account and everything the server holds. The user id comes from the
// verified JWT, never the request, so only the caller goes. Tables keyed to a user cascade
// from auth.users; its web orders keep only their number and status. The memory is on the
// device.
import { createClient } from 'npm:@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
// An account Apple opened ends its Apple link first, as Apple asks: the app sends a fresh
// authorization code, swapped here for the token Apple revokes. The key is the one the
// developer account issued; unset, the link stays.
const APPLE_TEAM_ID = Deno.env.get('APPLE_TEAM_ID')
const APPLE_SIWA_KEY_ID = Deno.env.get('APPLE_SIWA_KEY_ID')
const APPLE_SIWA_PRIVATE_KEY = Deno.env.get('APPLE_SIWA_PRIVATE_KEY')
// The app's bundle id: the client every authorization code it obtains is issued to.
const APPLE_CLIENT_ID = 'app.longbook.longbook'

// Called from the app, which sends Authorization, so the browser-style preflight applies here
// too. Origin is open: the boundary is the JWT below, not which caller is asking.
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// An address as a LIKE pattern matching only itself. PostgREST's star stays a wildcard, so the
// rows found are compared exactly as well.
const likeExactly = (email: string) => email.trim().replace(/[\\%_]/g, '\\$&')
const sameEmail = (a: string | null | undefined, b: string) => !!a && a.trim().toLowerCase() === b.trim().toLowerCase()

type Admin = ReturnType<typeof createClient>

// What a deleted account's web order keeps: its number and status, so a repeated delivery or a
// late refund from Polar finds it gone rather than writing the buyer back. claimed_at set with
// user_id null marks it; a zero amount keeps it out of the seat count.
const emptied = () => ({
  email: null, external_customer_id: null, polar_customer_id: null, license_key_id: null,
  claimed_by: null, user_id: null, country: null, amount: 0, claimed_at: new Date().toISOString(),
})

/** The account's web orders, emptied: those it claimed, and those still unclaimed under its
 *  address. False when either step failed, so the account stays for a retry. */
async function emptyOrders(admin: Admin, userId: string, email: string | undefined): Promise<boolean> {
  const { error } = await admin.from('web_orders').update(emptied()).or(`claimed_by.eq.${userId},user_id.eq.${userId}`)
  if (error) return false
  if (!email) return true
  const { data, error: findFailure } = await admin.from('web_orders').select('order_id, email')
    .is('claimed_at', null).ilike('email', likeExactly(email))
  if (findFailure) return false
  const ids = ((data ?? []) as { order_id: string; email: string | null }[])
    .filter((row) => sameEmail(row.email, email)).map((row) => row.order_id)
  if (!ids.length) return true
  const { error: unclaimedFailure } = await admin.from('web_orders').update(emptied()).in('order_id', ids)
  return !unclaimedFailure
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS, 'content-type': 'application/json' } })

const utf8 = (text: string) => new TextEncoder().encode(text)
const base64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

// Apple's client secret: a five-minute ES256 token signed with the key, which the secret
// holds as the .p8's base64 body — with or without the PEM lines.
async function appleClientSecret(): Promise<string> {
  const body = APPLE_SIWA_PRIVATE_KEY!.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0))
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign'])
  const now = Math.floor(Date.now() / 1000)
  const header = base64url(utf8(JSON.stringify({ alg: 'ES256', kid: APPLE_SIWA_KEY_ID })))
  const claims = base64url(utf8(JSON.stringify({
    iss: APPLE_TEAM_ID, iat: now, exp: now + 300, aud: 'https://appleid.apple.com', sub: APPLE_CLIENT_ID,
  })))
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, utf8(`${header}.${claims}`))
  return `${header}.${claims}.${base64url(new Uint8Array(signature))}`
}

// Null once Apple has ended the link, else the sentence the app shows. The code lives five
// minutes and works once, so a retry needs a fresh confirmation in the app.
async function revokeApple(code: string): Promise<string | null> {
  const secret = await appleClientSecret()
  const ask = (path: string, form: Record<string, string>) =>
    fetch(`https://appleid.apple.com/auth/${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: APPLE_CLIENT_ID, client_secret: secret, ...form }),
    })
  const exchanged = await ask('token', { grant_type: 'authorization_code', code })
  const tokens = exchanged.ok ? await exchanged.json() : null
  if (typeof tokens?.refresh_token !== 'string') return 'Apple did not confirm the sign-in. Try again.'
  const revoked = await ask('revoke', { token: tokens.refresh_token, token_type_hint: 'refresh_token' })
  return revoked.ok ? null : 'Apple could not end the sign-in. Try again.'
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)

  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer /, '')
  if (!jwt) return json({ error: 'Sign in first.' }, 401)

  // A token an AI connector holds names its client (client_id). Deleting the account is the
  // account holder's act, from the app.
  try {
    const part = jwt.split('.')[1] ?? ''
    const claims = JSON.parse(atob(part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=')))
    if (typeof claims.client_id === 'string') return json({ error: 'Only the app can delete the account.' }, 403)
  } catch {
    // Not a readable token: getUser below refuses it.
  }

  const asCaller = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  const { data: { user }, error } = await asCaller.auth.getUser(jwt)
  if (error || !user) return json({ error: 'That session is no longer valid.' }, 401)

  // Builds before 48 send no code: the account still goes, and the Apple link stays until
  // the reader ends it in Settings.
  const body = (await req.json().catch(() => ({}))) as { apple_code?: unknown }
  const viaApple = (user.identities ?? []).some((identity) => identity.provider === 'apple')
  if (viaApple && typeof body.apple_code === 'string' && APPLE_SIWA_PRIVATE_KEY) {
    const refusal = await revokeApple(body.apple_code).catch(() => 'Apple could not be reached. Try again.')
    if (refusal) return json({ error: refusal }, 502)
  }

  // The service role is the only key that may delete a user. It is used for that one call and
  // the orders before it, on an id and an address that came from the token rather than the body.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  if (!(await emptyOrders(admin, user.id, user.email))) {
    return json({ error: 'The account could not be deleted. Try again shortly.' }, 500)
  }
  const { error: failure } = await admin.auth.admin.deleteUser(user.id)
  if (failure) {
    // The delete either takes the row and its cascades, or changes nothing; the licence still
    // stands on its entitlement if only the orders went.
    return json({ error: 'The account could not be deleted. Try again shortly.' }, 500)
  }

  return json({ ok: true, folder_untouched: true })
})
