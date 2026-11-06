// The launch-pricing count: App Store licences bought in production and still held, plus paid
// web orders from longbook.app (see isWebSeat). Family copies, TestFlight's sandbox purchases,
// free orders, free grants and refunded licences are not seats.
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { WEB_SEATS_FROM } from './licence-seats.ts'

export async function soldSeats(service: Pick<SupabaseClient, 'from'>): Promise<number> {
  const apple = await service
    .from('entitlements')
    .select('user_id', { count: 'exact', head: true })
    .eq('apple_environment', 'Production')
    .eq('status', 'active')
    .not('apple_original_transaction_id', 'is', null)
    .or('apple_ownership.is.null,apple_ownership.eq.PURCHASED')
  if (apple.error) throw new Error(apple.error.message)
  // The same rule as isWebSeat, asked of the database.
  const web = await service
    .from('web_orders')
    .select('order_id', { count: 'exact', head: true })
    .eq('status', 'paid')
    .eq('environment', 'production')
    .gt('amount', 0)
    .gte('paid_at', WEB_SEATS_FROM)
  if (web.error) throw new Error(web.error.message)
  return (apple.count ?? 0) + (web.count ?? 0)
}


/** The highest price step already claimed, or 0: the bar never shows a price the App Store
 *  has stepped past, even after refunds bring the count back under a tier. */
export async function steppedTier(service: SupabaseClient): Promise<number> {
  const { data, error } = await service.from('licence_price_steps').select('tier').order('tier', { ascending: false }).limit(1)
  if (error) throw new Error(error.message)
  const tier = (data ?? [])[0]?.tier
  return typeof tier === 'number' ? tier : 0
}
