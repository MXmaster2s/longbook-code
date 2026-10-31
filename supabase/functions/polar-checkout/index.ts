// Opens Polar for a signed-in account: a checkout for the licence, carrying the account's id so
// the paid order finds it, or the customer portal with its receipts and licence key. An account
// that already holds an active licence is not sent to checkout.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { POLAR_PORTAL, WHY, checkoutBody, overLimit, polarApi, polarEnvironment, polarHeaders, portalBody, type Why } from '../_shared/polar.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
// An organization access token with checkouts:write and customer_sessions:write.
const POLAR_ACCESS_TOKEN = Deno.env.get('POLAR_ACCESS_TOKEN')
// The licence's product on Polar.
const PRODUCT_ID = Deno.env.get('POLAR_PRODUCT_ID')
// production or sandbox, which picks api.polar.sh or sandbox-api.polar.sh.
const API = polarApi(polarEnvironment(Deno.env.get('POLAR_ENVIRONMENT')))

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
}
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } })
const refuse = (why: Why, status: number) => json({ why: WHY[why] }, status)
const ATTEMPTS = new Map<string, number[]>()

async function polar(path: string, body: unknown): Promise<Response | null> {
  return await fetch(`${API}${path}`, {
    method: 'POST',
    headers: polarHeaders(POLAR_ACCESS_TOKEN),
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(10_000),
  }).catch(() => null)
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS_HEADERS })
  if (req.method !== 'POST') return json({ why: 'POST only.' }, 405)

  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer /, '')
  if (!jwt) return refuse('signIn', 401)
  const anon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  const { data: { user }, error: authError } = await anon.auth.getUser(jwt)
  if (authError || !user) return refuse('signIn', 401)
  if (overLimit(ATTEMPTS, user.id, Date.now())) return refuse('tooMany', 429)

  let body: { action?: unknown }
  try {
    body = await req.json()
  } catch {
    return refuse('noAction', 400)
  }
  if (!POLAR_ACCESS_TOKEN || !PRODUCT_ID) return refuse('notSet', 503)

  if (body.action === 'portal') {
    const res = await polar('/v1/customer-sessions/', portalBody(user.id))
    // No Polar customer carries this account's id yet: Polar answers 404 or 422, and the
    // portal's own sign-in by email takes over.
    if (res?.status === 404 || res?.status === 422) return json({ url: POLAR_PORTAL })
    if (!res?.ok) return refuse('unavailable', 502)
    const session = (await res.json()) as { customer_portal_url?: string }
    return json({ url: session.customer_portal_url ?? POLAR_PORTAL })
  }

  if (body.action !== 'checkout') return refuse('noAction', 400)
  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const { data: held, error } = await service.from('entitlements').select('status').eq('user_id', user.id).maybeSingle()
  if (error) return refuse('unavailable', 502)
  if (held?.status === 'active') return refuse('licensed', 409)
  const res = await polar('/v1/checkouts/', checkoutBody({ productId: PRODUCT_ID, userId: user.id, email: user.email ?? null }))
  if (!res?.ok) {
    console.error('polar checkout', res?.status ?? 'unreachable')
    return refuse('unavailable', 502)
  }
  const checkout = (await res.json()) as { url?: string }
  if (!checkout.url) return refuse('unavailable', 502)
  return json({ url: checkout.url })
})
