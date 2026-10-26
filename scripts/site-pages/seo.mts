// What search engines and AI tools read besides the page itself: structured data, the
// sitemap, the Markdown headers and the redirects that keep old or guessed addresses working.
import { ORIGIN, DOWNLOAD, type Automations, type Feature } from './content.mts'
import { type Ctx, type Picture, pageUrl, mdUrl, groupName, plainText, INDEX, AUTOMATIONS_URL } from './render.mts'
import { ACQUIRE_URL, COPYRIGHT, CREATOR, RIGHTS_URL } from './jpeg.mts'

export const ORG = `${ORIGIN}/#organization`
export const SITE = `${ORIGIN}/#website`
export const APP = `${ORIGIN}/#app`

export function jsonldScript(value: object): string {
  const text = JSON.stringify(value, null, 1).replace(/</g, '\\u003c')
  return `<script type="application/ld+json">\n${text}\n</script>`
}

export const organization = {
  '@type': 'Organization',
  '@id': ORG,
  name: 'longbook',
  url: `${ORIGIN}/`,
  logo: `${ORIGIN}/apple-touch-icon.png`,
  email: 'contact@longbook.app',
}

export const website = {
  '@type': 'WebSite',
  '@id': SITE,
  url: `${ORIGIN}/`,
  name: 'longbook',
  inLanguage: 'en',
  publisher: { '@id': ORG },
}

// Described once, on the home page; every other page points at it by @id.
export function application(features?: Feature[]): object {
  return {
    '@type': 'SoftwareApplication',
    '@id': APP,
    name: 'longbook',
    url: `${ORIGIN}/`,
    description: 'A memory for your financial commitments: subscriptions, insurance, rent, loans and every payment that comes back, on iPhone and Mac, readable and writable by your AI.',
    applicationCategory: 'FinanceApplication',
    operatingSystem: 'iOS 17 or later, macOS 14 or later',
    installUrl: DOWNLOAD,
    offers: { '@type': 'AggregateOffer', lowPrice: '38', highPrice: '149', offerCount: 3, priceCurrency: 'USD' },
    publisher: { '@id': ORG },
    ...(features ? { featureList: features.map((f) => `${f.title}: ${ORIGIN}/features/${f.slug}/`) } : {}),
  }
}

function imageObject(p: Picture): object {
  return {
    '@type': 'ImageObject',
    '@id': `${ORIGIN}${p.src}`,
    contentUrl: `${ORIGIN}${p.src}`,
    url: `${ORIGIN}${p.src}`,
    name: p.title,
    caption: p.alt,
    width: p.width,
    height: p.height,
    encodingFormat: 'image/jpeg',
    creator: { '@id': ORG },
    creditText: CREATOR,
    copyrightNotice: COPYRIGHT,
    license: RIGHTS_URL,
    acquireLicensePage: ACQUIRE_URL,
  }
}

export function featureJsonld(f: Feature, ctx: Ctx): object {
  const url = pageUrl(f.slug)
  const pics = [f.platforms.includes('iphone') ? ctx.picture(f.iphone, f.iphoneAlt) : null,
    f.platforms.includes('mac') ? ctx.picture(f.mac, f.macAlt) : null].filter((p): p is Picture => !!p)
  const graph: object[] = [
    {
      '@type': 'WebPage',
      '@id': `${url}#webpage`,
      url,
      name: `${f.title} — longbook`,
      description: f.description,
      inLanguage: 'en',
      isPartOf: { '@id': SITE },
      about: { '@id': APP },
      breadcrumb: { '@id': `${url}#breadcrumb` },
      ...(pics.length ? { primaryImageOfPage: { '@id': `${ORIGIN}${pics[0]!.src}` },
        image: pics.map((p) => ({ '@id': `${ORIGIN}${p.src}` })) } : {}),
      encoding: { '@type': 'MediaObject', contentUrl: mdUrl(f.slug), encodingFormat: 'text/markdown' },
    },
    {
      '@type': 'BreadcrumbList',
      '@id': `${url}#breadcrumb`,
      itemListElement: [
        { '@type': 'ListItem', position: 1, name: 'longbook', item: `${ORIGIN}/` },
        { '@type': 'ListItem', position: 2, name: 'Features', item: `${ORIGIN}/features/` },
        { '@type': 'ListItem', position: 3, name: groupName(f.group), item: `${ORIGIN}/features/#${f.group}` },
        { '@type': 'ListItem', position: 4, name: f.title, item: url },
      ],
    },
    ...pics.map(imageObject),
    organization,
    website,
  ]
  if (f.questions.length) {
    graph.push({
      '@type': 'FAQPage',
      '@id': `${url}#questions`,
      mainEntity: f.questions.map((q) => ({
        '@type': 'Question',
        name: q.title,
        acceptedAnswer: { '@type': 'Answer', text: q.body.map(plainText).join(' ') },
      })),
    })
  }
  return { '@context': 'https://schema.org', '@graph': graph }
}

export function indexJsonld(ctx: Ctx): object {
  const url = `${ORIGIN}/features/`
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'CollectionPage',
        '@id': `${url}#webpage`,
        url,
        name: INDEX.title,
        description: INDEX.description,
        inLanguage: 'en',
        isPartOf: { '@id': SITE },
        about: { '@id': APP },
        mainEntity: { '@id': `${url}#list` },
        encoding: { '@type': 'MediaObject', contentUrl: `${ORIGIN}/features.md`, encodingFormat: 'text/markdown' },
      },
      {
        '@type': 'ItemList',
        '@id': `${url}#list`,
        numberOfItems: ctx.features.length,
        itemListElement: ctx.features.map((f, i) => ({
          '@type': 'ListItem', position: i + 1, name: f.title, url: pageUrl(f.slug),
        })),
      },
      organization,
      website,
    ],
  }
}

export interface ShareTarget {
  path: string
  out: string
  /** The image's title, written into its metadata: the page's share title. */
  title: string
  page: string
  /** The card's own words: a headline and one line under it. */
  headline: string
  line: string
  iphone: string | null
  mac: string | null
}

// The pages that share a card of their own, beyond the features: its headline, line and screens.
const PAGE_CARDS: { path: string; slug: string; title?: string; headline: string; line: string; iphone?: string; mac?: string }[] = [
  { path: '/', slug: 'home', title: 'longbook — a tool to never forget your money again', headline: 'Remember your money', line: 'Subscriptions, bills, EMIs and renewals with their next due date, on iPhone and Mac, in your own iCloud.', iphone: 'iphone-dashboard', mac: 'mac-dashboard' },
  { path: '/features/', slug: 'features', headline: INDEX.title, line: 'Every feature for iPhone and Mac, each on its own page.', iphone: 'iphone-all-commitments', mac: 'mac-commitments' },
  { path: '/blog/', slug: 'blog', headline: 'The longbook blog', line: 'How we build longbook, and what we learn on the way.' },
  { path: '/faq/', slug: 'faq', headline: 'Frequently asked questions', line: 'What longbook remembers, where your data lives, how an AI connects, and what it costs.' },
  { path: '/download/', slug: 'download', headline: 'Download longbook', line: 'For iPhone and Mac, with your longbook in your own iCloud.', iphone: 'iphone-dashboard', mac: 'mac-dashboard' },
  { path: '/ios/', slug: 'ios', headline: 'longbook for iPhone', line: 'Every subscription, bill and renewal with its next due date, on your iPhone.', iphone: 'iphone-dashboard' },
  { path: '/contact/', slug: 'contact', headline: 'Contact', line: 'Support, billing and everything else: contact@longbook.app.' },
  { path: '/privacy-policy/', slug: 'privacy-policy', headline: 'Privacy Policy', line: 'What personal data longbook collects, why, who processes it and how long it is kept.' },
  { path: '/terms/', slug: 'terms', headline: 'Terms of Service', line: 'The licence, the Cloud subscription, refunds, payment and the rest of the terms.' },
  { path: '/source/', slug: 'source', headline: 'Work on the source', line: 'longbook is licensed GPL-3.0. Codebase access is by request, for developers.' },
  { path: '/why-we-built-longbook/', slug: 'why-we-built-longbook', headline: 'Why we built longbook', line: 'One place to see every payment that comes back, and an AI that keeps it current.' },
  { path: '/features/upcoming-features/', slug: 'upcoming-features', headline: 'Upcoming features', line: 'Next: iPad, Apple Watch and Android, then Income, Available to spend and Savings.' },
]

// Every page with a share card: where it is saved, its words and the screens it shows.
export function shareTargets(features: Feature[], automations: Automations): ShareTarget[] {
  return [
    ...PAGE_CARDS.map((c) => ({ path: c.path, out: `og/${c.slug}.jpg`, title: c.title ?? c.headline, page: `${ORIGIN}${c.path}`,
      headline: c.headline, line: c.line, iphone: c.iphone ?? null, mac: c.mac ?? null })),
    { path: '/automations/', out: 'og/automations.jpg', title: `${automations.title} — longbook`, page: AUTOMATIONS_URL,
      headline: automations.title, line: 'Your AI reads your email and records the charges it finds. Every change waits in Changes for you.',
      iphone: 'iphone-automations', mac: 'mac-automations' },
    ...features.map((f) => ({ path: `/features/${f.slug}/`, out: `og/features/${f.slug}.jpg`,
      title: `${f.title} — longbook`, page: pageUrl(f.slug), headline: f.title, line: f.card, iphone: f.iphone, mac: f.mac })),
  ]
}

// What a card shows, for its og:image:alt.
export const shareAlt = (t: ShareTarget): string => `${t.headline}. ${t.line}`

export function automationsJsonld(a: Automations, ctx: Ctx): object {
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'CollectionPage',
        '@id': `${AUTOMATIONS_URL}#webpage`,
        url: AUTOMATIONS_URL,
        name: a.title,
        description: a.description,
        inLanguage: 'en',
        isPartOf: { '@id': SITE },
        about: { '@id': APP },
        mainEntity: { '@id': `${AUTOMATIONS_URL}#list` },
        encoding: { '@type': 'MediaObject', contentUrl: `${ORIGIN}/automations.md`, encodingFormat: 'text/markdown' },
      },
      {
        '@type': 'ItemList',
        '@id': `${AUTOMATIONS_URL}#list`,
        numberOfItems: a.features.length,
        itemListElement: a.features.map((slug, i) => ({
          '@type': 'ListItem', position: i + 1, name: ctx.bySlug.get(slug)!.title, url: pageUrl(slug),
        })),
      },
      organization,
      website,
    ],
  }
}

export function homeJsonld(features: Feature[]): object {
  return { '@context': 'https://schema.org', '@graph': [website, organization, application(features)] }
}

// The FAQ page's questions, read straight from its markup so the structured copy never drifts.
export function faqJsonld(html: string): object {
  const text = (s: string): string => s.replace(/<[^>]+>/g, '').replace(/&rsquo;/g, '’').replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/\s+/g, ' ').trim()
  const items = [...html.matchAll(/<details><summary[^>]*>([\s\S]*?)<span class="pl">\+<\/span><\/summary>\s*<div class="ans">([\s\S]*?)<\/div><\/details>/g)]
  if (!items.length) throw new Error('faq page: no questions found')
  return {
    '@context': 'https://schema.org',
    '@graph': [{
      '@type': 'FAQPage',
      '@id': `${ORIGIN}/faq/#questions`,
      url: `${ORIGIN}/faq/`,
      isPartOf: { '@id': SITE },
      mainEntity: items.map((m) => ({
        '@type': 'Question',
        name: text(m[1]!),
        acceptedAnswer: { '@type': 'Answer', text: text(m[2]!) },
      })),
    }, organization, website],
  }
}

export interface SitemapEntry {
  loc: string
  lastmod: string
  images: string[]
}

// A page without its stylesheets' and media's ?v= content hashes, so a restyle or a rebuilt share
// card alone does not date the page.
export const unversioned = (html: string): string =>
  html.replace(/(href="[^"]*\.css)\?v=[^"]*"/g, '$1"').replace(/(="[^"]*\.(?:jpg|mp4))\?v=[0-9a-f]+"/g, '$1"')

export function sitemap(entries: SitemapEntry[]): string {
  const rows = entries.map((e) => [
    '  <url>',
    `    <loc>${e.loc}</loc>`,
    `    <lastmod>${e.lastmod}</lastmod>`,
    ...e.images.map((i) => `    <image:image><image:loc>${i}</image:loc></image:image>`),
    '  </url>',
  ].join('\n'))
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">',
    ...rows,
    '</urlset>',
    '',
  ].join('\n')
}

const MD_HEADERS = (canonical: string): string[] => [
  '  Content-Type: text/markdown; charset=utf-8',
  `  Link: <${canonical}>; rel="canonical"`,
]

// Every response gets these. No frames from other sites, no camera, microphone or location,
// and only the origin goes along when a visitor follows a link out.
const SECURITY = [
  '/*',
  '  X-Content-Type-Options: nosniff',
  '  X-Frame-Options: SAMEORIGIN',
  '  Referrer-Policy: strict-origin-when-cross-origin',
  '  Permissions-Policy: camera=(), microphone=(), geolocation=()',
  '',
]

// How long a file may be kept. Pages never, so a deploy shows at once; a file every link
// reaches with ?v=<hash> a year, since a change is a new address; fonts a month; the rest,
// linked by a bare path, a day.
const ONE_YEAR = '  Cache-Control: public, max-age=31536000, immutable'
// The Support scripts load from every page by a bare path: checked on each visit instead.
const REVALIDATE = '  Cache-Control: public, max-age=0, must-revalidate'
const CACHE = [
  '/support.js', REVALIDATE, '',
  '/support-chat.js', REVALIDATE, '',
  '/tokens.css', ONE_YEAR, '',
  '/site.css', ONE_YEAR, '',
  '/features/features.css', ONE_YEAR, '',
  '/features/media/*', ONE_YEAR, '',
  '/ready-for-the-run/media/*', ONE_YEAR, '',
  '/fonts/*', '  Cache-Control: public, max-age=2592000', '',
  '/features/img/*', '  Cache-Control: public, max-age=86400', '',
  '/blog/media/*', '  Cache-Control: public, max-age=86400', '',
  '/og/*', '  Cache-Control: public, max-age=86400', '',
]

// A hand-written page's Markdown copy: /faq/ is copied at /faq.md, the home page at /index.md.
export interface MdPage {
  md: string
  canonical: string
  variants?: string[]
}

// The other spellings of a Markdown address that AI tools try, per the llms.txt convention.
export const mdVariants = (md: string): string[] =>
  md === '/index.md' ? ['/index.html.md'] : [md.replace(/\.md$/, '/index.md'), md.replace(/\.md$/, '/index.html.md')]

// Every address a Markdown copy answers on carries its type and points search engines back at
// the page it copies, so the two never compete in results.
export function headersFile(features: Feature[], pages: MdPage[] = []): string {
  const out = [
    '# Generated by scripts/gen-site-pages.mts. Edit the generator, not this file.',
    '',
    ...SECURITY,
    ...CACHE,
  ]
  const md = (paths: string[], canonical: string): void => {
    for (const p of paths) out.push(p, ...MD_HEADERS(canonical), '')
  }
  md(['/features.md', '/features/index.md', '/features/index.html.md'], `${ORIGIN}/features/`)
  for (const f of features) {
    md([`/features/${f.slug}.md`, `/features/${f.slug}/index.md`, `/features/${f.slug}/index.html.md`], pageUrl(f.slug))
  }
  for (const p of pages) md([p.md, ...(p.variants ?? mdVariants(p.md))], p.canonical)
  out.push('# A shared report is private to the people holding its link and password.', '/r/*',
    '  X-Robots-Tag: noindex, nofollow', '')
  return out.join('\n')
}

export const REDIRECT_BEGIN = '# features:begin — generated by scripts/gen-site-pages.mts from apps/longbook-site-content'
export const REDIRECT_END = '# features:end'

// The Markdown variants AI tools try, the other names a feature answers to, and the same
// addresses without the /features/ prefix. Every one lands on the page's canonical address.
export function redirectBlock(features: Feature[], pages: MdPage[] = []): string {
  const rows: [string, string, string][] = [
    ['/features/index.md', '/features.md', '200'],
    ['/features/index.html.md', '/features.md', '200'],
    ...pages.flatMap((p) => (p.variants ?? mdVariants(p.md)).map((v): [string, string, string] => [v, p.md, '200'])),
  ]
  for (const f of features) {
    rows.push([`/features/${f.slug}/index.md`, `/features/${f.slug}.md`, '200'])
    rows.push([`/features/${f.slug}/index.html.md`, `/features/${f.slug}.md`, '200'])
  }
  for (const f of features) {
    rows.push([`/${f.slug}`, `/features/${f.slug}/`, '301!'])
    for (const a of f.aliases) {
      rows.push([`/features/${a}`, `/features/${f.slug}/`, '301!'])
      rows.push([`/features/${a}.md`, `/features/${f.slug}.md`, '301!'])
      // A short alias like "changes" stays under /features/; the site root keeps its own names.
      if (a.split('-').length >= 3) rows.push([`/${a}`, `/features/${f.slug}/`, '301!'])
    }
  }
  const width = Math.max(...rows.map((r) => r[0].length)) + 2
  const target = Math.max(...rows.map((r) => r[1].length)) + 2
  return [REDIRECT_BEGIN, ...rows.map(([a, b, c]) => `${a.padEnd(width)}${b.padEnd(target)}${c}`), REDIRECT_END].join('\n')
}

export function withRedirects(file: string, block: string): string {
  const i = file.indexOf(REDIRECT_BEGIN)
  const j = file.indexOf(REDIRECT_END)
  if (i < 0 && j < 0) return `${file.trimEnd()}\n\n${block}\n`
  if (i < 0 || j < i) throw new Error('_redirects: the features block markers are damaged')
  return `${file.slice(0, i)}${block}${file.slice(j + REDIRECT_END.length)}`
}
