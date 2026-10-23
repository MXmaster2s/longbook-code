// The launch-pricing count: App Store licences bought in production. Family copies, TestFlight's
// sandbox purchases and free grants are not seats.
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2'

export async function soldSeats(service: SupabaseClient): Promise<number> {
  const { count, error } = await service
    .from('entitlements')
    .select('user_id', { count: 'exact', head: true })
    .eq('apple_environment', 'Production')
    .not('apple_original_transaction_id', 'is', null)
    .or('apple_ownership.is.null,apple_ownership.eq.PURCHASED')
  if (error) throw new Error(error.message)
  return count ?? 0
}

