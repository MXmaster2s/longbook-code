// The review account's fixed code: shut without both secrets, exact on the code, loose only on
// the address's case and the code's spaces, and wired into the consent page. Run: npm run review:test.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { REVIEW_GRANT_NOTE, REVIEW_TRIES_PER_HOUR, isOn, sameText, verdict } from '../supabase/functions/review-sign-in/check.ts'

const read = (rel: string): string => readFileSync(new URL(`../${rel}`, import.meta.url), 'utf8')
const EMAIL = 'review@longbook.app'
const CODE = '48392017'

test('either secret unset, or a short code, shuts the door', () => {
  assert.equal(verdict(EMAIL, CODE, undefined, CODE), 'off')
  assert.equal(verdict(EMAIL, CODE, EMAIL, undefined), 'off')
  assert.equal(verdict(EMAIL, '1234567', EMAIL, '1234567'), 'off')
  assert.ok(isOn(EMAIL, CODE))
})

test('only the review address with the exact code is let in', () => {
  assert.equal(verdict(EMAIL, CODE, EMAIL, CODE), 'ok')
  assert.equal(verdict(' Review@Longbook.app ', '4839 2017', EMAIL, CODE), 'ok')
  assert.equal(verdict('owner@example.com', CODE, EMAIL, CODE), 'refused')
  assert.equal(verdict(EMAIL, '48392018', EMAIL, CODE), 'refused')
  assert.equal(verdict(EMAIL, CODE.slice(0, 7), EMAIL, CODE), 'refused')
  assert.equal(verdict(EMAIL, 48392017, EMAIL, CODE), 'refused')
  assert.equal(verdict(undefined, CODE, EMAIL, CODE), 'refused')
})

test('sameText compares whole strings', () => {
  assert.ok(sameText('abc', 'abc'))
  assert.ok(!sameText('abc', 'abd'))
  assert.ok(!sameText('abc', 'abcd'))
  assert.ok(!sameText('', 'a'))
})

test('the function answers a token only for the review grant, and the consent page uses it', () => {
  const index = read('supabase/functions/review-sign-in/index.ts')
  assert.ok(index.includes("Deno.env.get('REVIEW_EMAIL')") && index.includes("Deno.env.get('REVIEW_CODE')"))
  assert.ok(index.includes('REVIEW_GRANT_NOTE'), 'the grant note gates the token')
  assert.ok(index.indexOf("rpc('count_auth_email'") < index.indexOf('verdict(body.email'), 'a try is counted before the code is compared')
  assert.equal(REVIEW_TRIES_PER_HOUR, 10)
  assert.equal(REVIEW_GRANT_NOTE, 'Claude directory review account')
  assert.ok(read('scripts/deploy-function.mts').includes("'review-sign-in'"))
  const consent = read('apps/longbook-site/oauth/consent/consent.src.mts')
  assert.ok(consent.includes('/functions/v1/review-sign-in'))
  assert.ok(consent.includes("type: 'magiclink'"))
  assert.ok(read('apps/longbook-site/oauth/consent/consent.js').includes('review-sign-in'), 'the bundle is regenerated')
})

test('the consent page offers a password to the App Review address alone', async () => {
  const { APP_REVIEW_ADDRESS, mayUsePassword } = await import('../apps/longbook-site/oauth/consent/review-gate.mts')
  assert.equal(APP_REVIEW_ADDRESS, 'appreview@longbook.app')
  assert.ok(mayUsePassword('appreview@longbook.app'))
  assert.ok(mayUsePassword('  AppReview@Longbook.app '))
  for (const other of ['', 'owner@example.com', 'review@longbook.app', 'appreview@longbook.app.example.com', 'xappreview@longbook.app', 'appreview@longbook.ap']) {
    assert.equal(mayUsePassword(other), false, other)
  }
  // The same address the app and review:account use, so the password is the code they set.
  assert.ok(read('packages/swift-core/Sources/LongbookCore/AuthClient.swift').includes(`let REVIEW_EMAIL = "${APP_REVIEW_ADDRESS}"`))
  assert.ok(read('scripts/review-account.mts').includes(`const EMAIL = '${APP_REVIEW_ADDRESS}'`))
})

test('the password sign-in is reached only past the address check, and every other address still gets a code', () => {
  const consent = read('apps/longbook-site/oauth/consent/consent.src.mts')
  assert.equal(consent.split('signInWithPassword(').length - 1, 1, 'one password sign-in')
  const body = consent.slice(consent.indexOf('async function passwordSignIn'), consent.indexOf('async function decide'))
  assert.ok(body.indexOf('if (!mayUsePassword(email))') >= 0, 'the password form checks the address')
  assert.ok(body.indexOf('if (!mayUsePassword(email))') < body.indexOf('signInWithPassword('), 'before it signs in')
  const send = consent.slice(consent.indexOf('async function sendCode'), consent.indexOf('async function verifyCode'))
  assert.ok(send.indexOf('mayUsePassword(email)') < send.indexOf('signInWithOtp('), 'the review address never asks for an email code')
  assert.ok(send.includes("client.auth.signInWithOtp({ email, options: { shouldCreateUser: false } })"), 'everyone else is sent a code as before')
  const html = read('apps/longbook-site/oauth/consent/index.html')
  for (const id of ['use-password', 'pw-email', 'password', 'pw-signin', 'pw-error', 'pw-back']) assert.ok(html.includes(`id="${id}"`), id)
  assert.ok(read('apps/longbook-site/oauth/consent/consent.js').includes('signInWithPassword'), 'the bundle is regenerated')
})
