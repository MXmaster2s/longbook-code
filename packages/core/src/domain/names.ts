// Tolerant name matching so "aditi", "Aditi", "Aditi " all collapse to one key.
export function nameKey(s: string | null | undefined): string {
  return String(s ?? '').trim().toLowerCase().replace(/\s+/g, ' ')
}
