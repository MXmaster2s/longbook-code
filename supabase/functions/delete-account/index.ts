// Deletes the caller's account and everything the server holds. The user id comes from the
// verified JWT, never the request, so this can only delete the caller. Every table keyed
// to a user cascades from auth.users; the memory is a folder on the reader's device.
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

  // The service role is the only key that may delete a user, and it is used for exactly that
  // one call, on an id that came from the token rather than the body.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const { error: failure } = await admin.auth.admin.deleteUser(user.id)
  if (failure) {
    // Nothing partial: the delete either takes the row and its cascades, or changes nothing.
    return json({ error: 'The account could not be deleted. Try again shortly.' }, 500)
  }

  return json({ ok: true, folder_untouched: true })
})
