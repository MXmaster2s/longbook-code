// Gives a signed-in account its licence. With a key: Polar validates it, its order must be a
// paid one for the licence, and activating it binds the key to this account, so a second account
// is refused. With action email: the earliest unclaimed order paid under the account's confirmed email.
import { createClient, type SupabaseClient, type User } from 'npm:@supabase/supabase-js@2'
import type { models } from 'npm:@polar-sh/sdk@1.0.2/2026-10'
import { grantPolarLicence, recordOrder } from '../_shared/polar-live.ts'
import {
  ACTIVATION_LABEL,
  WEB_ORDER_COLUMNS,
  WHY,
  activatedBy,
  keyProblem,
  likeExactly,
  orderFromRow,
  pickOrder,
  polarApi,
  polarEnvironment,
  polarHeaders,
  polarRefusal,
  sameEmail,
  type OrderFacts,
  type Why,
} from '../_shared/polar.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
// An organization access token with orders:read and license_keys:read, for a key whose order
// is not recorded here yet. Validate and activate themselves need no token.
const POLAR_ACCESS_TOKEN = Deno.env.get('POLAR_ACCESS_TOKEN')
// The organization a key must belong to, and the licence's product its order must be for.
const ORGANIZATION_ID = Deno.env.get('POLAR_ORGANIZATION_ID')
const PRODUCT_ID = Deno.env.get('POLAR_PRODUCT_ID')
// production or sandbox, which picks api.polar.sh or sandbox-api.polar.sh.
const ENVIRONMENT = polarEnvironment(Deno.env.get('POLAR_ENVIRONMENT'))
const API = polarApi(ENVIRONMENT)
// The confirmation email once the licence is on the account. Without it nothing is sent.
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
}
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } })
const refuse = (why: Why, status: number) => json({ why: WHY[why] }, status)

async function polar(method: 'GET' | 'POST', path: string, body?: unknown, token?: string): Promise<Response | null> {
  return await fetch(`${API}${path}`, {
    method,
    headers: polarHeaders(token),
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    signal: AbortSignal.timeout(10_000),
  }).catch(() => null)
}

/** The key's order: recorded here by key or by customer, else asked of Polar and recorded. */
async function orderFor(service: SupabaseClient, key: models.ValidatedLicenseKey): Promise<OrderFacts | 'refunded' | Why | null> {
  const at = new Date().toISOString()
  for (const [column, value] of [['license_key_id', key.id], ['polar_customer_id', key.customer_id]] as const) {
    const { data } = await service.from('web_orders').select(WEB_ORDER_COLUMNS)
      .eq(column, value).eq('product_id', PRODUCT_ID!).order('paid_at', { ascending: true })
    const rows = (data ?? []) as unknown as Parameters<typeof orderFromRow>[0][]
    const paid = rows.find((r) => r.status === 'paid')
    const facts = paid && orderFromRow(paid)
    if (facts) return facts
    if (rows.some((r) => r.status === 'refunded')) return 'refunded'
  }
  if (!POLAR_ACCESS_TOKEN) return null
  const query = new URLSearchParams({ customer_id: key.customer_id, product_id: PRODUCT_ID!, limit: '20' })
  const res = await polar('GET', `/v1/orders/?${query}`, undefined, POLAR_ACCESS_TOKEN)
  if (!res?.ok) return 'unavailable'
  const { items = [] } = (await res.json()) as { items?: unknown[] }
  const found = pickOrder(items, PRODUCT_ID!, at)
  if (found && found !== 'refunded') await recordOrder(service, found.order, ENVIRONMENT)
  return found
}

const runtime = (globalThis as { EdgeRuntime?: { waitUntil?(work: Promise<unknown>): void } }).EdgeRuntime
/** The confirmation email: carried on after the reply where the runtime allows. */
async function after(work: Promise<void> | null): Promise<void> {
  if (!work) return
  if (runtime?.waitUntil) runtime.waitUntil(work)
  else await work
}

/** A purchase made before the account existed. The address is the one Supabase confirmed, never
 *  one a request names, and the key is left unactivated: the order's claim holds it to this
 *  account. An account already licensed is answered none, untouched. */
async function claimByEmail(user: User): Promise<Response> {
  const none = json({ ok: true, status: 'none' })
  if (!user.email || !user.email_confirmed_at) return none
  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const { data: held, error } = await service.from('entitlements').select('status').eq('user_id', user.id).maybeSingle()
  if (error) return refuse('failed', 500)
  if (held?.status === 'active') return none
  const { data, error: readError } = await service.from('web_orders').select(`${WEB_ORDER_COLUMNS}, license_key_id`)
    .eq('product_id', PRODUCT_ID!).eq('status', 'paid').eq('environment', ENVIRONMENT).is('claimed_at', null)
    .ilike('email', likeExactly(user.email)).order('paid_at', { ascending: true })
  if (readError) return refuse('failed', 500)
  const rows = (data ?? []) as unknown as (Parameters<typeof orderFromRow>[0] & { license_key_id: string | null })[]
  const row = rows.find((r) => sameEmail(r.email, user.email))
  const facts = row ? orderFromRow(row) : null
  if (!row || !facts) return none
  try {
    const granted = await grantPolarLicence(service, {
      order: facts.order,
      account: { id: user.id, email: user.email },
      licenseKeyId: row.license_key_id,
      environment: ENVIRONMENT,
      resendKey: RESEND_API_KEY,
    })
    if (granted.decision === 'held') return none
    await after(granted.confirming)
  } catch (e) {
    console.error('polar claim', (e as Error).message)
    return refuse('failed', 500)
  }
  return json({ ok: true, status: 'active' })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS_HEADERS })
  if (req.method !== 'POST') return json({ why: 'POST only.' }, 405)

  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer /, '')
  if (!jwt) return refuse('signIn', 401)
  const anon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  const { data: { user }, error: authError } = await anon.auth.getUser(jwt)
  if (authError || !user) return refuse('signIn', 401)

  let body: { key?: unknown; action?: unknown }
  try {
    body = await req.json()
  } catch {
    return refuse('noKey', 400)
  }
  if (body.action === 'email') return PRODUCT_ID ? await claimByEmail(user) : refuse('notSet', 503)
  const key = typeof body.key === 'string' ? body.key.trim() : ''
  if (!key || key.length > 256) return refuse('noKey', 400)
  if (!ORGANIZATION_ID || !PRODUCT_ID) return refuse('notSet', 503)

  const validated = await polar('POST', '/v1/customer-portal/license-keys/validate', { key, organization_id: ORGANIZATION_ID })
  if (!validated) return refuse('unavailable', 502)
  if (!validated.ok) return refuse(polarRefusal(validated.status, 'validate'), validated.status >= 500 ? 502 : 400)
  const licenceKey = (await validated.json()) as models.ValidatedLicenseKey
  const problem = keyProblem(licenceKey, new Date())
  if (problem) return refuse(problem, 409)

  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const { data: held } = await service.from('entitlements')
    .select('status, polar_license_key_id').eq('user_id', user.id).maybeSingle()
  if (held?.status === 'active') {
    return held.polar_license_key_id === licenceKey.id ? json({ ok: true, status: 'active' }) : refuse('licensed', 409)
  }

  const found = await orderFor(service, licenceKey)
  if (found === null) return refuse('notLongbook', 409)
  if (found === 'refunded') return refuse('refunded', 409)
  if (typeof found === 'string') return refuse(found, 502)
  const { data: order } = await service.from('web_orders').select('claimed_by').eq('order_id', found.order.order_id).maybeSingle()
  if (order?.claimed_by && order.claimed_by !== user.id) return refuse('inUse', 409)

  // A key whose benefit sets no activation limit cannot be activated; the claim on its order
  // above still holds it to one account.
  if (licenceKey.limit_activations !== null) {
    const activated = await polar('POST', '/v1/customer-portal/license-keys/activate', {
      key,
      organization_id: ORGANIZATION_ID,
      label: ACTIVATION_LABEL,
      meta: { user_id: user.id },
    })
    if (!activated) return refuse('unavailable', 502)
    if (!activated.ok) {
      const why = polarRefusal(activated.status, 'activate')
      // At the limit, the one activation may be this account's own, from a claim that failed after it.
      const own = why === 'inUse' && POLAR_ACCESS_TOKEN
        ? await polar('GET', `/v1/license-keys/${encodeURIComponent(licenceKey.id)}`, undefined, POLAR_ACCESS_TOKEN)
        : null
      const mine = own?.ok && activatedBy((await own.json()) as models.LicenseKeyWithActivations, user.id)
      if (!mine) return refuse(why, why === 'unavailable' ? 502 : 409)
    }
  }

  try {
    const granted = await grantPolarLicence(service, {
      order: found.order,
      account: { id: user.id, email: user.email ?? null },
      licenseKeyId: licenceKey.id,
      environment: ENVIRONMENT,
      resendKey: RESEND_API_KEY,
    })
    if (granted.decision === 'held') return refuse('licensed', 409)
    await after(granted.confirming)
  } catch (e) {
    console.error('polar claim', (e as Error).message)
    return refuse('failed', 500)
  }
  return json({ ok: true, status: 'active' })
})
