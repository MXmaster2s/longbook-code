// The polar functions' database work: the web_orders row, the account lookup, and the licence a
// web order grants or a refund takes back. The webhook and the claim share it, so both write the
// same rows the same way. Every write here may repeat safely.
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { confirmPurchase, entitlementSentMark } from './confirm-purchase.ts'
import { grantLicenceCloud, revokeLicenceCloud } from './licence-cloud.ts'
import {
  MAJOR_VERSION,
  isScrubbed,
  licenceDecision,
  pickByEmail,
  polarEntitlement,
  type Account,
  type AccountLookup,
  type Decision,
  type HeldLicence,
  type LicenceKeyGrant,
  type PolarEnvironment,
  type WebOrder,
} from './polar.ts'

export interface StoredOrder {
  status: 'paid' | 'refunded'
  claimed_by: string | null
  license_key_id: string | null
  /** The account is gone: nothing may name a buyer on this row again, or claim it. */
  scrubbed: boolean
}

/** Accounts by id through the admin API, and by email through its user search: each page is
 *  matched exactly, ignoring case, and pages are walked until one comes back short. */
export function accountLookup(service: SupabaseClient, supabaseUrl: string, serviceKey: string): AccountLookup {
  return {
    async byId(id) {
      const { data, error } = await service.auth.admin.getUserById(id)
      if (error || !data?.user) return null
      return { id: data.user.id, email: data.user.email ?? null }
    },
    async byEmail(email) {
      const perPage = 1000
      for (let page = 1; page <= 50; page++) {
        const query = new URLSearchParams({ filter: email, page: String(page), per_page: String(perPage) })
        const res = await fetch(`${supabaseUrl}/auth/v1/admin/users?${query}`, {
          headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
          signal: AbortSignal.timeout(8000),
        })
        if (!res.ok) throw new Error(`account lookup answered ${res.status}`)
        const { users = [] } = (await res.json()) as { users?: { id: string; email?: string | null }[] }
        const found = pickByEmail(users, email)
        if (found) return found
        if (users.length < perPage) return null
      }
      return null
    },
  }
}

/** Writes the order's row and answers with what it now holds. A refund is final: a late or
 *  repeated order.paid never makes a refunded order paid again, and the payment time is kept.
 *  A scrubbed row takes its status and refund time alone. */
export async function recordOrder(service: SupabaseClient, order: WebOrder, environment: PolarEnvironment): Promise<StoredOrder> {
  const { data: stored, error } = await service.from('web_orders')
    .select('status, claimed_by, claimed_at, user_id, license_key_id').eq('order_id', order.order_id).maybeSingle()
  if (error) throw new Error(`could not read the order: ${error.message}`)
  const scrubbed = !!stored && isScrubbed(stored)
  if (stored?.status === 'refunded' && order.status === 'paid') {
    return { status: 'refunded', claimed_by: stored.claimed_by, license_key_id: stored.license_key_id, scrubbed }
  }
  if (scrubbed) {
    const { error: writeError } = await service.from('web_orders')
      .update({ status: order.status, refunded_at: order.refunded_at }).eq('order_id', order.order_id)
    if (writeError) throw new Error(`could not record the order: ${writeError.message}`)
    return { status: order.status, claimed_by: null, license_key_id: null, scrubbed }
  }
  const { paid_at, ...rest } = order
  const row = { ...rest, environment, ...(stored ? {} : { paid_at }) }
  const { error: writeError } = await service.from('web_orders').upsert(row, { onConflict: 'order_id' })
  if (writeError) throw new Error(`could not record the order: ${writeError.message}`)
  return { status: order.status, claimed_by: stored?.claimed_by ?? null, license_key_id: stored?.license_key_id ?? null, scrubbed }
}

export interface Grant {
  order: WebOrder
  account: Account
  licenseKeyId: string | null
  environment: PolarEnvironment
  resendKey: string | undefined
}

export interface Granted {
  decision: Decision
  held: HeldLicence | null
  /** The confirmation email, for the caller to await or hand to the runtime. */
  confirming: Promise<void> | null
}

/** The licence a paid order brings to an account: written unless another active licence stands,
 *  then the order is claimed and the confirmation sent once. Cloud is granted on every pass,
 *  so a repeat after a failure finishes the work. */
export async function grantPolarLicence(service: SupabaseClient, g: Grant): Promise<Granted> {
  const userId = g.account.id
  const { data: held, error } = await service.from('entitlements')
    .select('status, source, polar_order_id').eq('user_id', userId).maybeSingle()
  if (error) throw new Error(`could not read the licence: ${error.message}`)
  const decision = licenceDecision(held as HeldLicence | null, g.order.order_id)
  if (decision === 'write') {
    const row = polarEntitlement({
      userId,
      orderId: g.order.order_id,
      customerId: g.order.polar_customer_id,
      licenseKeyId: g.licenseKeyId,
      paidAt: g.order.paid_at,
    })
    const { error: writeError } = await service.from('entitlements').upsert(row, { onConflict: 'user_id' })
    if (writeError) throw new Error(`could not record the licence: ${writeError.message}`)
  }
  if (decision !== 'held') await grantLicenceCloud(service, userId, new Date(g.order.paid_at))
  if (decision === 'same' && g.licenseKeyId) {
    await service.from('entitlements').update({ polar_license_key_id: g.licenseKeyId })
      .eq('user_id', userId).eq('polar_order_id', g.order.order_id).is('polar_license_key_id', null)
  }
  const now = new Date().toISOString()
  const { error: claimError } = await service.from('web_orders')
    .update({ claimed_at: now, claimed_by: userId, user_id: userId })
    .eq('order_id', g.order.order_id).is('claimed_at', null)
  if (claimError) throw new Error(`could not claim the order: ${claimError.message}`)
  if (g.licenseKeyId) {
    await service.from('web_orders').update({ license_key_id: g.licenseKeyId })
      .eq('order_id', g.order.order_id).is('license_key_id', null)
  }
  const confirming = decision === 'held' ? null : confirmPurchase(
    { apiKey: g.resendKey, mark: entitlementSentMark(service), send: fetch, log: console.error },
    {
      userId,
      transactionId: `polar-${g.order.order_id}`,
      email: g.account.email ?? g.order.email,
      purchasedAt: new Date(g.order.paid_at),
      majorVersion: MAJOR_VERSION,
      environment: g.environment === 'sandbox' ? 'Sandbox' : 'Production',
      seller: 'polar',
    },
  )
  return { decision, held: held as HeldLicence | null, confirming }
}

/** A refunded order's licence, revoked with its Cloud. Only a licence this order wrote is
 *  touched; one the account holds from the App Store or a grant stays. */
export async function revokePolarOrder(service: SupabaseClient, orderId: string): Promise<string[]> {
  const { data, error } = await service.from('entitlements').update({ status: 'revoked' })
    .eq('polar_order_id', orderId).eq('status', 'active').select('user_id')
  if (error) throw new Error(`could not revoke the licence: ${error.message}`)
  const users = (data ?? []).map((r: { user_id: string }) => r.user_id)
  for (const userId of users) await revokeLicenceCloud(service, userId)
  return users
}

/** A licence key Polar issued, stored on its order: by order id, else on the customer's
 *  earliest order still without one. A scrubbed order is answered as done and left empty.
 *  Answers how many orders took it. */
export async function linkLicenceKey(service: SupabaseClient, grant: LicenceKeyGrant): Promise<number> {
  let orderId = grant.orderId
  if (orderId) {
    const { data } = await service.from('web_orders').select('order_id, claimed_at, user_id').eq('order_id', orderId).maybeSingle()
    if (data && isScrubbed(data)) return 1
    if (!data) orderId = null
  }
  if (!orderId && grant.customerId) {
    const { data } = await service.from('web_orders').select('order_id')
      .eq('polar_customer_id', grant.customerId).is('license_key_id', null)
      .order('paid_at', { ascending: true }).limit(1).maybeSingle()
    orderId = (data as { order_id?: string } | null)?.order_id ?? null
  }
  if (!orderId) return 0
  const { error } = await service.from('web_orders').update({ license_key_id: grant.licenseKeyId }).eq('order_id', orderId)
  if (error) throw new Error(`could not store the licence key: ${error.message}`)
  await service.from('entitlements').update({ polar_license_key_id: grant.licenseKeyId })
    .eq('polar_order_id', orderId).is('polar_license_key_id', null)
  return 1
}
