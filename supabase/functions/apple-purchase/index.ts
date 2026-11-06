// Records a purchase made through the App Store: verifies the signed transaction StoreKit
// handed the app against Apple's pinned root, then writes the signed-in account's row — the
// licence into entitlements, a longbook Cloud subscription into cloud_subscriptions. The
// client's word about what was bought is never trusted.
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'
import * as jose from 'npm:jose@5'
import * as x509 from 'npm:@peculiar/x509@1'
import { confirmPurchase, entitlementSentMark } from '../_shared/confirm-purchase.ts'
import { isCloudTransaction, isStale, subscriptionRow } from '../_shared/cloud-subscription.ts'
import { cloudStep, isFamilyShared, licenceStep, type CloudHeld, type LicenceHeld, type SharedTransaction } from '../_shared/family-sharing.ts'
import { grantLicenceCloud, revokeLicenceCloud } from '../_shared/licence-cloud.ts'
import { ascKeyFromEnv, runPriceStep } from '../_shared/price-step-live.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
// Which App Store environments are recorded. A Sandbox purchase (TestFlight, App Review) is a
// test licence, active like any other but unlocking only copies in Apple's test environment.
// APPLE_ENVIRONMENTS=Production refuses it outright.
const ENVIRONMENTS = (Deno.env.get('APPLE_ENVIRONMENTS') ?? 'Sandbox,Production').split(',')
// The confirmation email. Without a key the function records purchases and sends nothing.
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
// App Store Connect's key (ASC_PRIVATE_KEY, ASC_KEY_ID, ASC_ISSUER_ID), for raising the price
// when a launch tier fills. Without it the step is still recorded and the owner is emailed to
// raise it by hand.
const ASC_KEY = ascKeyFromEnv((name) => Deno.env.get(name))

const BUNDLE_ID = 'app.longbook.longbook'
// Every App Store licence names Apple and carries no Polar ids, so a Polar refund, which
// matches on polar_order_id, cannot touch it.
const APPLE_SOURCE = { source: 'apple', polar_order_id: null, polar_customer_id: null, polar_license_key_id: null }
const PRODUCT_ID = 'app.longbook.licence'
const CURRENT_MAJOR_VERSION = 1

// Apple Root CA - G3, the root every App Store transaction chain ends in. Public, pinned by
// its bytes: a chain that ends anywhere else is refused whatever it says.
const APPLE_ROOT_CA_G3 =
  'MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9v' +
  'dCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UE' +
  'CgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2' +
  'WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmlj' +
  'YXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqG' +
  'SM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxE' +
  'tX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNC' +
  'MEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0P' +
  'AQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3m' +
  'eoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkL' +
  'F1vLUagM6BgD56KyKA=='

// The marks Apple puts on the certificates that may sign a transaction: the leaf carries the
// receipt-signing extension, the intermediate the WWDR one. A valid chain without them is
// some other Apple certificate, not this one.
const LEAF_OID = '1.2.840.113635.100.6.11.1'
const INTERMEDIATE_OID = '1.2.840.113635.100.6.2.1'

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
}
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } })
const refuse = (error: string, status: number) => json({ error }, status)

x509.cryptoProvider.set(crypto)

// Byte for byte, without Node's Buffer: the edge runtime does not provide it as a global.
function sameBytes(a: ArrayBuffer, b: ArrayBuffer): boolean {
  const x = new Uint8Array(a), y = new Uint8Array(b)
  return x.length === y.length && x.every((v, i) => v === y[i])
}

type Payload = SharedTransaction & {
  bundleId?: string
  transactionId?: string
  purchaseDate?: number
}

/** Apple's chain, leaf to root, verified link by link and ended at the pinned root. */
async function verifyChain(x5c: string[]): Promise<CryptoKey> {
  if (x5c.length < 3) throw new Error('chain too short')
  const certs = x5c.map((der) => new x509.X509Certificate(der))
  const [leaf, intermediate, root] = certs
  const pinned = new x509.X509Certificate(APPLE_ROOT_CA_G3)
  if (!sameBytes(root.rawData, pinned.rawData)) {
    throw new Error('chain does not end at Apple Root CA - G3')
  }
  const now = new Date()
  for (const cert of certs) {
    if (cert.notBefore > now || cert.notAfter < now) throw new Error('certificate out of its dates')
  }
  if (!(await leaf.verify({ publicKey: await intermediate.publicKey.export(), signatureOnly: true }))) {
    throw new Error('leaf not signed by the intermediate')
  }
  if (!(await intermediate.verify({ publicKey: await root.publicKey.export(), signatureOnly: true }))) {
    throw new Error('intermediate not signed by the root')
  }
  if (!(await root.verify({ publicKey: await root.publicKey.export(), signatureOnly: true }))) {
    throw new Error('root not self-signed')
  }
  if (!leaf.getExtension(LEAF_OID)) throw new Error('leaf is not a transaction signer')
  if (!intermediate.getExtension(INTERMEDIATE_OID)) throw new Error('intermediate is not WWDR')
  return leaf.publicKey.export()
}

/** The transaction as Apple signed it, or a reason it is refused. */
async function decode(jws: string): Promise<Payload> {
  const header = jose.decodeProtectedHeader(jws)
  if (header.alg !== 'ES256' || !Array.isArray(header.x5c)) throw new Error('not an App Store transaction')
  const key = await verifyChain(header.x5c as string[])
  const { payload } = await jose.compactVerify(jws, key)
  return JSON.parse(new TextDecoder().decode(payload)) as Payload
}

/**
 * A longbook Cloud transaction: the account's one subscription row, written by user id, as
 * cloudStep in family-sharing.ts decides. A family member's copy is recorded the same way on
 * their own account. One Apple signed before what the row holds leaves the row as it stands.
 */
async function recordCloud(tx: Payload, userId: string, auto: boolean): Promise<Response> {
  if (!tx.environment || !ENVIRONMENTS.includes(tx.environment)) return refuse('environment not accepted', 400)
  if (!tx.originalTransactionId) return refuse('no transaction id', 400)
  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const columns = 'user_id, status, expires_at, last_signed_at, apple_original_transaction_id, apple_ownership'
  const { data: found } = await service.from('cloud_subscriptions').select(columns)
    .eq('apple_original_transaction_id', tx.originalTransactionId).maybeSingle()
  const holder = found && found.user_id !== userId ? found as CloudHeld : null
  const { data: own } = await service.from('cloud_subscriptions').select(columns).eq('user_id', userId).maybeSingle()
  const mine = own as CloudHeld | null
  if (mine && mine.apple_original_transaction_id === tx.originalTransactionId && isStale(tx.signedDate, mine.last_signed_at)) {
    return json({ ok: true, status: mine.status, expires_at: mine.expires_at })
  }
  const now = new Date()
  const step = cloudStep({ tx, userId, mine, holder, auto, now })
  if (step.kind === 'refuse') return refuse(step.error, 409)
  if (step.kind === 'keep') return json({ ok: true, status: mine?.status ?? null, expires_at: mine?.expires_at ?? null })
  if (step.moveFrom) {
    // An explicit restore of a family copy: it leaves the account that held it.
    const { error: moveError } = await service.from('cloud_subscriptions').delete()
      .eq('user_id', step.moveFrom).eq('apple_original_transaction_id', tx.originalTransactionId)
    if (moveError) return refuse('could not move the subscription', 500)
  }
  const row = subscriptionRow(tx, now)
  const { error } = await service
    .from('cloud_subscriptions')
    .upsert({ user_id: userId, ...row, updated_at: now.toISOString() }, { onConflict: 'user_id' })
  if (error) return refuse('could not record the subscription', 500)
  return json({ ok: true, status: row.status, expires_at: row.expires_at, family: isFamilyShared(tx) })
}

const LICENCE_COLUMNS = 'user_id, status, kind, apple_original_transaction_id, apple_family_transaction_id'

/** The entitlements row the decision reads, by user or by the column a transaction lands in. */
async function licenceRows(service: SupabaseClient, tx: Payload, userId: string): Promise<{ mine: LicenceHeld | null; holder: LicenceHeld | null }> {
  const { data: mine } = await service.from('entitlements').select(LICENCE_COLUMNS).eq('user_id', userId).maybeSingle()
  const column = isFamilyShared(tx) ? 'apple_family_transaction_id' : 'apple_original_transaction_id'
  const { data: held } = await service.from('entitlements').select(LICENCE_COLUMNS)
    .eq(column, tx.originalTransactionId!).neq('user_id', userId).limit(1)
  return { mine: (mine as LicenceHeld | null) ?? null, holder: ((held ?? [])[0] as LicenceHeld | undefined) ?? null }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS_HEADERS })
  if (req.method !== 'POST') return refuse('method not allowed', 405)

  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer /, '')
  if (!jwt) return refuse('unauthorized', 401)
  const anon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  const { data: { user }, error: authError } = await anon.auth.getUser(jwt)
  if (authError || !user) return refuse('unauthorized', 401)

  let body: { jws?: unknown; auto?: unknown }
  try {
    body = await req.json()
  } catch {
    return refuse('bad json', 400)
  }
  if (typeof body.jws !== 'string' || body.jws.length > 20_000) return refuse('a signed transaction is required', 400)
  // Sent by the app on its own, at launch or from the App Store's updates, rather than by a
  // purchase or Restore Purchase: such a record never moves a purchase between accounts.
  const auto = body.auto === true

  let tx: Payload
  try {
    tx = await decode(body.jws)
  } catch (e) {
    return refuse(`the transaction could not be verified: ${(e as Error).message}`, 400)
  }
  if (tx.bundleId !== BUNDLE_ID) return refuse('not this app', 400)
  if (isCloudTransaction(tx)) return recordCloud(tx, user.id, auto)
  if (tx.productId !== PRODUCT_ID) return refuse('not the licence', 400)
  if (tx.type !== 'Non-Consumable') return refuse('not a licence purchase', 400)
  if (!tx.environment || !ENVIRONMENTS.includes(tx.environment)) return refuse('environment not accepted', 400)
  if (!tx.originalTransactionId) return refuse('no transaction id', 400)

  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const { mine, holder } = await licenceRows(service, tx, user.id)
  const step = licenceStep({ tx, mine, holder, auto })
  if (step.kind === 'refuse') return refuse(step.error, 409)
  if (step.kind === 'keep') return json({ ok: true, status: step.status })
  const { status, family, licence } = step
  // The purchase, or the family copy, belongs to one longbook account at a time. Restored on
  // another account, the licence and its Cloud move there and leave the old one.
  if (step.moveFrom) {
    const { error: moveError } = await service.from('entitlements')
      .update(family ? { status: 'revoked', apple_family_transaction_id: null } : { status: 'revoked', apple_original_transaction_id: null })
      .eq('user_id', step.moveFrom)
    if (moveError) return refuse('could not move the licence', 500)
    await revokeLicenceCloud(service, step.moveFrom)
  }

  const purchasedAt = tx.purchaseDate ? new Date(tx.purchaseDate) : new Date()
  // A family copy is recorded without the purchase's unique id, so the buyer keeps it; its
  // own id sits beside it for refunds and revocations. It never counts as a seat.
  const ids = family
    ? { apple_original_transaction_id: null, apple_family_transaction_id: tx.originalTransactionId, apple_ownership: 'FAMILY_SHARED' }
    : { apple_original_transaction_id: tx.originalTransactionId, apple_family_transaction_id: null, apple_ownership: 'PURCHASED' }
  const { error } = await service.from('entitlements').upsert(
    {
      user_id: user.id,
      major_version: CURRENT_MAJOR_VERSION,
      status,
      kind: licence,
      ...ids,
      apple_environment: tx.environment,
      ...APPLE_SOURCE,
      purchased_at: purchasedAt.toISOString(),
    },
    { onConflict: 'user_id' },
  )
  if (error) return refuse(family ? 'could not record the family copy' : 'could not record the purchase', 500)
  // The licence brings 12 months of Cloud, to the buyer and to each family copy alike.
  if (status === 'active') await grantLicenceCloud(service, user.id, purchasedAt)
  else await revokeLicenceCloud(service, user.id)
  // A family copy sends no purchase email and is never a sale.
  if (family) return json({ ok: true, status, family: true })
  const runtime = (globalThis as { EdgeRuntime?: { waitUntil?(work: Promise<unknown>): void } }).EdgeRuntime
  // A new App Store sale may fill a launch tier. It runs after the reply where the runtime allows.
  if (step.first && status === 'active' && tx.environment === 'Production') {
    const stepping = runPriceStep(service, { asc: ASC_KEY, resend: RESEND_API_KEY })
      .catch((e) => console.error('price step', (e as Error).message))
    if (runtime?.waitUntil) runtime.waitUntil(stepping)
    else await stepping
  }
  // A test licence cost nothing, so it earns no confirmation.
  if (status === 'active' && licence === 'real') {
    const confirming = confirmPurchase(
      { apiKey: RESEND_API_KEY, mark: entitlementSentMark(service), send: fetch, log: console.error },
      {
        userId: user.id,
        transactionId: tx.originalTransactionId,
        email: user.email ?? '',
        purchasedAt,
        majorVersion: CURRENT_MAJOR_VERSION,
        environment: tx.environment,
      },
    )
    // The app waits on this response to finish the purchase, and the email is a courtesy: where
    // the runtime can carry on after replying, it does; elsewhere the reply waits for it.
    if (runtime?.waitUntil) runtime.waitUntil(confirming)
    else await confirming
  }
  return json({ ok: true, status })
})
