import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseFeature, paragraphs, validate, loadAutomations, PROMPTS_SECTION, type Screen } from './content.mts'
import { inlineHtml, inlineMd, plainText, checkHref, promptsHtml, promptsMarkdown, promptsOmitted, misquotedPrompts, misquotedOnPage, pageText, COPY_SCRIPT, type PromptCatalogue } from './render.mts'
import { PROMPTS, PROMPT_GROUPS } from '../../packages/core/src/prompts'
import { redirectBlock, withRedirects, headersFile, unversioned, REDIRECT_BEGIN } from './seo.mts'
import { stampChrome, stampHead, emailsReadable, HEADER_BEGIN, FOOTER_BEGIN } from './chrome.mts'
import { jpegSize, readMetadata, withMetadata } from './jpeg.mts'
import { htmlToMarkdown } from './html-md.mts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..')

const SOURCE = `---
slug: sample-feature
order: 3
group: track
title: Sample feature
seo_title: Sample tracker for iPhone and Mac
description: A sample.
card: A sample card.
platforms: iphone, mac
iphone: iphone-a
mac: mac-a
aliases: sample-alias, a-longer-sample-alias
related: one, two, three
labels: Mark paid
---

The summary line.

## On the screen

**All commitments** on iPhone.

## What it does

### First

One [link](/features/one/).

### Second

Two.

## Why it exists

Because.

## Questions

### A question?

An answer.
`

test('a feature source parses into its sections', () => {
  const f = parseFeature(SOURCE, 'sample-feature.md')
  assert.equal(f.slug, 'sample-feature')
  assert.deepEqual(f.platforms, ['iphone', 'mac'])
  assert.deepEqual(f.aliases, ['sample-alias', 'a-longer-sample-alias'])
  assert.deepEqual(f.summary, ['The summary line.'])
  assert.equal(f.does.length, 2)
  assert.equal(f.does[0]!.title, 'First')
  assert.deepEqual(f.questions.map((q) => q.title), ['A question?'])
})

test('a missing section or an unknown heading fails the parse', () => {
  assert.throws(() => parseFeature(SOURCE.replace('## Why it exists\n\nBecause.\n', ''), 'x.md'), /Why it exists/)
  assert.throws(() => parseFeature(SOURCE.replace('## Questions', '## Extras'), 'x.md'), /unknown section/)
  assert.throws(() => parseFeature(SOURCE.replace('order: 3\n', 'order: 3\ncolour: red\n'), 'x.md'), /unknown frontmatter/)
})

test('lines that all start with a dash stay a list', () => {
  assert.deepEqual(paragraphs(['- a', '- b', '', 'c', 'd']), ['- a\n- b', 'c d'])
})

test('validation catches a related page that does not exist and a screen on the wrong platform', () => {
  const f = parseFeature(SOURCE, 'sample-feature.md')
  const screens = new Map<string, Screen>([
    ['iphone-a', { key: 'iphone-a', platform: 'iphone', source: null, title: 't', description: 'd' }],
    ['mac-a', { key: 'mac-a', platform: 'iphone', source: null, title: 't', description: 'd' }],
  ])
  const problems = validate([f], screens)
  assert.ok(problems.some((p) => p.includes('related "one" does not exist')))
  assert.ok(problems.some((p) => p.includes('"mac-a" is not an mac screen')))
})

test('inline copy is escaped, bolded and linked', () => {
  assert.equal(inlineHtml('A <b> & **Mark paid**'), 'A &lt;b&gt; &amp; <strong>Mark paid</strong>')
  assert.equal(inlineHtml('[Claude](/features/automate-longbook-with-claude/)'),
    '<a href="/features/automate-longbook-with-claude/">Claude</a>')
  assert.equal(inlineHtml('[site](https://example.com)'), '<a href="https://example.com" rel="noopener">site</a>')
  assert.equal(inlineHtml('`longbook.app/mcp` **x**'), '<code>longbook.app/mcp</code> <strong>x</strong>')
})

test('the Markdown copy points feature links at their .md and makes site links absolute', () => {
  assert.equal(inlineMd('[a](/features/x-y/) [b](/faq/) [c](/features/)'),
    '[a](https://longbook.app/features/x-y.md) [b](https://longbook.app/faq/) [c](https://longbook.app/features.md)')
  assert.equal(plainText('**Keep all** and [Changes](/features/x/)'), 'Keep all and Changes')
})

test('links must lead somewhere real', () => {
  const slugs = new Set(['real-one'])
  assert.equal(checkHref('/features/real-one/', slugs), null)
  assert.match(checkHref('/features/ghost/', slugs)!, /no feature/)
  assert.match(checkHref('/pricing', slugs)!, /unknown link/)
  assert.equal(checkHref('https://longbook.app/mcp', slugs), null)
})

test('redirects cover aliases, the root shorthand and the Markdown variants', () => {
  const f = parseFeature(SOURCE, 'sample-feature.md')
  const block = redirectBlock([f])
  assert.match(block, /^\/features\/sample-alias\s+\/features\/sample-feature\/\s+301!$/m)
  assert.match(block, /^\/sample-feature\s+\/features\/sample-feature\/\s+301!$/m)
  assert.match(block, /^\/a-longer-sample-alias\s+\/features\/sample-feature\/\s+301!$/m)
  assert.doesNotMatch(block, /^\/sample-alias\s/m, 'a two-word alias stays under /features/')
  assert.match(block, /^\/features\/sample-feature\/index\.html\.md\s+\/features\/sample-feature\.md\s+200$/m)
  const once = withRedirects('/a  /b  301\n', block)
  assert.equal(withRedirects(once, block), once)
  assert.equal(once.split(REDIRECT_BEGIN).length, 2)
})

test('every Markdown address is served as Markdown and names its page as canonical', () => {
  const f = parseFeature(SOURCE, 'sample-feature.md')
  const headers = headersFile([f])
  const block = headers.split('\n\n').find((b) => b.startsWith('/features/sample-feature.md\n'))!
  assert.match(block, /Content-Type: text\/markdown; charset=utf-8/)
  assert.match(block, /Link: <https:\/\/longbook\.app\/features\/sample-feature\/>; rel="canonical"/)
  assert.match(headers, /\/r\/\*\n {2}X-Robots-Tag: noindex/)
})

test('the header and footer are replaced between markers, and stamping twice changes nothing', () => {
  const page = '<body>\n<div class="top"><div>old</div></div>\n<main>x</main>\n<footer><div>old</div></footer>\n</body>'
  const once = stampChrome(page, '<div class="top">new</div>', '<footer>new</footer>')
  assert.ok(once.includes(HEADER_BEGIN) && once.includes(FOOTER_BEGIN))
  assert.ok(!once.includes('old'))
  assert.ok(once.includes('<main>x</main>'))
  assert.equal(stampChrome(once, '<div class="top">new</div>', '<footer>new</footer>'), once)
  const head = '<head>\n<script defer src="/analytics.js"></script>\n</head>'
  const withData = stampHead(head, '<script type="application/ld+json">{}</script>')
  assert.equal(stampHead(withData, '<script type="application/ld+json">{}</script>'), withData)
})

test('metadata goes into a JPEG without touching the picture', () => {
  const original = readFileSync(join(ROOT, 'apps/longbook-site/hero.jpg'))
  const meta = { title: 'A title', description: 'A description with ₹ and “quotes”', keywords: ['longbook', 'Mac'], pageUrl: 'https://longbook.app/features/x/' }
  const out = withMetadata(original, meta)
  assert.deepEqual(jpegSize(out), jpegSize(original))
  const found = readMetadata(out)
  assert.equal(found.caption, meta.description)
  assert.equal(found.hasExif, false)
  assert.match(found.xmp!, /<dc:creator><rdf:Seq><rdf:li>longbook<\/rdf:li><\/rdf:Seq><\/dc:creator>/)
  assert.match(found.xmp!, /© 2026 longbook/)
  const scan = (b: Buffer): Buffer => b.subarray(b.indexOf(Buffer.from([0xff, 0xda])))
  assert.ok(scan(out).equals(scan(original)), 'the compressed image data is byte-identical')
  assert.deepEqual(readMetadata(withMetadata(out, meta)), found, 'writing twice gives the same result')
})

test('a label and its value in two columns stay apart in the Markdown copy', () => {
  const md = htmlToMarkdown('<ul class="rows"><li><span class="k">Claude</span><span>Settings → Connectors</span></li></ul>')
  assert.equal(md, '- **Claude**: Settings → Connectors\n')
})

test('a numbered step keeps its text inside the step', () => {
  const md = htmlToMarkdown('<ol><li><h2>Install</h2><p>From the App Store.</p></li><li><h2>Open</h2></li></ol>')
  assert.equal(md, '1. ## Install\n\n   From the App Store.\n2. ## Open\n')
})

test('mockups marked data-md="skip" and page controls stay out of the Markdown copy', () => {
  const md = htmlToMarkdown('<h1>Title</h1><div data-md="skip"><p>₹12,700 · Car insurance</p></div><button>Menu</button><p>Body <a href="/faq">FAQ</a></p>')
  assert.equal(md, '# Title\n\nBody [FAQ](https://longbook.app/faq)\n')
})

test('side-by-side links and labels stay apart, and punctuation stays attached', () => {
  assert.equal(htmlToMarkdown('<p><a href="/a">SVG</a><a href="/b">PNG</a></p>'),
    '[SVG](https://longbook.app/a) [PNG](https://longbook.app/b)\n')
  assert.equal(htmlToMarkdown('<p><span>longbook</span><span>Not Longbook</span></p>'), 'longbook Not Longbook\n')
  assert.equal(htmlToMarkdown('<p>See <strong>Changes</strong>, then <em>Keep</em>.</p>'), 'See **Changes**, then *Keep*.\n')
})

test('a page body sits inside email_off once, and a page with markers of its own keeps them', () => {
  const page = '<html><body class="x">\n<p>contact@longbook.app</p>\n</body></html>'
  const once = emailsReadable(page)
  assert.equal(once, '<html><body class="x"><!--email_off-->\n<p>contact@longbook.app</p>\n<!--/email_off--></body></html>')
  assert.equal(emailsReadable(once), once)
  const own = '<body><p><!--email_off--><a>contact@longbook.app</a><!--/email_off--></p></body>'
  assert.equal(emailsReadable(own), own)
})

test('the automations page lists every catalogue prompt, and the build names any it leaves out', () => {
  const all: PromptCatalogue = { groups: PROMPT_GROUPS, prompts: PROMPTS }
  const html = promptsHtml(all)
  const md = promptsMarkdown(all).join('\n')
  assert.deepEqual(promptsOmitted(html, md, all), [])
  assert.ok(loadAutomations(join(ROOT, 'apps/longbook-site-content/automations.md')).sections.some((s) => s.title === PROMPTS_SECTION))
  assert.match(html, /data-copy="Add September month report in my longbook"/, 'a month prompt shows its example')

  const fewer: PromptCatalogue = { groups: PROMPT_GROUPS, prompts: PROMPTS.filter((p) => p.id !== 'find-bills-from-my-email') }
  assert.deepEqual(promptsOmitted(promptsHtml(fewer), promptsMarkdown(fewer).join('\n'), all), [
    'the page omits the prompt "find-bills-from-my-email"',
    'the Markdown copy omits the prompt "find-bills-from-my-email"',
  ])
  assert.deepEqual(promptsOmitted(html, md, fewer), ['the page shows a prompt "find-bills-from-my-email" that the catalogue does not have'])

  const noGroup: PromptCatalogue = { groups: PROMPT_GROUPS.filter((g) => g.id !== 'email'), prompts: PROMPTS }
  assert.equal(promptsOmitted(promptsHtml(noGroup), md, all).length, PROMPTS.filter((p) => p.group === 'email').length)
  assert.deepEqual(promptsOmitted(html.replace('data-copy="Add my statement in my longbook"', 'data-copy="Add my statements"'), md, all),
    ['the page does not show and copy "Add my statement in my longbook" for "add-my-statement"'])
})

test('a prompt quoted in the copy is in the catalogue\'s words', () => {
  assert.deepEqual(misquotedPrompts('Siri adds it with "Add an expense in my longbook".'), [])
  assert.deepEqual(misquotedPrompts('Ask “Add October month report in my longbook” each month.'), [])
  assert.deepEqual(misquotedPrompts('A "Netflix" charge.'), [])
  assert.deepEqual(misquotedPrompts('Start with "Setup my longbook".'),
    ['quotes "Setup my longbook"; the catalogue says "Read my 12-month bank statement and help me set up my longbook"'])
})

test('a month prompt carries its template, and the build accepts it with another month named', () => {
  const all: PromptCatalogue = { groups: PROMPT_GROUPS, prompts: PROMPTS }
  const html = promptsHtml(all)
  const md = promptsMarkdown(all).join('\n')
  assert.match(html, /data-copy="Add September month report in my longbook" data-template="Add \{month\} month report in my longbook"/)
  assert.match(html, /data-template="What did I spend in \{month\} in my longbook\?"/)
  const october = html.replace('<code>Add September month report in my longbook</code>', '<code>Add October month report in my longbook</code>')
    .replace('data-copy="Add September month report in my longbook"', 'data-copy="Add October month report in my longbook"')
  assert.deepEqual(promptsOmitted(october, md.replace('- "What did I spend in July in my longbook?"', '- "What did I spend in March in my longbook?"'), all), [])
  assert.deepEqual(promptsOmitted(html.replace('data-copy="Add September month report in my longbook"', 'data-copy="Add October month report in my longbook"'), md, all),
    ['the page does not show and copy "Add September month report in my longbook" for "add-a-month-report-in-my-longbook"'],
    'the words shown and the words copied must agree')
  assert.deepEqual(promptsOmitted(html.replace(' data-template="Add {month} month report in my longbook"', ''), md, all),
    ['the page does not name this month in "add-a-month-report-in-my-longbook"'])
})

test('a quote with a curly apostrophe or closing punctuation is still the catalogue\'s words', () => {
  assert.deepEqual(misquotedPrompts('Ask “What’s my next commitment in my longbook”.'), [])
  assert.deepEqual(misquotedPrompts('Say "Tidy my longbook." and it tidies.'), [])
  assert.deepEqual(misquotedPrompts('Say “Add my statement!”'), [])
  assert.deepEqual(misquotedPrompts('Ask "What did I spend in July"'), [])
})

test('a quote may be a prompt\'s title, which Claude\'s prompt menu shows', () => {
  assert.deepEqual(misquotedPrompts('Offer "Add a month report in my longbook" for the month.'), [])
  assert.deepEqual(misquotedPrompts('Pick “What did I spend in a month?” from the menu.'), [])
})

test('a month is a slot only in a prompt with a template, and matches in any case', () => {
  assert.deepEqual(misquotedPrompts('Ask "Add october month report in my longbook".'), [])
  assert.deepEqual(misquotedPrompts('Ask "What did I spend in MAY in my longbook?"'), [])
  assert.deepEqual(misquotedPrompts('Ask "Which premiums are due before March?"'), [])
  assert.deepEqual(misquotedPrompts('Ask "Which premiums are due before April?"'),
    ['quotes "Which premiums are due before April?"; the catalogue says "What renews this year in my longbook?"'])
})

test('a hand-written page copies and quotes prompts in the catalogue\'s words', () => {
  const box = (words: string): string =>
    `<div class="copy prompt"><code>${words}</code><button class="cbtn" type="button" data-copy="${words}">Copy</button></div>`
  assert.deepEqual(misquotedOnPage(box('Read my 12-month bank statement and help me set up my longbook')), [])
  assert.deepEqual(misquotedOnPage(box('Setup my longbook')), [
    'copies "Setup my longbook"; the catalogue says "Read my 12-month bank statement and help me set up my longbook"',
  ])
  assert.deepEqual(misquotedOnPage(box('Add a month report in my longbook')),
    ['copies "Add a month report in my longbook"; the catalogue says "Add September month report in my longbook"'],
    'a Copy button copies words the owner says, never the title')
  assert.deepEqual(misquotedOnPage(box('Add October month report in my longbook')), [])
  assert.deepEqual(misquotedOnPage('<div class="prompt copy wide"><code>Import my statement</code></div>'),
    ['copies "Import my statement"; the catalogue says "Add my statement in my longbook"'], 'a prompt box is found by its classes in any order')
  assert.deepEqual(misquotedOnPage('<button data-copy="https://longbook.app/mcp">Copy</button>'), [])
  assert.deepEqual(misquotedOnPage('<p>Then say &ldquo;Import my statements&rdquo;.</p>'),
    ['quotes "Import my statements"; the catalogue says "Add my statement in my longbook"'])
  assert.deepEqual(misquotedOnPage('<p title="Import my statements">Say <strong>"Add my statement"</strong>.</p>'), [],
    'an attribute is not a quote, and inline tags stay inside the quote')
  assert.deepEqual(misquotedOnPage('<script>var a = "Import my statements";</script><p>Hello</p>'), [])
  assert.deepEqual(pageText('<p>One\n two</p><p>Three &amp; four</p>'), ['One two', 'Three & four'])
})

test('a restyle alone does not change a page', () => {
  const page = (v: string): string => `<link rel="stylesheet" href="/tokens.css?v=${v}">\n<link rel="stylesheet" href="/features/features.css?v=${v}"><p>x</p>`
  assert.equal(unversioned(page('0123456789')), unversioned(page('abcdef0123')))
  assert.equal(unversioned(page('0123456789')), '<link rel="stylesheet" href="/tokens.css">\n<link rel="stylesheet" href="/features/features.css"><p>x</p>')
  assert.notEqual(unversioned(page('0123456789')), unversioned(page('0123456789').replace('<p>x</p>', '<p>y</p>')))
  const card = (v: string): string => `<meta property="og:image" content="https://longbook.app/og/faq.jpg?v=${v}">`
  assert.equal(unversioned(card('0123456789')), unversioned(card('abcdef0123')))
})

// The page's copy script run against stand-ins for the browser.
interface Node { textContent: string; attrs: Record<string, string>; parentNode?: Node; code?: Node; done?: boolean; click?: () => void }
function runCopyScript(clipboard: 'works' | 'refuses', execOk: boolean): { buttons: Node[]; said: Node; selected: () => Node | null; copied: string[] } {
  const said: Node = { textContent: '', attrs: {} }
  const copied: string[] = []
  let selected: Node | null = null
  const button = (words: string, template?: string): Node => {
    const code: Node = { textContent: words, attrs: {} }
    const box: Node = { textContent: '', attrs: {}, code }
    return { textContent: 'Copy', attrs: { 'data-copy': words, ...(template ? { 'data-template': template } : {}) }, parentNode: box }
  }
  const buttons = [button('Add September month report in my longbook', 'Add {month} month report in my longbook'), button('Tidy my longbook')]
  const element = (n: Node): object => ({
    get textContent() { return n.textContent },
    set textContent(v: string) { n.textContent = v },
    getAttribute: (k: string) => n.attrs[k] ?? null,
    setAttribute: (k: string, v: string) => { n.attrs[k] = v },
    classList: { add: () => { n.done = true }, remove: () => { n.done = false } },
    addEventListener: (_: string, fn: () => void) => { n.click = fn },
    get parentNode() { return n.parentNode ? { querySelector: () => (n.parentNode!.code ? element(n.parentNode!.code) : null), node: n.parentNode } : null },
    node: n,
  })
  const context: Record<string, unknown> = {
    setTimeout: (fn: () => void, ms: number) => (ms < 100 ? setTimeout(fn, 0) : 0),
    clearTimeout: () => {},
    Date,
    Promise,
    Error,
    Array,
    navigator: { clipboard: { writeText: (t: string) => (clipboard === 'works' ? (copied.push(t), Promise.resolve()) : Promise.reject(new Error('denied'))) } },
    document: {
      getElementById: () => element(said),
      querySelectorAll: (sel: string) => buttons.filter((b) => sel === '[data-copy]' || b.attrs['data-template']).map(element),
      createElement: () => ({ style: {}, setAttribute: () => {}, select: () => {}, parentNode: { removeChild: () => {} } }),
      body: { appendChild: () => {} },
      execCommand: () => execOk,
      createRange: () => ({ selectNodeContents(n: { node?: Node }) { (this as { n?: Node }).n = n.node } }),
    },
    getSelection: () => ({ removeAllRanges: () => { selected = null }, addRange: (r: { n?: Node }) => { selected = r.n ?? null } }),
  }
  context.window = context
  runInNewContext(COPY_SCRIPT.replace(/^<script>|<\/script>\s*$/g, ''), context)
  return { buttons, said, selected: () => selected, copied }
}
const settle = (): Promise<void> => new Promise((r) => setTimeout(r, 20))

test('the copy script names this month in a month prompt, in the words shown and copied', async () => {
  const { buttons, copied } = runCopyScript('works', false)
  const month = new Date().toLocaleString('en', { month: 'long' })
  assert.equal(buttons[0]!.attrs['data-copy'], `Add ${month} month report in my longbook`)
  assert.equal(buttons[0]!.parentNode!.code!.textContent, `Add ${month} month report in my longbook`)
  assert.equal(buttons[1]!.attrs['data-copy'], 'Tidy my longbook')
  buttons[0]!.click!()
  await settle()
  assert.deepEqual(copied, [`Add ${month} month report in my longbook`])
  assert.equal(buttons[0]!.textContent, 'Copied')
})

test('when the clipboard refuses, the copy script falls back to the copy command, then selects the words', async () => {
  const viaCommand = runCopyScript('refuses', true)
  viaCommand.buttons[1]!.click!()
  await settle()
  assert.equal(viaCommand.buttons[1]!.textContent, 'Copied')
  assert.equal(viaCommand.said.textContent, 'Copied')

  const blocked = runCopyScript('refuses', false)
  blocked.buttons[1]!.click!()
  await settle()
  assert.equal(blocked.buttons[1]!.textContent, 'Select and copy')
  assert.equal(blocked.selected(), blocked.buttons[1]!.parentNode!.code, 'the prompt\'s words are selected')
  assert.equal(blocked.said.textContent, 'Copying was blocked. The prompt is selected for you to copy.')
})

test('the ChatGPT domain challenge is served as plain text, the token alone, past every edge function', () => {
  const block = headersFile([]).split('\n\n').find((b) => b.includes('/.well-known/openai-apps-challenge\n'))
  assert.ok(block?.includes('Content-Type: text/plain; charset=utf-8'), 'the generated _headers names its type')
  const token = readFileSync(join(ROOT, 'apps/longbook-site/.well-known/openai-apps-challenge'), 'utf8')
  assert.match(token, /^\S+$/, 'one token, no newline, no wrapping')
  const edge = (name: string) => readFileSync(join(ROOT, `apps/longbook-site/netlify/edge-functions/${name}.ts`), 'utf8')
  assert.ok(edge('markdown-for-agents').includes("'/.well-known/*'"), 'the Markdown function leaves /.well-known alone')
  assert.ok(edge('mcp-explainer').includes("export const config = { path: '/mcp' }"), 'the mcp page answers /mcp only')
  const redirects = readFileSync(join(ROOT, 'apps/longbook-site/_redirects'), 'utf8')
  assert.ok(!/^\/\.well-known\/openai-apps-challenge|^\/\*\s/m.test(redirects), 'no redirect takes the path')
})
