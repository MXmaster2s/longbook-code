// The seeded tag library — one source for the contract generator, the Swift bundle
// (via the generated library.json), and the MCP server's tag registration. A tag is a name
// and an icon, and carries no template: a commitment's or an account's specifics are the
// lines of its notes.
export type LibraryTag = { kind: string; name: string; icon: string }

export const LIBRARY_TAGS: LibraryTag[] = [
  // -- commitments -------------------------------------------------------------------------
  { kind: 'commitment', name: 'food & groceries', icon: 'fork.knife' },
  { kind: 'commitment', name: 'shopping', icon: 'bag' },
  { kind: 'commitment', name: 'subscription', icon: 'arrow.triangle.2.circlepath' },
  { kind: 'commitment', name: 'streaming', icon: 'play.tv' },
  { kind: 'commitment', name: 'software', icon: 'app.badge' },
  { kind: 'commitment', name: 'ai', icon: 'sparkles' },
  { kind: 'commitment', name: 'social media', icon: 'at' },
  { kind: 'commitment', name: 'telecom', icon: 'antenna.radiowaves.left.and.right' },
  { kind: 'commitment', name: 'insurance', icon: 'shield.checkered' },
  { kind: 'commitment', name: 'emi', icon: 'building.columns' },
  { kind: 'commitment', name: 'rent', icon: 'house' },
  { kind: 'commitment', name: 'utility', icon: 'bolt' },
  { kind: 'commitment', name: 'salary', icon: 'banknote' },
  { kind: 'commitment', name: 'education', icon: 'graduationcap' },
  { kind: 'commitment', name: 'fees', icon: 'doc.text' },
  { kind: 'commitment', name: 'membership', icon: 'checkmark.seal' },
  { kind: 'commitment', name: 'domain & hosting', icon: 'globe' },
  { kind: 'commitment', name: 'travel', icon: 'airplane' },
  { kind: 'commitment', name: 'health & fitness', icon: 'heart' },
  { kind: 'commitment', name: 'home', icon: 'wrench.and.screwdriver' },
  { kind: 'commitment', name: 'vehicle', icon: 'car' },
  { kind: 'commitment', name: 'gift', icon: 'gift' },
  { kind: 'commitment', name: 'donation', icon: 'heart.circle' },
  { kind: 'commitment', name: 'warranty & amc', icon: 'checkmark.shield' },
  { kind: 'commitment', name: 'tax', icon: 'percent' },
  // -- members -----------------------------------------------------------------------------
  { kind: 'member', name: 'family', icon: 'person.2' },
  { kind: 'member', name: 'household help', icon: 'person.badge.clock' },
  { kind: 'member', name: 'team', icon: 'briefcase' },
  { kind: 'member', name: 'vendor', icon: 'shippingbox' },
  { kind: 'member', name: 'professional', icon: 'person.text.rectangle' },
  { kind: 'member', name: 'landlord', icon: 'building.2' },
  { kind: 'member', name: 'tenant', icon: 'key' },
  { kind: 'member', name: 'friend', icon: 'hand.wave' },
  // -- accounts ----------------------------------------------------------------------------
  { kind: 'account', name: 'credit card', icon: 'creditcard.fill' },
  { kind: 'account', name: 'debit card', icon: 'creditcard' },
  { kind: 'account', name: 'bank account', icon: 'building.columns' },
  { kind: 'account', name: 'upi', icon: 'qrcode' },
  { kind: 'account', name: 'wallet', icon: 'wallet.pass' },
  { kind: 'account', name: 'cash', icon: 'banknote' },
  { kind: 'account', name: 'brokerage', icon: 'chart.line.uptrend.xyaxis' },
  { kind: 'account', name: 'loan account', icon: 'doc.plaintext' },
]

const key = (name: string): string => name.trim().toLowerCase()

/** The seeded entry for a tag name within one kind, or null when the name is the owner's own. */
export function libraryTag(kind: string, name: string): LibraryTag | null {
  const k = key(name)
  return LIBRARY_TAGS.find((t) => t.kind === kind && key(t.name) === k) ?? null
}
