// Lists the caller's active sessions for the sign-out screen. The user id and the current
// session both come from the verified token, never the request, so this can only describe the
// caller's own sessions. It reads; it changes nothing.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { describeAll, isConnectorToken, sessionIdOf, totalOf, type SessionRow } from './describe.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// Called from the app with Authorization, so the preflight applies. Origin is open: the
// boundary is the JWT below, not which caller is asking.
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS, 'content-type': 'application/json' } })

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)

  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer /, '')
  if (!jwt) return json({ error: 'Sign in first.' }, 401)

  // A token an AI connector holds names its client. The device list is the account holder's.
  if (isConnectorToken(jwt)) return json({ error: 'Only the app can list sessions.' }, 403)

  const asCaller = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  const { data: { user }, error } = await asCaller.auth.getUser(jwt)
  if (error || !user) return json({ error: 'That session is no longer valid.' }, 401)

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const { data, error: failure } = await admin.rpc('my_sessions', { p_user: user.id })
  if (failure) return json({ error: 'Your sessions could not be read. Try again shortly.' }, 500)

  const rows = (data ?? []) as SessionRow[]
  return json({ sessions: describeAll(rows, sessionIdOf(jwt)), total: totalOf(rows) })
})
