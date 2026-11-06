// The facts page, longbook.app/facts/: every fact a directory or listing form asks, from
// apps/longbook-site-content/facts.md. Values that change ({{version}}, {{features}} and the rest)
// are filled from their sources at build time, so the page cannot drift.
import { readFileSync } from 'node:fs'
import { ORIGIN } from './content.mts'
import { type Ctx, absolute, attr, esc, inlineHtml, inlineMd, linksIn, plainText, page } from './render.mts'
import { APP, ORG, SITE, organization, website } from './seo.mts'

export const FACTS_URL = `${ORIGIN}/facts/`
export const FACTS_MD = `${ORIGIN}/facts.md`

export interface Fact {
  label: string
  href?: string
  paras: string[]
}

export interface FactGroup {
  id: string
  title: string
  more: string
  /** Facts as written, or the name of a generated list ({{features}}) where one stands. */
  items: (Fact | { list: string })[]
}

export interface Facts {
  title: string
  seoTitle: string
  description: string
  lead: string
  groups: FactGroup[]
  /** The source as written, for the checks on literal values. */
  raw: string
}

export interface FactSources {
  values: Record<string, string>
  lists: Record<string, Fact[]>
}

export interface FactsBuilt {
  title: string
  seoTitle: string
  description: string
  lead: string
  groups: { id: string; title: string; more: string; facts: Fact[] }[]
}

const slugOf = (s: string): string => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')

export function parseFacts(text: string, file = 'facts.md'): Facts {
  const fm = /^---\n([\s\S]*?)\n---\n/.exec(text)
  if (!fm) throw new Error(`${file}: no frontmatter`)
  const meta = Object.fromEntries(fm[1]!.split('\n').map((l) => {
    const at = l.indexOf(':')
    return [l.slice(0, at).trim(), l.slice(at + 1).trim()]
  }))
  for (const k of ['title', 'seo_title', 'description', 'lead']) if (!meta[k]) throw new Error(`${file}: frontmatter has no ${k}`)
  const groups: FactGroup[] = []
  let fact: Fact | null = null
  let gap = false
  for (const line of text.slice(fm[0].length).split('\n')) {
    const g = groups.at(-1)
    if (line.startsWith('## ')) {
      const title = line.slice(3).trim()
      groups.push({ id: slugOf(title), title, more: '', items: [] })
      fact = null
      continue
    }
    if (!line.trim()) { gap = true; continue }
    if (!g) throw new Error(`${file}: text before the first ## group: "${line}"`)
    const list = /^\{\{([a-z_]+)\}\}$/.exec(line.trim())
    if (list && !line.startsWith(' ')) { g.items.push({ list: list[1]! }); fact = null; continue }
    if (line.startsWith('More: ')) { g.more = line.slice(6).trim(); fact = null; continue }
    const item = /^- ([^:]+):(.*)$/.exec(line)
    if (item) {
      fact = { label: item[1]!.trim(), paras: item[2]!.trim() ? [item[2]!.trim()] : [] }
      g.items.push(fact)
      gap = false
      continue
    }
    if (line.startsWith('  ') && fact) {
      if (gap || !fact.paras.length) fact.paras.push(line.trim())
      else fact.paras[fact.paras.length - 1] += ` ${line.trim()}`
      gap = false
      continue
    }
    throw new Error(`${file}: "${line}" is not a fact (- Label: value), a More: line or a {{list}}`)
  }
  return { title: meta.title, seoTitle: meta.seo_title, description: meta.description, lead: meta.lead, groups, raw: text }
}

/** Fills each {{value}} and {{list}} from its source; anything it cannot fill is a problem. */
export function buildFacts(f: Facts, src: FactSources, problems: string[]): FactsBuilt {
  const fill = (s: string): string => s.replace(/\{\{([a-z_]+)\}\}/g, (whole, k: string) => {
    if (k in src.values) return src.values[k]!
    problems.push(`facts: no source for {{${k}}}`)
    return whole
  })
  return {
    title: fill(f.title), seoTitle: fill(f.seoTitle), description: fill(f.description), lead: fill(f.lead),
    groups: f.groups.map((g) => ({
      id: g.id, title: g.title, more: fill(g.more),
      facts: g.items.flatMap((i) => {
        if (!('list' in i)) return [{ ...i, label: fill(i.label), paras: i.paras.map(fill) }]
        if (!src.lists[i.list]?.length) problems.push(`facts: the list {{${i.list}}} has no source or is empty`)
        return src.lists[i.list] ?? []
      }),
    })),
  }
}

const BANNED: [RegExp, string][] = [
  [/subscription tracker/i, 'calls longbook a subscription tracker'],
  [/open[ -]source/i, 'talks of open source'],
]

/** The copy rules, and the rule that a value which changes is never typed into the source. */
export function validateFacts(f: Facts, built: FactsBuilt, known: Set<string>): string[] {
  const problems: string[] = []
  const body = f.raw.replace(/^---\n[\s\S]*?\n---\n/, '')
  for (const m of body.matchAll(/\$\d[\d,.]*/g)) problems.push(`facts.md: "${m[0]}" is typed in; use a {{price}} value from the pricing section`)
  for (const m of body.matchAll(/\b\d+\.\d+\.\d+\b/g)) problems.push(`facts.md: "${m[0]}" is typed in; use {{version}} or another generated value`)
  const ids = new Set<string>()
  for (const g of built.groups) {
    if (ids.has(g.id)) problems.push(`facts: the group "${g.title}" is there twice`)
    ids.add(g.id)
    if (!g.more) problems.push(`facts: "${g.title}" has no More: line linking to the page that explains it`)
    if (!g.facts.length) problems.push(`facts: "${g.title}" has no facts`)
    const labels = new Set<string>()
    for (const x of g.facts) {
      if (labels.has(x.label)) problems.push(`facts: "${x.label}" is in "${g.title}" twice`)
      labels.add(x.label)
      if (x.label.includes('?')) problems.push(`facts: the label "${x.label}" asks a question; a label names its field`)
      if (!/^[A-Z0-9]|^(longbook|iPhone|iOS|macOS|npm|mcprush)\b|^@/.test(x.label)) problems.push(`facts: the label "${x.label}" is not sentence case`)
      if (!x.paras.length) problems.push(`facts: "${x.label}" has no value`)
    }
  }
  const texts = [built.description, built.lead, ...built.groups.flatMap((g) => [g.more, ...g.facts.flatMap((x) => [x.label, ...x.paras])])]
  for (const t of texts) {
    for (const [re, why] of BANNED) if (re.test(t)) problems.push(`facts: "${plainText(t).slice(0, 60)}…" ${why}`)
    for (const href of linksIn(t)) {
      if (/^(https:\/\/|mailto:)\S+$/.test(href)) continue
      if (!known.has(href.replace(/#.*$/, '') || '/')) problems.push(`facts: unknown link "${href}"`)
    }
  }
  const short = built.groups.flatMap((g) => g.facts).find((x) => x.label === 'Short description')
  if (short && plainText(short.paras.join(' ')).length > 160) problems.push(`facts: the short description is ${plainText(short.paras.join(' ')).length} characters, over 160`)
  return problems
}

const factHtml = (x: Fact): string =>
  `<div class="fxrow"><dt>${x.href ? `<a href="${attr(x.href)}">${esc(x.label)}</a>` : esc(x.label)}</dt>` +
  `<dd>${x.paras.map((p) => `<p>${inlineHtml(p)}</p>`).join('')}</dd></div>`

export function factsPage(f: FactsBuilt, ctx: Ctx, jsonld: object): string {
  const side = f.groups.map((g) => `<a href="#${g.id}">${esc(g.title)}<span>${g.facts.length}</span></a>`).join('')
  const groups = f.groups.map((g) => `<section class="fxg" id="${g.id}" aria-labelledby="${g.id}-h">` +
    `<h2 id="${g.id}-h">${esc(g.title)}</h2><dl class="fxdl">${g.facts.map(factHtml).join('')}</dl>` +
    `<p class="fxmore">More: ${inlineHtml(g.more)}</p></section>`).join('\n')
  const main = [
    '<main class="ip fxp">',
    `<section class="ihero"><h1>${esc(f.title)}</h1><p class="lead">${inlineHtml(f.lead)}</p>` +
      `<p class="fxmeta"><a href="/facts.md">The same facts in Markdown</a></p></section>`,
    '<div class="fwrap"><div class="ilay">',
    `<nav class="iside" aria-label="Groups of facts">${side}</nav>`,
    `<div class="fxcol">\n${groups}\n</div>`,
    '</div></div></main>',
  ].join('\n')
  return page({
    title: `${f.seoTitle} — longbook`,
    description: f.description,
    canonical: FACTS_URL,
    markdown: FACTS_MD,
    ogTitle: f.title,
    ogImage: `${ORIGIN}/og/blog.jpg`,
    ogAlt: `${f.title}. ${f.description}`,
    jsonld: ctx.jsonld(jsonld),
  }, main, ctx)
}

const factMd = (x: Fact): string[] => {
  const label = x.href ? `[${x.label}](${absolute(x.href)})` : x.label
  if (x.paras.length === 1) return [`- **${label}:** ${inlineMd(x.paras[0]!)}`]
  return [`- **${label}:**`, '', ...x.paras.flatMap((p) => [`  ${inlineMd(p)}`, ''])]
}

export function factsMarkdown(f: FactsBuilt): string {
  const out = [`# ${f.title}`, '', `> ${plainText(f.lead)}`, '', `- Page: ${FACTS_URL}`, '',
    ...f.groups.flatMap((g) => [`## ${g.title}`, '', ...g.facts.flatMap(factMd), '', `More: ${inlineMd(g.more)}`, ''])]
  return out.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n'
}

export function factsJsonld(f: FactsBuilt): object {
  return {
    '@context': 'https://schema.org',
    '@graph': [
      { '@type': 'WebPage', '@id': `${FACTS_URL}#webpage`, url: FACTS_URL, name: f.title, description: f.description,
        inLanguage: 'en', isPartOf: { '@id': SITE }, about: { '@id': APP }, publisher: { '@id': ORG },
        encoding: { '@type': 'MediaObject', contentUrl: FACTS_MD, encodingFormat: 'text/markdown' } },
      organization,
      website,
    ],
  }
}

export const loadFacts = (file: string): Facts => parseFacts(readFileSync(file, 'utf8'), file.split('/').pop())
