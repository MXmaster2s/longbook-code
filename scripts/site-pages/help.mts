// The help articles on longbook.app/help/: the same files longbook Support answers from
// (apps/longbook-site-content/help), each a page and a Markdown copy, grouped on /help/.
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { ORIGIN } from './content.mts'
import { type Ctx, aboutMd, aboutSection, esc, inlineHtml, page } from './render.mts'
import { type PostBlock, blockHtml, blockMd, parseBlocks } from './blog.mts'
import { ORG, SITE, organization, website } from './seo.mts'

type HelpBlock = PostBlock | { kind: 'table'; head: string[]; rows: string[][] }

export interface HelpArticle {
  slug: string
  number: number
  title: string
  body: HelpBlock[]
}

export const HELP_URL = `${ORIGIN}/help/`
export const helpUrl = (slug: string): string => `${ORIGIN}/help/${slug}/`
export const helpMdUrl = (slug: string): string => `${ORIGIN}/help/${slug}.md`
export const HELP = {
  title: 'Help',
  lead: 'Answers to questions about longbook. Support in the app answers from these same articles.',
  description: 'longbook help: getting started, importing statements, connecting Claude or ChatGPT, purchases and Cloud, privacy, and troubleshooting.',
}

/** The groups on /help/, by article number. Every article sits in exactly one. */
const GROUPS: { name: string; numbers: number[] }[] = [
  { name: 'Getting started', numbers: [1, 2, 9, 28, 33] },
  { name: 'Using longbook', numbers: [10, 11, 12, 13, 14, 15, 16, 29, 19, 20, 31] },
  { name: 'Statements and your AI', numbers: [3, 17, 4, 21, 22, 23, 24, 25, 26, 27] },
  { name: 'Purchase, account and Cloud', numbers: [5, 6, 7] },
  { name: 'Privacy and your data', numbers: [18, 30, 8] },
  { name: 'When something goes wrong', numbers: [32] },
]

const cells = (line: string): string[] => line.replace(/^\||\|$/g, '').split('|').map((c) => c.trim())

/** Blog blocks, plus tables: a run of lines that all start with "|", its second line the rule. */
function blocksOf(lines: string[], file: string): HelpBlock[] {
  const out: HelpBlock[] = []
  let prose: string[] = []
  for (let i = 0; i < lines.length; i++) {
    if (!lines[i]!.trim().startsWith('|')) { prose.push(lines[i]!); continue }
    out.push(...parseBlocks(prose, file))
    prose = []
    const run: string[] = []
    for (; i < lines.length && lines[i]!.trim().startsWith('|'); i++) run.push(lines[i]!.trim())
    i--
    if (run.length < 2 || !/^\|[\s|:-]+\|$/.test(run[1]!)) throw new Error(`${file}: a table needs a header row and a rule`)
    out.push({ kind: 'table', head: cells(run[0]!), rows: run.slice(2).map(cells) })
  }
  out.push(...parseBlocks(prose, file))
  return out
}

export function loadHelp(dir: string): HelpArticle[] {
  return readdirSync(dir).filter((n) => /^\d\d-.+\.md$/.test(n)).sort().map((name) => {
    const lines = readFileSync(join(dir, name), 'utf8').split('\n')
    const t = lines.findIndex((l) => l.startsWith('# '))
    if (t < 0) throw new Error(`help/${name} has no # title`)
    return { slug: name.slice(3, -3), number: Number(name.slice(0, 2)), title: lines[t]!.slice(2).trim(), body: blocksOf(lines.slice(t + 1), `help/${name}`) }
  })
}

export function validateHelp(articles: HelpArticle[]): string[] {
  const placed = GROUPS.flatMap((g) => g.numbers)
  return articles.filter((a) => placed.filter((n) => n === a.number).length !== 1).map((a) => `help: "${a.title}" sits in ${placed.filter((n) => n === a.number).length} groups, not one`)
}

function helpBlockHtml(b: HelpBlock): string {
  if (b.kind !== 'table') return blockHtml(b, new Map())
  return `<table class="htable"><thead><tr>${b.head.map((c) => `<th>${inlineHtml(c)}</th>`).join('')}</tr></thead>` +
    `<tbody>${b.rows.map((r) => `<tr>${r.map((c) => `<td>${inlineHtml(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`
}

function helpBlockMd(b: HelpBlock): string {
  if (b.kind !== 'table') return blockMd(b)
  return [`| ${b.head.join(' | ')} |`, `|${b.head.map(() => '---').join('|')}|`, ...b.rows.map((r) => `| ${r.join(' | ')} |`)].join('\n')
}

const firstLine = (a: HelpArticle): string => {
  const p = a.body.find((b): b is Extract<PostBlock, { kind: 'p' }> => b.kind === 'p')
  return p ? p.text.replace(/\*\*/g, '') : a.title
}

const STILL = '<aside class="hstill" aria-labelledby="still"><h2 id="still">Still have a question?</h2>' +
  '<p>Open <strong>Support</strong> in the app, under <strong>Settings</strong>, then <strong>Help &amp; about</strong>, ' +
  'or write to <a href="mailto:contact@longbook.app">contact@longbook.app</a> and a person answers.</p></aside>'

export function helpPage(a: HelpArticle, ctx: Ctx, jsonld: object): string {
  const main = [
    '<main class="fp bp"><div class="fwrap">',
    '<article class="post" aria-labelledby="post-title">',
    `<nav class="crumbs" aria-label="Breadcrumb"><ol><li><a href="/help/">Help</a></li><li aria-current="page">${esc(a.title)}</li></ol></nav>`,
    `<header class="bhero"><h1 id="post-title">${esc(a.title)}</h1></header>`,
    `<div class="prose">\n${a.body.map(helpBlockHtml).join('\n')}\n</div>`,
    STILL,
    '</article>',
    '</div></main>',
  ].join('\n')
  return page({
    title: `${a.title} — longbook help`,
    description: firstLine(a).slice(0, 300),
    canonical: helpUrl(a.slug),
    markdown: helpMdUrl(a.slug),
    ogTitle: a.title,
    ogImage: `${ORIGIN}/og/blog.jpg`,
    ogAlt: `longbook help: ${a.title}`,
    jsonld: ctx.jsonld(jsonld),
  }, main, ctx)
}

export function helpIndexPage(articles: HelpArticle[], ctx: Ctx, jsonld: object): string {
  const byNumber = new Map(articles.map((a) => [a.number, a]))
  const groups = GROUPS.map((g) => `<section class="hgroup"><h2>${esc(g.name)}</h2><ul>` +
    g.numbers.map((n) => byNumber.get(n)).filter((a): a is HelpArticle => !!a)
      .map((a) => `<li><a href="/help/${a.slug}/">${esc(a.title)}</a></li>`).join('') + '</ul></section>').join('\n')
  const main = [
    '<main class="ip bp">',
    `<section class="ihero"><h1>${HELP.title}</h1><p class="lead">${esc(HELP.lead)}</p></section>`,
    '<div class="fwrap">',
    `<div class="hgroups">\n${groups}\n</div>`,
    STILL,
    aboutSection(ctx),
    '</div></main>',
  ].join('\n')
  return page({
    title: `${HELP.title} — longbook`,
    description: HELP.description,
    canonical: HELP_URL,
    markdown: `${ORIGIN}/help.md`,
    ogTitle: 'longbook help',
    ogImage: `${ORIGIN}/og/blog.jpg`,
    ogAlt: 'longbook help. Answers to questions about longbook.',
    jsonld: ctx.jsonld(jsonld),
  }, main, ctx)
}

const STILL_MD = 'Still have a question? Open **Support** in the app, under **Settings**, then **Help & about**, or write to contact@longbook.app and a person answers.'

export function helpMarkdown(a: HelpArticle): string {
  const out = [`# ${a.title}`, '', `- Page: ${helpUrl(a.slug)}`, '', ...a.body.flatMap((b) => [helpBlockMd(b), '']),
    STILL_MD, '', `- [All help articles](${ORIGIN}/help.md)`]
  return out.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n'
}

export function helpIndexMarkdown(articles: HelpArticle[], ctx: Ctx): string {
  const byNumber = new Map(articles.map((a) => [a.number, a]))
  const out = [`# ${HELP.title}`, '', `> ${HELP.lead}`, '', `- Page: ${HELP_URL}`, '',
    ...GROUPS.flatMap((g) => [`## ${g.name}`, '', ...g.numbers.map((n) => byNumber.get(n)).filter((a): a is HelpArticle => !!a)
      .map((a) => `- [${a.title}](${helpMdUrl(a.slug)})`), '']),
    STILL_MD, '', ...aboutMd(ctx)]
  return out.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n'
}

export function helpJsonld(a: HelpArticle): object {
  return {
    '@context': 'https://schema.org',
    '@graph': [
      { '@type': 'TechArticle', '@id': `${helpUrl(a.slug)}#article`, headline: a.title, url: helpUrl(a.slug), inLanguage: 'en',
        isPartOf: { '@id': `${HELP_URL}#webpage` }, publisher: { '@id': ORG },
        encoding: { '@type': 'MediaObject', contentUrl: helpMdUrl(a.slug), encodingFormat: 'text/markdown' } },
      organization,
      website,
    ],
  }
}

export function helpIndexJsonld(articles: HelpArticle[]): object {
  return {
    '@context': 'https://schema.org',
    '@graph': [
      { '@type': 'CollectionPage', '@id': `${HELP_URL}#webpage`, url: HELP_URL, name: 'longbook help', description: HELP.description,
        inLanguage: 'en', isPartOf: { '@id': SITE },
        hasPart: articles.map((a) => ({ '@id': `${helpUrl(a.slug)}#article`, '@type': 'TechArticle', headline: a.title, url: helpUrl(a.slug) })),
        encoding: { '@type': 'MediaObject', contentUrl: `${ORIGIN}/help.md`, encodingFormat: 'text/markdown' } },
      organization,
      website,
    ],
  }
}

