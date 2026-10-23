// Emails a person about their own account. A database job calls this once a minute while notices
// wait, with a key only the database and this function hold. It is never called from an app or a
// browser.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { dispatch } from './dispatch.ts'
import { storeOf, type Client } from './store.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const NOTICE_KEY = Deno.env.get('NOTICE_KEY')
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } })

const sha256 = async (s: string): Promise<string> =>
  Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s))))
    .map((b) => b.toString(16).padStart(2, '0')).join('')

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405)
  const given = req.headers.get('x-notice-key') ?? ''
  if (!NOTICE_KEY || (await sha256(given)) !== (await sha256(NOTICE_KEY))) return json({ error: 'unauthorized' }, 401)
  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const outcome = await dispatch({ apiKey: RESEND_API_KEY, store: storeOf(service as unknown as Client), send: fetch, log: console.error, now: () => new Date() })
  return json(outcome)
})
