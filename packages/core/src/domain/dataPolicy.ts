// Data minimization by design. The memory has no field for a card number, CVV, expiry, PIN,
// or credential — see model.ts. This layer scans free text so a value the schema can't hold
// can't enter through prose. Mirrored in Swift.

export type DataPolicyViolationKind = 'card_number' | 'expiry' | 'cvv' | 'iban' | 'secret'

export interface DataPolicyViolation {
  kind: DataPolicyViolationKind
  /** The exact substring that triggered the refusal, for a UI to point at. */
  match: string
}

export const DATA_POLICY_REFUSAL =
  "longbook is designed not to hold this — if this data ever leaked, you'd want it not to have been here."

const KIND_WORDS: Record<DataPolicyViolationKind, string> = {
  card_number: 'a card number',
  expiry: 'a card expiry date',
  cvv: 'a card security code',
  iban: 'an IBAN',
  secret: 'a password, PIN or key',
}

/** What a refusal adds after DATA_POLICY_REFUSAL: what was found and where, never the value
 * itself, and how to file again, so the AI that wrote it can fix it. Mirrored in Swift. */
export function policyFix(violation: DataPolicyViolation, field?: string): string {
  const where = field ? ` in ${field}` : ''
  return ` Found what looks like ${KIND_WORDS[violation.kind]}${where}. Remove it (a card's last four digits are fine) and file again.`
}

/** Luhn checksum — the same check card issuers use, so a false-positive digit run this long and
 * this well-formed is vanishingly rare (phone numbers, IDs, etc. essentially never pass it). */
function passesLuhn(digits: string): boolean {
  let sum = 0
  let double = false
  for (let i = digits.length - 1; i >= 0; i--) {
    let d = digits.charCodeAt(i) - 48
    if (double) {
      d *= 2
      if (d > 9) d -= 9
    }
    sum += d
    double = !double
  }
  return sum % 10 === 0
}

/** Digit runs of 13–19, allowing space/dash separators as real card numbers are often typed. */
const CARD_LIKE_RUN = /\b(?:\d[ -]?){12,18}\d\b/g

const EXPIRY_KEYWORD = /\b(exp(?:iry|ires)?|valid\s*thru|valid\s*to)\b/i
const EXPIRY_PATTERN = /\b(0[1-9]|1[0-2])\s?\/\s?\d{2}\b/g

const CVV_KEYWORD = /\b(cvv2?|cvc2?|security\s*code|card\s*verification)\b/i
const CVV_NEARBY_DIGITS = /\b\d{3,4}\b/g

/** IBAN shape: 2 letters (country) + 2 check digits + 10–30 alphanumeric. */
const IBAN_LIKE = /\b[A-Z]{2}\d{2}[A-Z0-9]{10,30}\b/g

const SECRET_KEY_VALUE =
  /\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|pin)\s*[:=]\s*\S+/gi

const NEARBY_WINDOW = 40

function withinWindow(text: string, index: number, keyword: RegExp): boolean {
  const start = Math.max(0, index - NEARBY_WINDOW)
  const end = Math.min(text.length, index + NEARBY_WINDOW)
  return keyword.test(text.slice(start, end))
}

/**
 * Scan one string for a data-policy violation. Returns the first hit, or null if the text is
 * clean. Order matters only in that a card number is reported before a coincidental CVV-shaped
 * neighbor — both would refuse the save either way.
 */
export function scanText(text: string): DataPolicyViolation | null {
  if (!text) return null

  for (const m of text.matchAll(CARD_LIKE_RUN)) {
    const digits = m[0].replace(/[ -]/g, '')
    if (digits.length >= 13 && digits.length <= 19 && passesLuhn(digits)) {
      return { kind: 'card_number', match: m[0] }
    }
  }

  for (const m of text.matchAll(IBAN_LIKE)) {
    return { kind: 'iban', match: m[0] }
  }

  const secretMatch = SECRET_KEY_VALUE.exec(text)
  SECRET_KEY_VALUE.lastIndex = 0
  if (secretMatch) return { kind: 'secret', match: secretMatch[0] }

  for (const m of text.matchAll(EXPIRY_PATTERN)) {
    if (withinWindow(text, m.index ?? 0, EXPIRY_KEYWORD)) {
      return { kind: 'expiry', match: m[0] }
    }
  }

  for (const m of text.matchAll(CVV_NEARBY_DIGITS)) {
    if (withinWindow(text, m.index ?? 0, CVV_KEYWORD)) {
      return { kind: 'cvv', match: m[0] }
    }
  }

  return null
}

/**
 * Scan a set of an entity's free-text field values (e.g. `{ name, notes }`) and return every
 * violation found, field by field. A caller refuses the whole save on the first result.
 */
export function scanFields(fields: Record<string, string | null | undefined>): DataPolicyViolation[] {
  const out: DataPolicyViolation[] = []
  for (const value of Object.values(fields)) {
    if (!value) continue
    const hit = scanText(value)
    if (hit) out.push(hit)
  }
  return out
}

/**
 * A whole number as its digits, so a digit-run scan has a run to see. Past 1e21 JavaScript
 * prints "1e+21", and Swift switches sooner; neither form shows a card number. Mirrors
 * numberWord in swift-core's VaultWriter.
 */
export function numberWord(value: number): string {
  if (!Number.isFinite(value)) return ''
  return Number.isInteger(value) && Math.abs(value) < 9e18 ? BigInt(value).toString() : String(value)
}

/**
 * One stored value as the words the scan should see: a string as itself, a list flattened, a
 * number as its digits, a boolean as yes/no. Anything else renders to nothing. Mirrors
 * scannableWords in swift-core's VaultWriter, so both doors refuse one input.
 */
export function scannableWords(value: unknown): string[] {
  if (typeof value === 'string') return [value]
  if (Array.isArray(value)) return value.flatMap(scannableWords)
  if (typeof value === 'number') return [numberWord(value)]
  if (typeof value === 'boolean') return [value ? 'yes' : 'no']
  return []
}
