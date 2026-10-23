// The four account emails: what they say, what they leave out, how a device is described, and how
// the dispatcher decides to send, skip or retry, with stand-ins for the database and the mail API.
// Also that the SQL, the function and the share function agree. Run: npm run email:test.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { BATCH, HOURLY_LIMIT, RUN_SECONDS, dispatch, type Deps, type Store, type Waiting } from '../supabase/functions/account-notice/dispatch.ts'
import { storeOf, type Client } from '../supabase/functions/account-notice/store.ts'
import { KINDS, describeDevice, renderNotice, when } from '../supabase/functions/account-notice/notice-emails.ts'

const read = (rel: string): string => readFileSync(new URL(`../${rel}`, import.meta.url), 'utf8')
const AT = '2026-09-29T18:29:14.000Z'
const IPHONE_APP = 'longbook/18 CFNetwork/3896.200.41 Darwin/27.2.0'
const CHROME_MAC = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36'

/** What a reader sees: no markup, no style block, one space between words. */
const seen = (html: string): string =>
  html.replace(/<style[\s\S]*?<\/style>/g, '').replace(/<[^>]+>/g, ' ').replace(/&#\d+;/g, ' ')
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/\s+/g, ' ')

test('a time is written the same way on every runtime, in UTC', () => {
  assert.equal(when(AT, AT), '29 September 2026 at 18:29 UTC')
  assert.equal(when('2027-01-01T00:05:00+05:30', AT), '31 December 2026 at 18:35 UTC')
  assert.equal(when('not a date', AT), '29 September 2026 at 18:29 UTC', 'an unreadable time falls back to when it was recorded')
  assert.equal(when(undefined, AT), '29 September 2026 at 18:29 UTC')
})

test('a device is described only as far as its string reveals', () => {
  assert.equal(describeDevice(IPHONE_APP), 'longbook app, build 18', 'the app never says whether it is an iPhone or a Mac')
  assert.equal(describeDevice(CHROME_MAC), 'Chrome on a Mac')
  assert.equal(describeDevice('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1'), 'Safari on iPhone')
  assert.equal(describeDevice('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/154.0 Safari/537.36 Edg/154.0'), 'Edge on Windows')
  assert.equal(describeDevice('Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/154.0 Mobile Safari/537.36'), 'Chrome on Android')
  assert.equal(describeDevice('Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0'), 'Firefox on Linux')
  assert.equal(describeDevice('python-httpx/0.28.1'), 'Another app or script')
  assert.equal(describeDevice(''), null)
  assert.equal(describeDevice(undefined), null)
  assert.equal(describeDevice(42), null)
})

test('a sign-in notice says what was recorded and omits what was not', () => {
  const full = renderNotice('signin', { at: AT, user_agent: CHROME_MAC, ip: '203.0.113.7', method: 'oauth' }, AT)!
  assert.equal(full.subject, 'A new sign-in to your longbook account')
  const s = seen(full.html)
  for (const line of ['New sign-in to your account', '29 September 2026 at 18:29 UTC', 'Your longbook account was signed in.', 'Method Google or Apple', 'App or browser Chrome on a Mac', 'IP address 203.0.113.7']) {
    assert.ok(s.includes(line), `lacks: ${line}`)
  }
  assert.ok(full.text.includes('IP address: 203.0.113.7') && full.text.includes('App or browser: Chrome on a Mac'))
  assert.ok(!/\bTime\b/.test(s.replace('sign-in', '')), 'the time is the subline; the card does not repeat it')
  const bare = renderNotice('signin', { at: AT }, AT)!
  assert.ok(!seen(bare.html).includes('Sign-in details'), 'a card with nothing in it is not drawn')
  assert.ok(seen(bare.html).includes('29 September 2026 at 18:29 UTC'), 'the time is always known')
  assert.ok(seen(renderNotice('signin', { at: AT, method: 'otp' }, AT)!.html).includes('Method Email code'))
  assert.ok(!seen(renderNotice('signin', { at: AT, method: 'sso' }, AT)!.html).includes('Method'), 'a method it does not know is not guessed')
})

test('nothing recorded can become markup or break a line of the email', () => {
  const evil = renderNotice('signin', { at: AT, user_agent: '<img src=x onerror=1>\nEvil "quote" & more', ip: '<script>alert(1)</script>' }, AT)!
  assert.ok(!evil.html.includes('<script>') && !evil.html.includes('<img src=x'))
  assert.ok(!seen(evil.html).includes('IP address'), 'a value that is not an address is left out')
  assert.ok(!evil.html.includes('onerror') && !evil.html.includes('Evil'), 'the device string is reduced to a label and never echoed')
  assert.ok(seen(evil.html).includes('App or browser Another app or script'))
  const shared = renderNotice('report_shared', { at: AT, report: '<b>July</b>\r\n2026 "x" '.padEnd(200, 'z'), expires_at: AT }, AT)!
  assert.ok(!shared.html.includes('<b>July</b>') && shared.html.includes('&lt;b&gt;July&lt;/b&gt; 2026 &quot;x&quot;'))
  assert.ok(!/\n2026/.test(seen(shared.html).replace(/\s+/g, ' ')))
  const title = /Report<\/td>\s*<td[^>]*>([^<]*)</.exec(shared.html)![1]!
  assert.ok(title.length <= 80 + 40, 'a long title is cut')
})

test('the hosted copy notices say what the app says, no more', () => {
  const on = renderNotice('mcp_on', { at: AT }, AT)!
  assert.equal(on.subject, 'longbook’s MCP server is on')
  const s = seen(on.html)
  assert.ok(s.includes('Turned on 29 September 2026 at 18:29 UTC'))
  assert.ok(s.includes('deleted when you turn the server off or after 90 days without opening longbook'))
  assert.ok(s.includes('Address https://longbook.app/mcp') && s.includes('Hosted copy On'))
  const off = renderNotice('mcp_off', { at: AT }, AT)!
  assert.equal(off.subject, 'longbook’s MCP server is off')
  const t = seen(off.html)
  assert.ok(t.includes('Turned off 29 September 2026 at 18:29 UTC'))
  assert.ok(t.includes('Keys you created stay valid until you revoke them, even with the server off.'))
  assert.ok(t.includes('They have nothing to read until you turn it back on, and you can revoke them then.'))
  assert.ok(!t.includes('You can revoke them in longbook'), 'the app shows the keys only while the server is on')
  assert.ok(t.includes('Your own files in iCloud were not touched.'))
  assert.ok(!t.includes('Nothing of your longbook is stored'), 'tag structures are kept, so that would be untrue')
})

test('the report notice never claims to know who has the link, and drops empty details', () => {
  const full = renderNotice('report_shared', { at: AT, report: 'July 2026', expires_at: '2026-10-02T18:29:14Z' }, AT)!
  assert.equal(full.subject, 'You shared a report from longbook')
  const s = seen(full.html)
  assert.ok(s.includes('Report July 2026') && s.includes('Link expires 2 October 2026 at 18:29 UTC'))
  assert.ok(s.includes('longbook keeps no copy of the password and never emails it.'))
  assert.ok(!/who has the link|shared with/i.test(s), 'that note stays on the owner\'s device')
  const bare = renderNotice('report_shared', { at: AT }, AT)!
  assert.ok(!seen(bare.html).includes('Share details'), 'a card with no rows is not drawn')
})

test('every notice follows the house rules: lowercase name, no capitals by style, https only, dark mode', () => {
  for (const kind of KINDS) {
    const mail = renderNotice(kind, { at: AT, user_agent: IPHONE_APP, ip: '203.0.113.7', method: 'otp', report: 'July 2026', expires_at: AT }, AT)!
    for (const part of [mail.subject, seen(mail.html), mail.text]) assert.ok(!/longbook/i.test(part.replace(/longbook/g, '')), `${kind}: a capitalised name`)
    assert.ok(!/text-transform/i.test(mail.html) && !mail.html.includes('{{'))
    assert.ok(mail.html.includes('@media (prefers-color-scheme: dark)') && mail.html.includes('.hr { border-color:'))
    for (const href of [...mail.html.matchAll(/(?:href|src)="([^"]+)"/g)].map((m) => m[1]!)) assert.ok(href.startsWith('https://'), `${kind}: ${href}`)
    for (const img of mail.html.match(/<img\b[^>]*>/g) ?? []) assert.ok(/\balt="/.test(img))
    assert.ok(!/<[a-z][^>]*>/i.test(mail.text), `${kind}: markup in the text version`)
    assert.ok(mail.html.length < 20_000)
  }
})

test('an unknown kind, or details that are not an object, are handled', () => {
  assert.equal(renderNotice('password_changed', {}, AT), null)
  assert.ok(renderNotice('mcp_on', null, AT))
  assert.ok(renderNotice('mcp_on', 'text', AT))
  assert.ok(renderNotice('signin', undefined, AT))
})

// ---- the dispatcher -----------------------------------------------------------------------------

const KEY = 're_test_not_a_real_key'
const EMAIL = 'alex.morgan@example.com'
const row = (n: number, kind = 'mcp_on', extra: Partial<Waiting> = {}): Waiting =>
  ({ id: `n${n}`, user_id: `u${n}`, kind, details: { at: AT, ip: '203.0.113.7', user_agent: IPHONE_APP }, created_at: AT, ...extra })

interface Options {
  apiKey?: string | undefined
  rows?: Waiting[]
  claimThrows?: boolean
  address?: string | null | 'throws'
  sentCount?: number
  status?: number
  sendThrows?: boolean
  sentThrows?: boolean
  releaseThrows?: boolean
}

function harness(options: Options = {}) {
  const seen2 = { claims: 0, sent: [] as string[], skipped: [] as [string, string][], released: [] as string[], requests: [] as { url: string; init: RequestInit }[], logs: [] as string[], since: [] as Date[] }
  const store: Store = {
    async claim(limit) {
      seen2.claims++
      assert.equal(limit, BATCH)
      if (options.claimThrows) throw new Error('database unreachable')
      return options.rows ?? []
    },
    async addressOf() {
      if (options.address === 'throws') throw new Error('lookup failed')
      return options.address === undefined ? EMAIL : options.address
    },
    async sentSince(_u, _k, since) {
      seen2.since.push(since)
      return options.sentCount ?? 0
    },
    async sent(id) {
      if (options.sentThrows) throw new Error('database unreachable')
      seen2.sent.push(id)
    },
    async skip(id, reason) { seen2.skipped.push([id, reason]) },
    async release(id) {
      if (options.releaseThrows) throw new Error('database unreachable')
      seen2.released.push(id)
    },
  }
  const send = (async (url: string, init: RequestInit) => {
    seen2.requests.push({ url, init })
    if (options.sendThrows) throw new Error('the operation was aborted')
    return new Response('{}', { status: options.status ?? 200 })
  }) as unknown as typeof fetch
  const deps: Deps = { apiKey: 'apiKey' in options ? options.apiKey : KEY, store, send, log: (l) => seen2.logs.push(l), now: () => new Date(AT) }
  return { seen: seen2, deps }
}

test('a waiting notice is sent once, from longbook, and marked sent', async () => {
  const { seen: s, deps } = harness({ rows: [row(1, 'signin')] })
  const outcome = await dispatch(deps)
  assert.deepEqual(outcome, { claimed: 1, sent: 1, skipped: 0, retry: 0 })
  assert.deepEqual(s.sent, ['n1'])
  const { url, init } = s.requests[0]!
  assert.equal(url, 'https://api.resend.com/emails')
  const headers = init.headers as Record<string, string>
  assert.equal(headers.Authorization, `Bearer ${KEY}`)
  assert.equal(headers['Idempotency-Key'], 'notice-n1')
  const body = JSON.parse(init.body as string)
  assert.equal(body.from, 'longbook <contact@longbook.app>')
  assert.deepEqual(body.to, [EMAIL])
  assert.equal(body.reply_to, 'contact@longbook.app')
  assert.equal(body.subject, 'A new sign-in to your longbook account')
  assert.ok(body.html.includes('New sign-in to your account') && body.text.includes('New sign-in to your account'))
  assert.ok(init.signal, 'a slow mail API must not hold the run')
})

test('without a mail key nothing is claimed, so nothing is lost', async () => {
  const { seen: s, deps } = harness({ apiKey: undefined, rows: [row(1)] })
  assert.deepEqual(await dispatch(deps), { claimed: 0, sent: 0, skipped: 0, retry: 0 })
  assert.equal(s.claims, 0)
  assert.equal(s.requests.length, 0)
})

test('a claim that fails ends the run quietly', async () => {
  const { seen: s, deps } = harness({ claimThrows: true })
  assert.deepEqual(await dispatch(deps), { claimed: 0, sent: 0, skipped: 0, retry: 0 })
  assert.deepEqual(s.logs, ['account notices: database unreachable'])
})

test('a notice for an account with no address, or of an unknown kind, is skipped for good', async () => {
  const gone = harness({ rows: [row(1)], address: null })
  await dispatch(gone.deps)
  assert.deepEqual(gone.seen.skipped, [['n1', 'no_address']])
  assert.equal(gone.seen.requests.length, 0)
  const odd = harness({ rows: [row(2, 'password_changed')] })
  await dispatch(odd.deps)
  assert.deepEqual(odd.seen.skipped, [['n2', 'unknown_kind']])
  assert.equal(odd.seen.requests.length, 0)
})

test('a person is sent at most three of one kind in an hour', async () => {
  assert.equal(HOURLY_LIMIT, 3)
  const over = harness({ rows: [row(1)], sentCount: 3 })
  await dispatch(over.deps)
  assert.deepEqual(over.seen.skipped, [['n1', 'throttled']])
  assert.equal(over.seen.requests.length, 0)
  assert.equal(over.seen.since[0]!.toISOString(), '2026-09-29T17:29:14.000Z', 'the hour is counted back from now')
  const under = harness({ rows: [row(1)], sentCount: 2 })
  await dispatch(under.deps)
  assert.deepEqual(under.seen.sent, ['n1'])
})

test('a refused or failed send is given back to be tried again, and never marked sent', async () => {
  for (const options of [{ status: 500 }, { status: 401 }, { status: 429 }, { sendThrows: true }] as Options[]) {
    const { seen: s, deps } = harness({ rows: [row(1)], ...options })
    const outcome = await dispatch(deps)
    assert.deepEqual(s.released, ['n1'])
    assert.deepEqual(s.sent, [])
    assert.equal(outcome.retry, 1)
  }
})

test('an address that cannot be looked up is a retry, not a skip', async () => {
  const { seen: s, deps } = harness({ rows: [row(1)], address: 'throws' })
  await dispatch(deps)
  assert.deepEqual(s.released, ['n1'])
  assert.deepEqual(s.skipped, [])
})

test('a mark that cannot be written after a send is tried again under the same key, and then marks', async () => {
  const requests: RequestInit[] = []
  let marks = 0
  const sent: string[] = []
  const store: Store = {
    async claim() { return sent.length ? [] : [row(1)] },
    async addressOf() { return EMAIL },
    async sentSince() { return 0 },
    async sent(id) { if (marks++ === 0) throw new Error('database unreachable'); sent.push(id) },
    async skip() {},
    async release() {},
  }
  const send = (async (_url: string, init: RequestInit) => { requests.push(init); return new Response('{}', { status: 200 }) }) as unknown as typeof fetch
  const deps: Deps = { apiKey: KEY, store, send, log: () => {}, now: () => new Date(AT) }
  await dispatch(deps)
  assert.deepEqual(sent, [], 'the first mark failed')
  await dispatch(deps)
  assert.deepEqual(sent, ['n1'], 'the second run marked it')
  assert.equal(requests.length, 2)
  assert.deepEqual(requests.map((r) => (r.headers as Record<string, string>)['Idempotency-Key']), ['notice-n1', 'notice-n1'], 'Resend delivers the one email once')
})

test('a refusal that no retry can fix is skipped, and one that might pass is not', async () => {
  for (const status of [400, 422]) {
    const { seen: s, deps } = harness({ rows: [row(1)], status })
    const outcome = await dispatch(deps)
    assert.deepEqual(s.skipped, [['n1', 'rejected']])
    assert.deepEqual(s.released, [])
    assert.deepEqual(outcome, { claimed: 1, sent: 0, skipped: 1, retry: 0 })
  }
  for (const status of [401, 403, 429, 500, 503]) {
    const { seen: s, deps } = harness({ rows: [row(1)], status })
    await dispatch(deps)
    assert.deepEqual(s.skipped, [], `${status} must stay retryable`)
    assert.deepEqual(s.released, ['n1'])
  }
})

test('Resend\'s own error code is logged, and nothing else it says', async () => {
  const { seen: s, deps } = harness({ rows: [row(1)] })
  deps.send = (async () => new Response(JSON.stringify({ name: 'rate_limit_exceeded', message: `slow down for ${EMAIL}` }), { status: 429 })) as unknown as typeof fetch
  await dispatch(deps)
  assert.deepEqual(s.logs, ['account notice mcp_on: Resend answered 429, rate_limit_exceeded'])
  const odd = harness({ rows: [row(1)] })
  odd.deps.send = (async () => new Response(JSON.stringify({ name: `bad ${EMAIL}` }), { status: 500 })) as unknown as typeof fetch
  await dispatch(odd.deps)
  assert.deepEqual(odd.seen.logs, ['account notice mcp_on: Resend answered 500'], 'a name that is not a code is not logged')
})

test('a run starts no new notice after its time is up, and gives the rest back', async () => {
  assert.equal(RUN_SECONDS, 20)
  const { seen: s, deps } = harness({ rows: [row(1), row(2), row(3)] })
  let t = new Date(AT).getTime()
  deps.now = () => new Date((t += 12_000))
  const outcome = await dispatch(deps)
  assert.deepEqual(s.sent, ['n1'])
  assert.deepEqual(s.released, ['n2', 'n3'])
  assert.deepEqual(outcome, { claimed: 3, sent: 1, skipped: 0, retry: 2 })
})

test('one failure does not stop the rest, and a release that fails does not throw', async () => {
  const { seen: s, deps } = harness({ rows: [row(1), row(2), row(3)], releaseThrows: true })
  let n = 0
  const real = deps.send
  deps.send = (async (...args: Parameters<typeof fetch>) => {
    if (n++ === 1) return new Response('{}', { status: 500 })
    return real(...args)
  }) as typeof fetch
  const outcome = await dispatch(deps)
  assert.deepEqual(outcome, { claimed: 3, sent: 2, skipped: 0, retry: 1 })
  assert.deepEqual(s.sent, ['n1', 'n3'])
  assert.ok(s.logs.includes('account notices: could not give a notice back'))
})

test('what is logged never names the person, the address or the device', async () => {
  for (const options of [{ status: 500 }, { sendThrows: true }, { address: 'throws' as const }, { claimThrows: true }, { releaseThrows: true, status: 500 }] as Options[]) {
    const { seen: s, deps } = harness({ rows: [row(1, 'signin')], ...options })
    await dispatch(deps)
    for (const line of s.logs) {
      for (const secret of [EMAIL, '203.0.113.7', 'CFNetwork', KEY, 'u1']) assert.ok(!line.includes(secret), `${secret} in: ${line}`)
    }
  }
})

// ---- the real store ---------------------------------------------------------------------------

function clientOf(options: { count?: number; user?: { email?: string | null } | null; userError?: { status?: number; message: string } | null; updateError?: string; rows?: unknown[]; rpcError?: string } = {}) {
  const calls: Record<string, unknown>[] = []
  const client: Client = {
    from(table: string) {
      return {
        update(patch: Record<string, unknown>) {
          return { eq: async (col: string, val: unknown) => { calls.push({ op: 'update', table, patch, col, val }); return { error: options.updateError ? { message: options.updateError } : null } } }
        },
        select(cols: string, opts: unknown) {
          const filters: unknown[][] = []
          const query: any = {
            eq(c: string, v: unknown) { filters.push(['eq', c, v]); return query },
            gte(c: string, v: unknown) { filters.push(['gte', c, v]); return query },
            then(resolve: (v: unknown) => unknown) { calls.push({ op: 'count', table, cols, opts, filters }); return Promise.resolve({ count: options.count ?? 0, error: null }).then(resolve) },
          }
          return query
        },
      }
    },
    async rpc(name, args) { calls.push({ op: 'rpc', name, args }); return { data: options.rows ?? [], error: options.rpcError ? { message: options.rpcError } : null } },
    auth: { admin: { async getUserById() { return { data: { user: options.user === undefined ? { email: EMAIL } : options.user }, error: options.userError ?? null } } } },
  }
  return { client, calls }
}

test('the real store drops what a notice recorded when it is sent or skipped', async () => {
  const { client, calls } = clientOf()
  const store = storeOf(client)
  await store.sent('n1')
  await store.skip('n2', 'throttled')
  assert.equal(calls.length, 2)
  const [sent, skipped] = calls as { patch: Record<string, unknown>; col: string; val: string; table: string }[]
  assert.equal(sent!.table, 'account_notices')
  assert.deepEqual([sent!.col, sent!.val], ['id', 'n1'])
  assert.deepEqual(sent!.patch.details, {}, 'the IP address and device string must go when it is sent')
  assert.ok(typeof sent!.patch.sent_at === 'string' && !Number.isNaN(Date.parse(sent!.patch.sent_at as string)))
  assert.deepEqual([skipped!.col, skipped!.val, skipped!.patch.skipped_reason], ['id', 'n2', 'throttled'])
  assert.deepEqual(skipped!.patch.details, {}, 'and when it is skipped')
})

test('a released notice is claimed now, so the wait runs from the failure', async () => {
  const { client, calls } = clientOf()
  await storeOf(client).release('n3')
  const patch = (calls[0] as { patch: { claimed_at: unknown } }).patch
  assert.ok(typeof patch.claimed_at === 'string' && Math.abs(Date.now() - Date.parse(patch.claimed_at)) < 5000, 'not null: null would be retried at once')
})

test('the real store claims through the function, counts one person\'s kind since a time, and finds addresses', async () => {
  const claimed = clientOf({ rows: [row(1)] })
  assert.deepEqual(await storeOf(claimed.client).claim(7), [row(1)])
  assert.deepEqual(claimed.calls[0], { op: 'rpc', name: 'claim_account_notices', args: { max_rows: 7 } })
  const counted = clientOf({ count: 2 })
  assert.equal(await storeOf(counted.client).sentSince('u1', 'signin', new Date(AT)), 2)
  const q = counted.calls[0] as { table: string; opts: unknown; filters: unknown[][] }
  assert.equal(q.table, 'account_notices')
  assert.deepEqual(q.opts, { count: 'exact', head: true })
  assert.deepEqual(q.filters, [['eq', 'user_id', 'u1'], ['eq', 'kind', 'signin'], ['gte', 'sent_at', AT]])
  assert.equal(await storeOf(clientOf().client).addressOf('u1'), EMAIL)
  assert.equal(await storeOf(clientOf({ user: { email: null } }).client).addressOf('u1'), null)
  assert.equal(await storeOf(clientOf({ user: null }).client).addressOf('u1'), null)
  assert.equal(await storeOf(clientOf({ user: null, userError: { status: 404, message: 'user_not_found' } }).client).addressOf('u1'), null)
  await assert.rejects(storeOf(clientOf({ user: null, userError: { status: 500, message: 'boom' } }).client).addressOf('u1'), /could not look up an account: boom/, 'an error that is not "no such account" is retried, never a skip')
})

test('the real store turns database errors into errors, never into silence', async () => {
  await assert.rejects(storeOf(clientOf({ updateError: 'down' }).client).sent('n1'), /could not update a notice: down/)
  await assert.rejects(storeOf(clientOf({ rpcError: 'down' }).client).claim(5), /could not claim notices: down/)
})

// ---- the pieces agree ---------------------------------------------------------------------------

test('the SQL, the function and the share function name the same things', () => {
  const sql = read('supabase/migrations/20260929150000_account_notices.sql')
  const kinds = /check \(kind in \(([^)]*)\)\)/.exec(sql)![1]!.split(',').map((k) => k.trim().replace(/'/g, ''))
  assert.deepEqual(kinds, [...KINDS], 'the table accepts exactly the kinds the emails are written for')
  const index = read('supabase/functions/account-notice/index.ts')
  const store = read('supabase/functions/account-notice/store.ts')
  assert.ok(store.includes("client.rpc('claim_account_notices', { max_rows: limit })") && sql.includes('function public.claim_account_notices(max_rows integer'))
  assert.ok(store.includes("from('account_notices')") && sql.includes('create table public.account_notices'))
  assert.ok(sql.includes('/functions/v1/account-notice') && sql.includes("where name = 'notice_key'") && index.includes("Deno.env.get('NOTICE_KEY')"))
  const backoff = "interval '5 minutes' * greatest("
  assert.equal(sql.split(backoff).length - 1, 2, 'the claim and the poke wait the same, longer after each try')
  assert.ok(sql.includes('coalesce(u.email_confirmed_at, u.created_at)'), 'the sign-up is measured from confirmation')
  for (const job of ['account-notices-scan', 'account-notices-send', 'account-notices-tidy']) {
    assert.ok(sql.includes(`cron.schedule('${job}'`), `${job} is scheduled`)
    assert.ok(read('scripts/guard-rls.mts').includes(job), `${job} is watched by the guard`)
  }
  assert.ok(sql.includes("'mcp_on'") && sql.includes("'mcp_off'") && sql.includes("'signin'"))
  assert.ok(read('supabase/functions/share-report/index.ts').includes("kind: 'report_shared'"))
  assert.ok(read('scripts/deploy-function.mts').includes("'account-notice'"))
  for (const fn of ['notice_hosted_copy()', 'scan_new_sessions()', 'poke_account_notices()', 'tidy_account_notices()', 'claim_account_notices(integer)']) {
    assert.ok(sql.includes(`revoke all on function public.${fn} from public, anon, authenticated;`), `${fn} must not be callable by a client`)
  }
  assert.ok(sql.includes('revoke all on table public.account_notices from public, anon, authenticated;'))
})
