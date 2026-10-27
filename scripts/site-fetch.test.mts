// The site deploy's reads: which answers are tried again, how long it waits, and the bounded pool.
// Run: npm run site:deploy:test.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { eachLimited, fetchWithRetry, uncached } from './site-fetch.mts'

// A fetch that plays back a script of answers, a number as a status and an Error as a dropped connection.
const scripted = (script: (number | Error)[]) => {
  const calls: string[] = []
  const fetcher = (async (url: string) => {
    calls.push(url)
    const next = script.shift()
    if (next instanceof Error) throw next
    return new Response(next === 200 ? 'body' : '', { status: next })
  }) as typeof fetch
  return { calls, fetcher }
}

test('a dropped connection and a 5xx are tried again, waiting 1 s then 2 s', async () => {
  const { calls, fetcher } = scripted([new TypeError('fetch failed'), 503, 200])
  const waits: number[] = []
  const answer = await fetchWithRetry('https://x/a', { fetcher, wait: async (ms) => { waits.push(ms) } })
  assert.equal(answer.status, 200)
  assert.equal(answer.bytes.toString(), 'body')
  assert.deepEqual(waits, [1000, 2000])
  assert.equal(calls.length, 3)
})

test('a 404 is final unless asked for, then tried until the attempts run out', async () => {
  const once = scripted([404])
  assert.equal((await fetchWithRetry('https://x/a', { fetcher: once.fetcher, wait: async () => {} })).status, 404)
  assert.equal(once.calls.length, 1)
  const waits: number[] = []
  const after = scripted([404, 404, 404, 404])
  const answer = await fetchWithRetry('https://x/a', { fetcher: after.fetcher, retry404: true, wait: async (ms) => { waits.push(ms) } })
  assert.equal(answer.status, 404)
  assert.deepEqual(waits, [1000, 2000, 4000])
})

test('four dropped connections throw the last error', async () => {
  const { fetcher } = scripted([1, 2, 3, 4].map((n) => new TypeError(`drop ${n}`)))
  await assert.rejects(fetchWithRetry('https://x/a', { fetcher, wait: async () => {} }), /drop 4/)
})

test('a stalled answer is cut off by the timeout', async () => {
  const fetcher = ((_: string, init?: RequestInit) => new Promise((_, fail) => {
    init?.signal?.addEventListener('abort', () => fail(init.signal?.reason))
  })) as typeof fetch
  // The timeout's own timer does not hold the process open, so this one does.
  const hold = setTimeout(() => {}, 1000)
  await assert.rejects(fetchWithRetry('https://x/a', { fetcher, attempts: 1, timeoutMs: 20 }), { name: 'TimeoutError' })
  clearTimeout(hold)
})

test('the pool runs every item and never more than its limit at once', async () => {
  let running = 0
  let most = 0
  const done: number[] = []
  await eachLimited([...Array(20).keys()], 6, async (n) => {
    running++
    most = Math.max(most, running)
    await new Promise((r) => setTimeout(r, 2))
    running--
    done.push(n)
  })
  assert.equal(done.length, 20)
  assert.equal(most, 6)
})

test('the cache-busting query joins an existing one', () => {
  assert.match(uncached('https://x/a.png'), /^https:\/\/x\/a\.png\?v=\w+$/)
  assert.match(uncached('https://x/a?b=1'), /^https:\/\/x\/a\?b=1&v=\w+$/)
})
