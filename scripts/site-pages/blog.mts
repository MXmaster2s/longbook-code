// The blog: posts written in Markdown in apps/longbook-site-content/blog, each built as a page in
// the features section's shell, a Markdown copy and structured data, with a card on /blog/.
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { ORIGIN, LIMITS, frontmatter } from './content.mts'
import { type Ctx, COPY_SCRIPT, aboutMd, aboutSection, attr, checkHref, esc, inlineHtml, inlineMd, linksIn, page, plainText } from './render.mts'
import { APP, ORG, SITE, organization, website } from './seo.mts'
import { ACQUIRE_URL, COPYRIGHT, CREATOR, RIGHTS_URL } from './jpeg.mts'

/** A picture that site:media builds from media.json, at the size its page draws it. */
export interface Still {
  width: number
  height: number
}

export type PostBlock =
  | { kind: 'h2' | 'h3'; text: string; id: string }
  | { kind: 'p'; text: string }
  | { kind: 'ul' | 'ol'; items: string[] }
  | { kind: 'quote'; blocks: PostBlock[] }
  | { kind: 'figure'; alt: string; src: string; caption: string }
  | { kind: 'audit'; title: string; alt: string; src: string; notes: { tag: string; text: string }[] }
  | { kind: 'film'; src: string; alt: string; caption: string }
  | { kind: 'code'; lang: string; text: string }

export interface Post {
  slug: string
  title: string
  seoTitle: string
  description: string
  card: string
  lead: string
  date: string
  updated: string
  image: string
  imageAlt: string
  body: PostBlock[]
  words: number
}

export const BLOG_URL = `${ORIGIN}/blog/`
export const postUrl = (slug: string): string => `${ORIGIN}/blog/${slug}/`
export const postMdUrl = (slug: string): string => `${ORIGIN}/blog/${slug}.md`
export const BLOG = {
  title: 'Blog',
  lead: 'How we build longbook, and what we learn on the way.',
  description: 'Notes from building longbook, the memory for your financial commitments on iPhone and Mac: how we design, write and test it, and the tools we use.',
}
const AUTHOR = 'The longbook team'
const TAGS = ['Words', 'Design', 'Type']
const FIELDS = ['slug', 'title', 'seo_title', 'description', 'card', 'lead', 'date', 'image', 'image_alt']
const FIGURE = /^!\[([^\]]+)\]\((\/[^\s)]+)(?: "([^"]*)")?\)$/

export const headingId = (text: string): string =>
  plainText(text).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')

// Blocks are runs of lines between blank lines: a heading, a picture on its own line, a list, a
// quote (every line starting with ">"), a paragraph, a screen's audit between ":::audit" and ":::",
// a film between ":::film /blog/media/<name>.mp4" and ":::" (its description, then any caption),
// or code fenced by "```", kept as written.
export function parseBlocks(lines: string[], file: string): PostBlock[] {
  const out: PostBlock[] = []
  // A ### belongs to the ## above it, so its id carries that one's: two versions on a page can each
  // have an "On the Mac" and an old link to one still finds it when a newer version is added.
  let section = ''
  let run: string[] = []
  const flush = (): void => {
    if (run.length) out.push(blockOf(run, file))
    run = []
  }
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!.trim()
    const audit = /^:::audit (.+)$/.exec(line)
    if (audit) {
      flush()
      const inner: string[] = []
      for (i++; i < lines.length && lines[i]!.trim() !== ':::'; i++) if (lines[i]!.trim()) inner.push(lines[i]!.trim())
      if (i >= lines.length) throw new Error(`${file}: ":::audit ${audit[1]}" is never closed`)
      out.push(auditOf(audit[1]!.trim(), inner, file))
      continue
    }
    const film = /^:::film (\/\S+\.mp4)$/.exec(line)
    if (film) {
      flush()
      const inner: string[] = []
      for (i++; i < lines.length && lines[i]!.trim() !== ':::'; i++) if (lines[i]!.trim()) inner.push(lines[i]!.trim())
      if (i >= lines.length) throw new Error(`${file}: ":::film ${film[1]}" is never closed`)
      if (inner.length < 1 || inner.length > 2) throw new Error(`${file}: the film ${film[1]} takes its description, then optionally a caption`)
      out.push({ kind: 'film', src: film[1]!, alt: inner[0]!, caption: inner[1] ?? '' })
      continue
    }
    const fence = /^```([a-z]*)$/.exec(line)
    if (fence) {
      flush()
      const inner: string[] = []
      for (i++; i < lines.length && lines[i]!.trim() !== '```'; i++) inner.push(lines[i]!)
      if (i >= lines.length) throw new Error(`${file}: a "${'```'}${fence[1]}" block is never closed`)
      const indent = Math.min(...inner.filter((l) => l.trim()).map((l) => /^ */.exec(l)![0].length))
      out.push({ kind: 'code', lang: fence[1]!, text: inner.map((l) => l.slice(Number.isFinite(indent) ? indent : 0)).join('\n') })
      continue
    }
    const h = /^(##|###) (.+)$/.exec(line)
    if (h) {
      flush()
      const id = headingId(h[2]!)
      if (h[1] === '##') section = id
      out.push({ kind: h[1] === '##' ? 'h2' : 'h3', text: h[2]!.trim(), id: h[1] === '###' && section ? `${section}-${id}` : id })
    } else if (line) run.push(line)
    else flush()
  }
  flush()
  return out
}

function blockOf(run: string[], file: string): PostBlock {
  if (run.every((l) => l.startsWith('>'))) return { kind: 'quote', blocks: parseBlocks(run.map((l) => l.replace(/^> ?/, '')), file) }
  const fig = run.length === 1 ? FIGURE.exec(run[0]!) : null
  if (fig) return { kind: 'figure', alt: fig[1]!, src: fig[2]!, caption: fig[3] ?? '' }
  if (run.some((l) => l.startsWith('!['))) throw new Error(`${file}: a picture stands on a line of its own: "${run[0]}"`)
  if (run.every((l) => l.startsWith('- '))) return { kind: 'ul', items: run.map((l) => l.slice(2)) }
  if (run.every((l) => /^\d+\. /.test(l))) return { kind: 'ol', items: run.map((l) => l.replace(/^\d+\. /, '')) }
  if (run.some((l) => /^(- |\d+\. )/.test(l))) throw new Error(`${file}: a list runs into a paragraph: "${run[0]}"`)
  return { kind: 'p', text: run.join(' ') }
}

function auditOf(title: string, lines: string[], file: string): PostBlock {
  const fig = lines.length ? FIGURE.exec(lines[0]!) : null
  if (!fig) throw new Error(`${file}: the audit "${title}" opens with its screenshot`)
  const notes = lines.slice(1).map((l) => {
    const m = /^- ([A-Za-z]+): (.+)$/.exec(l)
    if (!m || !TAGS.includes(m[1]!)) throw new Error(`${file}: in the audit "${title}", "${l}" is not "- ${TAGS.join('|')}: comment"`)
    return { tag: m[1]!, text: m[2]! }
  })
  if (!notes.length) throw new Error(`${file}: the audit "${title}" has no comments`)
  return { kind: 'audit', title, alt: fig[1]!, src: fig[2]!, notes }
}

const textsOf = (blocks: PostBlock[]): string[] => blocks.flatMap((b) => {
  switch (b.kind) {
    case 'h2': case 'h3': return [b.text]
    case 'p': return [b.text]
    case 'ul': case 'ol': return b.items
    case 'quote': return textsOf(b.blocks)
    case 'figure': case 'film': return [b.caption]
    case 'audit': return [b.title, ...b.notes.map((n) => n.text)]
    case 'code': return []
  }
})
const picturesIn = (blocks: PostBlock[]): string[] => blocks.flatMap((b) =>
  b.kind === 'figure' || b.kind === 'audit' ? [b.src] : b.kind === 'quote' ? picturesIn(b.blocks) : [])

export function parsePost(text: string, file: string): Post {
  const { data, body } = frontmatter(text, file)
  for (const k of FIELDS) if (!data[k]) throw new Error(`${file}: no ${k}`)
  for (const k of Object.keys(data)) if (!FIELDS.includes(k) && k !== 'updated') throw new Error(`${file}: unknown field "${k}"`)
  for (const k of ['date', 'updated']) {
    if (data[k] && !/^\d{4}-\d{2}-\d{2}$/.test(data[k]!)) throw new Error(`${file}: ${k} is not a YYYY-MM-DD date`)
  }
  const blocks = parseBlocks(body.split('\n'), file)
  const words = [data.lead!, ...textsOf(blocks)].map(plainText).join(' ').split(/\s+/).filter(Boolean).length
  return {
    slug: data.slug!,
    title: data.title!,
    seoTitle: data.seo_title!,
    description: data.description!,
    card: data.card!,
    lead: data.lead!,
    date: data.date!,
    updated: data.updated ?? data.date!,
    image: data.image!,
    imageAlt: data.image_alt!,
    body: blocks,
    words,
  }
}

/** Newest first. */
export function loadPosts(dir: string): Post[] {
  if (!existsSync(dir)) return []
  const posts = readdirSync(dir).filter((n) => n.endsWith('.md')).sort().map((n) => {
    const p = parsePost(readFileSync(join(dir, n), 'utf8'), `blog/${n}`)
    if (`${p.slug}.md` !== n) throw new Error(`blog/${n}: slug "${p.slug}" does not match the file name`)
    return p
  })
  return posts.sort((a, b) => (a.date === b.date ? (a.slug < b.slug ? -1 : 1) : a.date < b.date ? 1 : -1))
}

const filmsIn = (blocks: PostBlock[]): Extract<PostBlock, { kind: 'film' }>[] => blocks.flatMap((b) =>
  b.kind === 'film' ? [b] : b.kind === 'quote' ? filmsIn(b.blocks) : [])

export const postPictures = (p: Post): string[] => [p.image, ...new Set(picturesIn(p.body))]
/** A film's poster frame is built beside it, with the same name. */
export const posterOf = (src: string): string => src.replace(/\.mp4$/, '.jpg')

/** The films media.json builds for the blog, by address, with the poster each is built with. */
export type BlogFilms = Map<string, { poster: string }>

export function validatePosts(posts: Post[], stills: Map<string, Still>, features: Set<string>, films: BlogFilms = new Map()): string[] {
  const problems: string[] = []
  const slugs = new Set(posts.map((p) => p.slug))
  for (const p of posts) {
    const at = `blog/${p.slug}`
    if (`${p.seoTitle} — longbook`.length > LIMITS.seoTitle) problems.push(`${at}: seo_title is over ${LIMITS.seoTitle} characters with " — longbook"`)
    if (p.description.length > LIMITS.description) problems.push(`${at}: description is ${p.description.length} characters`)
    if (p.card.length > LIMITS.card) problems.push(`${at}: card is ${p.card.length} characters`)
    if (p.updated < p.date) problems.push(`${at}: updated is before date`)
    const share = stills.get(p.image)
    if (!share) problems.push(`${at}: media.json builds no ${p.image}`)
    else if (share.width !== 1200 || share.height !== 630) problems.push(`${at}: ${p.image} is not 1200×630`)
    for (const src of picturesIn(p.body)) if (!stills.has(src)) problems.push(`${at}: media.json builds no ${src} with a width and height`)
    for (const f of filmsIn(p.body)) {
      const built = films.get(f.src)
      if (!built) problems.push(`${at}: media.json builds no film ${f.src}`)
      else if (built.poster !== posterOf(f.src)) problems.push(`${at}: the film ${f.src} must be built with its poster at ${posterOf(f.src)}`)
    }
    for (const href of [p.lead, ...textsOf(p.body)].flatMap(linksIn)) {
      const bad = checkHref(href, features, slugs)
      if (bad) problems.push(`${at}: ${bad}`)
    }
    const ids = p.body.filter((b) => b.kind === 'h2' || b.kind === 'h3').map((b) => (b as { id: string }).id)
    for (const id of new Set(ids.filter((id, i) => ids.indexOf(id) !== i))) problems.push(`${at}: two headings make the id "${id}"`)
  }
  return problems
}

// What the TL;DR button copies: the post's Markdown copy, which an AI can fetch and read whole.
export const tldrPrompt = (p: Post): string => `Read ${postMdUrl(p.slug)} and summarise it for me in 5 bullet points.`

export const readingMinutes = (p: Post): number => Math.max(1, Math.round(p.words / 230))
export const longDate = (iso: string): string =>
  new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' })

function picture(src: string, alt: string, s: Still): string {
  return `<img src="${src}" width="${s.width}" height="${s.height}" alt="${attr(alt)}" loading="lazy" decoding="async">`
}

export function blockHtml(b: PostBlock, stills: Map<string, Still>): string {
  switch (b.kind) {
    case 'h2': case 'h3': return `<${b.kind} id="${b.id}">${inlineHtml(b.text)}</${b.kind}>`
    case 'p': return `<p>${inlineHtml(b.text)}</p>`
    case 'ul': case 'ol': return `<${b.kind}>${b.items.map((i) => `<li>${inlineHtml(i)}</li>`).join('')}</${b.kind}>`
    case 'quote': return `<blockquote>${b.blocks.map((x) => blockHtml(x, stills)).join('')}</blockquote>`
    case 'figure': {
      const s = stills.get(b.src)!
      return `<figure class="bfig">${picture(b.src, b.alt, s)}` +
        `${b.caption ? `<figcaption>${inlineHtml(b.caption)}</figcaption>` : ''}</figure>`
    }
    case 'film':
      // A film plays only when asked: sound on, no autoplay, nothing fetched before the play button.
      return `<figure class="bfig bfilm"><div class="film"><video controls playsinline preload="none" width="1280" height="720" ` +
        `poster="${posterOf(b.src)}" aria-label="${attr(b.alt)}"><source src="${b.src}" type="video/mp4"></video></div>` +
        `${b.caption ? `<figcaption>${inlineHtml(b.caption)}</figcaption>` : ''}</figure>`
    case 'code': return `<pre class="bcode"><code${b.lang ? ` class="language-${b.lang}"` : ''}>${esc(b.text)}</code></pre>`
    case 'audit': {
      // A phone screen sits beside its comments; a Mac window is wide enough to sit above them.
      const s = stills.get(b.src)!
      return `<figure class="baud${s.height > s.width ? ' phone' : ''}"><div class="bshot">${picture(b.src, b.alt, s)}</div>` +
        `<figcaption><p class="btitle">${esc(b.title)}</p><p class="bby">Claude’s comments</p><ul>` +
        b.notes.map((n) => `<li><span class="btag ${n.tag.toLowerCase()}">${n.tag}</span><span>${inlineHtml(n.text)}</span></li>`).join('') +
        '</ul></figcaption></figure>'
    }
  }
}

export function postPage(p: Post, ctx: Ctx, stills: Map<string, Still>, jsonld: object): string {
  const h2s = p.body.filter((b): b is Extract<PostBlock, { kind: 'h2' }> => b.kind === 'h2')
  const toc = h2s.length > 2
    ? `<nav class="btoc" aria-label="In this post"><p>In this post</p><ol>` +
      h2s.map((h) => `<li><a href="#${h.id}">${inlineHtml(h.text)}</a></li>`).join('') + '</ol></nav>'
    : ''
  const main = [
    '<main class="fp bp"><div class="fwrap">',
    '<article class="post" aria-labelledby="post-title">',
    `<nav class="crumbs" aria-label="Breadcrumb"><ol><li><a href="/blog/">Blog</a></li><li aria-current="page">${esc(p.title)}</li></ol></nav>`,
    `<header class="bhero"><h1 id="post-title">${esc(p.title)}</h1><p class="lead">${inlineHtml(p.lead)}</p>` +
      `<p class="bmeta">${AUTHOR} · <time datetime="${p.date}">${longDate(p.date)}</time> · ${readingMinutes(p)} min read</p>` +
      `<div class="tldr"><button class="btn" type="button" data-copy="${attr(tldrPrompt(p))}">TL;DR using your AI</button>` +
      `<p>Feeling lazy to read? Ask your AI to summarise.</p><code class="sr">${esc(tldrPrompt(p))}</code>` +
      '<p id="said" class="sr" aria-live="polite"></p></div></header>',
    toc,
    `<div class="prose">\n${p.body.map((b) => blockHtml(b, stills)).join('\n')}\n</div>`,
    '</article>',
    aboutSection(ctx),
    '</div></main>',
  ].filter(Boolean).join('\n')
  return page({
    title: `${p.seoTitle} — longbook`,
    description: p.description,
    canonical: postUrl(p.slug),
    markdown: postMdUrl(p.slug),
    ogTitle: p.title,
    ogImage: `${ORIGIN}${p.image}`,
    ogAlt: p.imageAlt,
    jsonld: ctx.jsonld(jsonld),
    article: { published: p.date, modified: p.updated },
  }, main, { ...ctx, scripts: `${ctx.scripts}${COPY_SCRIPT}` })
}

function postCard(p: Post): string {
  return `<a class="fcard bcard" href="/blog/${p.slug}/"><div class="bthumb">` +
    `<img src="${p.image}" width="1200" height="630" alt="${attr(p.imageAlt)}" loading="lazy" decoding="async"></div>` +
    `<div class="cbody"><h2>${esc(p.title)}</h2><p class="ctext">${esc(p.card)}</p>` +
    `<p class="plat"><time datetime="${p.date}">${longDate(p.date)}</time> · ${readingMinutes(p)} min read</p></div></a>`
}

export function blogIndexPage(posts: Post[], ctx: Ctx, jsonld: object): string {
  const main = [
    '<main class="ip bp">',
    `<section class="ihero"><h1>${BLOG.title}</h1><p class="lead">${esc(BLOG.lead)}</p></section>`,
    '<div class="fwrap">',
    `<div class="cards bcards">${posts.map(postCard).join('')}</div>`,
    aboutSection(ctx),
    '</div></main>',
  ].join('\n')
  return page({
    title: `${BLOG.title} — longbook`,
    description: BLOG.description,
    canonical: BLOG_URL,
    markdown: `${ORIGIN}/blog.md`,
    ogTitle: `The longbook ${BLOG.title.toLowerCase()}`,
    ogImage: `${ORIGIN}/og/blog.jpg`,
    ogAlt: 'The longbook blog. How we build longbook, and what we learn on the way.',
    jsonld: ctx.jsonld(jsonld),
  }, main, ctx)
}

export function blockMd(b: PostBlock): string {
  switch (b.kind) {
    case 'h2': return `## ${inlineMd(b.text)}`
    case 'h3': return `### ${inlineMd(b.text)}`
    case 'p': return inlineMd(b.text)
    case 'ul': return b.items.map((i) => `- ${inlineMd(i)}`).join('\n')
    case 'ol': return b.items.map((i, n) => `${n + 1}. ${inlineMd(i)}`).join('\n')
    case 'quote': return b.blocks.map(blockMd).join('\n\n').split('\n').map((l) => (l ? `> ${l}` : '>')).join('\n')
    case 'figure': return `![${b.alt}](${ORIGIN}${b.src}${b.caption ? ` "${b.caption.replace(/"/g, "'")}"` : ''})`
    case 'film': return `Film: [${b.alt}](${ORIGIN}${b.src}${b.caption ? ` "${b.caption.replace(/"/g, "'")}"` : ''})`
    case 'code': return ['```' + b.lang, b.text, '```'].join('\n')
    case 'audit': return [`**${b.title}**`, '', `![${b.alt}](${ORIGIN}${b.src})`, '', 'Claude’s comments:', '',
      ...b.notes.map((n) => `- ${n.tag}: ${inlineMd(n.text)}`)].join('\n')
  }
}

export function postMarkdown(p: Post, ctx: Ctx): string {
  const out = [
    `# ${p.title}`, '',
    `> ${inlineMd(p.lead)}`, '',
    `- Page: ${postUrl(p.slug)}`,
    `- Published: ${longDate(p.date)}`,
    ...(p.updated !== p.date ? [`- Updated: ${longDate(p.updated)}`] : []),
    `- By: ${AUTHOR}`, '',
    ...p.body.flatMap((b) => [blockMd(b), '']),
    `- [All posts on the longbook blog](${ORIGIN}/blog.md)`, '',
    ...aboutMd(ctx),
  ]
  return out.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n'
}

export function blogIndexMarkdown(posts: Post[], ctx: Ctx): string {
  const out = [`# ${BLOG.title}`, '', `> ${BLOG.lead}`, '', `- Page: ${BLOG_URL}`, '', '## Posts', '',
    ...posts.map((p) => `- [${p.title}](${postMdUrl(p.slug)}): ${p.card} (${longDate(p.date)})`), '', ...aboutMd(ctx)]
  return out.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n'
}

function imageObject(src: string, s: Still, caption: string): object {
  return {
    '@type': 'ImageObject',
    '@id': `${ORIGIN}${src}`,
    contentUrl: `${ORIGIN}${src}`,
    url: `${ORIGIN}${src}`,
    caption,
    width: s.width,
    height: s.height,
    encodingFormat: 'image/jpeg',
    creator: { '@id': ORG },
    creditText: CREATOR,
    copyrightNotice: COPYRIGHT,
    license: RIGHTS_URL,
    acquireLicensePage: ACQUIRE_URL,
  }
}

function videoObject(f: Extract<PostBlock, { kind: 'film' }>, p: Post): object {
  return {
    '@type': 'VideoObject',
    '@id': `${ORIGIN}${f.src}`,
    name: f.alt,
    description: f.alt,
    contentUrl: `${ORIGIN}${f.src}`,
    thumbnailUrl: `${ORIGIN}${posterOf(f.src)}`,
    // Google wants a time and a zone: the post's day, from midnight India time, where it is written.
    uploadDate: `${p.date}T00:00:00+05:30`,
    encodingFormat: 'video/mp4',
    inLanguage: 'en',
    creator: { '@id': ORG },
  }
}

export function postJsonld(p: Post, stills: Map<string, Still>): object {
  const url = postUrl(p.slug)
  const alts = new Map<string, string>([[p.image, p.imageAlt]])
  const walk = (blocks: PostBlock[]): void => {
    for (const b of blocks) {
      if (b.kind === 'figure' || b.kind === 'audit') alts.set(b.src, b.alt)
      if (b.kind === 'quote') walk(b.blocks)
    }
  }
  walk(p.body)
  const pictures = postPictures(p)
  const films = filmsIn(p.body)
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'WebPage',
        '@id': `${url}#webpage`,
        url,
        name: p.title,
        description: p.description,
        inLanguage: 'en',
        isPartOf: { '@id': SITE },
        breadcrumb: { '@id': `${url}#breadcrumb` },
        primaryImageOfPage: { '@id': `${ORIGIN}${p.image}` },
        encoding: { '@type': 'MediaObject', contentUrl: postMdUrl(p.slug), encodingFormat: 'text/markdown' },
      },
      {
        '@type': 'BlogPosting',
        '@id': `${url}#article`,
        headline: p.title,
        description: p.description,
        url,
        datePublished: p.date,
        dateModified: p.updated,
        inLanguage: 'en',
        wordCount: p.words,
        author: { '@id': ORG },
        publisher: { '@id': ORG },
        about: { '@id': APP },
        mainEntityOfPage: { '@id': `${url}#webpage` },
        isPartOf: { '@id': `${BLOG_URL}#blog` },
        image: pictures.map((src) => ({ '@id': `${ORIGIN}${src}` })),
        ...(films.length ? { video: films.map((f) => ({ '@id': `${ORIGIN}${f.src}` })) } : {}),
      },
      {
        '@type': 'BreadcrumbList',
        '@id': `${url}#breadcrumb`,
        itemListElement: [
          { '@type': 'ListItem', position: 1, name: 'longbook', item: `${ORIGIN}/` },
          { '@type': 'ListItem', position: 2, name: BLOG.title, item: BLOG_URL },
          { '@type': 'ListItem', position: 3, name: p.title, item: url },
        ],
      },
      ...pictures.map((src) => imageObject(src, stills.get(src)!, alts.get(src)!)),
      ...films.map((f) => videoObject(f, p)),
      organization,
      website,
    ],
  }
}

export function blogJsonld(posts: Post[]): object {
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'CollectionPage',
        '@id': `${BLOG_URL}#webpage`,
        url: BLOG_URL,
        name: `The longbook ${BLOG.title.toLowerCase()}`,
        description: BLOG.description,
        inLanguage: 'en',
        isPartOf: { '@id': SITE },
        mainEntity: { '@id': `${BLOG_URL}#blog` },
        encoding: { '@type': 'MediaObject', contentUrl: `${ORIGIN}/blog.md`, encodingFormat: 'text/markdown' },
      },
      {
        '@type': 'Blog',
        '@id': `${BLOG_URL}#blog`,
        url: BLOG_URL,
        name: `The longbook ${BLOG.title.toLowerCase()}`,
        inLanguage: 'en',
        publisher: { '@id': ORG },
        blogPost: posts.map((p) => ({ '@id': `${postUrl(p.slug)}#article`, '@type': 'BlogPosting', headline: p.title,
          url: postUrl(p.slug), datePublished: p.date })),
      },
      organization,
      website,
    ],
  }
}
