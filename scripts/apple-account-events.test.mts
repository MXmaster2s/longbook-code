// Sign in with Apple's server-to-server notices: the JWT is Apple's, for longbook and current;
// each event does its one thing to the account it names. Also that Delete Account ends the Apple
// link through Apple's revoke endpoint. Run: npm run sessions:test.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import {
  APPLE_ISSUER,
  actionFor,
  handleAppleEvent,
  payloadOf,
  verifyAppleNotice,
  type AccountStore,
  type AppleKey,
} from '../supabase/functions/_shared/apple-account-events.ts'

const read = (rel: string): string => readFileSync(new URL(`../${rel}`, import.meta.url), 'utf8')
const NOW = new Date('2026-11-03T12:00:00Z')
const SECONDS = Math.floor(NOW.getTime() / 1000)
const SUB = '001234.abcdef0123456789abcdef0123456789.0219'
const USER = '33333333-3333-4333-8333-333333333333'

const b64url = (bytes: Uint8Array): string => Buffer.from(bytes).toString('base64url')
const text = (value: unknown): string => b64url(new TextEncoder().encode(JSON.stringify(value)))

const pair = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  true, ['sign', 'verify'],
)
const other = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  true, ['sign', 'verify'],
)
const jwk = (await crypto.subtle.exportKey('jwk', pair.publicKey)) as { n: string; e: string }
const KEYS: AppleKey[] = [{ kty: 'RSA', kid: 'apple-1', alg: 'RS256', n: jwk.n, e: jwk.e }]

async function sign(claims: Record<string, unknown>, over: { kid?: string; alg?: string; key?: CryptoKey } = {}): Promise<string> {
  const head = text({ alg: over.alg ?? 'RS256', kid: over.kid ?? 'apple-1' })
  const body = text(claims)
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', over.key ?? pair.privateKey, new TextEncoder().encode(`${head}.${body}`))
  return `${head}.${body}.${b64url(new Uint8Array(sig))}`
}

const claims = (events: unknown, over: Record<string, unknown> = {}) => ({
  iss: APPLE_ISSUER, aud: 'app.longbook.longbook', iat: SECONDS - 10, exp: SECONDS + 3600, jti: 'j1', events, ...over,
})
const keys = async () => KEYS
const verify = (token: string, extra: { keys?: (fresh: boolean) => Promise<AppleKey[]> } = {}) =>
  verifyAppleNotice(token, { keys: extra.keys ?? keys, now: NOW })

test('Apple\'s signed notice is read, with its events as Apple sends them, a JSON string', async () => {
  const token = await sign(claims(JSON.stringify({ type: 'consent-revoked', sub: SUB, event_time: SECONDS })))
  assert.deepEqual(await verify(token), { type: 'consent-revoked', sub: SUB, email: undefined, eventTime: SECONDS })
})

test('the events claim reads as an object too, as Apple\'s own examples show it', async () => {
  const token = await sign(claims({ type: 'email-disabled', sub: SUB, email: 'x@privaterelay.appleid.com', is_private_email: 'true' }))
  assert.equal((await verify(token)).email, 'x@privaterelay.appleid.com')
})

test('a token another key signed, or for another app, issuer or time, is refused', async () => {
  const events = { type: 'account-deleted', sub: SUB }
  await assert.rejects(verify(await sign(claims(events), { key: other.privateKey })), /bad signature/)
  await assert.rejects(verify(await sign(claims(events, { aud: 'com.someone.else' }))), /not for longbook/)
  await assert.rejects(verify(await sign(claims(events, { iss: 'https://example.com' }))), /not issued by Apple/)
  await assert.rejects(verify(await sign(claims(events, { exp: SECONDS - 3600 }))), /expired/)
  await assert.rejects(verify(await sign(claims(events, { iat: SECONDS + 3600 }))), /future/)
  await assert.rejects(verify(await sign(claims(events), { alg: 'HS256' })), /not signed the way Apple signs/)
  await assert.rejects(verify(await sign(claims(events), { kid: 'unknown' })), /no Apple key/)
  await assert.rejects(verify('not.a-jwt'), /not a JWT/)
  await assert.rejects(verify(await sign(claims({ type: 'consent-revoked' }))), /no event/)
})

test('a key Apple has newly rotated in is fetched again once', async () => {
  const asked: boolean[] = []
  const rotating = async (fresh: boolean) => { asked.push(fresh); return fresh ? KEYS : [] }
  const token = await sign(claims({ type: 'email-enabled', sub: SUB }))
  assert.equal((await verify(token, { keys: rotating })).type, 'email-enabled')
  assert.deepEqual(asked, [false, true])
})

test('an audience list that names longbook is accepted', async () => {
  const token = await sign(claims({ type: 'email-enabled', sub: SUB }, { aud: ['app.longbook.longbook'] }))
  assert.equal((await verify(token)).sub, SUB)
})

test('each event type has its one action', () => {
  assert.equal(actionFor('email-disabled'), 'relay_off')
  assert.equal(actionFor('email-enabled'), 'relay_on')
  assert.equal(actionFor('consent-revoked'), 'end_sessions')
  assert.equal(actionFor('account-deleted'), 'delete_account')
  assert.equal(actionFor('account-delete'), 'delete_account')
  assert.equal(actionFor('something-new'), 'ignore')
})

function fakeStore(known: string | null) {
  const calls: string[] = []
  const store: AccountStore = {
    async userForSub(sub) { calls.push(`lookup ${sub}`); return known },
    async setRelayOff(id, at) { calls.push(`relay ${id} ${at}`) },
    async endSessions(id) { calls.push(`sessions ${id}`) },
    async deleteAccount(id) { calls.push(`delete ${id}`) },
  }
  return { store, calls }
}

test('the events act on the longbook account that signed in with that Apple user', async () => {
  for (const [type, call] of [
    ['email-disabled', `relay ${USER} 2026-11-03T11:00:00.000Z`],
    ['email-enabled', `relay ${USER} null`],
    ['consent-revoked', `sessions ${USER}`],
    ['account-deleted', `delete ${USER}`],
  ] as const) {
    const { store, calls } = fakeStore(USER)
    const done = await handleAppleEvent({ type, sub: SUB, eventTime: SECONDS - 3600 }, store, NOW)
    assert.equal(done.matched, true, type)
    assert.deepEqual(calls, [`lookup ${SUB}`, call], type)
  }
})

test('an Apple user with no longbook account, or an unknown event, changes nothing', async () => {
  const none = fakeStore(null)
  assert.deepEqual(await handleAppleEvent({ type: 'account-deleted', sub: SUB }, none.store, NOW), { action: 'delete_account', matched: false })
  assert.deepEqual(none.calls, [`lookup ${SUB}`])
  const unknown = fakeStore(USER)
  assert.deepEqual(await handleAppleEvent({ type: 'something-new', sub: SUB }, unknown.store, NOW), { action: 'ignore', matched: false })
  assert.deepEqual(unknown.calls, [])
})

test('the JWT is read from a JSON body or a form', () => {
  assert.equal(payloadOf('{"payload":"a.b.c"}', 'application/json'), 'a.b.c')
  assert.equal(payloadOf('payload=a.b.c', 'application/x-www-form-urlencoded'), 'a.b.c')
  assert.equal(payloadOf('nonsense', 'text/plain'), null)
  assert.equal(payloadOf('{"other":1}', null), null)
})

test('the endpoint deletes as Delete Account does, and the migration keeps its functions to the service role', () => {
  const fn = read('supabase/functions/apple-account-events/index.ts')
  const del = read('supabase/functions/delete-account/index.ts')
  assert.ok(fn.includes('admin.auth.admin.deleteUser(userId)') && del.includes('admin.auth.admin.deleteUser(user.id)'))
  assert.ok(fn.includes("admin.rpc('apple_account_user'") && fn.includes("admin.rpc('end_account_sessions'"))
  const sql = read('supabase/migrations/20261103130000_apple_account_events.sql')
  for (const name of ['apple_account_user(text)', 'end_account_sessions(uuid)']) {
    assert.ok(sql.includes(`revoke all on function public.${name} from public, anon, authenticated;`), name)
    assert.ok(sql.includes(`grant execute on function public.${name} to service_role;`), name)
  }
  assert.ok(read('scripts/deploy-function.mts').includes("'apple-account-events'"))
})

test('Delete Account ends the Sign in with Apple link through Apple\'s revoke endpoint first', () => {
  const del = read('supabase/functions/delete-account/index.ts')
  assert.ok(del.includes("ask('token', { grant_type: 'authorization_code', code })"))
  assert.ok(del.includes("ask('revoke', { token: tokens.refresh_token, token_type_hint: 'refresh_token' })"))
  assert.ok(del.includes('https://appleid.apple.com/auth/${path}'))
  assert.ok(del.indexOf('revokeApple(body.apple_code)') < del.indexOf('admin.auth.admin.deleteUser(user.id)'), 'revoked before the account goes')
})
