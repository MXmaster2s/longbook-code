// Supabase Auth hands every sign-in email to this function instead of sending it itself. Each
// request is signed with a secret only Auth and this function hold. The answer is the email
// sent, or a sentence Auth passes back to the person.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { handle, HOURLY_CAP, PROJECT_HOURLY_CAP, type Count } from './hook.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const HOOK_SECRET = Deno.env.get('AUTH_EMAIL_HOOK_SECRET')
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')

const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

const json = (data: unknown, status: number) =>
  new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } })

/** One address's codes this hour, counted and recorded in the database in a single step. */
async function count(addressHash: string): Promise<Count> {
  const { data, error } = await service.rpc('count_auth_email', { address_hash: addressHash, cap: HOURLY_CAP, project_cap: PROJECT_HOURLY_CAP })
  if (error) throw new Error(error.message)
  const tally = (data ?? {}) as { allowed?: unknown; retry_after_seconds?: unknown; reason?: unknown }
  return {
    allowed: tally.allowed !== false,
    retryAfterSeconds: Number(tally.retry_after_seconds ?? 0) || 0,
    reason: tally.reason === 'project' ? 'project' : 'address',
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405)
  const body = await req.text()
  const answer = await handle({ headers: req.headers, body }, HOOK_SECRET, {
    apiKey: RESEND_API_KEY,
    verifyBase: SUPABASE_URL,
    count,
    send: fetch,
    log: console.error,
    now: () => new Date(),
  })
  return json(answer.body, answer.status)
})
