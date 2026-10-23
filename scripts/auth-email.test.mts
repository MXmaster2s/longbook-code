// The auth-email function without Deno or the network: the signature check, the cap and its
// message, the emails against Auth's own templates, and the names shared with the SQL.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import {
  addressHash, handle, HOURLY_CAP, limitMessage, mailFor, MAIL_FROM, PROJECT_HOURLY_CAP, projectMessage, SEND_MS, verifySignature, type Deps,
} from '../supabase/functions/auth-email/hook.ts'
import { AUTH_EMAILS, CODE, LINK, htmlOf } from './auth-emails/templates.mts'

const read = (rel: string): string => readFileSync(new URL(`../${rel}`, import.meta.url), 'utf8')
const SECRET = `v1,whsec_${Buffer.from('0123456789abcdef0123456789abcdef').toString('base64')}`
const NOW = new Date('2026-09-30T09:00:00Z')
const BASE = 'https://xbrnijgctmovoqbbmgmb.supabase.co'

async function signed(body: string, opts: { id?: string; at?: Date; secret?: string; extra?: string } = {}): Promise<Headers> {
  const id = opts.id ?? 'msg_1'
  const ts = String(Math.floor((opts.at ?? NOW).getTime() / 1000))
  const raw = (opts.secret ?? SECRET).replace(/^v1,/, '').replace(/^whsec_/, '')
  const key = await crypto.subtle.importKey('raw', Buffer.from(raw, 'base64'), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const sig = Buffer.from(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${id}.${ts}.${body}`))).toString('base64')
  return new Headers({ 'webhook-id': id, 'webhook-timestamp': ts, 'webhook-signature': `${opts.extra ?? ''}v1,${sig}` })
}

const payload = (kind: string, extra: Record<string, unknown> = {}, email: unknown = 'Reader@Example.com'): string =>
  JSON.stringify({
    user: { id: 'u1', email },
    email_data: { token: '482910', token_hash: 'hash-abc', redirect_to: 'longbook://auth/callback', email_action_type: kind, site_url: 'https://longbook.app', ...extra },
  })

function depsOf(over: { tally?: { allowed: boolean; retryAfterSeconds: number; reason?: 'address' | 'project' }; status?: number; broken?: boolean; failing?: boolean } = {}) {
  const sent: { url: string; body: Record<string, unknown> }[] = []
  const logs: string[] = []
  const counted: string[] = []
  const deps: Deps = {
    apiKey: 'rk',
    verifyBase: BASE,
    count: async (h) => {
      counted.push(h)
      if (over.broken) throw new Error('connection reset')
      return over.tally ?? { allowed: true, retryAfterSeconds: 0 }
    },
    send: (async (url, init) => {
      if (over.failing) throw Object.assign(new Error('timeout'), { name: 'TimeoutError' })
      sent.push({ url: String(url), body: JSON.parse(String(init?.body)) })
      return new Response('{"name":"internal_server_error"}', { status: over.status ?? 200 })
    }) as typeof fetch,
    log: (l) => logs.push(l),
    now: () => NOW,
  }
  return { deps, sent, logs, counted }
}

test('the signature is checked the way Auth signs: id, time and body, within five minutes', async () => {
  const body = payload('magiclink')
  assert.equal(await verifySignature(await signed(body), body, SECRET, NOW), true)
  assert.equal(await verifySignature(await signed(body), body + ' ', SECRET, NOW), false, 'a changed body')
  assert.equal(await verifySignature(await signed(body, { at: new Date(NOW.getTime() - 6 * 60_000) }), body, SECRET, NOW), false, 'six minutes old')
  assert.equal(await verifySignature(await signed(body, { at: new Date(NOW.getTime() + 4 * 60_000) }), body, SECRET, NOW), true, 'four minutes ahead')
  assert.equal(await verifySignature(await signed(body, { secret: 'v1,whsec_' + Buffer.from('other-secret-other-secret-other!').toString('base64') }), body, SECRET, NOW), false, 'another secret')
  assert.equal(await verifySignature(await signed(body, { extra: 'v1,bm90aGluZw== ' }), body, SECRET, NOW), true, 'one of two signatures matches')
  const headers = await signed(body)
  headers.delete('webhook-id')
  assert.equal(await verifySignature(headers, body, SECRET, NOW), false, 'a header missing')
  assert.equal(await verifySignature(await signed(body), body, SECRET.replace(/^v1,/, ''), NOW), true, 'the secret without its version prefix')
  assert.equal(await verifySignature(await signed(body), body, 'not base64 at all!', NOW), false, 'a secret that is not a key')
  const other = 'v1,whsec_' + Buffer.from('other-secret-other-secret-other!').toString('base64')
  assert.equal(await verifySignature(await signed(body), body, `${other}|${SECRET}`, NOW), true, 'the second of two secrets')
  assert.equal(await verifySignature(await signed(body), body, `not a key|${other}`, NOW), false, 'neither of two secrets')
})

test('an address hashes the same in any case or spacing, and the hash names nothing', async () => {
  const a = await addressHash('Reader@Example.com')
  assert.equal(a, await addressHash('  reader@example.com '))
  assert.match(a, /^[0-9a-f]{64}$/)
  assert.notEqual(a, await addressHash('reader@example.org'))
})

test('the cap message counts up to the next whole minute, never below one', () => {
  assert.equal(limitMessage(1), 'You have exceeded your hourly sign-in limit. Please try again in ~1 minute.')
  assert.equal(limitMessage(0), 'You have exceeded your hourly sign-in limit. Please try again in ~1 minute.')
  assert.equal(limitMessage(61), 'You have exceeded your hourly sign-in limit. Please try again in ~2 minutes.')
  assert.equal(limitMessage(3600), 'You have exceeded your hourly sign-in limit. Please try again in ~60 minutes.')
  assert.equal(projectMessage(200), 'longbook is sending too many sign-in emails right now. Please try again in ~4 minutes.')
  assert.equal(HOURLY_CAP, 5)
  assert.ok(PROJECT_HOURLY_CAP > HOURLY_CAP * 10, 'the ceiling is far above what one reader can reach')
  assert.ok(SEND_MS < 5000, 'Auth gives up after five seconds')
})

test('a sign-up and a sign-in are the very emails Auth sends from its own templates', () => {
  const link = `${BASE}/auth/v1/verify?token=hash-abc&type=signup&redirect_to=longbook%3A%2F%2Fauth%2Fcallback`
  const signUp = mailFor(JSON.parse(payload('signup')), BASE)
  assert.ok('mail' in signUp)
  assert.equal(signUp.mail.to, 'Reader@Example.com')
  assert.equal(signUp.mail.subject, AUTH_EMAILS[0]!.subject)
  assert.equal(signUp.mail.html, htmlOf(AUTH_EMAILS[0]!).replaceAll(CODE, '482910').replaceAll(LINK, link.replace(/&/g, '&amp;')))
  assert.ok(signUp.mail.text.includes('482910') && signUp.mail.text.includes(link))
  const signIn = mailFor(JSON.parse(payload('magiclink')), BASE)
  assert.ok('mail' in signIn)
  assert.equal(signIn.mail.subject, AUTH_EMAILS[1]!.subject)
  assert.equal(signIn.mail.html, htmlOf(AUTH_EMAILS[1]!).replaceAll(CODE, '482910'))
  assert.ok(!signIn.mail.html.includes('verify?token'), 'a returning reader gets no link')
})

test('other kinds get a plain email; an email change and a missing address are refused', () => {
  const recovery = mailFor(JSON.parse(payload('recovery')), BASE)
  assert.ok('mail' in recovery && recovery.mail.subject === 'Your longbook code' && recovery.mail.html.includes('482910'))
  const changed = mailFor(JSON.parse(payload('password_changed_notification', { token: '', token_hash: '' })), BASE)
  assert.ok('mail' in changed && changed.mail.subject === 'A change to your longbook account' && !changed.mail.html.includes('482910'))
  assert.deepEqual(mailFor(JSON.parse(payload('email_change')), BASE), { refusal: 'longbook does not change the email address of an account.' })
  assert.deepEqual(mailFor(JSON.parse(payload('magiclink', {}, null)), BASE), { refusal: 'No email address to send a code to.' })
  assert.deepEqual(mailFor(JSON.parse(payload('magiclink', {}, 'not an address')), BASE), { refusal: 'No email address to send a code to.' })
  assert.deepEqual(mailFor(JSON.parse(payload('signup', { token: '' })), BASE), { refusal: 'No code came with this request.' })
  const control = mailFor(JSON.parse(payload('magiclink', { token: '48\u00002910' })), BASE)
  assert.ok('mail' in control && control.mail.html.includes('482910') && !control.mail.html.includes('\u0000'))
})

test('a code within the cap is sent from longbook to the address, and Auth is told nothing else', async () => {
  const { deps, sent, counted } = depsOf()
  const body = payload('magiclink')
  const answer = await handle({ headers: await signed(body), body }, SECRET, deps)
  assert.deepEqual(answer, { status: 200, body: {} })
  assert.equal(sent.length, 1)
  assert.equal(sent[0]!.url, 'https://api.resend.com/emails')
  assert.equal(sent[0]!.body.from, MAIL_FROM)
  assert.deepEqual(sent[0]!.body.to, ['Reader@Example.com'])
  assert.equal(sent[0]!.body.subject, 'Your longbook sign-in code')
  assert.deepEqual(counted, [await addressHash('reader@example.com')])
})

test('past the cap nothing is sent, and the person is told how long to wait', async () => {
  const { deps, sent } = depsOf({ tally: { allowed: false, retryAfterSeconds: 400 } })
  const body = payload('magiclink')
  const answer = await handle({ headers: await signed(body), body }, SECRET, deps)
  assert.deepEqual(answer, { status: 200, body: { error: { http_code: 429, message: 'You have exceeded your hourly sign-in limit. Please try again in ~7 minutes.' } } })
  assert.equal(sent.length, 0)
  const ceiling = depsOf({ tally: { allowed: false, retryAfterSeconds: 90, reason: 'project' } })
  const stopped = await handle({ headers: await signed(body), body }, SECRET, ceiling.deps)
  assert.deepEqual(stopped, { status: 200, body: { error: { http_code: 429, message: 'longbook is sending too many sign-in emails right now. Please try again in ~2 minutes.' } } })
  assert.equal(ceiling.sent.length, 0)
  assert.ok(ceiling.logs.some((l) => l.includes('ceiling')), 'the ceiling is worth a log line; one address\'s cap is not')
  assert.equal(depsOf().logs.length, 0)
})

test('a send that fails or times out is passed back as a sentence, never as silence', async () => {
  const body = payload('signup')
  const refused = depsOf({ status: 500 })
  assert.deepEqual(await handle({ headers: await signed(body), body }, SECRET, refused.deps), { status: 200, body: { error: { http_code: 500, message: 'The email could not be sent. Please try again in a minute.' } } })
  assert.ok(refused.logs.some((l) => l.includes('500')))
  const timedOut = depsOf({ failing: true })
  assert.deepEqual(await handle({ headers: await signed(body), body }, SECRET, timedOut.deps), { status: 200, body: { error: { http_code: 500, message: 'The email could not be sent. Please try again in a minute.' } } })
  assert.ok(timedOut.logs.some((l) => l.includes('TimeoutError')))
})

test('a counter that cannot answer does not lock anyone out', async () => {
  const { deps, sent, logs } = depsOf({ broken: true })
  const body = payload('magiclink')
  assert.deepEqual(await handle({ headers: await signed(body), body }, SECRET, deps), { status: 200, body: {} })
  assert.equal(sent.length, 1)
  assert.ok(logs.some((l) => l.includes('counter failed')))
})

test('a bad signature, a missing secret and a body that is not JSON are refused before anything runs', async () => {
  const body = payload('magiclink')
  const bad = depsOf()
  assert.equal((await handle({ headers: await signed(body, { secret: 'v1,whsec_' + Buffer.from('other-secret-other-secret-other!').toString('base64') }), body }, SECRET, bad.deps)).status, 401)
  assert.equal((await handle({ headers: await signed(body), body }, undefined, bad.deps)).status, 500)
  const noKey = depsOf()
  noKey.deps.apiKey = undefined
  assert.equal((await handle({ headers: await signed(body), body }, SECRET, noKey.deps)).status, 500)
  assert.equal((await handle({ headers: await signed('{'), body: '{' }, SECRET, bad.deps)).status, 400)
  assert.equal((await handle({ headers: await signed(payload('magiclink', {}, null)), body: payload('magiclink', {}, null) }, SECRET, bad.deps)).body.error !== undefined, true)
  assert.equal(bad.sent.length + bad.counted.length + noKey.sent.length, 0)
})

test('what is logged never holds the address', async () => {
  const body = payload('magiclink')
  const all: string[] = []
  for (const over of [{ status: 500 }, { failing: true }, { broken: true }]) {
    const { deps, logs } = depsOf(over)
    await handle({ headers: await signed(body), body }, SECRET, deps)
    all.push(...logs)
  }
  assert.ok(all.length >= 3)
  for (const line of all) assert.ok(!/example\.com|reader/i.test(line), line)
})

test('the SQL, the function, the deploy script and the hook script name the same things', () => {
  const sql = read('supabase/migrations/20260930100000_auth_email_limit.sql')
  const index = read('supabase/functions/auth-email/index.ts')
  assert.ok(sql.includes('function public.count_auth_email(address_hash text, cap integer, project_cap integer)'))
  assert.ok(index.includes("rpc('count_auth_email', { address_hash: addressHash, cap: HOURLY_CAP, project_cap: PROJECT_HOURLY_CAP })"))
  assert.ok(sql.includes("'reason', 'address'") && sql.includes("'reason', 'project'"))
  assert.ok(sql.includes('revoke all on function public.count_auth_email(text, integer, integer) from public, anon, authenticated'))
  assert.ok(sql.includes('grant execute on function public.count_auth_email(text, integer, integer) to service_role'))
  assert.ok(sql.includes('alter table public.auth_email_sends enable row level security'))
  assert.ok(sql.includes('revoke all on table public.auth_email_sends from public, anon, authenticated'))
  assert.ok(sql.includes("interval '1 hour'"))
  assert.ok(read('scripts/deploy-function.mts').includes("'auth-email'"))
  const hook = read('scripts/auth-hook.mts')
  assert.ok(index.includes("Deno.env.get('AUTH_EMAIL_HOOK_SECRET')") && hook.includes("'AUTH_EMAIL_HOOK_SECRET'"))
  assert.ok(hook.includes('/functions/v1/auth-email'))
  assert.ok(hook.includes("proname = 'count_auth_email'"), '--on checks the counter is in place before any code goes uncounted')
  assert.ok(hook.includes('already on'), '--on never replaces the secret under a running hook')
  const consent = read('apps/longbook-site/oauth/consent/consent.src.mts')
  assert.ok(consent.includes("error.code !== 'over_email_send_rate_limit'"), 'the consent page tells the cap from Auth\'s own limits by code, as the app does')
})
