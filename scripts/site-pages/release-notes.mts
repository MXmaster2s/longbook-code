// The release notes on longbook.app/release-notes/: every version's changes, newest first, from
// apps/longbook/Resources/changelog.json, the file the apps' What's New reads. One version's builds
// are merged, each change said once, as the app's Check for Updates lists them.
import { ORIGIN } from './content.mts'
import { type Ctx, aboutMd, aboutSection, esc, page } from './render.mts'
import { longDate } from './blog.mts'
import { APP, SITE, organization, website } from './seo.mts'

export interface ReleaseEntry {
  version: string
  build: number
  date: string
  changes: string[]
}

export interface VersionNotes {
  version: string
  /** The newest build's date, as the changelog gives it. */
  date: string
  changes: string[]
}

export const RELEASE_NOTES_URL = `${ORIGIN}/release-notes/`
export const RELEASE_NOTES_MD = `${ORIGIN}/release-notes.md`
export const RELEASE_NOTES = {
  title: 'Release notes',
  lead: 'What changed in each version of longbook for iPhone and Mac, newest first. The same notes are in the app, under What’s New.',
  description: 'longbook release notes: what changed in each version of the app for iPhone and Mac, newest first.',
}

/** A line the app leaves out of What's New, since nothing changes for the reader. */
const unseen = (line: string): boolean => line.startsWith('Nothing you will see')

/** The changelog's entries, newest build first, folded into one entry per version. */
export function versionNotes(json: string): VersionNotes[] {
  const rows = (JSON.parse(json) as ReleaseEntry[]).filter((r) => r.version && Number.isInteger(r.build) && r.changes?.length)
    .sort((a, b) => b.build - a.build)
  const out: VersionNotes[] = []
  for (const r of rows) {
    let v = out.find((x) => x.version === r.version)
    if (!v) out.push((v = { version: r.version, date: r.date, changes: [] }))
    for (const c of r.changes) if (!unseen(c) && !v.changes.includes(c)) v.changes.push(c)
  }
  return out.filter((v) => v.changes.length)
}

export function validateReleaseNotes(versions: VersionNotes[]): string[] {
  const problems: string[] = []
  if (!versions.length) problems.push('release notes: changelog.json names no version')
  for (const v of versions) if (!/^\d{4}-\d{2}-\d{2}$/.test(v.date)) problems.push(`release notes: ${v.version} has no date`)
  return problems
}

/** The first sentence says what changed and is set in bold; the rest says how. The app's rule. */
export function firstSentence(text: string): string {
  const m = /^.*?\.(?= \p{Lu})/u.exec(text)
  return m ? m[0] : text
}

const anchor = (version: string): string => `v${version.replace(/\./g, '-')}`

function changeHtml(line: string): string {
  const lead = firstSentence(line)
  const rest = line.slice(lead.length).trim()
  return `<li><strong>${esc(lead)}</strong>${rest ? ` ${esc(rest)}` : ''}</li>`
}

export function releaseNotesPage(versions: VersionNotes[], ctx: Ctx, jsonld: object): string {
  const sections = versions.map((v) => `<section class="rnver" id="${anchor(v.version)}" aria-labelledby="${anchor(v.version)}-h">` +
    `<h2 id="${anchor(v.version)}-h">Version ${esc(v.version)}</h2>` +
    `<p class="bmeta"><time datetime="${v.date}">${longDate(v.date)}</time></p>` +
    `<ul>${v.changes.map(changeHtml).join('')}</ul></section>`).join('\n')
  const main = [
    '<main class="fp bp"><div class="fwrap">',
    '<article class="post" aria-labelledby="post-title">',
    `<header class="bhero"><h1 id="post-title">${esc(RELEASE_NOTES.title)}</h1><p class="lead">${esc(RELEASE_NOTES.lead)}</p></header>`,
    `<div class="prose">\n${sections}\n</div>`,
    '</article>',
    aboutSection(ctx),
    '</div></main>',
  ].join('\n')
  return page({
    title: `${RELEASE_NOTES.title} — longbook`,
    description: RELEASE_NOTES.description,
    canonical: RELEASE_NOTES_URL,
    markdown: RELEASE_NOTES_MD,
    ogTitle: 'longbook release notes',
    ogImage: `${ORIGIN}/og/blog.jpg`,
    ogAlt: 'longbook release notes: what changed in each version.',
    jsonld: ctx.jsonld(jsonld),
  }, main, ctx)
}

export function releaseNotesMarkdown(versions: VersionNotes[], ctx: Ctx): string {
  const out = [`# ${RELEASE_NOTES.title}`, '', `> ${RELEASE_NOTES.lead}`, '', `- Page: ${RELEASE_NOTES_URL}`, '',
    ...versions.flatMap((v) => [`## Version ${v.version}`, '', longDate(v.date), '',
      ...v.changes.map((c) => {
        const lead = firstSentence(c)
        const rest = c.slice(lead.length).trim()
        return `- **${lead}**${rest ? ` ${rest}` : ''}`
      }), '']),
    ...aboutMd(ctx)]
  return out.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n'
}

export function releaseNotesJsonld(versions: VersionNotes[]): object {
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'WebPage',
        '@id': `${RELEASE_NOTES_URL}#webpage`,
        url: RELEASE_NOTES_URL,
        name: 'longbook release notes',
        description: RELEASE_NOTES.description,
        inLanguage: 'en',
        isPartOf: { '@id': SITE },
        about: { '@id': APP },
        ...(versions[0] ? { dateModified: versions[0].date } : {}),
        encoding: { '@type': 'MediaObject', contentUrl: RELEASE_NOTES_MD, encodingFormat: 'text/markdown' },
      },
      organization,
      website,
    ],
  }
}
