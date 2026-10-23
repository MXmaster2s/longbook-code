// The real store behind the dispatcher: the outbox and the accounts behind it. It takes the
// database client as an argument, so a test can stand in for it. A notice that is sent or skipped
// keeps nothing it recorded about an IP address or a device.
import type { Store, Waiting } from './dispatch.ts'

/** The part of the Supabase client this uses. */
export interface Client {
  // deno-lint-ignore no-explicit-any
  from(table: string): any
  rpc(name: string, args: Record<string, unknown>): PromiseLike<{ data: unknown; error: { message: string } | null }>
  auth: {
    admin: {
      getUserById(id: string): PromiseLike<{
        data: { user: { email?: string | null } | null }
        error: { status?: number; message: string } | null
      }>
    }
  }
}

export function storeOf(client: Client): Store {
  const mark = async (id: string, patch: Record<string, unknown>): Promise<void> => {
    const { error } = await client.from('account_notices').update(patch).eq('id', id)
    if (error) throw new Error(`could not update a notice: ${error.message}`)
  }
  return {
    async claim(limit) {
      const { data, error } = await client.rpc('claim_account_notices', { max_rows: limit })
      if (error) throw new Error(`could not claim notices: ${error.message}`)
      return (data ?? []) as Waiting[]
    },
    async addressOf(userId) {
      const { data, error } = await client.auth.admin.getUserById(userId)
      if (error) {
        if (error.status === 404) return null
        throw new Error(`could not look up an account: ${error.message}`)
      }
      return data.user?.email ?? null
    },
    async sentSince(userId, kind, since) {
      const { count, error } = await client
        .from('account_notices')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', userId)
        .eq('kind', kind)
        .gte('sent_at', since.toISOString())
      if (error) throw new Error(`could not count notices: ${error.message}`)
      return count ?? 0
    },
    sent: (id) => mark(id, { sent_at: new Date().toISOString(), details: {} }),
    skip: (id, reason) => mark(id, { skipped_reason: reason, details: {} }),
    // Claimed now, so the wait before another try runs from this moment.
    release: (id) => mark(id, { claimed_at: new Date().toISOString() }),
  }
}
