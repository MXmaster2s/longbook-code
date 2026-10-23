// Answers Supabase Auth's Send Email hook: checks the signature, caps how many codes one address
// gets in an hour, renders the email and sends it through Resend. The clock, the counter and the
// sender arrive as arguments, so a test can stand in for each.
import { otherSpec, signInSpec, signUpSpec } from '../_shared/auth-emails.ts'
import { render, renderText } from '../_shared/email-shell.ts'

/** Codes one address is sent in an hour, across every device and browser. */
export const HOURLY_CAP = 5
/** Codes every address together is sent in an hour: a flood of made-up addresses stops here. */
export const PROJECT_HOURLY_CAP = 100
export const MAIL_FROM = 'longbook <contact@longbook.app>'
export const MAIL_REPLY_TO = 'contact@longbook.app'
/** Auth waits five seconds for an answer and then asks again, so Resend gets less than that. */
export const SEND_MS = 3500
/** How far a request's timestamp may sit from now before the signature is refused. */
const TOLERANCE_S = 300

export interface Payload {
  user?: { email?: unknown }
  email_data?: { token?: unknown; token_hash?: unknown; redirect_to?: unknown; email_action_type?: unknown }
}

export interface Count {
  allowed: boolean
  retryAfterSeconds: number
  /** Which cap stopped it: this address's own, or every address together. */
  reason?: 'address' | 'project'
}

export interface Deps {
  apiKey: string | undefined
  /** The project's own address, which the verify link in a sign-up email starts with. */
  verifyBase: string
  count: (addressHash: string) => Promise<Count>
  send: typeof fetch
  log: (line: string) => void
  now: () => Date
}

/** What goes back to Auth: 200 with an empty body means sent; 200 with an error is passed to the person. */
export interface Answer {
  status: number
  body: Record<string, unknown>
}

export interface Mail {
  to: string
  subject: string
  html: string
  text: string
}

const text = (value: unknown, max: number): string =>
  typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, max) : ''

const bytesOf = (b64: string): Uint8Array => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))
const b64Of = (bytes: ArrayBuffer): string => btoa(String.fromCharCode(...new Uint8Array(bytes)))

/** Equal or not, in time that does not depend on where they first differ. */
function sameString(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

/**
 * The Standard Webhooks check Auth signs with: HMAC-SHA256 over "id.timestamp.body", within five
 * minutes. Auth may hold several secrets separated by "|" while one is being replaced; any of them
 * passes.
 */
export async function verifySignature(headers: Headers, body: string, secret: string, now: Date): Promise<boolean> {
  const id = headers.get('webhook-id')
  const timestamp = headers.get('webhook-timestamp')
  const given = headers.get('webhook-signature')
  if (!id || !timestamp || !given || !/^\d{1,12}$/.test(timestamp)) return false
  if (Math.abs(now.getTime() / 1000 - Number(timestamp)) > TOLERANCE_S) return false
  const signed = new TextEncoder().encode(`${id}.${timestamp}.${body}`)
  const offered = given.split(/\s+/).map((part) => part.split(',')).filter(([v, s]) => v === 'v1' && s !== undefined).map(([, s]) => s!)
  for (const one of secret.split('|')) {
    const raw = one.trim().replace(/^v1,/, '').replace(/^whsec_/, '')
    let key: CryptoKey
    try {
      key = await crypto.subtle.importKey('raw', bytesOf(raw), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
    } catch {
      continue
    }
    const expected = b64Of(await crypto.subtle.sign('HMAC', key, signed))
    if (offered.some((s) => sameString(s, expected))) return true
  }
  return false
}

/** The address as the counter knows it: one hash, the same for any spelling of the case. */
export async function addressHash(email: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(email.trim().toLowerCase()))
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

const minutesOf = (seconds: number): string => {
  const minutes = Math.max(1, Math.ceil(seconds / 60))
  return `~${minutes} minute${minutes === 1 ? '' : 's'}`
}

export const limitMessage = (retryAfterSeconds: number): string =>
  `You have exceeded your hourly sign-in limit. Please try again in ${minutesOf(retryAfterSeconds)}.`

export const projectMessage = (retryAfterSeconds: number): string =>
  `longbook is sending too many sign-in emails right now. Please try again in ${minutesOf(retryAfterSeconds)}.`

const looksLikeAddress = (s: string): boolean => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s) && s.length <= 254

/** The email for one request, or the sentence Auth should pass back instead. */
export function mailFor(payload: Payload, verifyBase: string): { mail: Mail } | { refusal: string } {
  const to = text(payload.user?.email, 254)
  if (!looksLikeAddress(to)) return { refusal: 'No email address to send a code to.' }
  const data = payload.email_data ?? {}
  const kind = text(data.email_action_type, 40)
  const code = text(data.token, 12)
  const tokenHash = text(data.token_hash, 200)
  const redirectTo = text(data.redirect_to, 500)
  const link = tokenHash && redirectTo
    ? `${verifyBase}/auth/v1/verify?token=${encodeURIComponent(tokenHash)}&type=${encodeURIComponent(kind)}&redirect_to=${encodeURIComponent(redirectTo)}`
    : null
  if (kind === 'email_change') return { refusal: 'longbook does not change the email address of an account.' }
  if ((kind === 'signup' || kind === 'magiclink') && !code) return { refusal: 'No code came with this request.' }
  const spec = kind === 'signup' ? signUpSpec(code, link) : kind === 'magiclink' ? signInSpec(code) : otherSpec(code || null)
  return { mail: { to, subject: spec.subject, html: render(spec), text: renderText(spec) } }
}

const passBack = (httpCode: number, message: string): Answer => ({ status: 200, body: { error: { http_code: httpCode, message } } })

export async function handle(req: { headers: Headers; body: string }, secret: string | undefined, deps: Deps): Promise<Answer> {
  const { apiKey, verifyBase, count, send, log, now } = deps
  if (!secret || !apiKey) {
    log('auth email: the hook secret or the mail key is missing, so nothing was sent')
    return { status: 500, body: { error: 'not configured' } }
  }
  if (!(await verifySignature(req.headers, req.body, secret, now()))) return { status: 401, body: { error: 'unauthorized' } }
  let payload: Payload
  try {
    payload = JSON.parse(req.body) as Payload
  } catch {
    return { status: 400, body: { error: 'not json' } }
  }
  const made = mailFor(payload && typeof payload === 'object' ? payload : {}, verifyBase)
  if ('refusal' in made) return passBack(400, made.refusal)
  const kind = text(payload.email_data?.email_action_type, 40) || 'unknown'
  try {
    const tally = await count(await addressHash(made.mail.to))
    if (!tally.allowed && tally.reason === 'project') {
      log(`auth email ${kind}: the hourly ceiling for every address together was reached`)
      return passBack(429, projectMessage(tally.retryAfterSeconds))
    }
    if (!tally.allowed) return passBack(429, limitMessage(tally.retryAfterSeconds))
  } catch (e) {
    // A counter that cannot answer must not lock everyone out; the code still goes.
    log(`auth email ${kind}: the counter failed (${(e as Error).message}); sent without it`)
  }
  let res: Response
  try {
    res = await send('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: MAIL_FROM, to: [made.mail.to], reply_to: MAIL_REPLY_TO, subject: made.mail.subject, html: made.mail.html, text: made.mail.text }),
      signal: AbortSignal.timeout(SEND_MS),
    })
  } catch (e) {
    log(`auth email ${kind}: Resend did not answer (${(e as Error).name})`)
    return passBack(500, 'The email could not be sent. Please try again in a minute.')
  }
  if (!res.ok) {
    log(`auth email ${kind}: Resend answered ${res.status}`)
    await res.body?.cancel().catch(() => {})
    return passBack(500, 'The email could not be sent. Please try again in a minute.')
  }
  await res.body?.cancel().catch(() => {})
  return { status: 200, body: {} }
}
