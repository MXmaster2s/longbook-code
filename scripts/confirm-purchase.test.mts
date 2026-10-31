// Sending the confirmation exactly once, and never at the purchase's expense, with a stand-in
// for the database mark and for the mail API. Run: npm run email:test.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { confirmPurchase, type Purchase, type SentMark } from '../supabase/functions/_shared/confirm-purchase.ts'

const KEY = 're_test_not_a_real_key'
const purchase: Purchase = {
  userId: 'user-1',
  transactionId: '2000000123456789',
  email: 'alex.morgan@example.com',
  purchasedAt: new Date('2026-09-29T06:49:04Z'),
  majorVersion: 1,
  environment: 'Production',
}

interface Options {
  apiKey?: string | undefined
  taken?: boolean
  claimThrows?: boolean
  releaseThrows?: boolean
  status?: number
  sendThrows?: boolean
}

function harness(options: Options = {}) {
  const seen = { claims: 0, releases: 0, requests: [] as { url: string; init: RequestInit }[], logs: [] as string[] }
  let taken = options.taken ?? false
  const mark: SentMark = {
    async claim() {
      seen.claims++
      if (options.claimThrows) throw new Error('database unreachable')
      if (taken) return false
      taken = true
      return true
    },
    async release() {
      seen.releases++
      if (options.releaseThrows) throw new Error('database unreachable')
      taken = false
    },
  }
  const send = (async (url: string, init: RequestInit) => {
    seen.requests.push({ url, init })
    if (options.sendThrows) throw new Error('the operation was aborted')
    return new Response('{}', { status: options.status ?? 200 })
  }) as unknown as typeof fetch
  const deps = { apiKey: 'apiKey' in options ? options.apiKey : KEY, mark, send, log: (l: string) => seen.logs.push(l) }
  return { seen, deps }
}

test('a new purchase sends one email, and keeps the mark', async () => {
  const { seen, deps } = harness()
  await confirmPurchase(deps, purchase)
  assert.equal(seen.requests.length, 1)
  assert.equal(seen.releases, 0)
  const { url, init } = seen.requests[0]!
  assert.equal(url, 'https://api.resend.com/emails')
  assert.equal(init.method, 'POST')
  const headers = init.headers as Record<string, string>
  assert.equal(headers.Authorization, `Bearer ${KEY}`)
  assert.equal(headers['Idempotency-Key'], 'purchase-2000000123456789')
  const body = JSON.parse(init.body as string)
  assert.equal(body.from, 'longbook <contact@longbook.app>')
  assert.deepEqual(body.to, ['alex.morgan@example.com'])
  assert.equal(body.reply_to, 'contact@longbook.app')
  assert.equal(body.subject, 'Your longbook license is now active')
  assert.ok(body.html.includes('Thank you for purchasing longbook!'))
  assert.ok(body.text.includes('Thank you for purchasing longbook!'))
  assert.ok(init.signal, 'a slow mail API must not hold the purchase')
})

test('without a key, or without an address, nothing is claimed or sent', async () => {
  for (const [deps, buyer] of [
    [harness({ apiKey: undefined }), purchase],
    [harness({ apiKey: '' }), purchase],
    [harness(), { ...purchase, email: '' }],
  ] as const) {
    await confirmPurchase(deps.deps, buyer)
    assert.equal(deps.seen.claims, 0)
    assert.equal(deps.seen.requests.length, 0)
  }
})

test('a purchase whose mark is already taken sends nothing and gives nothing back', async () => {
  const { seen, deps } = harness({ taken: true })
  await confirmPurchase(deps, purchase)
  assert.equal(seen.requests.length, 0)
  assert.equal(seen.releases, 0)
})

test('the same purchase delivered twice is one email', async () => {
  const { seen, deps } = harness()
  await confirmPurchase(deps, purchase)
  await confirmPurchase(deps, purchase)
  assert.equal(seen.requests.length, 1)
})

test('a failed send gives the mark back, so the next delivery sends it', async () => {
  const failing = harness({ status: 500 })
  await confirmPurchase(failing.deps, purchase)
  assert.equal(failing.seen.releases, 1)
  assert.deepEqual(failing.seen.logs, ['purchase email: Resend answered 500'])

  // The same mark, a mail API that works again.
  const state = { taken: false }
  const seen = { sends: 0 }
  const mark: SentMark = {
    async claim() { if (state.taken) return false; state.taken = true; return true },
    async release() { state.taken = false },
  }
  let attempt = 0
  const send = (async () => { seen.sends++; return new Response('{}', { status: attempt++ === 0 ? 503 : 200 }) }) as unknown as typeof fetch
  const deps = { apiKey: KEY, mark, send, log: () => {} }
  await confirmPurchase(deps, purchase)
  await confirmPurchase(deps, purchase)
  await confirmPurchase(deps, purchase)
  assert.equal(seen.sends, 2, 'one failed try, one that worked, then nothing more')
})

test('a key that is refused gives the mark back too, so fixing the key is enough', async () => {
  const { seen, deps } = harness({ status: 401 })
  await confirmPurchase(deps, purchase)
  assert.equal(seen.releases, 1)
})

test('a send that throws gives the mark back and does not throw', async () => {
  const { seen, deps } = harness({ sendThrows: true })
  await confirmPurchase(deps, purchase)
  assert.equal(seen.releases, 1)
  assert.deepEqual(seen.logs, ['purchase email: the operation was aborted'])
})

test('a claim that fails sends nothing and never clears an earlier send\'s mark', async () => {
  const { seen, deps } = harness({ claimThrows: true })
  await confirmPurchase(deps, purchase)
  assert.equal(seen.requests.length, 0)
  assert.equal(seen.releases, 0)
  assert.deepEqual(seen.logs, ['purchase email: database unreachable'])
})

test('a mark that cannot be given back does not fail the purchase', async () => {
  const { seen, deps } = harness({ status: 500, releaseThrows: true })
  await assert.doesNotReject(confirmPurchase(deps, purchase))
  assert.equal(seen.releases, 1)
  assert.ok(seen.logs.includes('purchase email: could not give the mark back'), 'a mark left taken must be visible in the logs')
})

test('what is logged never names the buyer or holds the key', async () => {
  for (const options of [{ status: 500 }, { status: 401 }, { sendThrows: true }, { claimThrows: true }] as Options[]) {
    const { seen, deps } = harness(options)
    await confirmPurchase(deps, purchase)
    for (const line of seen.logs) {
      assert.ok(!line.includes(purchase.email), line)
      assert.ok(!line.includes(KEY), line)
    }
  }
})

test('a TestFlight purchase is sent as a test', async () => {
  const { seen, deps } = harness()
  await confirmPurchase(deps, { ...purchase, environment: 'Sandbox' })
  assert.equal(JSON.parse(seen.requests[0]!.init.body as string).subject, '[Test purchase] Your longbook license is now active')
})
