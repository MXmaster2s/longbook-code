// The review account's fixed sign-in code, as test phone numbers work elsewhere: directory and
// App Store reviewers sign in to review@longbook.app with the code in the listing. It answers a
// sign-in token for that one account, and only while its review grant stands.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { REVIEW_GRANT_NOTE, REVIEW_TRIES_KEY, REVIEW_TRIES_PER_HOUR, isOn, isReviewAddress, verdict } from './check.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// Called from the consent page without a session. The boundary is the code, not the origin.
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS, 'content-type': 'application/json' } })

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)

  const body = (await req.json().catch(() => ({}))) as { email?: unknown; code?: unknown }
  const reviewEmail = Deno.env.get('REVIEW_EMAIL')
  const reviewCode = Deno.env.get('REVIEW_CODE')
  if (!isOn(reviewEmail, reviewCode)) return json({ error: 'Review sign-in is switched off.' }, 404)
  if (!isReviewAddress(body.email, reviewEmail!)) return json({ error: 'That code is not right.' }, 401)

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } })
  // Tries are counted with the sign-in emails' own counter, so each one also counts
  // toward their project-wide hourly ceiling.
  const { data: count, error: counted } = await admin.rpc('count_auth_email', {
    address_hash: REVIEW_TRIES_KEY, cap: REVIEW_TRIES_PER_HOUR, project_cap: 1_000_000,
  })
  if (counted) return json({ error: 'Review sign-in is unavailable.' }, 503)
  if (!(count as { allowed?: boolean } | null)?.allowed) return json({ error: 'Too many tries. Wait an hour, then try again.' }, 429)
  if (verdict(body.email, body.code, reviewEmail, reviewCode) !== 'ok') return json({ error: 'That code is not right.' }, 401)

  // A link generated here is never emailed; its hashed token is the one sign-in it allows.
  const { data, error } = await admin.auth.admin.generateLink({ type: 'magiclink', email: String(body.email).trim().toLowerCase() })
  if (error || !data.user || !data.properties?.hashed_token) return json({ error: 'Review sign-in is unavailable.' }, 503)

  const { data: grant } = await admin.from('cloud_grants').select('note').eq('user_id', data.user.id).maybeSingle()
  if (grant?.note !== REVIEW_GRANT_NOTE) return json({ error: 'Review sign-in is switched off.' }, 404)

  return json({ token_hash: data.properties.hashed_token })
})
