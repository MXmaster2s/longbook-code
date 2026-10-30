// The other side of a statement line: the account or person a transfer, a card bill or a
// payment goes to or comes from. The shape the reader answers in, and the tidy every
// answer passes through, so no full number ever leaves the server.
import { statementRuleText } from './statement-rules.ts'

/** Each charge's counterpart fields: required, so a reader that cannot tell answers null. */
export const COUNTERPART_PROPERTIES = {
  counterpart: {
    type: ['string', 'null'],
    description: 'The other account or person this line moves money to or from, only when the line prints it; account numbers to the last four digits at most; else null',
  },
  // anyOf, not a nullable enum: Anthropic refuses an enum whose null doesn't match its type.
  counterpart_kind: {
    anyOf: [{ type: 'string', enum: ['account', 'person'] }, { type: 'null' }],
    description: 'account for a bank account, card or wallet; person for a person; null when counterpart is null',
  },
  counterpart_bank: {
    type: ['string', 'null'],
    description: 'The bank account printed beside a person on the other side, or the owner\'s own other account on a payment to it or a card bill payment: bank, kind, last four digits after "••" ("Axis savings ••1234"); else null',
  },
} as const

export const COUNTERPART_REQUIRED = ['counterpart', 'counterpart_kind', 'counterpart_bank'] as const

/** What the charges prompt says about the other side: the rules, then which field holds what. */
export const COUNTERPART_INSTRUCTIONS =
  statementRuleText('counterparts') +
  ' counterpart holds the other side ("HDFC savings ••4417", "Ramesh K"), counterpart_kind "account" or "person", both null when the line prints none. counterpart_bank holds the bank account printed beside a person, or the owner\'s own other account on a payment to it or a card bill payment; else null.'

const MAX_COUNTERPART_CHARS = 60

/** A mask in front of digits, like the "XX" of "XX4417" or "xxxx-xxxx-" of a card. */
const MASK = /(?<![\p{L}\d])(?:[xX*•·]+[\s-]*)+(?=\d)/gu
/** A run of digits, spaced or dashed, maybe after a mask's mark. */
const DIGITS = /\u0000?\d(?:[\d\s-]*\d)?/g

/** One counterpart as the server hands it on: trimmed, short, numbers cut to the last four
 *  after "••", a handle or address dropped. Null when nothing readable is left. */
export function tidyCounterpart(value: unknown): string | null {
  if (typeof value !== 'string') return null
  let text = value.replace(/\s+/g, ' ').trim()
  // A UPI id or an email address names nobody the owner would say; the words around it stay.
  text = text.replace(/\S+@\S+/g, ' ')
  text = text.replace(MASK, '\u0000').replace(DIGITS, (run) => {
    const digits = run.replace(/\D/g, '')
    if (digits.length >= 4) return ` ••${digits.slice(-4)} `
    return run.startsWith('\u0000') ? ' ' : run
  }).replace(/\u0000/g, ' ')
  text = text.replace(/\s+/g, ' ').replace(/(?:••\s*)+(?=••)/g, '').trim()
  if (!/\p{L}|••\d{4}/u.test(text)) return null
  return text.length > MAX_COUNTERPART_CHARS ? text.slice(0, MAX_COUNTERPART_CHARS).trim() : text
}

/** Every charge's counterpart and bank tidied, the kind kept only beside a counterpart. */
export function tidyCounterparts(result: Record<string, unknown>): Record<string, unknown> {
  const charges = Array.isArray(result.charges) ? result.charges : null
  if (!charges) return result
  return {
    ...result,
    charges: charges.map((charge) => {
      if (!charge || typeof charge !== 'object') return charge
      const row = charge as Record<string, unknown>
      const counterpart = tidyCounterpart(row.counterpart)
      const kind = counterpart && (row.counterpart_kind === 'account' || row.counterpart_kind === 'person') ? row.counterpart_kind : null
      return { ...row, counterpart: kind ? counterpart : null, counterpart_kind: kind, counterpart_bank: tidyCounterpart(row.counterpart_bank) }
    }),
  }
}
