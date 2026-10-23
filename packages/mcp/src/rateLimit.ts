// A sliding window per key. Pure and clock-injected so tests own time; the hosted
// function holds one per isolate — a bound per running instance, not a global ledger,
// and the docs say so plainly.
export class RateLimiter {
  private hits = new Map<string, number[]>()

  constructor(
    readonly limit: number,
    readonly windowMs: number,
  ) {}

  allow(key: string, now: number): { allowed: boolean; retryAfterSeconds: number } {
    const floor = now - this.windowMs
    const recent = (this.hits.get(key) ?? []).filter((t) => t > floor)
    if (recent.length >= this.limit) {
      this.hits.set(key, recent)
      const oldest = recent[0] ?? now
      return { allowed: false, retryAfterSeconds: Math.max(1, Math.ceil((oldest - floor) / 1000)) }
    }
    recent.push(now)
    this.hits.set(key, recent)
    return { allowed: true, retryAfterSeconds: 0 }
  }
}
