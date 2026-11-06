// Agents that ask for Markdown get the page's Markdown copy; browsers, link previews and plain
// requests keep the HTML. A Markdown address with no page behind it answers in Markdown too.
// Named to sort after guard-staging: file-based edge functions run alphabetically.
import type { Context } from 'https://edge.netlify.com'
import { MARKDOWN_FOR } from './lib/markdown-pages.gen.ts'

// How much an Accept header wants a media type: its own entry, else the nearest wildcard, else 0.
export const quality = (accept: string, type: string): number => {
  const family = `${type.split('/')[0]}/*`
  let best = 0
  let specificity = -1
  for (const part of accept.toLowerCase().split(',')) {
    const [range, ...params] = part.split(';').map((s) => s.trim())
    const rank = range === type ? 2 : range === family ? 1 : range === '*/*' ? 0 : -1
    if (rank <= specificity) continue
    const q = Number(params.find((p) => p.startsWith('q='))?.slice(2) ?? '1')
    specificity = rank
    best = Number.isFinite(q) ? q : 1
  }
  return best
}

// Markdown only when the client names it and ranks it above HTML; a bare */* stays HTML.
export const wantsMarkdown = (accept: string): boolean =>
  /(^|[\s,])text\/markdown\s*(;|,|$)/i.test(accept) && quality(accept, 'text/markdown') > quality(accept, 'text/html')

const notFound = (path: string): string => [
  '# Not found',
  '',
  `longbook.app has no Markdown page at ${path}.`,
  '',
  'Every page and its Markdown copy is listed at https://longbook.app/llms.txt and https://longbook.app/sitemap.xml.',
  '',
].join('\n')

export default async (request: Request, context: Context) => {
  if (request.method !== 'GET' && request.method !== 'HEAD') return context.next()
  const { pathname } = new URL(request.url)

  if (pathname.endsWith('.md')) {
    const response = await context.next()
    if (response.status !== 404) return response
    return new Response(request.method === 'HEAD' ? null : notFound(pathname), {
      status: 404,
      headers: { 'Content-Type': 'text/markdown; charset=utf-8', 'X-Robots-Tag': 'noindex' },
    })
  }

  const markdown = MARKDOWN_FOR[pathname]
  if (!markdown) return context.next()
  if (wantsMarkdown(request.headers.get('accept') ?? '')) return new URL(markdown, request.url)
  // The same address answers two ways, so caches keep them apart.
  const response = await context.next()
  response.headers.append('Vary', 'Accept')
  return response
}

export const config = {
  path: '/*',
  excludedPath: ['/mcp', '/mcp/*', '/r/*', '/oauth/*', '/.well-known/*', '/*.jpg', '/*.png', '/*.webp', '/*.svg', '/*.mp4',
    '/*.css', '/*.js', '/*.json', '/*.txt', '/*.xml', '/*.ico', '/*.woff2'],
}
