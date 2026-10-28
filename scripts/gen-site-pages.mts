#!/usr/bin/env -S npx tsx
// Builds the site's shared parts from apps/longbook-site-content: the header and footer on every
// page, the features section, the blog and their Markdown copies, structured data, the sitemap,
// _headers and the features block of _redirects. --check verifies instead of writing. Regenerate: npm run site:pages.
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'
import { loadAbout, loadAutomations, loadFeatures, loadScreens, validate, DOWNLOAD, GROUPS, LIMITS, ORIGIN, PROMPTS_SECTION, type Feature } from './site-pages/content.mts'
import { type Ctx, type Picture, type PromptCatalogue, featurePage, indexPage, featureMarkdown, indexMarkdown, automationsPage, automationsMarkdown, checkHref, linksIn, misquotedPrompts, misquotedOnPage, promptsOmitted, AUTOMATIONS_URL, GENERATED, attr } from './site-pages/render.mts'
import { featureJsonld, indexJsonld, automationsJsonld, homeJsonld, faqJsonld, jsonldScript, sitemap, headersFile, redirectBlock, withRedirects, shareTargets, shareAlt, unversioned, type MdPage, type SitemapEntry } from './site-pages/seo.mts'
import { stampChrome, stampHead, wrapped, emailsReadable, HEADER_BEGIN, HEADER_END, FOOTER_BEGIN, FOOTER_END } from './site-pages/chrome.mts'
import { htmlToMarkdown } from './site-pages/html-md.mts'
import { jpegSize, readMetadata } from './site-pages/jpeg.mts'
import { readBuilt, sha256, BUILT_LIST } from './site-pages/built.mts'
import { loadHelp, validateHelp, helpPage, helpIndexPage, helpMarkdown, helpIndexMarkdown, helpJsonld, helpIndexJsonld, helpUrl, HELP_URL } from './site-pages/help.mts'
import { loadPosts, validatePosts, postPage, postMarkdown, postJsonld, postPictures, postUrl, blogIndexPage, blogIndexMarkdown, blogJsonld, longDate, BLOG_URL, type BlogFilms, type Still } from './site-pages/blog.mts'
import { loadFacts, buildFacts, validateFacts, factsPage, factsMarkdown, factsJsonld, FACTS_URL, type Fact } from './site-pages/facts.mts'
import { loadReviews, validateReviews, reviewsPage, reviewsMarkdown, reviewsJsonld, REVIEWS_URL, REVIEWS_SHARE } from './site-pages/reviews.mts'
import { PROMPTS, PROMPT_GROUPS } from '../packages/core/src/prompts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SITE = join(ROOT, 'apps/longbook-site')
const CONTENT = join(ROOT, 'apps/longbook-site-content')
const CHECK = process.argv.includes('--check')
// --lint checks the sources alone and writes nothing, so several editors can run it at once.
const LINT = process.argv.includes('--lint')

// Hand-written pages that wear the shared header and footer. The shared-report viewer and the
// sign-in consent screen stand alone on purpose.
const STAMPED = ['index.html', '404.html', 'faq/index.html', 'download/index.html', 'ios/index.html',
  'source/index.html', 'contact/index.html', 'support/index.html', 'privacy-policy/index.html', 'terms/index.html', 'media-kit/index.html',
  'ready-for-the-run/index.html', 'why-we-built-longbook/index.html', 'features/upcoming-features/index.html']
const LISTED: [string, string][] = [['/', 'index.html'], ['/faq/', 'faq/index.html'],
  ['/download/', 'download/index.html'], ['/ios/', 'ios/index.html'], ['/source/', 'source/index.html'],
  ['/contact/', 'contact/index.html'], ['/support/', 'support/index.html'], ['/media-kit/', 'media-kit/index.html'],
  ['/privacy-policy/', 'privacy-policy/index.html'], ['/terms/', 'terms/index.html'],
  ['/ready-for-the-run/', 'ready-for-the-run/index.html'], ['/why-we-built-longbook/', 'why-we-built-longbook/index.html'],
  ['/features/upcoming-features/', 'features/upcoming-features/index.html']]
const SWIFT_SOURCES = ['apps/longbook/Sources', 'apps/longbook/Widget', 'packages/swift-core/Sources']
const MCP_SOURCES = ['packages/mcp/src']

interface LockEntry {
  source: string
  width: number
  height: number
  smallWidth: number
  smallHeight: number
}

const read = (p: string): string => readFileSync(p, 'utf8')
const problems: string[] = []

const features = loadFeatures(join(CONTENT, 'features'))
const automations = loadAutomations(join(CONTENT, 'automations.md'))
const about = loadAbout(join(CONTENT, 'about.md'))
const screens = loadScreens(join(CONTENT, 'screens.json'))
const lockFile = join(CONTENT, 'screens.lock.json')
const lock = (existsSync(lockFile) ? JSON.parse(read(lockFile)) : {}) as Record<string, LockEntry>
problems.push(...validate(features, screens))
const posts = loadPosts(join(CONTENT, 'blog'))
const help = loadHelp(join(CONTENT, 'help'))
const reviews = loadReviews(join(CONTENT, 'reviews.json'))
problems.push(...validateReviews(reviews, SITE))

const slugs = new Set(features.map((f) => f.slug))
for (const f of features) {
  const texts = [...f.summary, ...f.screen, ...f.why, ...f.does.flatMap((b) => b.body), ...f.questions.flatMap((q) => q.body)]
  for (const href of texts.flatMap(linksIn)) {
    const bad = checkHref(href, slugs)
    if (bad) problems.push(`${f.slug}: ${bad}`)
  }
}
const automationTexts = [...automations.summary,
  ...automations.sections.flatMap((s) => [...s.intro, ...s.blocks.flatMap((b) => b.body)])]
for (const href of automationTexts.flatMap(linksIn)) {
  const bad = checkHref(href, slugs)
  if (bad) problems.push(`automations: ${bad}`)
}
for (const slug of automations.features) if (!slugs.has(slug)) problems.push(`automations: no feature "${slug}"`)
if (`${automations.seoTitle} — longbook`.length > LIMITS.seoTitle) problems.push(`automations: title is over ${LIMITS.seoTitle} characters`)
if (automations.description.length > LIMITS.description) problems.push(`automations: description is ${automations.description.length} characters`)

function sourceText(dirs: string[], ext: string): string {
  const parts: string[] = []
  const walk = (dir: string): void => {
    for (const name of readdirSync(dir)) {
      const p = join(dir, name)
      if (statSync(p).isDirectory()) walk(p)
      else if (name.endsWith(ext)) parts.push(read(p))
    }
  }
  for (const d of dirs) if (existsSync(join(ROOT, d))) walk(join(ROOT, d))
  return parts.join('\n')
}
// A page that quotes the app must quote words the app still shows.
const swift = sourceText(SWIFT_SOURCES, '.swift')
for (const f of features) {
  for (const label of f.labels) if (!swift.includes(label)) problems.push(`${f.slug}: the app no longer says "${label}"`)
}
// And the automations page names exactly the tools the MCP server registers, no more and no fewer.
const registered = new Set([...sourceText(MCP_SOURCES, '.ts').matchAll(/registerTool\(\s*'([a-z_]+)'/g)].map((m) => m[1]!))
const named = new Set(automationTexts.flatMap((t) => [...t.matchAll(/`([a-z]+(?:_[a-z]+)*)`/g)].map((m) => m[1]!)))
if (!registered.size) problems.push('automations: found no registerTool calls in the MCP server to check the page against')
for (const n of named) if (!registered.has(n)) problems.push(`automations: the MCP server has no tool "${n}"`)
for (const r of registered) if (!named.has(r)) problems.push(`automations: the page does not name the MCP tool "${r}"`)
// It lists the whole prompt catalogue under its own section, and any prompt the copy quotes is in
// the catalogue's words.
const catalogue: PromptCatalogue = { groups: PROMPT_GROUPS, prompts: PROMPTS }
if (!automations.sections.some((s) => s.title === PROMPTS_SECTION)) problems.push(`automations: no "## ${PROMPTS_SECTION}" section to list the prompts under`)
for (const t of automationTexts) for (const m of misquotedPrompts(t)) problems.push(`automations: ${m}`)
for (const f of features) {
  for (const t of [f.description, f.card, ...f.summary, ...f.screen, ...f.why, ...f.does.flatMap((b) => b.body), ...f.questions.flatMap((q) => q.body)]) {
    for (const m of misquotedPrompts(t)) problems.push(`${f.slug}: ${m}`)
  }
}
for (const t of about.body) for (const m of misquotedPrompts(t)) problems.push(`about.md: ${m}`)
// The hand-written pages too: what their Copy buttons copy, their prompt boxes and their quotes.
for (const page of STAMPED) for (const m of misquotedOnPage(read(join(SITE, page)))) problems.push(`${page}: ${m}`)

// A page that names a film must have one that site:media builds, at the address the page plays.
const mediaList = JSON.parse(read(join(CONTENT, 'media.json'))) as { films: { out: string; poster: string }[]; stills?: { out: string; width?: number; height?: number }[] }
const filmsBuilt = new Set(mediaList.films.map((f) => f.out))
for (const f of features) if (f.film && !filmsBuilt.has(`features/media/${f.slug}.mp4`)) problems.push(`${f.slug}: names a film, but media.json builds no features/media/${f.slug}.mp4`)
// A blog post draws each picture at the size media.json gives it.
const stills = new Map<string, Still>((mediaList.stills ?? []).filter((s) => s.width && s.height)
  .map((s) => [`/${s.out}`, { width: s.width!, height: s.height! }]))
const blogFilms: BlogFilms = new Map(mediaList.films.map((f) => [`/${f.out}`, { poster: `/${f.poster}` }]))
problems.push(...validatePosts(posts, stills, slugs, blogFilms))
problems.push(...validateHelp(help))
if (reviews.length && !stills.has(REVIEWS_SHARE)) problems.push(`reviews: media.json builds no ${REVIEWS_SHARE}`)

// The facts page: its source is facts.md, and every value that changes comes from where it lives.
const FACTS_SOURCES = ['apps/longbook/Resources/changelog.json', 'apps/longbook/project.yml', 'packages/mcp/server.json',
  'apps/longbook-site/index.html', 'apps/longbook-site/media-kit/kit.json', 'apps/longbook-site/media-kit/files.json',
  'apps/longbook-site/privacy-policy.md', 'apps/longbook-site/terms.md'].map((p) => join(ROOT, p))
const facts = loadFacts(join(CONTENT, 'facts.md'))
const factsBuilt = (() => {
  const need = (what: string, m: RegExpExecArray | null | undefined): string => {
    if (!m?.[1]) problems.push(`facts: could not read ${what}`)
    return m?.[1] ?? ''
  }
  const [changelog, projectYml, serverJson, home, kitJson, filesJson, policy, terms] = FACTS_SOURCES.map(read)
  const latest = (JSON.parse(changelog!) as { version: string; build: number; date: string }[])[0]!
  const server = JSON.parse(serverJson!) as { name: string; version: string; remotes: { type: string; url: string }[]; packages: { identifier: string }[] }
  const kit = JSON.parse(kitJson!)
  const files = new Map((JSON.parse(filesJson!).files as { path: string; url: string }[]).map((f) => [f.path, f.url]))
  const price = need('the pricing section', /<div class="price" id="price">([\s\S]*?)<div class="devs">/.exec(home!))
  const tiers = [...price.matchAll(/<p>\$(\d+) · (first \d+|next \d+|after that)<\/p>/g)].map((m) => ({ usd: `$${m[1]}`, who: m[2]! }))
  if (tiers.length < 1) problems.push('facts: found no price tiers in the pricing section')
  const tierText = tiers.map((t, i) => (t.who === 'after that' ? `then ${t.usd}` : `${t.usd} for the ${t.who}${i === 0 ? ' buyers' : ''}`)).join(', ')
  const os = (k: string): string => need(`the ${k} minimum`, new RegExp(`${k}:\\s*"(\\d+)(?:\\.0)?"`).exec(projectYml!))
  const fileUrl = (path: string): string => {
    const u = files.get(path)
    if (!u) problems.push(`facts: media-kit/files.json has no ${path}`)
    return u ?? ''
  }
  const fileLinks = (list: { label: string; file: string }[]): string => list.map((f) => `[${f.label}](${fileUrl(f.file)})`).join(', ')
  const region = /hosted with Supabase in the (.+?) region, `([a-z0-9-]+)`/.exec(policy!)
  const values: Record<string, string> = {
    version: latest.version, build: String(latest.build), release_date: longDate(latest.date),
    ios_min: os('iOS'), macos_min: os('macOS'), download: DOWNLOAD,
    price_tiers: tierText, price_first: tiers[0]?.usd ?? '',
    refund_days: need('the refund days', /within (\d+) days/.exec(price)),
    cloud_price: `$${need('the Cloud price', /padd-amt n">\$(\d+) <span class="amtsub">per month/.exec(price))} a month`,
    coming_soon: need('what is coming soon', /Coming soon: ([^<]+)<\/li>/.exec(price)),
    mcp_url: server.remotes[0]?.url ?? '', mcp_transport: server.remotes[0]?.type === 'streamable-http' ? 'Streamable HTTP' : (server.remotes[0]?.type ?? ''),
    npm_package: server.packages[0]?.identifier ?? '', npm_command: `npx -y ${server.packages[0]?.identifier}@latest`,
    registry_name: server.name, mcp_version: server.version,
    mcp_tools: `${registered.size}: ${[...registered].sort().map((t) => `\`${t}\``).join(', ')}`,
    prompts_count: String(PROMPTS.length),
    spelling: kit.spelling.text, keywords: (kit.keywords as string[]).join(', '), founder: kit.founder.name,
    country: need('the country', /established in ([A-Z][a-z]+)/.exec(terms!)),
    privacy_date: need('the policy date', /This policy took effect on (\d+ [A-Z][a-z]+ \d{4})/.exec(policy!)),
    server_region: region ? `${region[1]} region, ${region[2]}` : need('the server region', null),
  }
  const groupOrder = (f: Feature): number => GROUPS.findIndex((g) => g.id === f.group)
  const featureFacts: Fact[] = [...features].sort((a, b) => groupOrder(a) - groupOrder(b) || a.order - b.order)
    .map((f) => ({ label: f.title, href: `/features/${f.slug}/`, paras: [f.card] }))
  const shotList = (p: 'iphone' | 'mac'): string => `${kit.screens[p].length} screens: ${(kit.screens[p] as { title: string }[]).map((s) => s.title).join(', ')}. [See them](/media-kit/#screenshots)`
  const filmFact = (m: { out: string; poster: string }): Fact => {
    const slug = /^features\/media\/([a-z0-9-]+)\.mp4$/.exec(m.out)?.[1]
    const f = slug ? features.find((x) => x.slug === slug) : undefined
    const name = m.out.split('/').pop()!.replace(/\.mp4$/, '').replace(/-/g, ' ')
    const title = f ? f.title : /^longbook/.test(name) ? name : name.charAt(0).toUpperCase() + name.slice(1)
    const page = f ? `/features/${f.slug}/` : `/${m.out.split('/')[0]}/`
    return { label: `Film: ${title}`, paras: [`${f?.film ? `${f.film}. ` : ''}[MP4](${ORIGIN}/${m.out}), [poster](${ORIGIN}/${m.poster}), shown on [this page](${page})`] }
  }
  const assets: Fact[] = [
    ...(kit.logos as { title: string; files: { label: string; file: string }[] }[]).map((l) => ({ label: l.title, paras: [fileLinks(l.files)] })),
    { label: 'Hero image', paras: [`${kit.hero.text} [Light](${fileUrl('images/longbook-hero-light.jpg')}), [dark](${fileUrl('images/longbook-hero-dark.jpg')})`] },
    { label: 'iPhone screenshots', paras: [shotList('iphone')] },
    { label: 'Mac screenshots', paras: [shotList('mac')] },
    { label: 'Founder photo', paras: [`[Square](${fileUrl('founder/longbook-founder-rohit-kundliwal-square.jpg')}), [wide](${fileUrl('founder/longbook-founder-rohit-kundliwal.jpg')})`] },
    ...mediaList.films.map(filmFact),
  ]
  return buildFacts(facts, { values, lists: { features: featureFacts, assets } }, problems)
})()
const factsKnown = new Set(['/', '/faq/', '/download/', '/ios/', '/automations/', '/source/', '/contact/', '/why-we-built-longbook/',
  '/privacy-policy/', '/terms/', '/mcp', '/features/', '/features/upcoming-features/', '/blog/', '/reviews/', '/help/', '/support/',
  '/media-kit/', '/facts/', '/facts.md', ...features.map((f) => `/features/${f.slug}/`), ...help.map((a) => `/help/${a.slug}/`),
  ...posts.map((p) => `/blog/${p.slug}/`), ...LISTED.map(([loc]) => loc)])
problems.push(...validateFacts(facts, factsBuilt, factsKnown))
for (const g of factsBuilt.groups) for (const x of g.facts) for (const p of x.paras) for (const m of misquotedPrompts(p)) problems.push(`facts: ${m}`)

if (LINT) {
  for (const p of problems) console.error(`  ${p}`)
  console.log(problems.length ? `site pages lint — ${problems.length} problem(s).` : `site pages lint — ${features.length} features read clean.`)
  process.exit(problems.length ? 1 : 0)
}

const picture = (key: string | null, alt: string | null): Picture | null => {
  if (!key) return null
  const s = screens.get(key)
  const l = lock[key]
  if (!s || !s.source || !l) return null
  return {
    key,
    src: `/features/img/${key}.jpg`,
    srcSmall: `/features/img/${key}-sm.jpg`,
    width: l.width,
    height: l.height,
    smallWidth: l.smallWidth,
    alt: alt ?? s.description,
    title: s.title,
  }
}

const chrome = (name: string): string => read(join(CONTENT, 'chrome', name)).trimEnd()
const footer = (pricing: string): string => wrapped(FOOTER_BEGIN, chrome('footer.html').replace('{{pricing}}', pricing), FOOTER_END)
const ctx: Ctx = {
  features,
  bySlug: new Map(features.map((f) => [f.slug, f])),
  screens,
  picture,
  about,
  header: wrapped(HEADER_BEGIN, chrome('header.html'), HEADER_END),
  footer: footer('/#price'),
  scripts: read(join(CONTENT, 'chrome/scripts.html')),
  jsonld: jsonldScript,
}

const out = new Map<string, string>()
out.set('features/index.html', indexPage(ctx, indexJsonld(ctx)))
out.set('features.md', indexMarkdown(ctx))
for (const f of features) {
  out.set(`features/${f.slug}/index.html`, featurePage(f, ctx, featureJsonld(f, ctx)))
  out.set(`features/${f.slug}.md`, featureMarkdown(f, ctx))
}
out.set('automations/index.html', automationsPage(automations, ctx, automationsJsonld(automations, ctx), catalogue))
out.set('automations.md', automationsMarkdown(automations, ctx, catalogue))
for (const m of promptsOmitted(out.get('automations/index.html')!, out.get('automations.md')!, catalogue)) problems.push(`automations: ${m}`)
out.set('blog/index.html', blogIndexPage(posts, ctx, blogJsonld(posts)))
out.set('blog.md', blogIndexMarkdown(posts, ctx))
out.set('facts/index.html', factsPage(factsBuilt, ctx, factsJsonld(factsBuilt)))
out.set('facts.md', factsMarkdown(factsBuilt))
out.set('help/index.html', helpIndexPage(help, ctx, helpIndexJsonld(help)))
out.set('help.md', helpIndexMarkdown(help, ctx))
for (const a of help) {
  out.set(`help/${a.slug}/index.html`, helpPage(a, ctx, helpJsonld(a)))
  out.set(`help/${a.slug}.md`, helpMarkdown(a))
}
if (reviews.length) {
  out.set('reviews/index.html', reviewsPage(reviews, ctx, reviewsJsonld(reviews)))
  out.set('reviews.md', reviewsMarkdown(reviews, ctx))
}
for (const p of posts) {
  out.set(`blog/${p.slug}/index.html`, postPage(p, ctx, stills, postJsonld(p, stills)))
  out.set(`blog/${p.slug}.md`, postMarkdown(p, ctx))
}

// Each listed page is also copied as Markdown at its address plus .md, from the text between its
// header and footer, and names that copy in its head. The media kit writes its own
// (scripts/gen-media-kit.mts), so its .md address leads there.
const OWN_MD: Record<string, string> = { '/media-kit/': '/media-kit/index.md' }
const mdOf = (loc: string): string => OWN_MD[loc] ?? (loc === '/' ? '/index.md' : `${loc.slice(0, -1)}.md`)
const mdPages: MdPage[] = [...LISTED.map(([loc]) => ({
  md: mdOf(loc),
  canonical: `${ORIGIN}${loc}`,
  ...(OWN_MD[loc] ? { variants: [`${loc.slice(0, -1)}.md`, `${loc}index.html.md`] } : {}),
})), { md: '/automations.md', canonical: AUTOMATIONS_URL }, { md: '/blog.md', canonical: BLOG_URL },
  { md: '/help.md', canonical: HELP_URL }, { md: '/facts.md', canonical: FACTS_URL }, ...help.map((a) => ({ md: `/help/${a.slug}.md`, canonical: helpUrl(a.slug) })),
  ...(reviews.length ? [{ md: '/reviews.md', canonical: REVIEWS_URL }] : []),
  ...posts.map((p) => ({ md: `/blog/${p.slug}.md`, canonical: postUrl(p.slug) }))]
function pageMarkdown(html: string, loc: string): string {
  // Without the media hashes, so the copy reads the same whether or not a page carries them yet.
  const body = html.slice(html.indexOf(HEADER_END) + HEADER_END.length, html.indexOf(FOOTER_BEGIN))
    .replace(/(\.(?:mp4|jpg))\?v=[0-9a-f]+/g, '$1')
  const description = /<meta name="description" content="([^"]*)">/.exec(html)?.[1]
  const lines = htmlToMarkdown(body).split('\n')
  const at = Math.max(0, lines.findIndex((l) => l.startsWith('# ')))
  const quote = description ? [`> ${description.replace(/&amp;/g, '&').replace(/&quot;/g, '"')}`, ''] : []
  return [lines[at], '', ...quote, `- Page: ${ORIGIN}${loc}`, '', ...lines.slice(0, at), ...lines.slice(at + 1)]
    .join('\n').replace(/\n{3,}/g, '\n\n')
}

const shares = shareTargets(features, automations)
for (const page of STAMPED) {
  const home = page === 'index.html'
  let html = stampChrome(read(join(SITE, page)),
    home ? chrome('header-home.html') : chrome('header.html'),
    chrome('footer.html').replace('{{pricing}}', home ? '#price' : '/#price'))
  const found = LISTED.find(([, file]) => file === page)
  const listed = found && !OWN_MD[found[0]] ? found : undefined
  const head: string[] = []
  if (listed) head.push(`<link rel="alternate" type="text/markdown" href="${ORIGIN}${mdOf(listed[0])}">`)
  if (home) head.push(jsonldScript(homeJsonld(features)))
  if (page === 'faq/index.html') head.push(jsonldScript(faqJsonld(html)))
  if (head.length) html = stampHead(html, head.join('\n'))
  // A page with a share card of its own names it; the rest keep the home page's.
  const card = shares.find((t) => found && t.path === found[0])
  if (card) {
    html = html.replace(/(<meta property="og:image" content=")[^"]*(")/, `$1${ORIGIN}/${card.out}$2`)
      .replace(/(<meta property="og:image:alt" content=")[^"]*(")/, `$1${attr(shareAlt(card))}$2`)
  }
  out.set(page, html)
  if (listed) out.set(mdOf(listed[0]).slice(1), pageMarkdown(html, listed[0]))
}

// Cloudflare tells browsers to keep a stylesheet for four hours, so a page that named one by its
// bare path could meet the stylesheet from before a deploy and draw without its rules. Each link
// carries the file's content hash instead: a changed stylesheet is a new address.
const STYLESHEETS = ['tokens.css', 'site.css', 'features/features.css']
const cssVersion = new Map(STYLESHEETS.map((p) => [p, sha256(readFileSync(join(SITE, p))).slice(0, 10)]))
// The films and pictures that site:media builds, and site:og's share cards, are cached the same way, so each address to one
// carries its hash from built.json, which is what the deploy carries.
const mediaVersion = new Map([...readBuilt(ROOT).media, ...readBuilt(ROOT).shares].map((m) => [m.path, m.sha256.slice(0, 10)]))
const withMediaVersions = (html: string): string =>
  html.replace(/(="(?:https:\/\/longbook\.app)?\/)([a-z0-9/._-]+\.(?:mp4|jpg))(?:\?v=[0-9a-f]+)?"/g,
    (whole, pre: string, p: string) => (mediaVersion.has(p) ? `${pre}${p}?v=${mediaVersion.get(p)}"` : whole))
for (const [rel, text] of out) {
  if (!rel.endsWith('.html')) continue
  out.set(rel, emailsReadable(withMediaVersions(text.replace(/href="\/(tokens\.css|site\.css|features\/features\.css)(?:\?v=[0-9a-f]+)?"/g,
    (_, p: string) => `href="/${p}?v=${cssVersion.get(p)}"`))))
}

out.set('_headers', headersFile(features, mdPages))
// The edge function that answers agents asking for Markdown reads which copy each page has.
const markdownFor: [string, string][] = [['/features/', '/features.md'],
  ...features.map((f): [string, string] => [`/features/${f.slug}/`, `/features/${f.slug}.md`]),
  ...mdPages.map((p): [string, string] => [new URL(p.canonical).pathname, p.md])]
out.set('netlify/edge-functions/lib/markdown-pages.gen.ts', [
  '// Generated by scripts/gen-site-pages.mts. Edit the generator, not this file.',
  '// Each page address and the address of its Markdown copy.',
  `export const MARKDOWN_FOR: Record<string, string> = ${JSON.stringify(Object.fromEntries(markdownFor), null, 2)}`,
  ''].join('\n'))
// Domain-level discovery for the hosted MCP server, per MCP SEP-2127.
out.set('.well-known/ai-catalog.json', `${JSON.stringify({
  specVersion: '1.0',
  entries: [{ identifier: 'urn:air:longbook.app:mcp:mcp', type: 'application/mcp-server-card+json', url: `${ORIGIN}/mcp/server-card` }],
}, null, 2)}\n`)
out.set('_redirects', withRedirects(read(join(SITE, '_redirects')), redirectBlock(features, mdPages)))

// lastmod: today, in the machine's own time zone like git's %cs, for a page this run changes or whose
// sources are uncommitted; otherwise the later of the page's last change and its sources' last commit.
// A page whose only change is a stylesheet's ?v= hash has not changed.
const today = new Date().toLocaleDateString('en-CA')
const git = (args: string[]): string => execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 << 20 })
function pageChanged(rel: string): string | null {
  const versions = git(['log', '--format=%H %cs', '--', rel]).trim().split('\n').filter(Boolean).map((l) => l.split(' ') as [string, string])
  const at = (sha: string): string | null => {
    try {
      return unversioned(git(['show', `${sha}:${rel}`]))
    } catch {
      return null
    }
  }
  let text = versions.length ? at(versions[0]![0]) : null
  for (let i = 0; i < versions.length; i++) {
    if (i === versions.length - 1) return versions[i]![1]
    const before = at(versions[i + 1]![0])
    if (text !== before) return versions[i]![1]
    text = before
  }
  return null
}
function lastmod(output: string, sources: string[]): string {
  const onDisk = existsSync(join(SITE, output)) ? read(join(SITE, output)) : null
  const made = out.get(output)
  if (made !== undefined && (onDisk === null || unversioned(onDisk) !== unversioned(made))) return today
  const page = relative(ROOT, join(SITE, output))
  const rel = sources.map((p) => relative(ROOT, p))
  try {
    if (rel.length && git(['status', '--porcelain', '--', ...rel]).trim()) return today
    if (git(['status', '--porcelain', '--', page]).trim()) {
      const committed = (() => {
        try {
          return git(['show', `HEAD:${page}`])
        } catch {
          return null
        }
      })()
      if (committed === null || onDisk === null || unversioned(committed) !== unversioned(onDisk)) return today
    }
    const dates = [pageChanged(page), rel.length ? git(['log', '-1', '--format=%cs', '--', ...rel]).trim() : '']
      .filter((d): d is string => !!d).sort()
    return dates.at(-1) ?? today
  } catch {
    return today
  }
}
const imagesOf = (f: Feature): string[] => [f.platforms.includes('iphone') ? picture(f.iphone, null) : null,
  f.platforms.includes('mac') ? picture(f.mac, null) : null].filter((p): p is Picture => !!p).map((p) => `${ORIGIN}${p.src}`)
const entries: SitemapEntry[] = [
  ...LISTED.map(([loc, file]) => ({ loc: `${ORIGIN}${loc}`, lastmod: lastmod(file, []), images: [] })),
  { loc: `${ORIGIN}/features/`, lastmod: lastmod('features/index.html', [join(CONTENT, 'features')]), images: [] },
  {
    loc: AUTOMATIONS_URL,
    lastmod: lastmod('automations/index.html', [join(CONTENT, 'automations.md'), join(CONTENT, 'features'), join(CONTENT, 'about.md'),
      join(ROOT, 'packages/core/src/prompts.ts')]),
    images: [...new Set(automations.features.flatMap((s) => imagesOf(ctx.bySlug.get(s)!)))],
  },
  ...features.map((f) => ({
    loc: `${ORIGIN}/features/${f.slug}/`,
    lastmod: lastmod(`features/${f.slug}/index.html`, [join(CONTENT, 'features', `${f.slug}.md`), join(CONTENT, 'about.md')]),
    images: imagesOf(f),
  })),
  ...(reviews.length ? [{ loc: REVIEWS_URL, lastmod: lastmod('reviews/index.html', [join(CONTENT, 'reviews.json'), join(CONTENT, 'about.md')]),
    images: [`${ORIGIN}${REVIEWS_SHARE}`] }] : []),
  { loc: HELP_URL, lastmod: lastmod('help/index.html', [join(CONTENT, 'help')]), images: [] },
  { loc: FACTS_URL, lastmod: lastmod('facts/index.html', [join(CONTENT, 'facts.md'), join(CONTENT, 'features'), join(CONTENT, 'media.json'), ...FACTS_SOURCES]), images: [] },
  ...help.map((a) => ({ loc: helpUrl(a.slug), lastmod: lastmod(`help/${a.slug}/index.html`, [join(CONTENT, 'help')]), images: [] })),
  ...(posts.length ? [{ loc: BLOG_URL, lastmod: lastmod('blog/index.html', [join(CONTENT, 'blog')]), images: [] }] : []),
  ...posts.map((p) => ({
    loc: postUrl(p.slug),
    lastmod: lastmod(`blog/${p.slug}/index.html`, [join(CONTENT, 'blog', `${p.slug}.md`), join(CONTENT, 'about.md')]),
    images: postPictures(p).map((src) => `${ORIGIN}${src}`),
  })),
]
// The media kit's entry, with its list of images, belongs to scripts/gen-media-kit.mts and is kept
// as that script wrote it.
const KIT_ENTRY = /  <url>(?:(?!<\/url>)[\s\S])*?<loc>https:\/\/longbook\.app\/media-kit\/<\/loc>[\s\S]*?<\/url>\n/
const kitEntry = KIT_ENTRY.exec(existsSync(join(SITE, 'sitemap.xml')) ? read(join(SITE, 'sitemap.xml')) : '')?.[0]
const map = sitemap(entries)
out.set('sitemap.xml', kitEntry ? map.replace(KIT_ENTRY, () => kitEntry) : map)

// Images: the screenshots and share images are built on a Mac and kept out of git, so the list in
// built.json is what CI checks. Where the files are present, each must be the one the list names,
// the size the lock says, and carry its description inside.
const built = readBuilt(ROOT)
const listed = new Map([...built.images, ...built.shares, ...built.media].map((b) => [b.path, b]))
const xmpTitle = (xmp: string | null): string | null =>
  /<dc:title><rdf:Alt><rdf:li xml:lang="x-default">([^<]*)<\/rdf:li>/.exec(xmp ?? '')?.[1]
    ?.replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&') ?? null
// A build writes the pages first and the images after, so while writing, a stale image is a note.
const notes: string[] = []
function checkBuilt(rel: string, width: number, height: number, caption: string | null, title: string | null, rebuild: string): void {
  const flag = (m: string): number => (CHECK ? problems.push(m) : notes.push(m))
  const entry = listed.get(rel)
  if (!entry) {
    flag(`${rel} is not in ${BUILT_LIST} — run: ${rebuild}`)
    return
  }
  const p = join(SITE, rel)
  if (!existsSync(p)) return
  const buf = readFileSync(p)
  if (sha256(buf) !== entry.sha256) flag(`${rel} is not the file ${BUILT_LIST} names — run: ${rebuild}`)
  const size = jpegSize(buf)
  if (size.width !== width || size.height !== height) problems.push(`${rel} is ${size.width}×${size.height}, not ${width}×${height}`)
  const meta = readMetadata(buf)
  if (!meta.xmp) problems.push(`${rel} carries no XMP`)
  if (meta.hasExif) problems.push(`${rel} still carries Exif`)
  if (caption !== null && meta.caption !== caption) problems.push(`${rel} carries a different caption — run: ${rebuild}`)
  if (title !== null && xmpTitle(meta.xmp) !== title) flag(`${rel} was rendered for another title — run: ${rebuild}`)
}
const shown = new Set(features.flatMap((f) => [f.platforms.includes('iphone') ? f.iphone : null,
  f.platforms.includes('mac') ? f.mac : null]).filter((k): k is string => !!k))
for (const key of shown) {
  const s = screens.get(key)
  if (!s?.source) continue
  const l = lock[key]
  if (!l) {
    problems.push(`${key} has a screenshot source but no built image — run: npm run site:images`)
    continue
  }
  const name = s.source.split('/').pop()!
  if (!l.source.startsWith(`${s.source.split('/')[0]}/${name}.png`) && !l.source.startsWith(`${s.source.split('/')[0]}/${name}-v`)) {
    problems.push(`${key} was built from ${l.source}, not ${s.source} — run: npm run site:images`)
  }
  checkBuilt(`features/img/${key}.jpg`, l.width, l.height, s.description, null, 'npm run site:images')
  checkBuilt(`features/img/${key}-sm.jpg`, l.smallWidth, l.smallHeight, s.description, null, 'npm run site:images')
}
for (const t of shares) checkBuilt(t.out, 1200, 630, null, t.title, 'npm run site:og')
// The blog's pictures: named in built.json, and where present, the size the page draws them.
for (const [src, s] of stills) {
  const rel = src.slice(1)
  if (!listed.has(rel)) (CHECK ? problems : notes).push(`${rel} is not in ${BUILT_LIST} — run: npm run site:media -- --stills`)
  if (!existsSync(join(SITE, rel))) continue
  const size = jpegSize(readFileSync(join(SITE, rel)))
  if (size.width !== s.width || size.height !== s.height) problems.push(`${rel} is ${size.width}×${size.height}, not ${s.width}×${s.height} as media.json says`)
}
// The blog's films and their posters: named in built.json (their bytes are the deploy's check).
for (const [src, f] of blogFilms) {
  for (const rel of [src.slice(1), f.poster.slice(1)]) {
    if (!listed.has(rel)) (CHECK ? problems : notes).push(`${rel} is not in ${BUILT_LIST} — run: npm run site:media -- --only=${src.slice(1)}`)
  }
}
const absent = [...listed.keys()].filter((rel) => !existsSync(join(SITE, rel)))

const withoutDates = (s: string): string => s.replace(/<lastmod>[^<]*<\/lastmod>/g, '')

// The apps show the policy whole in the consent sheet: the same words as the page, bundled.
out.set('../longbook/Resources/privacy-policy.md', out.get('privacy-policy.md')!)

if (CHECK) {
  for (const [rel, text] of out) {
    const p = join(SITE, rel)
    const now = existsSync(p) ? read(p) : null
    const same = rel === 'sitemap.xml' ? now !== null && withoutDates(now) === withoutDates(text) : now === text
    if (!same) problems.push(`${rel} is not what the generator makes`)
  }
  const expected = new Set(features.map((f) => f.slug))
  for (const name of readdirSync(join(SITE, 'features'))) {
    const p = join(SITE, 'features', name)
    if (statSync(p).isDirectory() && name !== 'img' && name !== 'media' && name !== 'upcoming-features' && !expected.has(name)) problems.push(`features/${name}/ has no source`)
  }
  const written = new Set(posts.map((p) => p.slug))
  for (const name of existsSync(join(SITE, 'blog')) ? readdirSync(join(SITE, 'blog')) : []) {
    if (statSync(join(SITE, 'blog', name)).isDirectory() && name !== 'media' && !written.has(name)) problems.push(`blog/${name}/ has no source`)
  }
}

if (problems.length) {
  console.error(`site pages — ${problems.length} problem(s):`)
  for (const p of problems) console.error(`  ${p}`)
  if (!CHECK) console.error('nothing written.')
  process.exit(1)
}

if (CHECK) {
  console.log(`site pages — in sync: ${features.length} features, ${posts.length} blog post(s), ${STAMPED.length} stamped pages.`)
} else {
  let written = 0
  for (const [rel, text] of out) {
    const p = join(SITE, rel)
    if (existsSync(p) && read(p) === text) continue
    mkdirSync(dirname(p), { recursive: true })
    writeFileSync(p, text)
    written++
  }
  // A feature whose source is gone takes its generated page with it; anything else is left alone.
  for (const name of readdirSync(join(SITE, 'features'))) {
    const p = join(SITE, 'features', name)
    const page = join(p, 'index.html')
    if (!statSync(p).isDirectory() || name === 'img' || name === 'media' || name === 'upcoming-features' || slugs.has(name)) continue
    if (existsSync(page) && read(page).includes(GENERATED)) {
      rmSync(p, { recursive: true })
      rmSync(`${p}.md`, { force: true })
      console.log(`removed features/${name}/, whose source is gone`)
      written++
    } else console.log(`left features/${name}/ in place: it was not made by this generator`)
  }
  console.log(`site pages — wrote ${written} file(s): ${features.length} features, ${posts.length} blog post(s), ${STAMPED.length} stamped pages.`)
  if (absent.length) console.log(`${absent.length} built image(s) are not in this checkout; site:images and site:og make them.`)
  for (const n of notes) console.log(`note: ${n}`)
}
const empty = features.flatMap((f) => (['iphone', 'mac'] as const)
  .filter((p) => f.platforms.includes(p) && !picture(f[p], null))
  .map((p) => `${f.slug} (${p === 'iphone' ? 'iPhone' : 'Mac'})`))
if (empty.length) console.log(`screens shown empty: ${empty.join(', ')}`)
