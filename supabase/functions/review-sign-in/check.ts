// Whether a sign-in may use the review account's fixed code: the address and the code must both
// match the secrets, compared in constant time. Either secret unset means the door is shut.

export const REVIEW_GRANT_NOTE = 'Claude directory review account'
/** Tries per hour at the review address: an 8-digit code then takes centuries to guess. */
export const REVIEW_TRIES_PER_HOUR = 10
export const REVIEW_TRIES_KEY = 'review-sign-in'

export type Verdict = 'off' | 'refused' | 'ok'

const bytes = (s: string): Uint8Array => new TextEncoder().encode(s)

/** Equal strings, without leaking how much of them matched through the time taken. */
export function sameText(a: string, b: string): boolean {
  const x = bytes(a)
  const y = bytes(b)
  let diff = x.length ^ y.length
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0)
  return diff === 0
}

export const isOn = (reviewEmail: string | undefined, reviewCode: string | undefined): boolean =>
  !!reviewEmail && !!reviewCode && reviewCode.length >= 8

export const isReviewAddress = (email: unknown, reviewEmail: string): boolean =>
  typeof email === 'string' && sameText(email.trim().toLowerCase(), reviewEmail.trim().toLowerCase())

export function verdict(email: unknown, code: unknown, reviewEmail: string | undefined, reviewCode: string | undefined): Verdict {
  if (!isOn(reviewEmail, reviewCode)) return 'off'
  if (typeof code !== 'string' || !isReviewAddress(email, reviewEmail!)) return 'refused'
  return sameText(code.replace(/\s+/g, ''), reviewCode!) ? 'ok' : 'refused'
}
