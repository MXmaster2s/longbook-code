// Where a visit comes from, for the site's measurement: the country Cloudflare determines from
// the IP address at its edge, and the city when Cloudflare adds one. PostHog's cookieless mode
// looks up no location itself. The address is read by Cloudflare and never reaches this answer.
import type { Context } from 'https://edge.netlify.com'

// XX is Cloudflare's "unknown"; T1 is Tor.
const COUNTRY = /^[A-Z]{2}$/
const NOT_A_COUNTRY = new Set(['XX', 'T1'])
const CITY = /^[\p{L}\p{M} .'’-]{1,80}$/u

const names = new Intl.DisplayNames(['en'], { type: 'region' })

export default (request: Request, _context: Context) => {
  const code = request.headers.get('cf-ipcountry')?.trim().toUpperCase() ?? ''
  const city = request.headers.get('cf-ipcity')?.trim() ?? ''
  const place: Record<string, string> = {}
  if (COUNTRY.test(code) && !NOT_A_COUNTRY.has(code)) {
    place.country_code = code
    place.country = names.of(code) ?? code
    if (CITY.test(city)) place.city = city
  }
  return new Response(JSON.stringify(place), {
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'private, no-store',
      'X-Robots-Tag': 'noindex',
    },
  })
}

export const config = { path: '/visit-place', method: ['GET'] }
