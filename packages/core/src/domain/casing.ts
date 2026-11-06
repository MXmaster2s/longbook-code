// The casing register, readable instead of re-derived from a doc. Since 2026-08-18
// longbook writes standard professional sentence case everywhere it speaks; only the
// brand spellings below are special.
//
// Nothing here is callable: authored into a string as typed, never applied afterward —
// a runtime transform would flatten currency codes.

/**
 * The rule, stated in the register it describes, plus the two most commonly
 * misspelled brand casings we ship.
 *
 * A spec, not copy: clients import it to know the rule and render the brand name.
 */
export const BRAND_CASING = {
  /** The whole of it. */
  rule:
    'longbook writes standard sentence case: sentences start with a capital and read plainly. ' +
    'the brand name is the one exception — lowercase in every surface that speaks, including ' +
    'sentence-initial. proper nouns and acronyms keep their caps. user data is never ' +
    'transformed — casing is authored into our strings, never applied to theirs.',
  /** The product. Lowercase in every surface that speaks, including sentence-initial. */
  brand: 'longbook',
  /** The paid tier. Two lowercase words, never "Longbook Cloud" and never "longbook Cloud". */
  brandCloud: 'longbook cloud',
} as const

/**
 * Proper nouns and acronyms whose spellings copy has gotten wrong before — kept as a
 * reference for writers, no checker reads it anymore.
 *
 * **ILLUSTRATIVE, not exhaustive: absence here is never permission to respell.**
 */
export const CASING_WHITELIST = [
  'iPhone',
  'Mac',
  'Android',
  'Windows',
  'Linux',
  'AppleCare',
  'AmEx',
  'Netflix',
  'iCloud',
  'Obsidian',
  'EMI',
  'GST',
  'SIP',
  'OTT',
  'CFO',
  'AI',
  'Claude Code',
  'Finder',
  'GitHub',
  'Polar',
  'DM',
  'X',
] as const

export type CasingWhitelistEntry = (typeof CASING_WHITELIST)[number]

// Applies wherever longbook speaks: UI strings, aria-labels, `title`, `alt`, FAQ,
// landing page, store listings. NOT user data, `Intl` output, or code identifiers.
// Until 2026-08-18 this register barred a capital after a full stop; that voice read
// as informal on real pages and was retired, tripwire and all.
