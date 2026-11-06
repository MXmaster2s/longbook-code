// Ranks & monograms for tiles, chips and wedges standing in for an entity. Colour is a
// key: two entities may never wear one hue, ruling out hashing a name. Rank instead in
// one vault-wide ordering. THE SEAM: core keeps the DECISION, never the PAINT.
import { nameKey } from './names'

/**
 * Ranks for one kind of entity across a whole vault.
 *
 * Build one per loaded dataset and share it. Building scans every entity to establish the
 * ordering, so a palette rebuilt inside a rendered row costs the set once per row.
 */
export interface Palette {
  /**
   * The entity's rank in the vault-wide ordering (0-based), or null for a blank or unranked key —
   * an absence wears no hue, so null is the client's cue to use its neutral, same as a rank past
   * the end of its ramp.
   */
  rank(key: string | null | undefined): number | null
}

/** The three palettes a client draws with, all from one vault. */
export interface Palettes {
  /** Keyed by the category text as it sits on a subscription. */
  categories: Palette
  /** Keyed by `member_id`. */
  members: Palette
  /** Keyed by `account_id`. */
  methods: Palette
}

/** Just enough of a subscription to read the category off it. */
interface HasTag {
  tag: string | null
}

/** Just enough of a member or payment method to place it in the order the vault added it. */
interface HasIdentity {
  id: string
  created_at: string
}

function paletteOf(order: readonly string[], normalise: (key: string) => string): Palette {
  const rank = new Map<string, number>()
  for (const key of order) if (!rank.has(key)) rank.set(key, rank.size)
  return {
    rank: (key) => rank.get(normalise(String(key ?? ''))) ?? null,
  }
}

/**
 * Ranks for every category in a vault, keyed by the category text on a subscription.
 * Categories are free text with no row, so order is alphabetical over the normalised
 * name. Code unit comparison, not `localeCompare`, which would give locales different rings.
 */
export function tagPalette(subs: readonly HasTag[]): Palette {
  const names = [...new Set(subs.map((s) => nameKey(s.tag)))]
    .filter(Boolean)
    .sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
  return paletteOf(names, nameKey)
}

/**
 * Ranks for a set of members or payment methods, keyed by id.
 *
 * Real rows, so ordered by when added, tie-broken by id. Parsed rather than compared as
 * text, since UTC-offset rows sort wrong as strings.
 *
 * Keyed by id, not name, so renaming someone leaves the household's colours alone.
 */
export function entityPalette(rows: readonly HasIdentity[]): Palette {
  const addedAt = (row: HasIdentity) => {
    const t = Date.parse(row.created_at)
    return Number.isNaN(t) ? 0 : t
  }
  const ids = [...rows]
    .sort((a, b) => addedAt(a) - addedAt(b) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
    .map((r) => r.id)
  return paletteOf(ids, (id) => id)
}

/** Every palette a client draws with, from one loaded vault. Build once per load and share it. */
export function vaultPalettes(vault: {
  subs: readonly HasTag[]
  members: readonly HasIdentity[]
  methods: readonly HasIdentity[]
}): Palettes {
  return {
    categories: tagPalette(vault.subs),
    members: entityPalette(vault.members),
    methods: entityPalette(vault.methods),
  }
}

/** First letter, uppercased, for monogram tiles/circles. */
export function monogram(name: string | null | undefined): string {
  return String(name ?? '?').trim().charAt(0).toUpperCase() || '?'
}
