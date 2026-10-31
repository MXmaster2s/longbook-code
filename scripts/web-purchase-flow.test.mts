// The three polar functions run end to end under Node: the real files with a stand-in for
// Deno, for Supabase (web-purchase-fakes.mts), and for Polar and Resend over fetch. What each
// request leaves in the tables is what is asserted. Run: npm run web:test.
import assert from 'node:assert/strict'
import { createHmac } from 'node:crypto'
import Module from 'node:module'
import { fileURLToPath } from 'node:url'
import { beforeEach, test } from 'node:test'
import { db } from './web-purchase-fakes.mts'
import {
  CUSTOMER_ID,
  LICENSE_KEY_ID,
  ORDER_ID,
  ORGANIZATION_ID,
  PAID_AT,
  PRODUCT_ID,
  USER_ID,
  benefitGrantCreated,
  orderPaid,
  orderRefunded,
} from './web-purchase-fixtures.mts'

// The function files load as CommonJS here, so their npm: imports are mapped where require
// resolves them: Supabase to the stand-in, jose to the installed package.
const resolver = Module as unknown as { _resolveFilename(request: string, ...rest: unknown[]): string }
const resolveFilename = resolver._resolveFilename
resolver._resolveFilename = function (request, ...rest) {
  if (request === 'npm:@supabase/supabase-js@2') return fileURLToPath(new URL('./web-purchase-fakes.mts', import.meta.url))
  return resolveFilename.call(this, request === 'npm:jose@5' ? 'jose' : request, ...rest)
}

const SECRET = 'whsec_flow_test_secret_for_the_webhook'
const ENV: Record<string, string> = {
  SUPABASE_URL: 'https://project.supabase.test',
  SUPABASE_ANON_KEY: 'anon',
  SUPABASE_SERVICE_ROLE_KEY: 'service',
  POLAR_WEBHOOK_SECRET: SECRET,
  POLAR_PRODUCT_ID: PRODUCT_ID,
  POLAR_ORGANIZATION_ID: ORGANIZATION_ID,
  POLAR_ACCESS_TOKEN: 'polar_oat_test',
  POLAR_ENVIRONMENT: 'production',
  RESEND_API_KEY: 're_test',
}

type Handler = (req: Request) => Response | Promise<Response>
let serving: Handler | null = null
;(globalThis as { Deno?: unknown }).Deno = {
  env: { get: (name: string) => ENV[name] },
  serve: (handler: Handler) => void (serving = handler),
}

async function load(path: string): Promise<Handler> {
  serving = null
  await import(path)
  return serving!
}
const webhook = await load('../supabase/functions/polar-webhook/index.ts')
const checkout = await load('../supabase/functions/polar-checkout/index.ts')
const claim = await load('../supabase/functions/polar-claim/index.ts')
const deleteAccount = await load('../supabase/functions/delete-account/index.ts')

// ---- the outside world over fetch ---------------------------------------------------------

interface Outside {
  mail: { to: string[]; subject: string; idempotency: string | null }[]
  polar: { method: string; path: string; body: any; token: string | null; version: string | null }[]
  answers: Record<string, () => Response>
}
let outside: Outside
const answer = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status })

globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
  const url = new URL(String(input))
  const headers = new Headers(init?.headers)
  if (url.hostname === 'api.resend.com') {
    const body = JSON.parse(String(init?.body))
    outside.mail.push({ to: body.to, subject: body.subject, idempotency: headers.get('Idempotency-Key') })
    return answer({ id: 'email' })
  }
  if (url.hostname === 'project.supabase.test') {
    const wanted = (url.searchParams.get('filter') ?? '').toLowerCase()
    return answer({ users: db.users.filter((u) => u.email.toLowerCase().includes(wanted)) })
  }
  assert.equal(url.hostname, 'api.polar.sh', `an unexpected call to ${url.hostname}`)
  outside.polar.push({
    method: init?.method ?? 'GET',
    path: url.pathname,
    body: init?.body ? JSON.parse(String(init.body)) : null,
    token: headers.get('Authorization'),
    version: headers.get('Polar-Version'),
  })
  return (outside.answers[url.pathname] ?? (() => answer({}, 404)))()
}) as typeof fetch

const alex = { id: USER_ID, email: 'alex.morgan@example.com', email_confirmed_at: '2026-10-31T10:00:00Z' }

beforeEach(() => {
  db.reset()
  db.users.push(alex)
  outside = { mail: [], polar: [], answers: {} }
})

// ---- requests -----------------------------------------------------------------------------

let deliveries = 0
function delivery(payload: unknown, secret = SECRET): Request {
  const body = JSON.stringify(payload)
  const id = `msg_${++deliveries}`
  const ts = Math.floor(Date.now() / 1000)
  const sig = createHmac('sha256', secret).update(`${id}.${ts}.${body}`).digest('base64')
  return new Request('https://project.supabase.test/functions/v1/polar-webhook', {
    method: 'POST',
    headers: { 'webhook-id': id, 'webhook-timestamp': String(ts), 'webhook-signature': `v1,${sig}` },
    body,
  })
}

const signedIn = (body: unknown, user = USER_ID) =>
  new Request('https://project.supabase.test/functions/v1/polar', {
    method: 'POST',
    headers: { Authorization: `Bearer token-${user}` },
    body: JSON.stringify(body),
  })

const licence = () => db.rows('entitlements').find((r) => r.user_id === USER_ID)
const webOrder = () => db.rows('web_orders').find((r) => r.order_id === ORDER_ID)

// ---- polar-webhook ------------------------------------------------------------------------

test('order.paid records the order, writes the licence, grants Cloud, claims it and emails once', async () => {
  const res = await webhook(delivery(orderPaid))
  assert.equal(res.status, 200)
  assert.deepEqual(await res.json(), { recorded: ORDER_ID, claimed: true, licence: 'write' })
  const row = licence()!
  assert.equal(row.status, 'active')
  assert.equal(row.source, 'polar')
  assert.equal(row.polar_order_id, ORDER_ID)
  assert.equal(row.polar_customer_id, CUSTOMER_ID)
  assert.equal(row.purchased_at, PAID_AT)
  assert.ok(row.purchase_email_sent_at, 'the send-once mark is taken')
  const order = webOrder()!
  assert.equal(order.status, 'paid')
  assert.equal(order.amount, 3800)
  assert.equal(order.environment, 'production')
  assert.equal(order.claimed_by, USER_ID)
  assert.equal(order.user_id, USER_ID)
  assert.ok(order.claimed_at)
  assert.equal(db.rows('cloud_grants')[0]!.until, '2027-10-31T09:41:07.512Z')
  assert.deepEqual(outside.mail.map((m) => [m.to[0], m.subject, m.idempotency]),
    [[alex.email, 'Your longbook license is now active', `purchase-polar-${ORDER_ID}`]])
})

test('a repeat delivery changes nothing and sends nothing more', async () => {
  await webhook(delivery(orderPaid))
  const before = { ...webOrder()! }
  const res = await webhook(delivery(orderPaid))
  assert.deepEqual(await res.json(), { recorded: ORDER_ID, claimed: true, licence: 'same' })
  assert.equal(outside.mail.length, 1)
  assert.equal(webOrder()!.claimed_at, before.claimed_at)
  assert.equal(db.rows('web_orders').length, 1)
})

test('with no matching account the order waits unclaimed and the answer is still 200', async () => {
  db.users.length = 0
  const res = await webhook(delivery(orderPaid))
  assert.equal(res.status, 200)
  assert.deepEqual(await res.json(), { recorded: ORDER_ID, claimed: false })
  assert.equal(webOrder()!.claimed_at ?? null, null)
  assert.equal(licence(), undefined)
  assert.equal(outside.mail.length, 0)
})

test('an order with no ids on it still finds the account by email, ignoring case', async () => {
  const data = { ...orderPaid.data, metadata: {}, customer: { ...orderPaid.data.customer, external_id: null } }
  const res = await webhook(delivery({ ...orderPaid, data }))
  assert.deepEqual(await res.json(), { recorded: ORDER_ID, claimed: true, licence: 'write' })
  assert.equal(licence()!.status, 'active')
})

test('an account holding an App Store licence keeps it, and the second purchase is reported once', async () => {
  db.rows('entitlements').push({ user_id: USER_ID, status: 'active', source: 'apple', apple_original_transaction_id: '2000', polar_order_id: null })
  assert.deepEqual(await (await webhook(delivery(orderPaid))).json(), { recorded: ORDER_ID, claimed: true, licence: 'held' })
  await webhook(delivery(orderPaid))
  assert.equal(licence()!.source, 'apple')
  assert.equal(licence()!.apple_original_transaction_id, '2000')
  assert.equal(webOrder()!.claimed_by, USER_ID)
  assert.deepEqual(outside.mail.map((m) => [m.to[0], m.subject]), [['contact@longbook.app', 'longbook: a second licence was bought for one account']])
  await webhook(delivery(orderRefunded))
  assert.equal(licence()!.status, 'active', 'refunding the second purchase leaves the App Store licence')
})

test('a licence over a refunded App Store one drops the Apple ids and sends its own email', async () => {
  db.rows('entitlements').push({ user_id: USER_ID, status: 'revoked', source: 'apple', apple_original_transaction_id: '2000', apple_environment: 'Production', purchase_email_sent_at: '2026-10-01T00:00:00Z' })
  await webhook(delivery(orderPaid))
  assert.equal(licence()!.source, 'polar')
  assert.equal(licence()!.apple_original_transaction_id, null)
  assert.equal(outside.mail.length, 1)
})

test('order.refunded revokes the licence and its Cloud; a late order.paid never revives it', async () => {
  await webhook(delivery(orderPaid))
  const res = await webhook(delivery(orderRefunded))
  assert.deepEqual(await res.json(), { recorded: ORDER_ID, revoked: 1 })
  assert.equal(licence()!.status, 'revoked')
  assert.equal(db.rows('cloud_grants').length, 0)
  assert.equal(webOrder()!.status, 'refunded')
  assert.equal(webOrder()!.refunded_at, orderRefunded.timestamp)
  assert.equal(webOrder()!.paid_at, PAID_AT, 'the payment time is kept')

  assert.deepEqual(await (await webhook(delivery(orderPaid))).json(), { ignored: 'refunded' })
  assert.equal(licence()!.status, 'revoked')
  assert.equal(webOrder()!.status, 'refunded')
  assert.equal(outside.mail.length, 1)
})

test('a partial refund leaves the licence', async () => {
  await webhook(delivery(orderPaid))
  const partial = { ...orderRefunded, data: { ...orderRefunded.data, status: 'partially_refunded', refunded_amount: 800 } }
  assert.deepEqual(await (await webhook(delivery(partial))).json(), { recorded: ORDER_ID, revoked: 0 })
  assert.equal(licence()!.status, 'active')
  assert.equal(webOrder()!.status, 'paid')
})

test('a refund for an order written before web_orders existed still revokes its licence', async () => {
  const august = 'aaaaaaaa-1111-4222-8333-444444444444'
  db.rows('entitlements').push({ user_id: USER_ID, status: 'active', source: 'polar', polar_order_id: august })
  const data = { ...orderRefunded.data, id: august, product_id: 'the-august-product', product: null }
  assert.deepEqual(await (await webhook(delivery({ ...orderRefunded, data }))).json(), { recorded: august, revoked: 1 })
  assert.equal(licence()!.status, 'revoked')
  assert.equal(db.rows('web_orders').length, 0, 'another product is not recorded')
})

test('a licence key grant lands on its order and licence; with no order yet, Polar is asked to retry', async () => {
  const early = { ...benefitGrantCreated, data: { ...benefitGrantCreated.data, created_at: new Date().toISOString() } }
  assert.equal((await webhook(delivery(early))).status, 503)
  await webhook(delivery(orderPaid))
  assert.deepEqual(await (await webhook(delivery(early))).json(), { licence_key: 'stored' })
  assert.equal(webOrder()!.license_key_id, LICENSE_KEY_ID)
  assert.equal(licence()!.polar_license_key_id, LICENSE_KEY_ID)
})

test('a grant too old to wait for is answered and dropped', async () => {
  const old = { ...benefitGrantCreated, data: { ...benefitGrantCreated.data, created_at: new Date(Date.now() - 11 * 60 * 1000).toISOString() } }
  assert.deepEqual(await (await webhook(delivery(old))).json(), { licence_key: 'no matching order' })
})

test('another product, an unrelated event and a bad signature write nothing', async () => {
  const other = { ...orderPaid, data: { ...orderPaid.data, product_id: 'another-product', product: null } }
  assert.deepEqual(await (await webhook(delivery(other))).json(), { ignored: 'another product' })
  const noted = await (await webhook(delivery({ type: 'checkout.updated', timestamp: PAID_AT, data: {} }))).json()
  assert.equal(noted.ignored, 'checkout.updated')
  assert.equal((await webhook(delivery(orderPaid, 'whsec_someone_else'))).status, 401)
  assert.equal(db.rows('web_orders').length, 0)
  assert.equal(licence(), undefined)
})

test('the sale that fills a tier claims the step and emails contact@longbook.app; a repeat does not', async () => {
  for (let i = 0; i < 99; i++) {
    db.rows('entitlements').push({ user_id: `apple-${i}`, status: 'active', source: 'apple', apple_environment: 'Production', apple_original_transaction_id: `t${i}` })
  }
  await webhook(delivery(orderPaid))
  assert.deepEqual(db.rows('licence_price_steps').map((s) => [s.tier, s.price, s.sold]), [[1, '98', 100]])
  assert.match(db.rows('licence_price_steps')[0]!.error, /no App Store Connect key/)
  const notes = outside.mail.filter((m) => m.to[0] === 'contact@longbook.app')
  assert.deepEqual(notes.map((m) => m.subject), ['longbook: 100 licences sold, the price is now $98'])
  await webhook(delivery(orderPaid))
  assert.equal(outside.mail.filter((m) => m.to[0] === 'contact@longbook.app').length, 1)
})

test('an August order counts as no seat, and neither does a refunded one', async () => {
  const data = { ...orderPaid.data, id: 'aug-order', paid_at: '2026-08-14T09:12:00Z' }
  db.users.length = 0
  await webhook(delivery({ ...orderPaid, data }))
  assert.equal(db.rows('web_orders')[0]!.paid_at, '2026-08-14T09:12:00Z')
  const { soldSeats } = await import('../supabase/functions/_shared/seat-count.ts')
  const { createClient } = await import('./web-purchase-fakes.mts')
  const service = createClient('', '') as any
  assert.equal(await soldSeats(service), 0)
  await webhook(delivery(orderPaid))
  assert.equal(await soldSeats(service), 1)
  await webhook(delivery(orderRefunded))
  assert.equal(await soldSeats(service), 0)
})

// ---- polar-checkout -----------------------------------------------------------------------

test('a checkout carries the account and answers with Polar\'s url', async () => {
  outside.answers['/v1/checkouts/'] = () => answer({ id: 'chk', url: 'https://polar.sh/checkout/polar_c_abc' }, 201)
  const res = await checkout(signedIn({ action: 'checkout' }))
  assert.equal(res.status, 200)
  assert.deepEqual(await res.json(), { url: 'https://polar.sh/checkout/polar_c_abc' })
  const call = outside.polar[0]!
  assert.equal(call.token, 'Bearer polar_oat_test')
  assert.equal(call.version, '2026-10')
  assert.deepEqual(call.body, {
    products: [PRODUCT_ID],
    customer_email: alex.email,
    external_customer_id: USER_ID,
    metadata: { user_id: USER_ID },
    success_url: 'https://longbook.app/thanks/?checkout_id={CHECKOUT_ID}',
  })
})

test('an account with an active licence is refused, plainly, before Polar is asked', async () => {
  db.rows('entitlements').push({ user_id: USER_ID, status: 'active' })
  const res = await checkout(signedIn({ action: 'checkout' }))
  assert.equal(res.status, 409)
  assert.deepEqual(await res.json(), { why: 'This account already holds a longbook licence.' })
  assert.equal(outside.polar.length, 0)
})

test('the portal answers with a session url, or Polar\'s own page for a customer it does not know', async () => {
  outside.answers['/v1/customer-sessions/'] = () => answer({ customer_portal_url: 'https://polar.sh/ccs/portal?customer_session_token=x' }, 201)
  assert.deepEqual(await (await checkout(signedIn({ action: 'portal' }))).json(), { url: 'https://polar.sh/ccs/portal?customer_session_token=x' })
  assert.deepEqual(outside.polar[0]!.body, { external_customer_id: USER_ID })
  for (const status of [404, 422]) {
    outside.answers['/v1/customer-sessions/'] = () => answer({}, status)
    assert.deepEqual(await (await checkout(signedIn({ action: 'portal' }))).json(), { url: 'https://polar.sh/ccs/portal' })
  }
})

test('checkout and claim refuse anyone not signed in, and an unknown action', async () => {
  for (const fn of [checkout, claim]) {
    const res = await fn(signedIn({ action: 'checkout', key: 'K' }, 'nobody'))
    assert.equal(res.status, 401)
    assert.deepEqual(await res.json(), { why: 'Sign in to longbook to continue.' })
  }
  assert.equal((await checkout(signedIn({ action: 'refund' }))).status, 400)
})

// ---- polar-claim --------------------------------------------------------------------------

const KEY = 'LONGBOOK-11112222-3333-4444-5555-7C1D'
const validKey = { id: LICENSE_KEY_ID, customer_id: CUSTOMER_ID, status: 'granted', limit_activations: 1, expires_at: null }

function polarKnowsKey(orders: unknown[] = [orderPaid.data]) {
  outside.answers['/v1/customer-portal/license-keys/validate'] = () => answer(validKey)
  outside.answers['/v1/customer-portal/license-keys/activate'] = () => answer({ id: 'activation' })
  outside.answers['/v1/orders/'] = () => answer({ items: orders, pagination: { total_count: orders.length, max_page: 1 } })
}

test('a key claims its unclaimed order: validated, activated without a token, licence written', async () => {
  db.users.length = 0
  await webhook(delivery(orderPaid))
  db.users.push(alex)
  polarKnowsKey()
  const res = await claim(signedIn({ key: ` ${KEY} ` }))
  assert.equal(res.status, 200)
  assert.deepEqual(await res.json(), { ok: true, status: 'active' })
  const [validate, activate] = outside.polar
  assert.deepEqual(validate!.body, { key: KEY, organization_id: ORGANIZATION_ID })
  assert.equal(validate!.token, null)
  assert.deepEqual(activate!.body, { key: KEY, organization_id: ORGANIZATION_ID, label: 'longbook account', meta: { user_id: USER_ID } })
  assert.equal(activate!.token, null)
  assert.equal(licence()!.source, 'polar')
  assert.equal(licence()!.polar_license_key_id, LICENSE_KEY_ID)
  assert.equal(webOrder()!.claimed_by, USER_ID)
  assert.equal(webOrder()!.license_key_id, LICENSE_KEY_ID)
  assert.equal(db.rows('cloud_grants').length, 1)
  assert.equal(outside.mail.length, 1)
})

test('a key whose order was never recorded here is found through Polar and recorded', async () => {
  polarKnowsKey()
  assert.deepEqual(await (await claim(signedIn({ key: KEY }))).json(), { ok: true, status: 'active' })
  const asked = outside.polar.find((c) => c.path === '/v1/orders/')!
  assert.equal(asked.token, 'Bearer polar_oat_test')
  assert.equal(webOrder()!.claimed_by, USER_ID)
})

test('a second account is refused, by the activation limit or by the order\'s claim', async () => {
  const sam = { id: '9b9b9b9b-0000-4000-8000-000000000002', email: 'sam@example.com' }
  db.users.push(sam)
  polarKnowsKey()
  await claim(signedIn({ key: KEY }))
  const taken = await claim(signedIn({ key: KEY }, sam.id))
  assert.equal(taken.status, 409)
  assert.deepEqual(await taken.json(), { why: 'This licence key is already in use on another longbook account.' })
  assert.equal(db.rows('entitlements').filter((r) => r.user_id === sam.id).length, 0)

  db.rows('web_orders').length = 0
  outside.answers['/v1/customer-portal/license-keys/activate'] = () => answer({ detail: 'limit reached' }, 403)
  outside.answers[`/v1/license-keys/${LICENSE_KEY_ID}`] = () => answer({ activations: [{ meta: { user_id: USER_ID } }] })
  const limited = await claim(signedIn({ key: KEY }, sam.id))
  assert.equal(limited.status, 409)
  assert.deepEqual(await limited.json(), { why: 'This licence key is already in use on another longbook account.' })
})

test('the account\'s own activation, left by a claim that failed after it, lets the claim finish', async () => {
  polarKnowsKey()
  outside.answers['/v1/customer-portal/license-keys/activate'] = () => answer({ detail: 'limit reached' }, 403)
  outside.answers[`/v1/license-keys/${LICENSE_KEY_ID}`] = () => answer({ activations: [{ meta: { user_id: USER_ID } }] })
  assert.deepEqual(await (await claim(signedIn({ key: KEY }))).json(), { ok: true, status: 'active' })
  assert.equal(licence()!.status, 'active')
})

test('claims refuse a missing, unknown or refunded key, another product and a licensed account', async () => {
  const why = async (body: unknown) => (await (await claim(signedIn(body))).json()).why
  assert.equal(await why({}), 'Enter the licence key from the email Polar sent after your purchase.')
  outside.answers['/v1/customer-portal/license-keys/validate'] = () => answer({ detail: 'not found' }, 404)
  assert.equal(await why({ key: KEY }), 'This licence key was not found. Copy it again from the email Polar sent after your purchase.')

  polarKnowsKey([])
  assert.equal(await why({ key: KEY }), 'This licence key is not for longbook.')
  polarKnowsKey([{ ...orderPaid.data, product_id: 'another-product', product: null }])
  assert.equal(await why({ key: KEY }), 'This licence key is not for longbook.')
  polarKnowsKey([orderRefunded.data])
  assert.equal(await why({ key: KEY }), 'This licence key belongs to a refunded order.')
  assert.ok(!outside.polar.some((c) => c.path.endsWith('/activate')), 'nothing is activated for a key that fails')

  polarKnowsKey()
  db.rows('entitlements').push({ user_id: USER_ID, status: 'active', polar_license_key_id: null })
  assert.equal(await why({ key: KEY }), 'This account already holds a longbook licence.')
  licence()!.polar_license_key_id = LICENSE_KEY_ID
  assert.deepEqual(await (await claim(signedIn({ key: KEY }))).json(), { ok: true, status: 'active' }, 'the same key again is simply done')
})

// ---- bought before the account existed ----------------------------------------------------

async function unclaimedOrder(payload: unknown = orderPaid): Promise<void> {
  const here = [...db.users]
  db.users.length = 0
  await webhook(delivery(payload))
  db.users.push(...here)
}
const byEmail = (extra: Record<string, unknown> = {}, user = USER_ID) => claim(signedIn({ action: 'email', ...extra }, user))

test('an order waiting under the confirmed email reaches the account, without calling Polar', async () => {
  await unclaimedOrder()
  const key = await webhook(delivery({ ...benefitGrantCreated, data: { ...benefitGrantCreated.data, created_at: new Date().toISOString() } }))
  assert.equal(key.status, 200)
  assert.deepEqual(await (await byEmail()).json(), { ok: true, status: 'active' })
  assert.deepEqual(outside.polar, [], 'no validate, no activate')
  assert.equal(licence()!.source, 'polar')
  assert.equal(licence()!.polar_order_id, ORDER_ID)
  assert.equal(licence()!.polar_license_key_id, LICENSE_KEY_ID, 'the stored key is used')
  assert.equal(webOrder()!.claimed_by, USER_ID)
  assert.equal(db.rows('cloud_grants').length, 1)
  assert.equal(outside.mail.length, 1)
  assert.deepEqual(await (await byEmail()).json(), { ok: true, status: 'none' }, 'a second ask finds the licence active')
  assert.equal(outside.mail.length, 1)
})

test('the earliest paid order goes first, and the other waits', async () => {
  const later = { ...orderPaid.data, id: 'later-order' }
  await unclaimedOrder({ ...orderPaid, timestamp: '2026-11-01T00:00:00Z', data: later })
  await unclaimedOrder()
  assert.deepEqual(await (await byEmail()).json(), { ok: true, status: 'active' })
  assert.equal(licence()!.polar_order_id, ORDER_ID)
  assert.equal(db.rows('web_orders').find((r) => r.order_id === 'later-order')!.claimed_at ?? null, null)
})

test('nothing is granted for an unconfirmed email, an address in the body, or a licensed account', async () => {
  await unclaimedOrder()
  const unconfirmed = { id: '9c9c9c9c-0000-4000-8000-000000000003', email: alex.email, email_confirmed_at: null }
  db.users.length = 0
  db.users.push(unconfirmed as never)
  assert.deepEqual(await (await byEmail({}, unconfirmed.id)).json(), { ok: true, status: 'none' })

  const sam = { id: '9b9b9b9b-0000-4000-8000-000000000002', email: 'sam@example.com', email_confirmed_at: alex.email_confirmed_at }
  db.users.push(sam, alex)
  assert.deepEqual(await (await byEmail({ email: alex.email, user_id: USER_ID }, sam.id)).json(), { ok: true, status: 'none' })

  db.rows('entitlements').push({ user_id: USER_ID, status: 'active', source: 'apple', polar_order_id: null })
  assert.deepEqual(await (await byEmail()).json(), { ok: true, status: 'none' })
  assert.equal(licence()!.source, 'apple')
  assert.equal(webOrder()!.claimed_at ?? null, null, 'the order is left alone')
  assert.equal(outside.mail.length, 0)
})

test('the match is the whole address ignoring case: a wildcard in it matches nothing else', async () => {
  await unclaimedOrder()
  const lookalike = { id: '9d9d9d9d-0000-4000-8000-000000000004', email: 'alex_morgan@example.com', email_confirmed_at: alex.email_confirmed_at }
  const star = { id: '9e9e9e9e-0000-4000-8000-000000000005', email: 'alex*@example.com', email_confirmed_at: alex.email_confirmed_at }
  db.users.push(lookalike, star)
  assert.deepEqual(await (await byEmail({}, lookalike.id)).json(), { ok: true, status: 'none' })
  assert.deepEqual(await (await byEmail({}, star.id)).json(), { ok: true, status: 'none' })
  alex.email = 'ALEX.MORGAN@example.com'
  try {
    assert.deepEqual(await (await byEmail()).json(), { ok: true, status: 'active' }, 'the fixture order says Alex.Morgan')
  } finally {
    alex.email = 'alex.morgan@example.com'
  }
})

test('a refunded order is not offered, and a sandbox order is not offered to production', async () => {
  await unclaimedOrder()
  await webhook(delivery(orderRefunded))
  assert.deepEqual(await (await byEmail()).json(), { ok: true, status: 'none' })
  db.rows('web_orders').length = 0
  await unclaimedOrder()
  webOrder()!.environment = 'sandbox'
  assert.deepEqual(await (await byEmail()).json(), { ok: true, status: 'none' })
})

test('after an email claim, another account is refused the key, found by key or by customer', async () => {
  await unclaimedOrder()
  await byEmail()
  const sam = { id: '9b9b9b9b-0000-4000-8000-000000000002', email: 'sam@example.com', email_confirmed_at: alex.email_confirmed_at }
  db.users.push(sam)
  polarKnowsKey()
  for (const stored of [null, LICENSE_KEY_ID]) {
    webOrder()!.license_key_id = stored
    const res = await claim(signedIn({ key: KEY }, sam.id))
    assert.equal(res.status, 409)
    assert.deepEqual(await res.json(), { why: 'This licence key is already in use on another longbook account.' })
  }
  assert.ok(!outside.polar.some((c) => c.path.endsWith('/activate')), 'the refusal comes before activating')
  assert.equal(db.rows('entitlements').filter((r) => r.user_id === sam.id).length, 0)
})

// ---- deleting the account -----------------------------------------------------------------

test('deleting the account empties what names the buyer and keeps the figures', async () => {
  const someoneElse = { order_id: 'other', claimed_by: 'someone', user_id: 'someone', email: 'other@example.com', status: 'paid' }
  await webhook(delivery(orderPaid))
  await webhook(delivery({ ...benefitGrantCreated, data: { ...benefitGrantCreated.data, created_at: new Date().toISOString() } }))
  db.rows('web_orders').push({ ...someoneElse })
  const res = await deleteAccount(signedIn({}))
  assert.deepEqual(await res.json(), { ok: true, folder_untouched: true })
  assert.equal(db.users.length, 0)
  assert.equal(licence(), undefined)
  const row = webOrder()!
  for (const gone of ['email', 'external_customer_id', 'polar_customer_id', 'license_key_id', 'claimed_by', 'user_id']) {
    assert.equal(row[gone], null, gone)
  }
  assert.deepEqual([row.order_id, row.amount, row.currency, row.country, row.status, row.paid_at],
    [ORDER_ID, 3800, 'usd', 'IN', 'paid', PAID_AT])
  assert.ok(row.claimed_at, 'claimed_at marks the row as scrubbed')
  assert.deepEqual(db.rows('web_orders').find((r) => r.order_id === 'other'), someoneElse, 'only this account\'s orders')
})

test('a failure emptying the orders stops the deletion', async () => {
  await webhook(delivery(orderPaid))
  db.failing = ['web_orders']
  const res = await deleteAccount(signedIn({}))
  assert.equal(res.status, 500)
  assert.deepEqual(await res.json(), { error: 'The account could not be deleted. Try again shortly.' })
  assert.equal(db.users.length, 1)
  assert.equal(licence()!.status, 'active')
})

test('after deletion, later events never write the buyer back, and the order stays claimed', async () => {
  await webhook(delivery(orderPaid))
  await deleteAccount(signedIn({}))
  const after = () => ({ ...webOrder()! })

  const fresh = { id: '9f9f9f9f-0000-4000-8000-000000000006', email: alex.email, email_confirmed_at: alex.email_confirmed_at }
  db.users.push(fresh)
  assert.deepEqual(await (await webhook(delivery(orderPaid))).json(), { ignored: 'account deleted' })
  assert.equal(after().email, null, 'a repeated order.paid')
  assert.equal(db.rows('entitlements').length, 0, 'a new account with the same address gets nothing')
  assert.deepEqual(await (await byEmail({}, fresh.id)).json(), { ok: true, status: 'none' })

  await webhook(delivery({ ...benefitGrantCreated, data: { ...benefitGrantCreated.data, created_at: new Date().toISOString() } }))
  assert.equal(after().license_key_id, null, 'a late key grant')

  polarKnowsKey()
  const refused = await claim(signedIn({ key: KEY }, fresh.id))
  assert.deepEqual(await refused.json(), { why: 'This licence key is already in use on another longbook account.' })
  assert.equal(after().email, null, 'a key claim that found it through Polar')
  assert.equal(after().claimed_by, null)

  await webhook(delivery(orderRefunded))
  const refunded = after()
  assert.equal(refunded.status, 'refunded')
  assert.equal(refunded.refunded_at, orderRefunded.timestamp)
  for (const gone of ['email', 'external_customer_id', 'polar_customer_id', 'license_key_id', 'user_id', 'claimed_by']) {
    assert.equal(refunded[gone], null, gone)
  }
  assert.equal(refunded.paid_at, PAID_AT)
})

test('a Polar outage reads as an outage, not as a bad key', async () => {
  outside.answers['/v1/customer-portal/license-keys/validate'] = () => answer({}, 503)
  const res = await claim(signedIn({ key: KEY }))
  assert.equal(res.status, 502)
  assert.deepEqual(await res.json(), { why: 'Polar could not be reached. Try again in a few minutes.' })
})
