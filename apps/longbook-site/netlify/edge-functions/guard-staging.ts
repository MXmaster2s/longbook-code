// Staging must never reach a search index; Cloudflare Access is the real gate and this is
// the backstop. Host-scoped, so production never inherits a noindex. Named to sort before
// mcp-explainer: file-based edge functions run alphabetically. Why obscurity is not enough:
// docs/staging-site.md.
import type { Context } from 'https://edge.netlify.com'

const LIVE = 'longbook.app'

const isStaging = (host: string): boolean =>
  host !== LIVE && host !== `www.${LIVE}`

export default async (request: Request, context: Context) => {
  const host = new URL(request.url).hostname
  if (!isStaging(host)) return context.next()

  if (new URL(request.url).pathname === '/robots.txt') {
    return new Response('User-agent: *\nDisallow: /\n', {
      headers: { 'Content-Type': 'text/plain; charset=utf-8', 'X-Robots-Tag': 'noindex' },
    })
  }

  const response = await context.next()
  response.headers.set('X-Robots-Tag', 'noindex, nofollow, noarchive, nosnippet')
  return response
}

export const config = { path: '/*' }
