// What a viewer may leave on a shared report, and how often. Comments go only to the owner. The
// caps are per link, so no one link floods its owner; viewers hold no account and no address
// is kept, so there is nothing per person to count.

export const COMMENT_LIMITS = {
  body: 2000,
  author: 80,
  moduleId: 80,
  /** Comments on one link within the window below. */
  perWindow: 20,
  windowMinutes: 60,
  /** Comments one link can ever hold. */
  perShare: 200,
} as const

export interface CommentInput {
  moduleId: string
  body: string
  author: string
}

/** Reads a viewer's comment from the request body, or says what is wrong with it. */
export function readComment(body: Record<string, unknown>): { comment: CommentInput } | { refusal: string } {
  const moduleId = typeof body.module_id === 'string' ? body.module_id : ''
  const text = typeof body.body === 'string' ? body.body : ''
  const author = typeof body.author === 'string' ? body.author : ''
  if (!moduleId || moduleId.length > COMMENT_LIMITS.moduleId) return { refusal: 'module_id required' }
  if (!text.trim() || text.length > COMMENT_LIMITS.body) return { refusal: `body must be 1 to ${COMMENT_LIMITS.body} characters` }
  if (author.length > COMMENT_LIMITS.author) return { refusal: `author must be ${COMMENT_LIMITS.author} characters or fewer` }
  return { comment: { moduleId, body: text, author } }
}

/** The start of the rate window, as an ISO instant. */
export function windowStart(now: Date): string {
  return new Date(now.getTime() - COMMENT_LIMITS.windowMinutes * 60 * 1000).toISOString()
}

/** Null when one more comment fits; otherwise the reason it does not. */
export function rateRefusal(recent: number, total: number): string | null {
  if (total >= COMMENT_LIMITS.perShare) return 'this report has taken all the comments it can'
  if (recent >= COMMENT_LIMITS.perWindow) return 'too many comments on this report for now; try again later'
  return null
}

/** A comment's id as the table makes it, so a malformed one is refused before the database. */
export function isCommentId(value: unknown): value is string {
  return typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
}
