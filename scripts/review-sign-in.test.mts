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
