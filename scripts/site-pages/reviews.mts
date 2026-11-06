// The reviews page: what people have posted about longbook on X and Reddit, quoted as posted,
// each module a link to the original. Data in apps/longbook-site-content/reviews.json, the same
// reviews as longbookreviews.com; pictures in apps/longbook-site/reviews/avatars.
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { ORIGIN } from './content.mts'
import { type Ctx, aboutMd, aboutSection, attr, esc, page } from './render.mts'
import { APP, SITE, organization, website } from './seo.mts'

export interface Review {
  id: string
  source: 'x' | 'reddit'
  url: string
  date: string
  author: { name?: string; handle: string; verified?: boolean; avatar?: string }
  context?: string | { subreddit?: string; postTitle?: string; score?: number }
  text: string
}

export const REVIEWS_URL = `${ORIGIN}/reviews/`
export const REVIEWS_MD = `${ORIGIN}/reviews.md`
export const REVIEWS_SHARE = '/reviews/share.jpg'
export const REVIEWS = {
  title: 'What people say about longbook',
  seoTitle: 'longbook reviews from X and Reddit',
  lead: 'Wondering what longbook is like before you try it? These are the words of people who did, as they posted them on X and Reddit, each with a link to the original.',
  description: 'Reviews of longbook from X and Reddit, quoted as posted with a link to each original. longbook remembers your subscriptions, bills and renewals on iPhone and Mac.',
  shareAlt: 'What people say about longbook, on longbook.app',
}

export function loadReviews(file: string): Review[] {
  if (!existsSync(file)) return []
  const data = JSON.parse(readFileSync(file, 'utf8')) as { reviews: Review[] }
  return data.reviews.slice().sort((a, b) => b.date.localeCompare(a.date))
}

export function validateReviews(reviews: Review[], site: string): string[] {
  const problems: string[] = []
  const ids = new Set<string>()
  for (const r of reviews) {
    const at = `reviews.json: ${r.id}`
    if (ids.has(r.id)) problems.push(`${at}: the id is used twice`)
    ids.add(r.id)
    if (!/^[a-z0-9-]+$/.test(r.id)) problems.push(`${at}: the id may use lowercase letters, digits and hyphens only`)
    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(r.date)) problems.push(`${at}: date must look like 2026-10-11T18:23:05Z`)
    const host = /^https:\/\/([^/]+)\//.exec(r.url)?.[1]
    if (r.source === 'x' ? host !== 'x.com' : r.source === 'reddit' ? host !== 'www.reddit.com' : true)
      problems.push(`${at}: a ${r.source} review links to ${host ?? 'nothing'}`)
    if (r.source === 'x' && !r.author.name) problems.push(`${at}: an X review needs the author's name`)
    if (r.author.avatar && !existsSync(join(site, 'reviews/avatars', r.author.avatar))) problems.push(`${at}: no reviews/avatars/${r.author.avatar}`)
    if (!r.text.trim()) problems.push(`${at}: no text`)
  }
  return problems
}

const day = (iso: string): string =>
  new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' })
const initials = (name: string): string =>
  name.split(/\s+/).filter((w) => /[\p{L}\p{N}]/u.test(w)).slice(0, 2).map((w) => w.match(/[\p{L}\p{N}]/u)![0]).join('').toUpperCase()
const mentions = (html: string): string => html.replace(/(^|\s)(@[A-Za-z0-9_]+)/g, '$1<span class="rmention">$2</span>')
const paragraphs = (text: string): string =>
  text.trim().split(/\n\s*\n/).map((p) => `<p>${mentions(esc(p).replace(/\n/g, '<br>'))}</p>`).join('')
const SOURCE = { x: 'X', reddit: 'Reddit' } as const
const ICON = {
  x: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18.901 1.153h3.68l-8.04 9.19L24 22.846h-7.406l-5.8-7.584-6.638 7.584H.474l8.6-9.83L0 1.154h7.594l5.243 6.932ZM17.61 20.644h2.039L6.486 3.24H4.298Z"/></svg>',
  reddit: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 0a12 12 0 1 0 0 24 12 12 0 0 0 0-24Zm5.01 4.744c.688 0 1.25.561 1.25 1.249a1.25 1.25 0 0 1-2.498.056l-2.597-.547-.8 3.747c1.824.07 3.48.632 4.674 1.488.308-.309.73-.491 1.207-.491.968 0 1.754.786 1.754 1.754 0 .716-.435 1.333-1.01 1.614a3.11 3.11 0 0 1 .042.52c0 2.694-3.13 4.87-7.004 4.87-3.874 0-7.004-2.176-7.004-4.87 0-.183.015-.366.043-.534A1.748 1.748 0 0 1 4.028 12c0-.968.786-1.754 1.754-1.754.463 0 .898.196 1.207.49 1.207-.883 2.878-1.43 4.744-1.487l.885-4.182a.342.342 0 0 1 .14-.197.35.35 0 0 1 .238-.042l2.906.617a1.214 1.214 0 0 1 1.108-.701ZM9.25 12C8.561 12 8 12.562 8 13.25c0 .687.561 1.248 1.25 1.248.687 0 1.248-.561 1.248-1.249 0-.688-.561-1.249-1.249-1.249Zm5.5 0c-.687 0-1.248.561-1.248 1.25 0 .687.561 1.248 1.249 1.248.688 0 1.249-.561 1.249-1.249 0-.687-.562-1.249-1.25-1.249Zm-5.466 3.99a.327.327 0 0 0-.231.094.33.33 0 0 0 0 .463c.842.842 2.484.913 2.961.913.477 0 2.105-.056 2.961-.913a.361.361 0 0 0 .029-.463.33.33 0 0 0-.464 0c-.547.533-1.684.73-2.512.73-.828 0-1.979-.196-2.512-.73a.326.326 0 0 0-.232-.095Z"/></svg>',
}
const VERIFIED = '<svg class="rver" viewBox="0 0 22 22" role="img" aria-label="Verified"><path d="M20.396 11c-.018-.646-.215-1.275-.57-1.816-.354-.54-.852-.972-1.438-1.246.223-.607.27-1.264.14-1.897-.131-.634-.437-1.218-.882-1.687-.47-.445-1.053-.75-1.687-.882-.633-.13-1.29-.083-1.897.14-.273-.587-.704-1.086-1.245-1.44S11.647 1.62 11 1.604c-.646.017-1.273.213-1.813.568s-.969.854-1.24 1.44c-.608-.223-1.267-.272-1.902-.14-.635.13-1.22.436-1.69.882-.445.47-.749 1.055-.878 1.688-.13.633-.08 1.29.144 1.896-.587.274-1.087.705-1.443 1.245-.356.54-.555 1.17-.574 1.817.02.647.218 1.276.574 1.817.356.54.856.972 1.443 1.245-.224.606-.274 1.263-.144 1.896.13.634.433 1.218.877 1.688.47.443 1.054.747 1.687.878.633.132 1.29.084 1.897-.136.274.586.705 1.084 1.246 1.439.54.354 1.17.551 1.816.569.647-.016 1.276-.213 1.817-.567s.972-.854 1.245-1.44c.604.239 1.266.296 1.903.164.636-.132 1.22-.447 1.68-.907.46-.46.776-1.044.908-1.681s.075-1.299-.165-1.903c.586-.274 1.084-.705 1.439-1.246.354-.54.551-1.17.569-1.816ZM9.662 14.85l-3.429-3.428 1.293-1.302 2.072 2.072 4.4-4.794 1.347 1.246Z"/></svg>'

function reviewCard(r: Review): string {
  const name = r.source === 'x' ? r.author.name! : `u/${r.author.handle}`
  const sub = r.source === 'x' ? `@${r.author.handle}`
    : typeof r.context === 'object' && r.context.subreddit ? `in r/${r.context.subreddit}` : 'on Reddit'
  const face = r.author.avatar
    ? `<img src="/reviews/avatars/${attr(r.author.avatar)}" width="44" height="44" alt="" decoding="async">`
    : `<span aria-hidden="true">${esc(initials(name))}</span>`
  const context = typeof r.context === 'string' ? mentions(esc(r.context))
    : r.context?.postTitle ? `On “${esc(r.context.postTitle)}”` : ''
  return `<a class="fcard rcard" id="${attr(r.id)}" href="${attr(r.url)}" rel="noopener">` +
    `<div class="rhead"><span class="rface">${face}</span>` +
    `<span class="rwho"><span class="rname">${esc(name)}${r.author.verified ? VERIFIED : ''}</span><span class="rsub">${esc(sub)}</span></span>` +
    `<span class="rsrc ${r.source}" title="Posted on ${SOURCE[r.source]}">${ICON[r.source]}</span></div>` +
    (context ? `<p class="rctx">${context}</p>` : '') +
    `<blockquote class="rtext" cite="${attr(r.url)}">${paragraphs(r.text)}</blockquote>` +
    `<p class="rfoot"><time datetime="${r.date}">${day(r.date)}</time><span>View on ${SOURCE[r.source]}</span></p></a>`
}

export function reviewsPage(reviews: Review[], ctx: Ctx, jsonld: object): string {
  const sources = [...new Set(reviews.map((r) => SOURCE[r.source]))].join(' and ')
  const main = [
    '<main class="ip rp">',
    `<section class="ihero"><h1>${esc(REVIEWS.title)}</h1><p class="lead">${esc(REVIEWS.lead)}</p>` +
      `<p class="rcount">${reviews.length} reviews from ${sources}, newest first</p></section>`,
    '<div class="fwrap">',
    `<div class="rcards">${reviews.map(reviewCard).join('')}</div>`,
    '<p class="rnote">Each review belongs to the person who posted it. The same reviews are on ' +
      '<a href="https://longbookreviews.com/" rel="noopener">longbookreviews.com</a>. ' +
      'Posted about longbook yourself? Write to <a href="mailto:contact@longbook.app">contact@longbook.app</a> to have it added, or taken off.</p>',
    aboutSection(ctx),
    '</div></main>',
  ].join('\n')
  return page({
    title: `${REVIEWS.seoTitle} — longbook`,
    description: REVIEWS.description,
    canonical: REVIEWS_URL,
    markdown: REVIEWS_MD,
    ogTitle: REVIEWS.title,
    ogImage: `${ORIGIN}${REVIEWS_SHARE}`,
    ogAlt: REVIEWS.shareAlt,
    jsonld: ctx.jsonld(jsonld),
  }, main, ctx)
}

const who = (r: Review): string => (r.source === 'x' ? `${r.author.name} (@${r.author.handle})` : `u/${r.author.handle}`)

export function reviewsMarkdown(reviews: Review[], ctx: Ctx): string {
  const out = [`# ${REVIEWS.title}`, '', `> ${REVIEWS.lead}`, '', `- Page: ${REVIEWS_URL}`, '- Also at: https://longbookreviews.com/', '',
    ...reviews.flatMap((r) => [`## ${who(r)}, ${day(r.date)}`, '',
      r.text.trim().split('\n').map((l) => (l ? `> ${l}` : '>')).join('\n'), '', `Original on ${SOURCE[r.source]}: ${r.url}`, '']),
    ...aboutMd(ctx)]
  return out.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n'
}

export function reviewsJsonld(reviews: Review[]): object {
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'CollectionPage',
        '@id': `${REVIEWS_URL}#webpage`,
        url: REVIEWS_URL,
        name: REVIEWS.title,
        description: REVIEWS.description,
        inLanguage: 'en',
        isPartOf: { '@id': SITE },
        about: { '@id': APP },
        primaryImageOfPage: { '@type': 'ImageObject', url: `${ORIGIN}${REVIEWS_SHARE}`, width: 1200, height: 630 },
        encoding: { '@type': 'MediaObject', contentUrl: REVIEWS_MD, encodingFormat: 'text/markdown' },
        mainEntity: {
          '@type': 'ItemList',
          numberOfItems: reviews.length,
          itemListOrder: 'https://schema.org/ItemListOrderDescending',
          itemListElement: reviews.map((r, i) => ({
            '@type': 'ListItem',
            position: i + 1,
            item: {
              '@type': 'Review',
              '@id': `${REVIEWS_URL}#${r.id}`,
              url: r.url,
              reviewBody: r.text.replace(/\s+/g, ' ').trim(),
              datePublished: r.date,
              inLanguage: 'en',
              author: {
                '@type': 'Person',
                name: r.author.name ?? r.author.handle,
                alternateName: r.source === 'x' ? `@${r.author.handle}` : `u/${r.author.handle}`,
                url: r.source === 'x' ? `https://x.com/${r.author.handle}` : `https://www.reddit.com/user/${r.author.handle}/`,
              },
              publisher: { '@type': 'Organization', name: SOURCE[r.source], url: r.source === 'x' ? 'https://x.com/' : 'https://www.reddit.com/' },
              itemReviewed: { '@id': APP },
            },
          })),
        },
      },
      organization,
      website,
    ],
  }
}
