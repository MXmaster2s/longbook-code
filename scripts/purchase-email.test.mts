// The purchase email's words, its guards and its two variants. Run: npm run email:test.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { renderPurchaseEmail } from '../supabase/functions/apple-purchase/purchase-email.ts'

const buyer = { email: 'alex.morgan@example.com', purchasedAt: new Date('2026-09-29T06:49:04Z'), majorVersion: 1 }

/** What a reader sees: no markup, no style block, one space between words. */
const seen = (html: string): string =>
  html.replace(/<style[\s\S]*?<\/style>/g, '').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/&copy;/g, '©').replace(/&#\d+;/g, ' ').replace(/\s+/g, ' ').replace(/\s([.,!?])/g, '$1')

test('the headline, the line under it and the thank-you are the owner\'s words', () => {
  const { html, text } = renderPurchaseEmail(buyer)
  for (const line of ['Your longbook one-time license is now active!', 'Purchased version 1 on 29 September 2026',
    'Thank you for purchasing longbook!']) {
    assert.ok(seen(html).includes(line), `html lacks: ${line}`)
    assert.ok(text.includes(line), `text lacks: ${line}`)
  }
})

test('the subject names the license without the exclamation', () => {
  assert.equal(renderPurchaseEmail(buyer).subject, 'Your longbook license is now active')
})

test('the date is the purchase day in UTC and the footer year follows it', () => {
  const late = renderPurchaseEmail({ ...buyer, purchasedAt: new Date('2026-12-31T23:59:59Z') })
  assert.ok(late.text.includes('Purchased version 1 on 31 December 2026'))
  assert.ok(late.text.includes('© 2026 longbook'))
  const early = renderPurchaseEmail({ ...buyer, purchasedAt: new Date('2027-01-01T00:00:00Z') })
  assert.ok(early.text.includes('Purchased version 1 on 1 January 2027'))
  assert.ok(early.text.includes('© 2027 longbook'))
})

test('the version follows the license that was bought', () => {
  const two = renderPurchaseEmail({ ...buyer, majorVersion: 2 })
  assert.ok(two.text.includes('Purchased version 2 on'))
  assert.ok(two.text.includes('updates to version 2'))
})

test('the buyer\'s address is escaped in the page and plain in the text', () => {
  const email = 'a&b"<i>@example.com'
  const { html, text } = renderPurchaseEmail({ ...buyer, email })
  assert.ok(!html.includes('<i>'), 'markup in an address must not become markup')
  assert.ok(html.includes('a&amp;b&quot;&lt;i&gt;@example.com'))
  assert.ok(text.includes(`Account: ${email}`))
})

test('a TestFlight purchase says so, and a real one points at Apple\'s receipt', () => {
  const real = renderPurchaseEmail({ ...buyer, environment: 'Production' })
  assert.equal(real.subject, 'Your longbook license is now active')
  assert.ok(seen(real.html).includes('Apple emails a receipt for every App Store purchase'))
  assert.ok(real.html.includes('href="https://reportaproblem.apple.com"'))
  assert.ok(!seen(real.html).includes('test purchase'))

  const sandbox = renderPurchaseEmail({ ...buyer, environment: 'Sandbox' })
  assert.equal(sandbox.subject, '[Test purchase] Your longbook license is now active')
  assert.ok(seen(sandbox.html).includes('This is a test purchase made in TestFlight. Nothing was charged.'))
  assert.ok(sandbox.text.includes('Nothing was charged.'))
  assert.ok(!sandbox.html.includes('reportaproblem.apple.com'), 'no receipt exists for a test purchase')
})

test('the name is lowercase everywhere, and nothing is capitalised by style', () => {
  for (const environment of ['Production', 'Sandbox']) {
    const { subject, html, text } = renderPurchaseEmail({ ...buyer, environment })
    for (const part of [subject, seen(html), text]) assert.ok(!/longbook/i.test(part.replace(/longbook/g, '')), 'a capitalised name')
    assert.ok(!/text-transform/i.test(html))
    const attributes = [...html.matchAll(/\b(?:alt|title|aria-label)="([^"]*)"/g)].map((m) => m[1]!)
    for (const value of attributes) assert.ok(!/longbook/i.test(value.replace(/longbook/g, '')), `a capitalised name in an attribute: ${value}`)
  }
})

test('the page follows the device\'s appearance and every link is https', () => {
  const { html } = renderPurchaseEmail(buyer)
  assert.ok(html.includes('name="color-scheme" content="light dark"'))
  assert.ok(html.includes('@media (prefers-color-scheme: dark)'))
  const dark = /@media \(prefers-color-scheme: dark\) \{([\s\S]*?)\n  \}/.exec(html)?.[1] ?? ''
  for (const rule of ['.cv', '.cd', '.tk', '.tm', '.lk', '#0D1115', '#14171D', '#D3D8DE']) assert.ok(dark.includes(rule), `dark mode lacks ${rule}`)
  const links = [...html.matchAll(/(?:href|src)="([^"]+)"/g)].map((m) => m[1]!)
  assert.ok(links.length >= 3)
  for (const link of links) assert.ok(link.startsWith('https://'), `not https: ${link}`)
  assert.ok(links.includes('https://longbook.app/automations/'))
})

test('every image has an alt attribute, and the text version holds no markup', () => {
  const { html, text } = renderPurchaseEmail(buyer)
  for (const img of html.match(/<img\b[^>]*>/g) ?? []) assert.ok(/\balt="/.test(img), `no alt: ${img}`)
  assert.ok(!/<[a-z][^>]*>/i.test(text))
})

test('the same words go to both versions', () => {
  const { html, text } = renderPurchaseEmail(buyer)
  for (const line of text.split('\n').map((l) => l.trim()).filter((l) => l && l !== '--' && !l.startsWith('https://'))) {
    const heard = line.replace(/^[A-Za-z ]+: /, '').replace(/https:\/\//g, '')
    assert.ok(seen(html).includes(heard.replace(/\s+/g, ' ')), `the page lacks: ${line}`)
  }
})

test('the receipt link is a whole address in the text, and the preheader is long enough to hide the body', () => {
  const { html, text } = renderPurchaseEmail(buyer)
  assert.ok(text.includes('You can also find it at https://reportaproblem.apple.com\n'), 'no scheme, or a full stop that would be swallowed')
  const hidden = /display:none[^>]*>([^<]*)</.exec(html)?.[1] ?? ''
  assert.ok(hidden.replace(/&#\d+;/g, ' ').length > 140, 'the inbox preview would reach into the body')
})

test('the button carries its padding where Outlook reads it', () => {
  assert.ok(renderPurchaseEmail(buyer).html.includes('mso-padding-alt:14px 26px'))
})

test('the module needs no runtime of its own, so the function, tests and preview all load it', () => {
  const source = readFileSync(new URL('../supabase/functions/apple-purchase/purchase-email.ts', import.meta.url), 'utf8')
  const code = source.replace(/\/\/.*$/gm, '')
  assert.ok(!/\bDeno\b|from 'node:|require\(/.test(code))
})
