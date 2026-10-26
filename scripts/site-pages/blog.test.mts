import { test } from 'node:test'
import assert from 'node:assert/strict'
import { blockHtml, blockMd, parseBlocks, parsePost, postJsonld, posterOf, validatePosts, type BlogFilms, type Still } from './blog.mts'

const FILM = '/blog/media/sample/clip.mp4'
const film = (inner: string): string[] => [`:::film ${FILM}`, ...inner.split('\n'), ':::']

test('a film block holds its description and an optional caption', () => {
  const [b] = parseBlocks(film('A 25-second film of the dashboard.\nThe dashboard, in motion.'), 'blog/x.md')
  assert.deepEqual(b, { kind: 'film', src: FILM, alt: 'A 25-second film of the dashboard.', caption: 'The dashboard, in motion.' })
  const [bare] = parseBlocks(film('A film.'), 'blog/x.md')
  assert.equal((bare as { caption: string }).caption, '')
})

test('a film block that is not closed, empty or overfull is refused', () => {
  assert.throws(() => parseBlocks([`:::film ${FILM}`, 'A film.'], 'blog/x.md'), /never closed/)
  assert.throws(() => parseBlocks(film(''), 'blog/x.md'), /description/)
  assert.throws(() => parseBlocks(film('one\ntwo\nthree'), 'blog/x.md'), /description/)
})

test('a film plays only when asked, with its poster beside it', () => {
  const [b] = parseBlocks(film('A film of "Coming up".\nCaption **here**.'), 'blog/x.md')
  const html = blockHtml(b!, new Map())
  assert.match(html, /<video controls playsinline preload="none" width="1280" height="720" poster="\/blog\/media\/sample\/clip\.jpg"/)
  assert.match(html, /aria-label="A film of &quot;Coming up&quot;\."/)
  assert.match(html, /<source src="\/blog\/media\/sample\/clip\.mp4" type="video\/mp4">/)
  assert.doesNotMatch(html, /autoplay/)
  assert.match(html, /<figcaption>Caption <strong>here<\/strong>\.<\/figcaption>/)
  assert.doesNotMatch(blockHtml(parseBlocks(film('A film.'), 'blog/x.md')[0]!, new Map()), /figcaption/)
})

test('the Markdown copy links the film, so an AI can find it', () => {
  const [b] = parseBlocks(film('A film.\nThe "dashboard".'), 'blog/x.md')
  assert.equal(blockMd(b!), `Film: [A film.](https://longbook.app${FILM} "The 'dashboard'.")`)
})

const POST = `---
slug: sample
title: Sample
seo_title: Sample post
description: A sample post.
card: A sample card.
lead: A sample lead.
date: 2026-10-16
image: /blog/media/sample/share.jpg
image_alt: Sample share
---

## A step

${film('A film.\nA caption.').join('\n')}
`
const stills = new Map<string, Still>([['/blog/media/sample/share.jpg', { width: 1200, height: 630 }]])

test('a post that names a film needs media.json to build it with its poster', () => {
  const post = parsePost(POST, 'blog/sample.md')
  const none = validatePosts([post], stills, new Set(), new Map())
  assert.ok(none.some((p) => p.includes(`media.json builds no film ${FILM}`)), none.join('\n'))
  const wrong: BlogFilms = new Map([[FILM, { poster: '/blog/media/sample/other.jpg' }]])
  assert.ok(validatePosts([post], stills, new Set(), wrong).some((p) => p.includes(posterOf(FILM))))
  const ok: BlogFilms = new Map([[FILM, { poster: posterOf(FILM) }]])
  assert.deepEqual(validatePosts([post], stills, new Set(), ok), [])
})

test('a post with a film carries it in its structured data', () => {
  const graph = (postJsonld(parsePost(POST, 'blog/sample.md'), stills) as { '@graph': Record<string, unknown>[] })['@graph']
  const video = graph.find((n) => n['@type'] === 'VideoObject')
  assert.ok(video)
  assert.equal(video.contentUrl, `https://longbook.app${FILM}`)
  assert.equal(video.thumbnailUrl, 'https://longbook.app/blog/media/sample/clip.jpg')
  assert.equal(video.uploadDate, '2026-10-16T00:00:00+05:30')
  const article = graph.find((n) => n['@type'] === 'BlogPosting') as { video?: unknown }
  assert.deepEqual(article.video, [{ '@id': `https://longbook.app${FILM}` }])
})

test('a code block keeps its lines as written, escaped on the page and fenced in the copy', () => {
  const [b] = parseBlocks(['```json', '  {', '    "app": "<longbook>"', '  }', '```'], 'blog/x.md')
  assert.deepEqual(b, { kind: 'code', lang: 'json', text: '{\n  "app": "<longbook>"\n}' })
  assert.equal(blockHtml(b!, new Map()), '<pre class="bcode"><code class="language-json">{\n  "app": "&lt;longbook&gt;"\n}</code></pre>')
  assert.equal(blockMd(b!), '```json\n{\n  "app": "<longbook>"\n}\n```')
})

test('a code block that is not closed is refused', () => {
  assert.throws(() => parseBlocks(['```json', '{}'], 'blog/x.md'), /never closed/)
})
