// The two sign-in emails: what they say, that only Supabase's placeholders sit in them, and that
// their colours are the site's. Run: npm run email:test.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { AUTH_EMAILS, CODE, LINK, htmlOf } from './auth-emails/templates.mts'
import { DARK, LIGHT } from '../supabase/functions/_shared/email-shell.ts'
import { OTP_SECONDS, differences, lifetimeProblem, otherChanges, restoreFields, same } from './auth-emails/live.mts'

const read = (rel: string): string => readFileSync(new URL(`../${rel}`, import.meta.url), 'utf8')
const [signUp, signIn] = AUTH_EMAILS.map((e) => ({ email: e, html: htmlOf(e) }))

/** What a reader sees: no markup, no style block, one space between words. */
const seen = (html: string): string =>
  html.replace(/<style[\s\S]*?<\/style>/g, '').replace(/<[^>]+>/g, ' ').replace(/&#\d+;/g, ' ')
    .replace(/&amp;/g, '&').replace(/\s+/g, ' ').replace(/\s([.,!?])/g, '$1')

test('each email holds only the placeholders Supabase fills in, each once', () => {
  for (const { email, html } of [signUp!, signIn!]) {
    assert.deepEqual(html.match(/\{\{[^}]*\}\}/g), email.placeholders, email.file)
    assert.ok(!html.replace(/\{\{[^}]*\}\}/g, '').match(/\{\{|\}\}/), `${email.file} has a stray double brace`)
  }
  assert.deepEqual(signUp!.email.placeholders, [CODE, LINK])
  assert.deepEqual(signIn!.email.placeholders, [CODE])
})

test('the subjects and headings say what the email is', () => {
  assert.equal(signUp!.email.subject, 'Your longbook sign-up code')
  assert.equal(signIn!.email.subject, 'Your longbook sign-in code')
  assert.ok(seen(signUp!.html).includes('Your sign-up code'))
  assert.ok(seen(signIn!.html).includes('Your sign-in code'))
  assert.ok(seen(signUp!.html).includes('finish creating your account'))
  assert.ok(seen(signIn!.html).includes('finish signing in'))
})

test('the code is set large, in monospace, on its own line', () => {
  for (const { html } of [signUp!, signIn!]) {
    assert.ok(/font-family:ui-monospace[^"]*font-size:34px[^"]*"[^>]*>\{\{ \.Token \}\}</.test(html))
  }
})

test('the sign-up email offers the link and the sign-in email does not', () => {
  assert.ok(signUp!.html.includes('href="{{ .ConfirmationURL }}"'))
  assert.ok(!signIn!.html.includes('ConfirmationURL'))
})

test('the lifetime the copy promises is the one the deploy insists on', () => {
  assert.equal(OTP_SECONDS, 3600)
  for (const { html } of [signUp!, signIn!]) assert.ok(seen(html).includes('expires in one hour'))
})

test('the small print is true: the newest code, no sharing, and an account that exists before it is confirmed', () => {
  for (const { html } of [signUp!, signIn!]) {
    assert.ok(seen(html).includes('only the newest code works'))
    assert.ok(seen(html).includes('Do not share this code with anyone. longbook will never ask you for it.'))
  }
  assert.ok(!seen(signUp!.html).includes('Nothing happens'), 'requesting a code already creates the unconfirmed account')
  assert.ok(seen(signUp!.html).includes('The address stays unconfirmed unless the code is entered or the link is opened.'))
  assert.ok(seen(signIn!.html).includes('a sign-in code was requested for this address'))
})

test('the name is lowercase everywhere and nothing is capitalised by style', () => {
  for (const { email, html } of [signUp!, signIn!]) {
    for (const part of [email.subject, seen(html)]) assert.ok(!/longbook/i.test(part.replace(/longbook/g, '')), 'a capitalised name')
    assert.ok(!/text-transform/i.test(html))
    for (const m of html.matchAll(/\b(?:alt|title|aria-label)="([^"]*)"/g)) assert.ok(!/longbook/i.test(m[1]!.replace(/longbook/g, '')))
  }
})

test('the page follows the device, reflows on a phone, and every image has alt text', () => {
  for (const { html } of [signUp!, signIn!]) {
    assert.ok(html.includes('name="color-scheme" content="light dark"'))
    const dark = /@media \(prefers-color-scheme: dark\) \{([\s\S]*?)\n  \}/.exec(html)?.[1] ?? ''
    for (const rule of ['.cv', '.cd', '.bx', '.tk', '.tm', '.lk', DARK.canvas, DARK.card, DARK.ink]) assert.ok(dark.includes(rule), `dark mode lacks ${rule}`)
    assert.ok(html.includes('@media only screen and (max-width: 620px)'))
    assert.ok(html.includes('class="co tk"') && html.includes('class="ts"') && html.includes('class="cd pad"'), 'the markup must carry the classes the dark rules name')
    assert.ok(/\.co \{ font-size: 30px !important; letter-spacing: 5px !important; \}/.test(html), 'a narrow phone needs a smaller code')
    for (const img of html.match(/<img\b[^>]*>/g) ?? []) assert.ok(/\balt="/.test(img))
    for (const href of [...html.matchAll(/(?:href|src)="([^"]+)"/g)].map((m) => m[1]!)) {
      assert.ok(href.startsWith('https://') || href === LINK, `not https: ${href}`)
    }
  }
})

test('each stays small enough for every mail app to show whole', () => {
  for (const { email, html } of [signUp!, signIn!]) assert.ok(html.length < 20_000, `${email.file} is ${html.length} bytes`)
})

test('the colours are the site\'s, in the emails here and in the purchase email', () => {
  const tokens = read('apps/longbook-site/tokens.css')
  const light = tokens.slice(tokens.indexOf(':root {'), tokens.indexOf(':root[data-appearance="dark"] {'))
  const dark = tokens.slice(tokens.indexOf(':root[data-appearance="dark"] {'), tokens.indexOf(':root[data-appearance="dark"] ::selection'))
  const value = (block: string, name: string): string => {
    const m = new RegExp(`--lb-${name}:\\s*(#[0-9A-Fa-f]{6})`).exec(block)
    assert.ok(m, `no --lb-${name}`)
    return m![1]!.toUpperCase()
  }
  const names = { canvas: 'canvas', card: 'card', sunken: 'sunken', hairline: 'hairline', ink: 'text-primary', muted: 'text-secondary', soft: 'text-tertiary' }
  for (const [mine, theirs] of Object.entries(names)) {
    assert.equal((LIGHT as Record<string, string>)[mine]!.toUpperCase(), value(light, theirs), `light ${mine}`)
    assert.equal((DARK as Record<string, string>)[mine]!.toUpperCase(), value(dark, theirs), `dark ${mine}`)
  }
  assert.equal(LIGHT.onBrand.toUpperCase(), value(light, 'on-brand'))
  assert.equal(LIGHT.link.toUpperCase(), value(light, 'brand-text'))
  assert.equal(DARK.link.toUpperCase(), value(dark, 'brand-text'))
  const purchase = read('supabase/functions/apple-purchase/purchase-email.ts').toUpperCase()
  for (const hex of [...Object.values(LIGHT), ...Object.values(DARK)]) assert.ok(purchase.includes(hex.toUpperCase()), `the purchase email lacks ${hex}`)
})

// The deploy's decisions, with stand-ins for the project's settings.
const wanted = { mailer_subjects_magic_link: 'Your longbook sign-in code', mailer_templates_magic_link_content: '<p>hello</p>\n' }

test('differences names what is not yet live, and ignores a trailing newline', () => {
  assert.deepEqual(differences({ mailer_subjects_magic_link: 'old', mailer_templates_magic_link_content: '<p>hello</p>' }, wanted), ['mailer_subjects_magic_link'])
  assert.deepEqual(differences({ mailer_subjects_magic_link: 'Your longbook sign-in code', mailer_templates_magic_link_content: '<p>hello</p>' }, wanted), [])
  assert.deepEqual(differences({}, wanted), ['mailer_subjects_magic_link', 'mailer_templates_magic_link_content'], 'a missing setting is a difference')
  assert.ok(!same('<p>hello</p> ', '<p>bye</p>'))
  assert.ok(!same(undefined, ''))
})

test('the deploy refuses unless a code lasts the hour the emails promise', () => {
  assert.equal(lifetimeProblem({ mailer_otp_exp: 3600 }), null)
  assert.match(lifetimeProblem({ mailer_otp_exp: 86400 })!, /86400 seconds/)
  assert.match(lifetimeProblem({})!, /undefined/)
  assert.match(lifetimeProblem({ mailer_otp_exp: '3600' })!, /3600 seconds/, 'a string is not the number the project uses')
})

test('a change outside the four settings is named, and the ones the project derives are not', () => {
  const own = ['a', 'b']
  const before = { a: 1, b: 2, smtp_host: 'smtp.resend.com', mailer_otp_exp: 3600, mailer_templates_custom_contents: { x: false } }
  assert.deepEqual(otherChanges(before, { ...before, a: 9, mailer_templates_custom_contents: { x: true } }, own), [])
  assert.deepEqual(otherChanges(before, { ...before, smtp_host: 'other', mailer_otp_exp: 60 }, own), ['mailer_otp_exp', 'smtp_host'])
  assert.deepEqual(otherChanges(before, { a: 1, b: 2, smtp_host: 'smtp.resend.com' }, own), ['mailer_otp_exp'], 'a setting that vanished counts')
})

test('a saved file is used only when it holds all four settings as text', () => {
  const fields = ['s1', 't1', 's2', 't2']
  assert.deepEqual(restoreFields({ s1: 'a', t1: 'b', s2: 'c', t2: 'd', extra: 'ignored' }, fields), { s1: 'a', t1: 'b', s2: 'c', t2: 'd' })
  assert.match(restoreFields({ s1: 'a', t1: 'b', s2: 'c' }, fields) as string, /does not hold t2/)
  assert.match(restoreFields({ s1: 'a', t1: 'b', s2: 'c', t2: null }, fields) as string, /does not hold t2/)
  assert.match(restoreFields(null, fields) as string, /not a saved set/)
  assert.match(restoreFields('text', fields) as string, /not a saved set/)
})
