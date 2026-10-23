// A licence brings its first twelve months of longbook Cloud, kept as a cloud_grants row with
// the note 'licence'. A grant made by hand that runs longer is never shortened, and a refund
// takes back only the licence's own grant.

export const LICENCE_CLOUD_MONTHS = 12
export const LICENCE_NOTE = 'licence'
/** App Review's account buys the licence without its Cloud months, so the reviewer can still
 *  reach the Cloud subscription it is asked to find. Matches REVIEW_EMAIL in AuthClient.swift. */
export const REVIEW_EMAIL = 'appreview@longbook.app'

export interface Grant { until: string; note: string | null }

/** When the licence's Cloud ends: the same day, twelve months after the purchase. */
export function licenceCloudUntil(purchasedAt: Date): Date {
  const until = new Date(purchasedAt)
  until.setUTCMonth(until.getUTCMonth() + LICENCE_CLOUD_MONTHS)
  return until
}

/** The row to write for a purchase, or null when a grant already on file reaches further. */
export function nextGrant(existing: Grant | null, purchasedAt: Date): { until: string; note: string } | null {
  const until = licenceCloudUntil(purchasedAt)
  if (existing && new Date(existing.until) >= until) return null
  return { until: until.toISOString(), note: LICENCE_NOTE }
}

interface GrantClient {
  from(table: string): any
  auth?: { admin?: { getUserById(id: string): Promise<{ data: { user: { email?: string } | null } | null }> } }
}

export async function grantLicenceCloud(service: GrantClient, userId: string, purchasedAt: Date): Promise<void> {
  const who = await service.auth?.admin?.getUserById(userId)
  if (who?.data?.user?.email?.toLowerCase() === REVIEW_EMAIL) return
  const { data } = await service.from('cloud_grants').select('until, note').eq('user_id', userId).maybeSingle()
  const row = nextGrant(data as Grant | null, purchasedAt)
  if (!row) return
  const { error } = await service.from('cloud_grants').upsert({ user_id: userId, ...row }, { onConflict: 'user_id' })
  if (error) console.error('licence cloud grant', error.message)
}

export async function revokeLicenceCloud(service: GrantClient, userId: string): Promise<void> {
  const { error } = await service.from('cloud_grants').delete().eq('user_id', userId).eq('note', LICENCE_NOTE)
  if (error) console.error('licence cloud revoke', error.message)
}
