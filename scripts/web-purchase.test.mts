// The licence bought on longbook.app through Polar: webhook signatures in both schemes, the
// events read defensively, which account an order finds, the seats it counts as, the price-step
// email, and the claim's words. Run: npm run web:test.
import assert from 'node:assert/strict'
import { createHmac, randomBytes } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import {
  POLAR_VERSION,
  SUCCESS_URL,
  WEB_ORDER_COLUMNS,
  WHY,
  activatedBy,
  checkoutBody,
  doublePurchaseNotice,
  keyProblem,
  licenceDecision,
  matchAccount,
  orderFromRow,
  pickByEmail,
  pickOrder,
  polarApi,
  polarEntitlement,
  polarEnvironment,
  polarHeaders,
  polarRefusal,
  portalBody,
  readEvent,
  readOrder,
  signingKeys,
  verifyDelivery,
  type Account,
  type AccountLookup,
  type OrderFacts,
} from '../supabase/functions/_shared/polar.ts'
import { WEB_SEATS_FROM } from '../supabase/functions/_shared/licence-seats.ts'
import { soldSeats } from '../supabase/functions/_shared/seat-count.ts'
import { stepNotice, stepPrices, type StepDeps } from '../supabase/functions/_shared/price-step.ts'
import {
  CUSTOMER_ID,
  LICENSE_KEY_ID,
  ORDER_ID,
  PAID_AT,
  PRODUCT_ID,
  USER_ID,
  benefitGrantCreated,
  legacyOrderPaid,
  orderPaid,
  orderRefunded,
} from './web-purchase-fixtures.mts'

const read = (rel: string): string => readFileSync(new URL(`../${rel}`, import.meta.url), 'utf8')
const NOW = new Date('2026-10-31T09:41:10Z')
const NOW_S = NOW.getTime() / 1000

// ---- signatures ---------------------------------------------------------------------------

const sign = (key: Buffer | string, id: string, ts: number, body: string): string =>
  createHmac('sha256', key).update(`${id}.${ts}.${body}`).digest('base64')

const LEGACY_SECRET = 'whsec_polar_legacy_signing_secret_issued_in_august'
const STANDARD_BYTES = randomBytes(32)
const STANDARD_SECRET = `whsec_${STANDARD_BYTES.toString('base64')}`
const body = JSON.stringify(orderPaid)
const delivery = (signature: string, ts = Math.floor(NOW_S), text = body) =>
  ({ id: 'msg_2rTq0bJ6m9', timestamp: String(ts), signature, body: text })

test('a legacy secret signs with the bytes of the whole whsec_ string', async () => {
  const sig = sign(LEGACY_SECRET, 'msg_2rTq0bJ6m9', Math.floor(NOW_S), body)
  assert.deepEqual(await verifyDelivery(delivery(`v1,${sig}`), LEGACY_SECRET, NOW_S), { ok: true })
})

test('a Standard Webhooks secret signs with the base64 after the prefix', async () => {
  const sig = sign(STANDARD_BYTES, 'msg_2rTq0bJ6m9', Math.floor(NOW_S), body)
  assert.deepEqual(await verifyDelivery(delivery(`v1,${sig}`), STANDARD_SECRET, NOW_S), { ok: true })
  const asText = sign(STANDARD_SECRET, 'msg_2rTq0bJ6m9', Math.floor(NOW_S), body)
  assert.deepEqual(await verifyDelivery(delivery(`v1,${asText}`), STANDARD_SECRET, NOW_S), { ok: true }, 'the whole string is tried too')
  assert.equal(signingKeys(STANDARD_SECRET).length, 2)
})

test('any v1 entry may match, as during a rotation; other versions are skipped', async () => {
  const good = sign(LEGACY_SECRET, 'msg_2rTq0bJ6m9', Math.floor(NOW_S), body)
  const header = `v1a,${good} v1,${Buffer.from('not it').toString('base64')} v1,${good}`
  assert.deepEqual(await verifyDelivery(delivery(header), LEGACY_SECRET, NOW_S), { ok: true })
  assert.equal((await verifyDelivery(delivery(`v1a,${good}`), LEGACY_SECRET, NOW_S)).ok, false)
})

test('a changed body, the wrong secret or a missing header is refused', async () => {
  const sig = sign(LEGACY_SECRET, 'msg_2rTq0bJ6m9', Math.floor(NOW_S), body)
  assert.deepEqual(await verifyDelivery(delivery(`v1,${sig}`, Math.floor(NOW_S), body.replace('3800', '1')), LEGACY_SECRET, NOW_S),
    { ok: false, status: 401, why: 'bad signature' })
  assert.equal((await verifyDelivery(delivery(`v1,${sig}`), STANDARD_SECRET, NOW_S)).ok, false)
  assert.deepEqual(await verifyDelivery({ ...delivery(`v1,${sig}`), id: null }, LEGACY_SECRET, NOW_S),
    { ok: false, status: 400, why: 'missing signature headers' })
  assert.equal((await verifyDelivery(delivery(`v1,${sig}`), '', NOW_S)).ok, false)
})

test('a delivery more than five minutes either side of now is stale', async () => {
  for (const offset of [-301, 301]) {
    const ts = Math.floor(NOW_S) + offset
    const sig = sign(LEGACY_SECRET, 'msg_2rTq0bJ6m9', ts, body)
    assert.deepEqual(await verifyDelivery(delivery(`v1,${sig}`, ts), LEGACY_SECRET, NOW_S), { ok: false, status: 400, why: 'stale' })
  }
  const ts = Math.floor(NOW_S) - 299
  const sig = sign(LEGACY_SECRET, 'msg_2rTq0bJ6m9', ts, body)
  assert.deepEqual(await verifyDelivery(delivery(`v1,${sig}`, ts), LEGACY_SECRET, NOW_S), { ok: true })
})

// ---- events -------------------------------------------------------------------------------

test('order.paid becomes the web_orders row, paid at the event time', () => {
  const event = readEvent(JSON.stringify(orderPaid), NOW)
  assert.equal(event.kind, 'order.paid')
  if (event.kind !== 'order.paid') return
  assert.deepEqual(event.facts.order, {
    order_id: ORDER_ID,
    email: 'Alex.Morgan@example.com',
    polar_customer_id: CUSTOMER_ID,
    external_customer_id: USER_ID,
    product_id: PRODUCT_ID,
    amount: 3800,
    currency: 'usd',
    country: 'IN',
    status: 'paid',
    paid_at: PAID_AT,
    refunded_at: null,
  })
  assert.equal(event.facts.metadataUserId, USER_ID)
  assert.equal(event.facts.polarStatus, 'paid')
  const kept = JSON.stringify(event.facts.order)
  for (const dropped of ['Alex Morgan', 'Pune', '411001']) assert.ok(!kept.includes(dropped), `the row holds ${dropped}`)
})

test('an order in the earlier shape reads amount and the user\'s email', () => {
  const event = readEvent(JSON.stringify(legacyOrderPaid), NOW)
  assert.equal(event.kind, 'order.paid')
  if (event.kind !== 'order.paid') return
  assert.equal(event.facts.order.amount, 3800)
  assert.equal(event.facts.order.email, 'jordan.lee@example.com')
  assert.equal(event.facts.order.currency, 'usd')
  assert.equal(event.facts.order.paid_at, NOW.toISOString(), 'no event time: the moment it arrived')
  assert.equal(event.facts.order.external_customer_id, null)
})

test('order.refunded marks a full refund only', () => {
  const event = readEvent(JSON.stringify(orderRefunded), NOW)
  assert.equal(event.kind, 'order.refunded')
  if (event.kind !== 'order.refunded') return
  assert.equal(event.facts.order.status, 'refunded')
  assert.equal(event.facts.order.refunded_at, orderRefunded.timestamp)
  const partial = { ...orderRefunded, data: { ...orderRefunded.data, status: 'partially_refunded', refunded_amount: 1000 } }
  const half = readEvent(JSON.stringify(partial), NOW)
  assert.ok(half.kind === 'order.refunded' && half.facts.order.status === 'paid' && half.facts.order.refunded_at === null)
})

test('a licence key grant names its key, order and customer', () => {
  assert.deepEqual(readEvent(JSON.stringify(benefitGrantCreated), NOW), {
    kind: 'licence_key',
    grant: { licenseKeyId: LICENSE_KEY_ID, orderId: ORDER_ID, customerId: CUSTOMER_ID, createdAt: benefitGrantCreated.data.created_at },
  })
  const discord = { ...benefitGrantCreated, data: { ...benefitGrantCreated.data, benefit: { ...benefitGrantCreated.data.benefit, type: 'discord' } } }
  assert.equal(readEvent(JSON.stringify(discord), NOW).kind, 'ignored')
  const revoked = { ...benefitGrantCreated, data: { ...benefitGrantCreated.data, is_revoked: true } }
  assert.equal(readEvent(JSON.stringify(revoked), NOW).kind, 'ignored')
})

test('everything else is answered and ignored', () => {
  for (const text of [JSON.stringify({ type: 'checkout.created', data: {} }), JSON.stringify({ type: 'order.created', data: orderPaid.data }), 'not json', '{}']) {
    assert.equal(readEvent(text, NOW).kind, 'ignored', text.slice(0, 40))
  }
  const noEmail = { ...orderPaid, data: { ...orderPaid.data, customer: { ...orderPaid.data.customer, email: null } } }
  assert.equal(readEvent(JSON.stringify(noEmail), NOW).kind, 'ignored', 'an order without an email has no one to claim it')
})

// ---- accounts -----------------------------------------------------------------------------

const facts = readOrder(orderPaid.data, PAID_AT, 'paid')!
const alex: Account = { id: USER_ID, email: 'alex.morgan@example.com' }

function lookup(byId: Record<string, Account>, byEmail: Account[]): AccountLookup & { asked: string[] } {
  const asked: string[] = []
  return {
    asked,
    async byId(id) {
      asked.push(`id:${id}`)
      return byId[id] ?? null
    },
    async byEmail(email) {
      asked.push(`email:${email}`)
      return pickByEmail(byEmail, email)
    },
  }
}

test('the checkout\'s user id finds the account first', async () => {
  const l = lookup({ [USER_ID]: alex }, [])
  assert.deepEqual(await matchAccount(facts, l), { account: alex, by: 'metadata' })
  assert.deepEqual(l.asked, [`id:${USER_ID}`])
})

test('then the customer\'s external id, then the email, ignoring case', async () => {
  const other = '7a7a7a7a-0000-4000-8000-000000000001'
  const viaExternal: OrderFacts = { ...facts, metadataUserId: other }
  assert.deepEqual(await matchAccount(viaExternal, lookup({ [USER_ID]: alex }, [])), { account: alex, by: 'external_id' })
  const viaEmail: OrderFacts = { order: { ...facts.order, external_customer_id: 'not-a-uuid' }, metadataUserId: null }
  const l = lookup({}, [{ id: 'u-2', email: 'alex.morgan@example.com.au' }, alex])
  assert.deepEqual(await matchAccount(viaEmail, l), { account: alex, by: 'email' })
  assert.deepEqual(l.asked, ['email:Alex.Morgan@example.com'], 'an id that is not a uuid is never looked up')
})

test('no account means the order waits unclaimed', async () => {
  assert.equal(await matchAccount(facts, lookup({}, [{ id: 'u-3', email: 'someone@example.com' }])), null)
})

test('an active licence from elsewhere stands; this order\'s own is kept; otherwise it is written', () => {
  assert.equal(licenceDecision(null, ORDER_ID), 'write')
  assert.equal(licenceDecision({ status: 'revoked', source: 'apple' }, ORDER_ID), 'write')
  assert.equal(licenceDecision({ status: 'active', source: 'polar', polar_order_id: ORDER_ID }, ORDER_ID), 'same')
  assert.equal(licenceDecision({ status: 'active', source: 'apple', polar_order_id: null }, ORDER_ID), 'held')
})

test('the web licence row: active, polar, paid_at as the purchase, no Apple ids, email mark empty', () => {
  assert.deepEqual(polarEntitlement({ userId: USER_ID, orderId: ORDER_ID, customerId: CUSTOMER_ID, licenseKeyId: null, paidAt: PAID_AT }), {
    user_id: USER_ID,
    major_version: 1,
    status: 'active',
    source: 'polar',
    polar_order_id: ORDER_ID,
    polar_customer_id: CUSTOMER_ID,
    polar_license_key_id: null,
    purchased_at: PAID_AT,
    purchase_email_sent_at: null,
    apple_original_transaction_id: null,
    apple_family_transaction_id: null,
    apple_ownership: null,
    apple_environment: null,
  })
})

test('a second licence for one account is reported for a refund by hand', () => {
  const note = doublePurchaseNotice(facts.order, 'apple')
  assert.equal(note.subject, 'longbook: a second licence was bought for one account')
  assert.ok(note.text.includes(`Polar order ${ORDER_ID} (38.00 USD) was paid by Alex.Morgan@example.com`))
  assert.ok(note.text.includes('already holds an active licence from apple'))
})

// ---- seats --------------------------------------------------------------------------------

function seatClient(apple: number, web: number) {
  const asked: Record<string, string[]> = {}
  const from = (table: string) => {
    const filters: string[] = (asked[table] = [])
    const chain: any = {
      select: () => chain,
      eq: (c: string, v: unknown) => (filters.push(`${c}=${v}`), chain),
      not: (c: string, op: string, v: unknown) => (filters.push(`${c} not ${op} ${v}`), chain),
      or: (f: string) => (filters.push(`or ${f}`), chain),
      gte: (c: string, v: unknown) => (filters.push(`${c}>=${v}`), chain),
      then: (ok: (r: unknown) => unknown) => ok({ count: table === 'entitlements' ? apple : web, error: null }),
    }
    return chain
  }
  return { client: { from } as any, asked }
}

test('seats are App Store licences plus paid production web orders from launch pricing on', async () => {
  const { client, asked } = seatClient(61, 39)
  assert.equal(await soldSeats(client), 100)
  assert.deepEqual(asked.web_orders, ['status=paid', 'environment=production', `paid_at>=${WEB_SEATS_FROM}`])
  assert.ok(asked.entitlements!.includes('apple_environment=Production'))
  assert.equal(WEB_SEATS_FROM, '2026-09-21T00:00:00Z', 'the three August orders are not seats')
})

// ---- the price step -----------------------------------------------------------------------

function stepper(sold: number, options: { taken?: number[]; appStore?: Error } = {}) {
  const seen = { claims: [] as number[], prices: [] as string[], records: [] as [number, string | null][], mail: [] as { subject: string; text: string }[] }
  const deps: StepDeps = {
    sold: async () => sold,
    claim: async (tier) => (seen.claims.push(tier), !(options.taken ?? []).includes(tier)),
    setAppStorePrice: async (price) => {
      seen.prices.push(price)
      if (options.appStore) throw options.appStore
    },
    record: async (tier, error) => void seen.records.push([tier, error]),
    notify: async (subject, text) => void seen.mail.push({ subject, text }),
  }
  return { deps, seen }
}

test('the hundredth seat, from either seller, steps the price once and emails the owner', async () => {
  const { deps, seen } = stepper(100)
  assert.deepEqual(await stepPrices(deps), [1])
  assert.deepEqual(seen.prices, ['98'])
  assert.deepEqual(seen.records, [[1, null]])
  assert.equal(seen.mail.length, 1)
  assert.equal(seen.mail[0]!.subject, 'longbook: 100 licences sold, the price is now $98')
  const text = seen.mail[0]!.text
  assert.ok(text.includes('100 licences have been bought on the App Store and longbook.app together'))
  assert.ok(text.includes('The App Store price of the licence is now $98, set automatically.'))
  assert.ok(text.includes('Set the longbook product to $98 on Polar by hand'))
  assert.ok(text.includes('250 seats are left at $98.'))
})

test('a step already claimed is not applied again, and 99 seats step nothing', async () => {
  const taken = stepper(140, { taken: [1] })
  assert.deepEqual(await stepPrices(taken.deps), [])
  assert.deepEqual(taken.seen.mail, [])
  const early = stepper(99)
  assert.deepEqual(await stepPrices(early.deps), [])
  assert.deepEqual(early.seen.claims, [])
})

test('when the App Store cannot be set, the email says to set both prices by hand', async () => {
  const { deps, seen } = stepper(100, { appStore: new Error('no App Store Connect key on the function') })
  await stepPrices(deps)
  assert.deepEqual(seen.records, [[1, 'no App Store Connect key on the function']])
  const text = seen.mail[0]!.text
  assert.ok(text.includes('could not be changed automatically (no App Store Connect key on the function)'))
  assert.ok(text.includes('Set the licence to $98 in App Store Connect'))
  assert.ok(text.includes('on Polar by hand'))
})

test('a count that raced past two tiers applies both, and the last says no seats left', async () => {
  const { deps, seen } = stepper(351)
  assert.deepEqual(await stepPrices(deps), [1, 2])
  assert.deepEqual(seen.prices, ['98', '149'])
  assert.ok(!seen.mail[1]!.text.includes('seats are left'))
  assert.equal(stepNotice({ sold: 1, price: '98', left: null, appStoreError: null }).text.includes('seats are left'), false)
})

// ---- requests and the claim ---------------------------------------------------------------

test('the checkout carries the account to the paid order', () => {
  assert.deepEqual(checkoutBody({ productId: PRODUCT_ID, userId: USER_ID, email: 'alex.morgan@example.com' }), {
    products: [PRODUCT_ID],
    customer_email: 'alex.morgan@example.com',
    external_customer_id: USER_ID,
    metadata: { user_id: USER_ID },
    success_url: 'https://longbook.app/thanks/?checkout_id={CHECKOUT_ID}',
  })
  assert.equal(SUCCESS_URL.includes('{CHECKOUT_ID}'), true)
  assert.deepEqual(portalBody(USER_ID), { external_customer_id: USER_ID })
})

test('the environment picks the API, and every request pins its version', () => {
  assert.equal(polarApi(polarEnvironment(undefined)), 'https://api.polar.sh')
  assert.equal(polarApi(polarEnvironment('production')), 'https://api.polar.sh')
  assert.equal(polarApi(polarEnvironment('Sandbox')), 'https://sandbox-api.polar.sh')
  assert.equal(polarHeaders()['Polar-Version'], POLAR_VERSION)
  assert.equal(polarHeaders().Authorization, undefined, 'validate and activate go without a token')
  assert.equal(polarHeaders('polar_oat_test').Authorization, 'Bearer polar_oat_test')
})

test('a key must be granted and unexpired; Polar\'s refusals map to plain words', () => {
  assert.equal(keyProblem({ status: 'granted', expires_at: null }, NOW), null)
  assert.equal(keyProblem({ status: 'granted', expires_at: '2026-10-01T00:00:00Z' }, NOW), 'inactive')
  assert.equal(keyProblem({ status: 'revoked' as 'granted' }, NOW), 'inactive')
  assert.equal(polarRefusal(404, 'validate'), 'notFound')
  assert.equal(polarRefusal(403, 'activate'), 'inUse')
  assert.equal(polarRefusal(403, 'validate'), 'inactive')
  assert.equal(polarRefusal(400, 'validate'), 'inactive')
  assert.equal(polarRefusal(429, 'validate'), 'unavailable', 'a rate limit says nothing about the key')
  assert.equal(polarRefusal(503, 'activate'), 'unavailable')
  assert.ok(activatedBy({ activations: [{ id: 'a', license_key_id: LICENSE_KEY_ID, label: 'longbook account', meta: { user_id: USER_ID }, created_at: PAID_AT, modified_at: null }] }, USER_ID))
  assert.ok(!activatedBy({ activations: [] }, USER_ID))
})

test('a row rebuilds its facts from the columns; one holding no email rebuilds nothing', () => {
  const { order } = readOrder(orderPaid.data, PAID_AT, 'paid')!
  assert.deepEqual(orderFromRow(order), { order, metadataUserId: null, polarStatus: 'paid' })
  assert.equal(orderFromRow({ ...order, email: null }), null)
  for (const column of Object.keys(order)) assert.ok(WEB_ORDER_COLUMNS.includes(column), column)
})

test('a key\'s order is the paid licence order; a refund or another product is refused', () => {
  const at = NOW.toISOString()
  const other = { ...orderPaid.data, id: 'other', product_id: 'another-product' }
  const pending = { ...orderPaid.data, id: 'pending', status: 'pending' }
  const found = pickOrder([other, pending, orderPaid.data], PRODUCT_ID, at)
  assert.ok(found && found !== 'refunded' && found.order.order_id === ORDER_ID)
  assert.equal(pickOrder([orderRefunded.data], PRODUCT_ID, at), 'refunded')
  assert.equal(pickOrder([other, pending], PRODUCT_ID, at), null)
})

test('every refusal is a plain sentence: capitalised, a full stop, no question or exclamation', () => {
  for (const [name, line] of Object.entries(WHY)) {
    assert.match(line, /^[A-Z][^?!]*\.$/, name)
    assert.ok(!/longbook/i.test(line.replace(/longbook/g, '')), `a capitalised name in ${name}`)
  }
})

// ---- wiring -------------------------------------------------------------------------------

test('the webhook verifies before it reads, and follows only the licence\'s product', () => {
  const hook = read('supabase/functions/polar-webhook/index.ts')
  assert.ok(hook.indexOf('verifyDelivery(') < hook.indexOf('readEvent('))
  assert.ok(hook.includes("if (order.product_id !== PRODUCT_ID) return reply({ ignored: 'another product' })"))
  assert.ok(hook.includes("if (ENVIRONMENT === 'production')"), 'sandbox orders never step the price')
  for (const name of ['POLAR_WEBHOOK_SECRET', 'POLAR_PRODUCT_ID', 'POLAR_ENVIRONMENT', 'RESEND_API_KEY']) assert.ok(hook.includes(`'${name}'`), name)
  const claim = read('supabase/functions/polar-claim/index.ts')
  assert.ok(claim.includes("'/v1/customer-portal/license-keys/validate'") && claim.includes("'/v1/customer-portal/license-keys/activate'"))
  for (const name of ['POLAR_ORGANIZATION_ID', 'POLAR_ACCESS_TOKEN', 'POLAR_PRODUCT_ID']) assert.ok(claim.includes(`'${name}'`), name)
  const checkout = read('supabase/functions/polar-checkout/index.ts')
  assert.ok(checkout.includes("'/v1/checkouts/'") && checkout.includes("'/v1/customer-sessions/'"))
  assert.ok(checkout.includes("if (held?.status === 'active') return refuse('licensed', 409)"))
})

test('the migration, the guard, the deploy list and CI carry web orders', () => {
  const sql = read('supabase/migrations/20261031120000_web_purchases.sql')
  for (const piece of [
    "add column source text not null default 'apple' check (source in ('apple', 'polar', 'grant'))",
    "update public.entitlements set source = 'polar' where polar_order_id is not null;",
    'alter table public.web_orders enable row level security;',
    'revoke all on table public.web_orders from public, anon, authenticated;',
    "status text not null check (status in ('paid', 'refunded'))",
  ]) assert.ok(sql.includes(piece), `migration lacks: ${piece}`)
  assert.ok(!/\braw\b/.test(sql), 'the name and billing address are not kept')
  assert.ok(read('scripts/guard-rls.mts').includes("table_name='web_orders'"))
  const deploy = read('scripts/deploy-function.mts')
  for (const fn of ['polar-webhook', 'polar-checkout', 'polar-claim']) assert.ok(deploy.includes(`'${fn}'`), fn)
  const ci = read('.github/workflows/ci.yml')
  assert.ok(ci.includes('- run: npm run cloud:test\n      - run: npm run web:test\n'))
  assert.ok(read('supabase/functions/apple-purchase/index.ts').includes('runPriceStep(service'), 'one price step for both sellers')
})
