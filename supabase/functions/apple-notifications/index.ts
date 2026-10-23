// App Store Server Notifications: Apple tells this address when a purchase is refunded,
// revoked or reversed, and when a longbook Cloud subscription renews, lapses or changes, so
// both follow the money with the app closed. The payload is a JWS Apple signed, verified
// against Apple's pinned root as apple-purchase does.
import { createClient } from 'npm:@supabase/supabase-js@2'
import * as jose from 'npm:jose@5'
import * as x509 from 'npm:@peculiar/x509@1'
import {
  CLOUD_NOTICES,
  accountToken,
  isCloudTransaction,
  isStale,
  noticeChange,
  subscriptionRow,
  type RenewalInfo,
  type SubscriptionTransaction,
} from '../_shared/cloud-subscription.ts'
import { grantLicenceCloud, revokeLicenceCloud } from '../_shared/licence-cloud.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
// The environments a subscription notice counts in, as apple-purchase reads them.
const ENVIRONMENTS = (Deno.env.get('APPLE_ENVIRONMENTS') ?? 'Sandbox,Production').split(',')
const BUNDLE_ID = 'app.longbook.longbook'
const PRODUCT_ID = 'app.longbook.licence'

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
const LEAF_OID = '1.2.840.113635.100.6.11.1'
const INTERMEDIATE_OID = '1.2.840.113635.100.6.2.1'

x509.cryptoProvider.set(crypto)

// Byte for byte, without Node's Buffer: the edge runtime does not provide it as a global.
function sameBytes(a: ArrayBuffer, b: ArrayBuffer): boolean {
  const x = new Uint8Array(a), y = new Uint8Array(b)
  return x.length === y.length && x.every((v, i) => v === y[i])
}

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
  if (!(await leaf.verify({ publicKey: await intermediate.publicKey.export(), signatureOnly: true }))) throw new Error('leaf not signed by the intermediate')
  if (!(await intermediate.verify({ publicKey: await root.publicKey.export(), signatureOnly: true }))) throw new Error('intermediate not signed by the root')
  if (!leaf.getExtension(LEAF_OID)) throw new Error('leaf is not an App Store signer')
  if (!intermediate.getExtension(INTERMEDIATE_OID)) throw new Error('intermediate is not WWDR')
  return leaf.publicKey.export()
}

async function decode<T>(jws: string): Promise<T> {
  const header = jose.decodeProtectedHeader(jws)
  if (header.alg !== 'ES256' || !Array.isArray(header.x5c)) throw new Error('not an App Store signature')
  const key = await verifyChain(header.x5c as string[])
  const { payload } = await jose.compactVerify(jws, key)
  return JSON.parse(new TextDecoder().decode(payload)) as T
}

type Notification = {
  notificationType?: string
  subtype?: string
  signedDate?: number
  data?: { bundleId?: string; environment?: string; signedTransactionInfo?: string; signedRenewalInfo?: string }
}
type Transaction = SubscriptionTransaction

// What each notice means for the licence. Anything else is none of this table's business.
const STATUS: Record<string, 'active' | 'revoked'> = {
  REFUND: 'revoked',
  REVOKE: 'revoked',
  REFUND_REVERSED: 'active',
}

const noted = () => new Response('noted', { status: 200 })
const json = (data: unknown) =>
  new Response(JSON.stringify(data), { status: 200, headers: { 'Content-Type': 'application/json' } })

/**
 * A notice about a longbook Cloud subscription, found by Apple's original transaction id;
 * a row the app has not recorded yet is made for the account the transaction names. One
 * signed before what the row holds, or for no account, is acknowledged and left alone.
 */
async function recordCloudNotice(notice: Notification, tx: Transaction): Promise<Response> {
  const environment = notice.data?.environment ?? tx.environment
  if (!environment || !ENVIRONMENTS.includes(environment)) return noted()
  if (!tx.originalTransactionId || !CLOUD_NOTICES.has(notice.notificationType ?? '')) return noted()
  let renewal: RenewalInfo | null = null
  if (notice.data?.signedRenewalInfo) {
    try {
      renewal = await decode<RenewalInfo>(notice.data.signedRenewalInfo)
    } catch (e) {
      return new Response(`unverified renewal info: ${(e as Error).message}`, { status: 400 })
    }
  }
  const now = new Date()
  const change = noticeChange(notice.notificationType ?? '', notice.subtype, tx, renewal, now)
  if (!change) return noted()
  const signedAt = typeof notice.signedDate === 'number' ? new Date(notice.signedDate).toISOString() : now.toISOString()

  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const { data: row } = await service
    .from('cloud_subscriptions')
    .select('user_id, last_signed_at')
    .eq('apple_original_transaction_id', tx.originalTransactionId)
    .maybeSingle()
  if (!row) {
    const userId = accountToken(tx.appAccountToken)
    if (!userId) return noted()
    const { error } = await service
      .from('cloud_subscriptions')
      .upsert({ user_id: userId, ...subscriptionRow(tx, now), ...change, last_signed_at: signedAt, updated_at: signedAt }, { onConflict: 'user_id' })
    // 23503: the account the transaction names is gone, or never was.
    if (error && error.code !== '23503') return new Response('could not record', { status: 500 })
    return json({ ok: true, ...change })
  }
  if (isStale(notice.signedDate, row.last_signed_at)) return noted()
  const { error } = await service
    .from('cloud_subscriptions')
    .update({ ...change, apple_environment: environment, last_signed_at: signedAt, updated_at: signedAt })
    .eq('apple_original_transaction_id', tx.originalTransactionId)
  if (error) return new Response('could not record', { status: 500 })
  return json({ ok: true, ...change })
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method not allowed', { status: 405 })
  let body: { signedPayload?: unknown }
  try {
    body = await req.json()
  } catch {
    return new Response('bad json', { status: 400 })
  }
  if (typeof body.signedPayload !== 'string') return new Response('signedPayload required', { status: 400 })

  let notice: Notification
  try {
    notice = await decode<Notification>(body.signedPayload)
  } catch (e) {
    return new Response(`unverified: ${(e as Error).message}`, { status: 400 })
  }
  // Acknowledged and ignored: the wrong app, a notice neither table has a row for, or one
  // without a transaction. Apple keeps retrying on anything but a 2xx.
  if (notice.data?.bundleId !== BUNDLE_ID) return new Response('not this app', { status: 200 })
  const type = notice.notificationType ?? ''
  const status = STATUS[type]
  if ((!status && !CLOUD_NOTICES.has(type)) || !notice.data?.signedTransactionInfo) return noted()

  let tx: Transaction
  try {
    tx = await decode<Transaction>(notice.data.signedTransactionInfo)
  } catch (e) {
    return new Response(`unverified transaction: ${(e as Error).message}`, { status: 400 })
  }
  if (isCloudTransaction(tx)) return recordCloudNotice(notice, tx)
  if (!status) return noted()
  if (tx.productId !== PRODUCT_ID || !tx.originalTransactionId) return noted()

  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  // A family member's copy is recorded under its own column; a notice about it touches the
  // family copies only, and one about the purchase touches the buyer's licence only.
  const family = (tx as { inAppOwnershipType?: string }).inAppOwnershipType === 'FAMILY_SHARED'
  const { error } = await service
    .from('entitlements')
    .update({ status })
    .eq(family ? 'apple_family_transaction_id' : 'apple_original_transaction_id', tx.originalTransactionId)
  if (error) return new Response('could not record', { status: 500 })
  // The licence's 12 months of Cloud follow each licence, the buyer's or a family copy: a
  // refund takes them back, a reversed refund restores them from the purchase date.
  const { data: rows } = await service.from('entitlements').select('user_id, purchased_at')
    .eq(family ? 'apple_family_transaction_id' : 'apple_original_transaction_id', tx.originalTransactionId)
  for (const row of rows ?? []) {
    if (status === 'revoked') await revokeLicenceCloud(service, row.user_id)
    else if (row.purchased_at) await grantLicenceCloud(service, row.user_id, new Date(row.purchased_at))
  }
  return new Response(JSON.stringify({ ok: true, status }), { status: 200, headers: { 'Content-Type': 'application/json' } })
})
