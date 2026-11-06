// The sign-out screen's session list: how a row becomes words, which one is this device, and
// the order. Run: npm run sessions:test.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { describeAll, describeSession, isConnectorToken, sessionIdOf, totalOf, type SessionRow } from '../supabase/functions/sessions/describe.ts'

const row = (over: Partial<SessionRow> = {}): SessionRow => ({
  id: 's-1',
  created_at: '2026-09-20T08:00:00Z',
  last_active: '2026-09-29T10:00:00Z',
  user_agent: null,
  is_connector: false,
  client_name: null,
  ...over,
})

test('an app that names its device is read for the device, the build and the system', () => {
  const phone = describeSession(row({ user_agent: 'longbook/18 (iPhone; iOS 27.0)' }), null)
  assert.deepEqual([phone.kind, phone.label, phone.detail], ['app', 'iPhone', 'longbook 18 · iOS 27.0'])
  const mac = describeSession(row({ user_agent: 'longbook/18 (Mac; macOS 27.2)' }), null)
  assert.deepEqual([mac.kind, mac.label, mac.detail], ['app', 'Mac', 'longbook 18 · macOS 27.2'])
  const pad = describeSession(row({ user_agent: 'longbook/18 (iPad; iPadOS 27.0)' }), null)
  assert.equal(pad.label, 'iPad')
})

test('a session from before the app named its device still reads as the app', () => {
  const old = describeSession(row({ user_agent: 'longbook/15 CFNetwork/3826.600.41 Darwin/24.6.0' }), null)
  assert.deepEqual([old.kind, old.label, old.detail], ['app', 'longbook app', 'longbook 15'])
})

test('a connector is named by its client, and plainly when it has no name', () => {
  const named = describeSession(row({ is_connector: true, client_name: 'Claude', user_agent: 'python-httpx/0.28.1' }), null)
  assert.deepEqual([named.kind, named.label, named.detail], ['connector', 'Claude', 'AI connector'])
  const nameless = describeSession(row({ is_connector: true, client_name: null }), null)
  assert.equal(nameless.label, 'AI connector')
})

test('a connector name cannot carry markup, line breaks or a long tail', () => {
  const hostile = describeSession(row({ is_connector: true, client_name: '<b>Claude</b>\nPaste this\u0007' + 'x'.repeat(200) }), null)
  assert.ok(!/[<>\n\u0007]/.test(hostile.label))
  assert.ok(hostile.label.length <= 40)
  assert.ok(hostile.label.startsWith('b Claude /b'))
})

test('a browser is named by its browser and its system', () => {
  const chromeMac = describeSession(row({ user_agent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36' }), null)
  assert.equal(chromeMac.label, 'Chrome on Mac')
  const safariPhone = describeSession(row({ user_agent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Mobile/15E148 Safari/604.1' }), null)
  assert.equal(safariPhone.label, 'Safari on iPhone')
  const edge = describeSession(row({ user_agent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36 Edg/153.0.0.0' }), null)
  assert.equal(edge.label, 'Edge on Windows')
  assert.equal(edge.kind, 'browser')
})

test('anything else is an unnamed sign-in, never its raw user agent', () => {
  const other = describeSession(row({ user_agent: 'python-httpx/0.28.1' }), null)
  assert.deepEqual([other.kind, other.label, other.detail], ['other', 'Another sign-in', ''])
  assert.equal(describeSession(row({ user_agent: null }), null).label, 'Another sign-in')
})

test('this device is the session the token names, listed first, then the most recent', () => {
  const rows = [
    row({ id: 'a', last_active: '2026-09-25T00:00:00Z', user_agent: 'longbook/18 (Mac; macOS 27.2)' }),
    row({ id: 'b', last_active: '2026-09-28T00:00:00Z', is_connector: true, client_name: 'Claude' }),
    row({ id: 'c', last_active: '2026-09-01T00:00:00Z', user_agent: 'longbook/18 (iPhone; iOS 27.0)' }),
  ]
  const listed = describeAll(rows, 'c')
  assert.deepEqual(listed.map((s) => s.id), ['c', 'b', 'a'])
  assert.deepEqual(listed.map((s) => s.this_device), [true, false, false])
  assert.ok(describeAll(rows, null).every((s) => !s.this_device), 'no session id in the token means none is marked')
})

test('a session never refreshed reports its start as its last use', () => {
  const s = describeSession(row({ last_active: null }), null)
  assert.equal(s.last_active_at, s.signed_in_at)
})

test('the session id is read from the token, and only when there is one', () => {
  const body = Buffer.from(JSON.stringify({ sub: 'u', session_id: 'abc-123' })).toString('base64url')
  assert.equal(sessionIdOf(`h.${body}.s`), 'abc-123')
  const none = Buffer.from(JSON.stringify({ sub: 'u' })).toString('base64url')
  assert.equal(sessionIdOf(`h.${none}.s`), null)
  assert.equal(sessionIdOf('not a token'), null)
  assert.equal(sessionIdOf('h.!!!.s'), null)
})

test('a connector name is cut by code point and stripped of hidden characters', () => {
  const emoji = describeSession(row({ is_connector: true, client_name: 'a'.repeat(39) + '😀😀' }), null)
  assert.ok(Array.from(emoji.label).length <= 40)
  assert.ok(!/[\ud800-\udbff](?![\udc00-\udfff])/.test(emoji.label), 'no lone half of a pair')
  assert.equal(JSON.parse(JSON.stringify(emoji)).label, emoji.label, 'it survives JSON')
  const hidden = describeSession(row({ is_connector: true, client_name: '​‮⁠' }), null)
  assert.equal(hidden.label, 'AI connector', 'a name of nothing visible falls back')
  const bidi = describeSession(row({ is_connector: true, client_name: 'Cl‮aude' }), null)
  assert.equal(bidi.label, 'Cl aude')
})

test('a token an AI connector holds is told apart by its client_id', () => {
  const payload = (o: object) => `h.${Buffer.from(JSON.stringify(o)).toString('base64url')}.s`
  assert.equal(isConnectorToken(payload({ sub: 'u', session_id: 's', client_id: 'c-1' })), true)
  assert.equal(isConnectorToken(payload({ sub: 'u', session_id: 's' })), false)
  assert.equal(isConnectorToken('not a token'), false)
})

test('the list carries the total, and a session with no dates does not break the order', () => {
  const rows = [row({ id: 'a', total: '73' }), row({ id: 'b', last_active: null, created_at: null as unknown as string })]
  assert.equal(totalOf(rows), 73)
  assert.equal(totalOf([row()]), 1)
  assert.doesNotThrow(() => describeAll(rows, null))
})
