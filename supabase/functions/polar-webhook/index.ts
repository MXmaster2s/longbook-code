// Receives Polar's webhooks for the licence sold on longbook.app. order.paid records the order
// and gives its licence to the buyer's account when one matches; order.refunded takes it back;
// a licence key grant is stored on its order. Every other event is answered and ignored.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { notifyOwner } from '../_shared/owner-mail.ts'
import { ascKeyFromEnv, runPriceStep } from '../_shared/price-step-live.ts'
import { accountLookup, grantPolarLicence, linkLicenceKey, recordOrder, revokePolarOrder } from '../_shared/polar-live.ts'
import { doublePurchaseNotice, matchAccount, polarEnvironment, readEvent, verifyDelivery, type OrderFacts } from '../_shared/polar.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
// The endpoint's signing secret, whsec_ and all. Secrets of either Polar scheme verify.
const WEBHOOK_SECRET = Deno.env.get('POLAR_WEBHOOK_SECRET') ?? ''
// The licence's product on Polar. Orders for any other product are answered and ignored.
const PRODUCT_ID = Deno.env.get('POLAR_PRODUCT_ID') ?? ''
// The licence's licence-key benefit. A grant from any other benefit is answered and ignored.
const BENEFIT_ID = Deno.env.get('POLAR_BENEFIT_ID')
// production or sandbox. Sandbox orders are recorded as such, never count as seats, and their
// email says nothing was charged.
const ENVIRONMENT = polarEnvironment(Deno.env.get('POLAR_ENVIRONMENT'))
// The confirmation email and the price-step note. Without it nothing is sent.
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
// App Store Connect's key (ASC_PRIVATE_KEY, ASC_KEY_ID, ASC_ISSUER_ID): a web sale that fills a
// launch tier raises the App Store price too. Without it the owner is emailed to do it by hand.
const ASC_KEY = ascKeyFromEnv((name) => Deno.env.get(name))

// A key grant can arrive before its order. For this long a grant with no order to land on is
// refused, so Polar delivers it again; after that it is answered and dropped.
const KEY_RETRY_MS = 10 * 60 * 1000

const reply = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } })

const runtime = (globalThis as { EdgeRuntime?: { waitUntil?(work: Promise<unknown>): void } }).EdgeRuntime
/** Work that need not hold the reply: carried on after it where the runtime allows. */
async function after(work: Promise<unknown>, label: string): Promise<void> {
  const quiet = work.catch((e) => console.error(label, (e as Error).message))
  if (runtime?.waitUntil) runtime.waitUntil(quiet)
  else await quiet
}

async function orderPaid(facts: OrderFacts, delivery: string): Promise<Response> {
  const { order } = facts
  if (order.product_id !== PRODUCT_ID) return reply({ ignored: 'another product' })
  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const stored = await recordOrder(service, order, ENVIRONMENT)
  if (stored.status === 'refunded') return reply({ ignored: 'refunded' })
  if (stored.scrubbed) return reply({ ignored: 'account deleted' })
  if (ENVIRONMENT === 'production') {
    await after(runPriceStep(service, { asc: ASC_KEY, resend: RESEND_API_KEY }), 'price step')
  }
  const lookup = accountLookup(service, SUPABASE_URL, SERVICE_ROLE_KEY)
  // An order already claimed stays with its account, whatever a repeat delivery says.
  const claimed = stored.claimed_by ? await lookup.byId(stored.claimed_by) : null
  const account = claimed ?? (await matchAccount(facts, lookup))?.account ?? null
  if (!account) {
    console.log('polar order unclaimed', order.order_id, delivery)
    return reply({ recorded: order.order_id, claimed: false })
  }
  const granted = await grantPolarLicence(service, {
    order,
    account,
    licenseKeyId: stored.license_key_id,
    environment: ENVIRONMENT,
    resendKey: RESEND_API_KEY,
  })
  if (granted.confirming) await after(granted.confirming, 'purchase email')
  if (granted.decision === 'held' && !stored.claimed_by) {
    const note = doublePurchaseNotice(order, granted.held?.source)
    await after(notifyOwner(RESEND_API_KEY, note.subject, note.text), 'double purchase')
  }
  return reply({ recorded: order.order_id, claimed: true, licence: granted.decision })
}

async function orderRefunded(facts: OrderFacts): Promise<Response> {
  const { order } = facts
  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  if (order.product_id === PRODUCT_ID) await recordOrder(service, order, ENVIRONMENT)
  // A partial refund leaves the licence; the row above keeps Polar's figures.
  if (order.status !== 'refunded') return reply({ recorded: order.order_id, revoked: 0 })
  // Matched on the order id, so a licence written for this order is revoked whichever
  // product it was bought under, and no other licence is touched.
  const revoked = await revokePolarOrder(service, order.order_id)
  return reply({ recorded: order.order_id, revoked: revoked.length })
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return reply({ error: 'method not allowed' }, 405)
  // Without the secret nothing can be verified; a 500 has Polar keep the delivery for later.
  if (!WEBHOOK_SECRET || !PRODUCT_ID) return reply({ error: 'not configured' }, 500)
  const body = await req.text()
  const id = req.headers.get('webhook-id')
  const verdict = await verifyDelivery(
    { id, timestamp: req.headers.get('webhook-timestamp'), signature: req.headers.get('webhook-signature'), body },
    WEBHOOK_SECRET,
  )
  if (!verdict.ok) return reply({ error: verdict.why }, verdict.status)

  const now = new Date()
  const event = readEvent(body, now)
  try {
    switch (event.kind) {
      case 'order.paid':
        return await orderPaid(event.facts, id ?? '')
      case 'order.refunded':
        return await orderRefunded(event.facts)
      case 'licence_key': {
        if (BENEFIT_ID && event.grant.benefitId !== BENEFIT_ID) return reply({ ignored: 'another benefit' })
        const linked = await linkLicenceKey(createClient(SUPABASE_URL, SERVICE_ROLE_KEY), event.grant)
        const made = event.grant.createdAt ? new Date(event.grant.createdAt).getTime() : 0
        if (!linked && now.getTime() - made < KEY_RETRY_MS) return reply({ error: 'order not recorded yet' }, 503)
        return reply({ licence_key: linked ? 'stored' : 'no matching order' })
      }
      default:
        return reply({ ignored: event.type || 'unknown', why: event.why })
    }
  } catch (e) {
    // Anything that failed midway is retried by Polar, and every step above may repeat.
    console.error('polar webhook', id, (e as Error).message)
    return reply({ error: 'could not record' }, 500)
  }
})
