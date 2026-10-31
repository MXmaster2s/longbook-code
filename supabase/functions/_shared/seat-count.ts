// The launch-pricing count: App Store licences bought in production, plus paid web orders from
// longbook.app (see isWebSeat). Family copies, sandbox purchases and free grants are not seats.
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { WEB_SEATS_FROM } from './licence-seats.ts'

export async function soldSeats(service: Pick<SupabaseClient, 'from'>): Promise<number> {
  const apple = await service
    .from('entitlements')
    .select('user_id', { count: 'exact', head: true })
    .eq('apple_environment', 'Production')
    .not('apple_original_transaction_id', 'is', null)
    .or('apple_ownership.is.null,apple_ownership.eq.PURCHASED')
  if (apple.error) throw new Error(apple.error.message)
  // The same rule as isWebSeat, asked of the database.
  const web = await service
    .from('web_orders')
    .select('order_id', { count: 'exact', head: true })
    .eq('status', 'paid')
    .eq('environment', 'production')
    .gte('paid_at', WEB_SEATS_FROM)
  if (web.error) throw new Error(web.error.message)
  return (apple.count ?? 0) + (web.count ?? 0)
}
