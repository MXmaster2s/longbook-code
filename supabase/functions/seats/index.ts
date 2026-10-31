// How many launch-price licences are left, for the pricing bar on longbook.app. Public and
// read-only: one number of licences sold on the App Store and longbook.app, never who bought.
// Family copies, sandbox purchases and free grants are not seats.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { TIERS, seatsFor } from '../_shared/licence-seats.ts'
import { soldSeats } from '../_shared/seat-count.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Content-Type': 'application/json',
  // A minute is fresh enough for a bar, and keeps a busy page from counting on every view.
  'Cache-Control': 'public, max-age=60',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: HEADERS })
  if (req.method !== 'GET') return new Response(JSON.stringify({ error: 'GET only' }), { status: 405, headers: HEADERS })
  try {
    const sold = await soldSeats(createClient(SUPABASE_URL, SERVICE_ROLE_KEY))
    // The page names Family Sharing only once it is switched on in App Store Connect and tested.
    const family = Deno.env.get('FAMILY_SHARING') === 'on'
    return new Response(JSON.stringify({ ...seatsFor(sold), tiers: TIERS, family }), { headers: HEADERS })
  } catch (e) {
    console.error('seats', (e as Error).message)
    return new Response(JSON.stringify({ error: 'unavailable' }), { status: 503, headers: { ...HEADERS, 'Cache-Control': 'no-store' } })
  }
})
