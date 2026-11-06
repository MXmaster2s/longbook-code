// Sign in with Apple's server-to-server endpoint, set on the App ID in the Developer portal.
// Once Apple's JWT is verified: Hide My Email changes are recorded, withdrawn consent ends
// the account's sessions, and a deleted Apple Account deletes the longbook account.
import { createClient } from 'npm:@supabase/supabase-js@2'
import {
  APPLE_KEYS_URL,
  handleAppleEvent,
  payloadOf,
  verifyAppleNotice,
  type AccountStore,
  type AppleKey,
} from '../_shared/apple-account-events.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// Apple's key set, kept an hour; a token naming a key not in it asks again once.
let cached: { keys: AppleKey[]; at: number } | null = null
async function appleKeys(fresh: boolean): Promise<AppleKey[]> {
  if (!fresh && cached && Date.now() - cached.at < 3_600_000) return cached.keys
  const res = await fetch(APPLE_KEYS_URL)
  if (!res.ok) throw new Error(`Apple's keys answered ${res.status}`)
  const keys = ((await res.json()) as { keys?: AppleKey[] }).keys ?? []
  cached = { keys, at: Date.now() }
  return keys
}

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

const store: AccountStore = {
  async userForSub(sub) {
    const { data, error } = await admin.rpc('apple_account_user', { p_sub: sub })
    if (error) throw new Error(`lookup: ${error.message}`)
    return typeof data === 'string' ? data : null
  },
  async setRelayOff(userId, offAt) {
    const { error } = await admin.from('profiles').update({ apple_relay_off_at: offAt }).eq('id', userId)
    if (error) throw new Error(`relay: ${error.message}`)
  },
  async endSessions(userId) {
    const { error } = await admin.rpc('end_account_sessions', { p_user: userId })
    if (error) throw new Error(`sessions: ${error.message}`)
  },
  async deleteAccount(userId) {
    // delete-account makes this same call: every table keyed to a user cascades from auth.users.
    const { error } = await admin.auth.admin.deleteUser(userId)
    if (error) throw new Error(`delete: ${error.message}`)
  },
}

const text = (body: string, status: number) => new Response(body, { status, headers: { 'Content-Type': 'text/plain' } })

Deno.serve(async (req) => {
  if (req.method !== 'POST') return text('method not allowed', 405)
  const token = payloadOf(await req.text(), req.headers.get('content-type'))
  if (!token) return text('payload required', 400)
  let event
  try {
    event = await verifyAppleNotice(token, { keys: appleKeys, now: new Date() })
  } catch (e) {
    return text(`unverified: ${(e as Error).message}`, 400)
  }
  try {
    const done = await handleAppleEvent(event, store, new Date())
    // The Apple user id is not logged: it names a person to Apple.
    console.log('apple account event', event.type, done.action, done.matched ? 'matched' : 'no account')
    return new Response(JSON.stringify({ ok: true, ...done }), { status: 200, headers: { 'Content-Type': 'application/json' } })
  } catch (e) {
    console.error('apple account event failed', event.type, (e as Error).message)
    return text('could not record', 500)
  }
})
