// Records a purchase made through the App Store: verifies the signed transaction StoreKit
// handed the app against Apple's pinned root, then writes the signed-in account's row — the
// licence into entitlements, a longbook Cloud subscription into cloud_subscriptions. The
// client's word about what was bought is never trusted.
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'
import * as jose from 'npm:jose@5'
import * as x509 from 'npm:@peculiar/x509@1'
import { confirmPurchase, entitlementSentMark } from '../_shared/confirm-purchase.ts'
import { isCloudTransaction, isStale, subscriptionRow, type SubscriptionTransaction } from '../_shared/cloud-subscription.ts'
import { grantLicenceCloud, revokeLicenceCloud } from '../_shared/licence-cloud.ts'
import { ascKeyFromEnv, runPriceStep } from '../_shared/price-step-live.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
// Which App Store environments count. Sandbox is TestFlight's; drop it at launch by setting
// APPLE_ENVIRONMENTS=Production, so a sandbox purchase can never become a real licence.
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

type Payload = SubscriptionTransaction & {
  bundleId?: string
  transactionId?: string
  purchaseDate?: number
  /** PURCHASED for the buyer; FAMILY_SHARED for a family member's copy through Family Sharing. */
  inAppOwnershipType?: string
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
 * A longbook Cloud transaction: the account's one subscription row, written by user id. A
 * transaction already recorded for someone else is refused, as a licence is; one Apple
 * signed before what the row holds leaves the row as it stands. No email for Cloud.
 */
async function recordCloud(tx: Payload, userId: string): Promise<Response> {
  if (!tx.environment || !ENVIRONMENTS.includes(tx.environment)) return refuse('environment not accepted', 400)
  if (!tx.originalTransactionId) return refuse('no transaction id', 400)
  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const { data: holder } = await service
    .from('cloud_subscriptions')
    .select('user_id, status, expires_at, last_signed_at')
    .eq('apple_original_transaction_id', tx.originalTransactionId)
    .maybeSingle()
  if (holder && holder.user_id !== userId) return refuse('this subscription belongs to another account', 409)
  if (holder && isStale(tx.signedDate, holder.last_signed_at)) {
    return json({ ok: true, status: holder.status, expires_at: holder.expires_at })
  }
  const row = subscriptionRow(tx, new Date())
  const { error } = await service
    .from('cloud_subscriptions')
    .upsert({ user_id: userId, ...row, updated_at: new Date().toISOString() }, { onConflict: 'user_id' })
  if (error) return refuse('could not record the subscription', 500)
  return json({ ok: true, status: row.status, expires_at: row.expires_at })
}

/** A family member's copy through Family Sharing: a licence for their own longbook account,
 *  with the same 12 months of Cloud. It never takes the buyer's place, never counts as a seat,
 *  and sends no purchase email; an account already holding an active licence keeps it. */
async function recordFamilyCopy(service: SupabaseClient, tx: Payload, userId: string): Promise<Response> {
  const { data: mine } = await service.from('entitlements').select('status').eq('user_id', userId).maybeSingle()
  if (mine?.status === 'active') return json({ ok: true, status: 'active' })
  const status = tx.revocationDate ? 'revoked' : 'active'
  const purchasedAt = tx.purchaseDate ? new Date(tx.purchaseDate) : new Date()
  const { error } = await service.from('entitlements').upsert(
    {
      user_id: userId,
      major_version: CURRENT_MAJOR_VERSION,
      status,
      apple_original_transaction_id: null,
      apple_family_transaction_id: tx.originalTransactionId,
      apple_ownership: 'FAMILY_SHARED',
      apple_environment: tx.environment,
      ...APPLE_SOURCE,
      purchased_at: purchasedAt.toISOString(),
    },
    { onConflict: 'user_id' },
  )
  if (error) return refuse('could not record the family copy', 500)
  if (status === 'active') await grantLicenceCloud(service, userId, purchasedAt)
  else await revokeLicenceCloud(service, userId)
  return json({ ok: true, status, family: true })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS_HEADERS })
  if (req.method !== 'POST') return refuse('method not allowed', 405)

  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer /, '')
  if (!jwt) return refuse('unauthorized', 401)
  const anon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  const { data: { user }, error: authError } = await anon.auth.getUser(jwt)
  if (authError || !user) return refuse('unauthorized', 401)

  let body: { jws?: unknown }
  try {
    body = await req.json()
  } catch {
    return refuse('bad json', 400)
  }
  if (typeof body.jws !== 'string' || body.jws.length > 20_000) return refuse('a signed transaction is required', 400)

  let tx: Payload
  try {
    tx = await decode(body.jws)
  } catch (e) {
    return refuse(`the transaction could not be verified: ${(e as Error).message}`, 400)
  }
  if (tx.bundleId !== BUNDLE_ID) return refuse('not this app', 400)
  if (isCloudTransaction(tx)) return recordCloud(tx, user.id)
  if (tx.productId !== PRODUCT_ID) return refuse('not the licence', 400)
  if (tx.type !== 'Non-Consumable') return refuse('not a licence purchase', 400)
  if (!tx.environment || !ENVIRONMENTS.includes(tx.environment)) return refuse('environment not accepted', 400)
  if (!tx.originalTransactionId) return refuse('no transaction id', 400)

  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  if (tx.inAppOwnershipType === 'FAMILY_SHARED') return recordFamilyCopy(service, tx, user.id)
  // The purchase belongs to the Apple account that paid. Bought again or restored on another
  // longbook account, the licence and its Cloud move here and leave the old account.
  const { data: holder } = await service
    .from('entitlements')
    .select('user_id')
    .eq('apple_original_transaction_id', tx.originalTransactionId)
    .maybeSingle()
  if (holder && holder.user_id !== user.id) {
    const { error: moveError } = await service.from('entitlements')
      .update({ status: 'revoked', apple_original_transaction_id: null })
      .eq('user_id', holder.user_id)
    if (moveError) return refuse('could not move the licence', 500)
    await revokeLicenceCloud(service, holder.user_id)
  }

  const status = tx.revocationDate ? 'revoked' : 'active'
  const purchasedAt = tx.purchaseDate ? new Date(tx.purchaseDate) : new Date()
  const { error } = await service.from('entitlements').upsert(
    {
      user_id: user.id,
      major_version: CURRENT_MAJOR_VERSION,
      status,
      apple_original_transaction_id: tx.originalTransactionId,
      apple_environment: tx.environment,
      apple_ownership: 'PURCHASED',
      apple_family_transaction_id: null,
      ...APPLE_SOURCE,
      purchased_at: purchasedAt.toISOString(),
    },
    { onConflict: 'user_id' },
  )
  if (error) return refuse('could not record the purchase', 500)
  // The licence brings 12 months of Cloud, to the buyer here and to each family copy above.
  if (status === 'active') await grantLicenceCloud(service, user.id, purchasedAt)
  else await revokeLicenceCloud(service, user.id)
  const runtime = (globalThis as { EdgeRuntime?: { waitUntil?(work: Promise<unknown>): void } }).EdgeRuntime
  // A new App Store sale may fill a launch tier. It runs after the reply where the runtime allows.
  if (!holder && status === 'active' && tx.environment === 'Production') {
    const stepping = runPriceStep(service, { asc: ASC_KEY, resend: RESEND_API_KEY })
      .catch((e) => console.error('price step', (e as Error).message))
    if (runtime?.waitUntil) runtime.waitUntil(stepping)
    else await stepping
  }
  if (status === 'active') {
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
