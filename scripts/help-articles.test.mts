// Website-only help text: App Store bundles and Support for them leave it out; the website,
// the direct Mac build and Support for those keep it. Run: npm run help:articles:test.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { fullText, markerProblems, restrictedText } from './help-markers.mts'
import { FULL_KNOWLEDGE, RESTRICTED_KNOWLEDGE, knowledgeFor } from '../supabase/functions/_shared/support-knowledge.ts'

interface Article { slug: string; title: string; body: string }
const read = (path: string): Article[] => JSON.parse(readFileSync(new URL(`../${path}`, import.meta.url), 'utf8'))
const restricted = read('apps/longbook/Resources/help-articles.json')
const full = read('apps/longbook/Resources/help-articles-web.json')

const PURCHASE_ARTICLES = ['what-longbook-is-and-what-it-costs', 'refunds-restoring-a-purchase-and-family-sharing', 'what-longbook-cloud-adds']
const WEBSITE_TALK = /longbook\.app(?!\/mcp)|polar|website/i
const body = (set: Article[], slug: string): string => set.find((a) => a.slug === slug)!.body

test('the App Store bundle has no website buying text and no Mac buying article', () => {
  assert.ok(!restricted.some((a) => a.slug === 'buying-longbook-for-mac'))
  for (const slug of PURCHASE_ARTICLES) assert.doesNotMatch(body(restricted, slug), WEBSITE_TALK, slug)
  for (const a of restricted) assert.doesNotMatch(a.body, /polar/i, a.slug)
})

test('the full bundle keeps the website text, without markers', () => {
  assert.ok(full.some((a) => a.slug === 'buying-longbook-for-mac'))
  assert.equal(full.length, restricted.length + 1)
  for (const slug of PURCHASE_ARTICLES) assert.match(body(full, slug), WEBSITE_TALK, slug)
  assert.match(body(full, 'refunds-restoring-a-purchase-and-family-sharing'), /Polar/)
  for (const a of [...full, ...restricted]) assert.doesNotMatch(a.body, /website-only/, a.slug)
})

test('a removed block leaves the text around it reading on', () => {
  const text = 'A.\n\n<!-- website-only -->\nB.\n<!-- /website-only -->\n\nC.\n- one\n<!-- website-only -->\n- two\n<!-- /website-only -->\n- three'
  assert.equal(restrictedText(text), 'A.\n\nC.\n- one\n- three')
  assert.equal(fullText(text), 'A.\n\nB.\n\nC.\n- one\n- two\n- three')
  assert.equal(restrictedText('<!-- website-only -->\n# T\n\nBody.'), null)
  assert.deepEqual(markerProblems(text, 'x'), [])
  assert.equal(markerProblems('<!-- website-only -->\n# T\n\n<!-- website-only -->\nB.', 'x').length, 1)
  assert.equal(markerProblems('# T\n\nB. <!-- website-only -->', 'x').length, 1)
})

test('Support picks the full articles for the website and the direct build only', () => {
  assert.equal(knowledgeFor('web'), FULL_KNOWLEDGE)
  assert.equal(knowledgeFor('direct'), FULL_KNOWLEDGE)
  for (const surface of ['app', undefined, null, '', 'WEB', 42]) assert.equal(knowledgeFor(surface), RESTRICTED_KNOWLEDGE, String(surface))
  assert.doesNotMatch(RESTRICTED_KNOWLEDGE.text, /polar/i)
  assert.ok(!RESTRICTED_KNOWLEDGE.titles.has('buying-longbook-for-mac'))
  assert.match(FULL_KNOWLEDGE.text, /Polar/)
  assert.ok(FULL_KNOWLEDGE.titles.has('buying-longbook-for-mac'))
})

test('only the direct Mac target bundles the full articles', () => {
  const yml = readFileSync(new URL('../apps/longbook/project.yml', import.meta.url), 'utf8')
  const target = (name: string): string => yml.split(/\n {2}(?=[A-Za-z-]+:\n)/).find((s) => s.startsWith(`${name}:`))!
  assert.match(target('longbook'), /excludes: \[help-articles-web\.json\]/)
  assert.doesNotMatch(target('longbook-direct'), /help-articles-web/)
  assert.doesNotMatch(target('LongbookWidget'), /- path: Resources/)
})

test('the website help pages keep the website text and show no markers', () => {
  const site = (path: string): string => readFileSync(new URL(`../apps/longbook-site/help/${path}`, import.meta.url), 'utf8')
  for (const path of ['buying-longbook-for-mac/index.html', 'buying-longbook-for-mac.md', 'refunds-restoring-a-purchase-and-family-sharing/index.html', 'refunds-restoring-a-purchase-and-family-sharing.md', 'what-longbook-cloud-adds.md', 'what-longbook-is-and-what-it-costs.md']) {
    assert.doesNotMatch(site(path), /website-only/, path)
  }
  assert.match(site('refunds-restoring-a-purchase-and-family-sharing.md'), /refund you through Polar/)
  assert.match(site('what-longbook-cloud-adds.md'), /The website doesn't sell Cloud/)
  assert.match(site('what-longbook-is-and-what-it-costs/index.html'), /from longbook\.app, write to Support/)
})
