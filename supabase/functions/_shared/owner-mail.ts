// A plain-text note to longbook's own inbox, for things a person has to act on. Never fails the
// caller: without a key, or when Resend refuses, the subject is logged instead.
import { MAIL_FROM } from './confirm-purchase.ts'

export const OWNER_INBOX = 'contact@longbook.app'

export async function notifyOwner(
  apiKey: string | undefined,
  subject: string,
  text: string,
  send: typeof fetch = fetch,
): Promise<void> {
  if (!apiKey) return console.error('owner mail', subject, '(no mail key)')
  const res = await send('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: MAIL_FROM, to: [OWNER_INBOX], subject, text }),
  }).catch(() => null)
  if (!res?.ok) console.error('owner mail', res?.status ?? 'unreachable')
}
