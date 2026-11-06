// Sends the one confirmation a purchase earns. The database mark and the mail API arrive as
// arguments, so a test can stand in for both and the function passes the real ones. Nothing
// here may fail the purchase, and nothing it logs names the buyer or holds the key.
import { renderPurchaseEmail, type PurchaseEmailInput } from './purchase-email.ts'

export const MAIL_FROM = 'longbook <contact@longbook.app>'
export const MAIL_REPLY_TO = 'contact@longbook.app'

/** The mark on the entitlement row that says a confirmation went out. */
export interface SentMark {
  /** True only if this call took the mark; false when it was already taken. */
  claim(userId: string): Promise<boolean>
  release(userId: string): Promise<void>
}

interface MarkClient {
  from(table: string): any
}

/** The mark as the entitlements row holds it: purchase_email_sent_at, taken only on an active
 *  licence whose mark is empty. */
export function entitlementSentMark(service: MarkClient): SentMark {
  return {
    async claim(userId) {
      const { data, error } = await service
        .from('entitlements')
        .update({ purchase_email_sent_at: new Date().toISOString() })
        .eq('user_id', userId)
        .eq('status', 'active')
        .is('purchase_email_sent_at', null)
        .select('user_id')
      if (error) throw new Error(`could not claim the send: ${error.message}`)
      return !!data?.length
    },
    async release(userId) {
      const { error } = await service.from('entitlements').update({ purchase_email_sent_at: null }).eq('user_id', userId)
      if (error) throw new Error(error.message)
    },
  }
}

export interface ConfirmDeps {
  apiKey: string | undefined
  mark: SentMark
  send: typeof fetch
  log: (line: string) => void
}

export interface Purchase extends PurchaseEmailInput {
  userId: string
  transactionId: string
}

/**
 * The mark is claimed before the send, so a restore or a repeat delivery finds it taken. A send
 * that fails gives the mark back, so a later restore tries again; a claim this call did not make
 * is never given back.
 */
export async function confirmPurchase(deps: ConfirmDeps, purchase: Purchase): Promise<void> {
  const { apiKey, mark, send, log } = deps
  const { userId, transactionId, ...buyer } = purchase
  if (!apiKey || !buyer.email) return
  let claimed = false
  const release = async () => {
    try {
      await mark.release(userId)
    } catch {
      // A mark left taken means no retry; a missed email still beats a failed purchase.
      log('purchase email: could not give the mark back')
    }
  }
  try {
    claimed = await mark.claim(userId)
    if (!claimed) return
    const mail = renderPurchaseEmail(buyer)
    const res = await send('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        // The same purchase sent twice within a day is delivered once.
        'Idempotency-Key': `purchase-${transactionId}`,
      },
      body: JSON.stringify({
        from: MAIL_FROM,
        to: [buyer.email],
        reply_to: MAIL_REPLY_TO,
        subject: mail.subject,
        html: mail.html,
        text: mail.text,
      }),
      signal: AbortSignal.timeout(5000),
    })
    if (!res.ok) {
      await release()
      log(`purchase email: Resend answered ${res.status}`)
    }
  } catch (e) {
    if (claimed) await release()
    log(`purchase email: ${(e as Error).message}`)
  }
}
