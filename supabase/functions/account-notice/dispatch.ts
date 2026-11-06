// Sends the waiting notices. The database and mail API arrive as arguments, so a test can replace
// both. A notice is claimed before it is sent; a failed send waits and tries again. Nothing here
// throws or logs a person.
import { isKind, renderNotice } from './notice-emails.ts'

export const MAIL_FROM = 'longbook <contact@longbook.app>'
export const MAIL_REPLY_TO = 'contact@longbook.app'
/** Most of one kind a person is sent in an hour; the rest are recorded and not sent. */
export const HOURLY_LIMIT = 3
export const BATCH = 20
/** A run starts no new notice after this long; the rest wait their turn. */
export const RUN_SECONDS = 20

export interface Waiting {
  id: string
  user_id: string
  kind: string
  details: Record<string, unknown> | null
  created_at: string
}

export interface Store {
  /** Takes up to `limit` waiting notices for this run and returns them. */
  claim(limit: number): Promise<Waiting[]>
  /** The account's address, or null when the account or its address is gone. Throws when unsure. */
  addressOf(userId: string): Promise<string | null>
  sentSince(userId: string, kind: string, since: Date): Promise<number>
  /** Marks it sent and drops what it recorded about the device. */
  sent(id: string): Promise<void>
  /** Marks it not to be sent, with why, and drops what it recorded. */
  skip(id: string, reason: string): Promise<void>
  /** Gives it back to wait its turn, longer after each try. */
  release(id: string): Promise<void>
}

export interface Deps {
  apiKey: string | undefined
  store: Store
  send: typeof fetch
  log: (line: string) => void
  now: () => Date
}

export interface Outcome {
  claimed: number
  sent: number
  skipped: number
  retry: number
}

export async function dispatch(deps: Deps): Promise<Outcome> {
  const { apiKey, store, send, log, now } = deps
  const outcome: Outcome = { claimed: 0, sent: 0, skipped: 0, retry: 0 }
  if (!apiKey) {
    log('account notices: no mail key, so nothing was claimed')
    return outcome
  }
  let waiting: Waiting[]
  try {
    waiting = await store.claim(BATCH)
  } catch (e) {
    log(`account notices: ${(e as Error).message}`)
    return outcome
  }
  outcome.claimed = waiting.length
  const stopAt = now().getTime() + RUN_SECONDS * 1000

  for (const notice of waiting) {
    try {
      if (now().getTime() > stopAt) {
        await release(store, notice.id, log)
        outcome.retry++
        continue
      }
      if (!isKind(notice.kind)) {
        await store.skip(notice.id, 'unknown_kind')
        outcome.skipped++
        continue
      }
      const email = await store.addressOf(notice.user_id)
      if (!email) {
        await store.skip(notice.id, 'no_address')
        outcome.skipped++
        continue
      }
      const hourAgo = new Date(now().getTime() - 3600 * 1000)
      if ((await store.sentSince(notice.user_id, notice.kind, hourAgo)) >= HOURLY_LIMIT) {
        await store.skip(notice.id, 'throttled')
        outcome.skipped++
        continue
      }
      const mail = renderNotice(notice.kind, notice.details, notice.created_at)
      if (!mail) {
        await store.skip(notice.id, 'unreadable')
        outcome.skipped++
        continue
      }
      const res = await send('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
          // The same notice sent twice within a day is delivered once.
          'Idempotency-Key': `notice-${notice.id}`,
        },
        body: JSON.stringify({ from: MAIL_FROM, to: [email], reply_to: MAIL_REPLY_TO, subject: mail.subject, html: mail.html, text: mail.text }),
        signal: AbortSignal.timeout(8000),
      })
      if (res.ok) {
        await res.body?.cancel().catch(() => {})
        await store.sent(notice.id)
        outcome.sent++
      } else if (res.status === 400 || res.status === 422) {
        // Resend refused this notice itself, an address it cannot use; trying again cannot help.
        log(`account notice ${notice.kind}: Resend refused it (${res.status}${await errorName(res)})`)
        await store.skip(notice.id, 'rejected')
        outcome.skipped++
      } else {
        log(`account notice ${notice.kind}: Resend answered ${res.status}${await errorName(res)}`)
        await release(store, notice.id, log)
        outcome.retry++
      }
    } catch (e) {
      await release(store, notice.id, log)
      outcome.retry++
      log(`account notice ${notice.kind}: ${(e as Error).message}`)
    }
  }
  return outcome
}

/** Resend's own error code, such as "validation_error"; it names nothing about a person. */
async function errorName(res: Response): Promise<string> {
  try {
    const name = ((await res.json()) as { name?: unknown }).name
    return typeof name === 'string' && /^[a-z_]{1,40}$/.test(name) ? `, ${name}` : ''
  } catch {
    return ''
  }
}

async function release(store: Store, id: string, log: (line: string) => void): Promise<void> {
  try {
    await store.release(id)
  } catch {
    // It stays claimed and is offered again after its wait.
    log('account notices: could not give a notice back')
  }
}
