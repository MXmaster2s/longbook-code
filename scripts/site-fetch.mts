// Reads a file from the site over a connection that drops: each attempt reads the whole body under
// its own timeout, and a network error or a 5xx is tried again after 1 s, 2 s, then 4 s.
export type Fetched = { status: number; ok: boolean; bytes: Buffer }

export type FetchOptions = {
  headers?: Record<string, string>
  attempts?: number
  timeoutMs?: number
  // Also tried again: a 404 straight after a deploy can be the CDN still catching up.
  retry404?: boolean
  wait?: (ms: number) => Promise<void>
  fetcher?: typeof fetch
}

const pause = (ms: number) => new Promise<void>((done) => setTimeout(done, ms))

export async function fetchWithRetry(url: string, options: FetchOptions = {}): Promise<Fetched> {
  const { headers, attempts = 4, timeoutMs = 30_000, retry404 = false, wait = pause, fetcher = fetch } = options
  for (let attempt = 1; ; attempt++) {
    try {
      const answer = await fetcher(url, { headers, signal: AbortSignal.timeout(timeoutMs) })
      const bytes = Buffer.from(await answer.arrayBuffer())
      const again = answer.status >= 500 || (retry404 && answer.status === 404)
      if (!again || attempt >= attempts) return { status: answer.status, ok: answer.ok, bytes }
    } catch (error) {
      if (attempt >= attempts) throw error
    }
    await wait(1000 * 2 ** (attempt - 1))
  }
}

// Asks past Cloudflare's cache, which can hold a stale copy or a 404 from before a deploy.
export const uncached = (url: string): string => `${url}${url.includes('?') ? '&' : '?'}v=${Date.now().toString(36)}`

// Runs one task per item, at most `limit` at once.
export async function eachLimited<T>(items: T[], limit: number, task: (item: T) => Promise<void>): Promise<void> {
  let next = 0
  const worker = async () => {
    while (next < items.length) await task(items[next++])
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker))
}
