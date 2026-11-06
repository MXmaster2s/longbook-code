// What longbook Support answers from, per surface. longbook.app's Support page ('web') and the
// direct Mac build ('direct') get every article in full. Anything else, a missing surface
// included, gets the articles without website-only text, so an App Store build never sees it.
import { HELP_ARTICLES, HELP_ARTICLES_WEB, type HelpArticle } from './help-articles.ts'

export interface Knowledge {
  /** The articles as the system prompt carries them; one string per set, so each caches. */
  text: string
  titles: Map<string, string>
}

const FULL_SURFACES = new Set(['web', 'direct'])

function knowledge(articles: HelpArticle[]): Knowledge {
  return {
    text: [
      'The help articles, each with its slug:',
      ...articles.map((a) => `<article slug="${a.slug}">\n# ${a.title}\n\n${a.body}\n</article>`),
    ].join('\n\n'),
    titles: new Map(articles.map((a) => [a.slug, a.title])),
  }
}

export const RESTRICTED_KNOWLEDGE = knowledge(HELP_ARTICLES)
export const FULL_KNOWLEDGE = knowledge(HELP_ARTICLES_WEB)

export const knowledgeFor = (surface: unknown): Knowledge =>
  typeof surface === 'string' && FULL_SURFACES.has(surface) ? FULL_KNOWLEDGE : RESTRICTED_KNOWLEDGE
