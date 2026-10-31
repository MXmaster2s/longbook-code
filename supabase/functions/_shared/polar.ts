// Polar sells the licence on longbook.app. This module holds what the three polar functions
// decide: webhook signatures, orders and licence keys read defensively, which account an order
// belongs to, and the words a refusal uses. Pure, so the functions and the tests share it.
import type { models, webhooks } from 'npm:@polar-sh/sdk@1.0.2/2026-10'

export type PolarEnvironment = 'production' | 'sandbox'

/** The API version every request pins, so responses keep the shapes typed here. */
export const POLAR_VERSION = '2026-10'
export const POLAR_PORTAL = 'https://polar.sh/ccs/portal'
export const SUCCESS_URL = 'https://longbook.app/thanks/?checkout_id={CHECKOUT_ID}'
export const ACTIVATION_LABEL = 'longbook account'
export const TOLERANCE_SECONDS = 5 * 60
export const MAJOR_VERSION = 1

export function polarEnvironment(value: string | undefined): PolarEnvironment {
  return value?.trim().toLowerCase() === 'sandbox' ? 'sandbox' : 'production'
}

export function polarApi(environment: PolarEnvironment): string {
  return environment === 'sandbox' ? 'https://sandbox-api.polar.sh' : 'https://api.polar.sh'
}

export function polarHeaders(token?: string): Record<string, string> {
  return {
    'Content-Type': 'application/json',
    Accept: 'application/json',
    'Polar-Version': POLAR_VERSION,
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
  }
}

// ---- signatures ---------------------------------------------------------------------------

export interface Delivery {
  id: string | null
  timestamp: string | null
  signature: string | null
  body: string
}

export type Verdict = { ok: true } | { ok: false; status: 400 | 401; why: string }

// Built on a fresh ArrayBuffer, so WebCrypto takes the bytes as they are.
function base64Bytes(value: string) {
  try {
    const raw = atob(value)
    const bytes = new Uint8Array(new ArrayBuffer(raw.length))
    for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i)
    return bytes
  } catch {
    return null
  }
}

/**
 * The keys a delivery may be signed with. Secrets issued before 8 September 2026 sign with the
 * UTF-8 bytes of the whole whsec_ string; later ones with the base64 after the prefix, as
 * Standard Webhooks does. Both are tried, so either secret verifies.
 */
export function signingKeys(secret: string) {
  const whole = new TextEncoder().encode(secret)
  const decoded = base64Bytes(secret.startsWith('whsec_') ? secret.slice(6) : secret)
  const same = decoded !== null && decoded.length === whole.length && decoded.every((b, i) => b === whole[i])
  return decoded && decoded.length > 0 && !same ? [whole, decoded] : [whole]
}

/** HMAC-SHA256 over "{id}.{timestamp}.{body}", any v1 entry of the header matching any key. */
export async function verifyDelivery(d: Delivery, secret: string, nowSeconds = Date.now() / 1000): Promise<Verdict> {
  if (!secret) return { ok: false, status: 401, why: 'no secret' }
  if (!d.id || !d.timestamp || !d.signature) return { ok: false, status: 400, why: 'missing signature headers' }
  const at = Number(d.timestamp)
  if (!Number.isFinite(at)) return { ok: false, status: 400, why: 'bad timestamp' }
  if (Math.abs(nowSeconds - at) > TOLERANCE_SECONDS) return { ok: false, status: 400, why: 'stale' }
  const signed = new TextEncoder().encode(`${d.id}.${Math.floor(at)}.${d.body}`)
  const keys = await Promise.all(signingKeys(secret).map((k) =>
    crypto.subtle.importKey('raw', k, { name: 'HMAC', hash: 'SHA-256' }, false, ['verify'])))
  for (const entry of d.signature.split(' ')) {
    const [version, value] = entry.split(',', 2)
    if (version !== 'v1' || !value) continue
    const given = base64Bytes(value)
    if (!given) continue
    for (const key of keys) {
      if (await crypto.subtle.verify('HMAC', key, given, signed)) return { ok: true }
    }
  }
  return { ok: false, status: 401, why: 'bad signature' }
}

// ---- orders -------------------------------------------------------------------------------

/** An order as any API version may send it: 2026-10's shape, or the earlier amount and user. */
type LooseOrder = Partial<Omit<models.Order, 'customer'>> & {
  customer?: Partial<models.OrderCustomer> | null
  amount?: number
  user?: { id?: string; email?: string | null } | null
  paid_at?: string | null
}

/** The web_orders row an order becomes, less what the functions add: environment and claims. */
export interface WebOrder {
  order_id: string
  email: string
  polar_customer_id: string | null
  external_customer_id: string | null
  product_id: string
  amount: number
  currency: string
  country: string | null
  status: 'paid' | 'refunded'
  paid_at: string
  refunded_at: string | null
}

export interface OrderFacts {
  order: WebOrder
  /** The user id the checkout carried in its metadata, when it did. */
  metadataUserId: string | null
  /** The order's status as Polar gives it: paid, pending, partially_refunded and so on. */
  polarStatus: string | null
}

/** The columns of web_orders that rebuild a WebOrder. */
export const WEB_ORDER_COLUMNS =
  'order_id, email, polar_customer_id, external_customer_id, product_id, amount, currency, country, status, paid_at, refunded_at'

/** A web_orders row back as facts, or null when it holds no email to send a confirmation to. */
export function orderFromRow(row: Omit<WebOrder, 'email'> & { email: string | null }): OrderFacts | null {
  const { email, ...rest } = row
  return email ? { order: { ...rest, email }, metadataUserId: null, polarStatus: row.status } : null
}

const text = (v: unknown): string | null => (typeof v === 'string' && v.trim() ? v.trim() : null)

/**
 * The order as a row, or null when it lacks an id, email, product, amount or currency. `at` is
 * the event's own time, standing in for the payment time on order.paid and the refund time on
 * order.refunded. Only a full refund marks the order refunded.
 */
export function readOrder(data: unknown, at: string, event: 'paid' | 'refunded' | 'fetched'): OrderFacts | null {
  if (!data || typeof data !== 'object') return null
  const o = data as LooseOrder
  const id = text(o.id)
  const email = text(o.customer?.email) ?? text(o.user?.email)
  const product = text(o.product_id) ?? text(o.product?.id)
  const amount = o.total_amount ?? o.amount
  const currency = text(o.currency)
  if (!id || !email || !product || typeof amount !== 'number' || !Number.isInteger(amount) || !currency) return null
  const refunded = o.status === 'refunded' || (amount > 0 && (o.refunded_amount ?? 0) >= amount)
  const metadata = (o.metadata ?? {}) as Record<string, unknown>
  return {
    order: {
      order_id: id,
      email,
      polar_customer_id: text(o.customer_id) ?? text(o.customer?.id),
      external_customer_id: text(o.customer?.external_id),
      product_id: product,
      amount,
      currency: currency.toLowerCase(),
      country: text(o.billing_address?.country) ?? text(o.customer?.billing_address?.country),
      status: refunded ? 'refunded' : 'paid',
      paid_at: text(o.paid_at) ?? (event === 'paid' ? at : text(o.created_at) ?? at),
      refunded_at: refunded ? (event === 'refunded' ? at : text(o.modified_at) ?? at) : null,
    },
    metadataUserId: text(metadata.user_id),
    polarStatus: text(o.status),
  }
}

export interface LicenceKeyGrant {
  licenseKeyId: string
  benefitId: string | null
  orderId: string | null
  customerId: string | null
  createdAt: string | null
}

export type PolarEvent =
  | { kind: 'order.paid'; facts: OrderFacts }
  | { kind: 'order.refunded'; facts: OrderFacts }
  | { kind: 'licence_key'; grant: LicenceKeyGrant }
  | { kind: 'ignored'; type: string; why: string }

type KnownPayload =
  | webhooks.WebhookOrderPaidPayload
  | webhooks.WebhookOrderRefundedPayload
  | webhooks.WebhookBenefitGrantCreatedPayload
  | webhooks.WebhookBenefitGrantUpdatedPayload

/** A verified delivery's body, read into the one thing the webhook acts on. */
export function readEvent(body: string, now: Date): PolarEvent {
  let payload: Partial<KnownPayload> & { type?: string; timestamp?: string; data?: unknown }
  try {
    payload = JSON.parse(body)
  } catch {
    return { kind: 'ignored', type: '', why: 'not json' }
  }
  const type = typeof payload?.type === 'string' ? payload.type : ''
  const at = text(payload.timestamp) ?? now.toISOString()
  if (type === 'order.paid' || type === 'order.refunded') {
    const facts = readOrder(payload.data, at, type === 'order.paid' ? 'paid' : 'refunded')
    return facts ? { kind: type, facts } : { kind: 'ignored', type, why: 'order without id, email, product or amount' }
  }
  if (type === 'benefit_grant.created' || type === 'benefit_grant.updated') {
    const grant = (payload.data ?? {}) as Partial<models.BenefitGrantLicenseKeysWebhook>
    const benefit = grant.benefit as { type?: string } | undefined
    const keyId = text(grant.properties?.license_key_id)
    if (benefit?.type !== 'license_keys') return { kind: 'ignored', type, why: 'not a licence key benefit' }
    if (!keyId || grant.is_revoked) return { kind: 'ignored', type, why: 'no licence key on the grant' }
    return {
      kind: 'licence_key',
      grant: { licenseKeyId: keyId, benefitId: text(grant.benefit_id), orderId: text(grant.order_id), customerId: text(grant.customer_id), createdAt: text(grant.created_at) },
    }
  }
  return { kind: 'ignored', type, why: 'not an event the licence follows' }
}

// ---- accounts -----------------------------------------------------------------------------

export interface Account {
  id: string
  email: string | null
}

export interface AccountLookup {
  byId(id: string): Promise<Account | null>
  byEmail(email: string): Promise<Account | null>
}

export type Match = { account: Account; by: 'metadata' | 'external_id' | 'email' }

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
export const isUuid = (v: string | null | undefined): v is string => !!v && UUID.test(v)

export const sameEmail = (a: string | null | undefined, b: string | null | undefined): boolean =>
  !!a && !!b && a.trim().toLowerCase() === b.trim().toLowerCase()

/** An email as a LIKE pattern matching only itself. PostgREST's star stays a wildcard, so the
 *  rows that come back are compared with sameEmail as well. */
export const likeExactly = (email: string): string => email.trim().replace(/[\\%_]/g, '\\$&')

export function pickByEmail(users: { id: string; email?: string | null }[], email: string): Account | null {
  const user = users.find((u) => sameEmail(u.email, email))
  return user ? { id: user.id, email: user.email ?? null } : null
}

/** The account an order belongs to: the checkout's user id, then the customer's external id,
 *  then the account signed in with the order's email. An id naming no account falls through. */
export async function matchAccount(facts: OrderFacts, lookup: AccountLookup): Promise<Match | null> {
  for (const [id, by] of [[facts.metadataUserId, 'metadata'], [facts.order.external_customer_id, 'external_id']] as const) {
    if (!isUuid(id)) continue
    const account = await lookup.byId(id)
    if (account) return { account, by }
  }
  const account = await lookup.byEmail(facts.order.email)
  return account ? { account, by: 'email' } : null
}

// ---- the licence --------------------------------------------------------------------------

/** An order whose account is gone: claimed once, with no account on it now. */
export const isScrubbed = (row: { claimed_at?: string | null; user_id?: string | null }): boolean =>
  !!row.claimed_at && !row.user_id

export interface HeldLicence {
  status: string
  source?: string | null
  polar_order_id?: string | null
}

/** write: no active licence, so this order's is written. same: this order's already stands.
 *  held: an active licence from elsewhere stays, and the order is only claimed. */
export type Decision = 'write' | 'same' | 'held'

export function licenceDecision(held: HeldLicence | null, orderId: string): Decision {
  if (!held || held.status !== 'active') return 'write'
  return held.polar_order_id === orderId ? 'same' : 'held'
}

export interface PolarLicence {
  userId: string
  orderId: string
  customerId: string | null
  licenseKeyId: string | null
  paidAt: string
}

/** The entitlements row for a web licence. It carries no Apple ids, so no App Store notice can
 *  revoke it, and its email mark starts empty, so the confirmation goes once. */
export function polarEntitlement(l: PolarLicence): Record<string, unknown> {
  return {
    user_id: l.userId,
    major_version: MAJOR_VERSION,
    status: 'active',
    source: 'polar',
    polar_order_id: l.orderId,
    polar_customer_id: l.customerId,
    polar_license_key_id: l.licenseKeyId,
    purchased_at: l.paidAt,
    purchase_email_sent_at: null,
    apple_original_transaction_id: null,
    apple_family_transaction_id: null,
    apple_ownership: null,
    apple_environment: null,
  }
}

export function doublePurchaseNotice(order: WebOrder, source: string | null | undefined): { subject: string; text: string } {
  const paid = order.amount > 0 ? `${(order.amount / 100).toFixed(2)} ${order.currency.toUpperCase()}` : 'no charge'
  const next = order.amount > 0
    ? 'Refund the order in the Polar dashboard if the buyer did not mean to buy twice.'
    : 'Nothing was charged, so there is nothing to refund.'
  return {
    subject: 'longbook: a second licence was bought for one account',
    text: `Polar order ${order.order_id} (${paid}) was placed by ${order.email}, whose longbook account already holds an active licence from ${source ?? 'another source'}.\n\n` +
      `The order is recorded and claimed by that account; its licence is unchanged. ${next}`,
  }
}

// ---- requests -----------------------------------------------------------------------------

export function checkoutBody(input: { productId: string; userId: string; email: string | null }): models.CheckoutCreate {
  return {
    products: [input.productId],
    ...(input.email ? { customer_email: input.email } : {}),
    external_customer_id: input.userId,
    metadata: { user_id: input.userId },
    success_url: SUCCESS_URL,
  }
}

export function portalBody(userId: string): models.CustomerSessionCustomerExternalIDCreate {
  return { external_customer_id: userId }
}

// ---- claiming a licence key ---------------------------------------------------------------

/** Every refusal the polar functions give, in the product's voice. */
export const WHY = {
  signIn: 'Sign in to longbook to continue.',
  noKey: 'Enter the licence key from the email Polar sent after your purchase.',
  notFound: 'This licence key was not found. Copy it again from the email Polar sent after your purchase.',
  inactive: 'This licence key is not active.',
  notLongbook: 'This licence key is not for longbook.',
  refunded: 'This licence key belongs to a refunded order.',
  inUse: 'This licence key is already in use on another longbook account.',
  licensed: 'This account already holds a longbook licence.',
  noAction: 'Choose checkout or portal.',
  unavailable: 'Polar could not be reached. Try again in a few minutes.',
  notSet: 'Purchases on longbook.app are not available right now.',
  failed: 'The licence could not be recorded. Try again in a few minutes.',
} as const

export type Why = keyof typeof WHY

/** What Polar's answer to validate means for a claim; null when the key may go on. */
export function keyProblem(key: Partial<models.ValidatedLicenseKey>, now: Date): Why | null {
  if (key.status !== 'granted') return 'inactive'
  if (key.expires_at && new Date(key.expires_at).getTime() <= now.getTime()) return 'inactive'
  return null
}

/** A refused validate or activate, by Polar's status code. 403 on activate is the limit. */
export function polarRefusal(status: number, step: 'validate' | 'activate'): Why {
  if (status === 404 || status === 422) return 'notFound'
  if (status === 403 && step === 'activate') return 'inUse'
  if (status === 400 || status === 403) return 'inactive'
  return 'unavailable'
}

/** True when one of the key's activations is this account's own, made by an earlier claim. */
export function activatedBy(key: Partial<models.LicenseKeyWithActivations>, userId: string): boolean {
  return (key.activations ?? []).some((a) => a.meta?.user_id === userId)
}

/** The licence order among a customer's orders: a paid one first, else a refund, else none. */
export function pickOrder(items: unknown[], productId: string, at: string): OrderFacts | 'refunded' | null {
  const ours = items.map((i) => readOrder(i, at, 'fetched')).filter((f): f is OrderFacts => !!f && f.order.product_id === productId)
  const paid = ours.find((f) => f.order.status === 'paid' && ['paid', 'partially_refunded'].includes(f.polarStatus ?? ''))
  if (paid) return paid
  return ours.some((f) => f.order.status === 'refunded') ? 'refunded' : null
}
