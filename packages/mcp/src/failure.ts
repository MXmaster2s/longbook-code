// One error vocabulary for both doors. An unattended agent has nobody to read a sentence
// for it, so every refusal carries a code it can act on: retry, stop, or escalate.
export const FAILURE_CODES = [
  'rate_limited',
  'unauthorized',
  'key_revoked',
  'key_expired',
  'insufficient_scope',
  'entitlement_required',
  'validation_failed',
  'not_found',
  'conflict',
  'payload_too_large',
  'queue_full',
  'upstream_error',
] as const
export type FailureCode = (typeof FAILURE_CODES)[number]

/** retry: try again later. stop: this will not work until a person acts. */
export const FAILURE_ADVICE: Record<FailureCode, 'retry' | 'stop'> = {
  rate_limited: 'retry',
  unauthorized: 'stop',
  key_revoked: 'stop',
  key_expired: 'stop',
  insufficient_scope: 'stop',
  entitlement_required: 'stop',
  validation_failed: 'stop',
  not_found: 'stop',
  conflict: 'retry',
  payload_too_large: 'stop',
  queue_full: 'stop',
  upstream_error: 'retry',
}

export interface Failure {
  code: FailureCode
  message: string
  advice: 'retry' | 'stop'
  retry_after?: number
  [key: string]: unknown
}

export function failure(code: FailureCode, message: string, extra: Record<string, unknown> = {}): Failure {
  return { code, message, advice: FAILURE_ADVICE[code], ...extra }
}

/** The body an HTTP refusal carries, so a 401 or 429 says the same words as a tool error. */
export const failureBody = (code: FailureCode, message: string, extra: Record<string, unknown> = {}) =>
  JSON.stringify({ error: failure(code, message, extra) })
