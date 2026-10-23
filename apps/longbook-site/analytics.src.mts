// longbook.app's measurement, as the privacy policy describes it: page views, clicks, sections
// reached, time on page, scroll depth, page speed and script errors, sent to PostHog with no
// cookie and nothing kept in the browser. Sent by hand: a few kilobytes, not the library's 180.
import { detectBrowser, detectBrowserVersion, detectDeviceType, detectOS } from '@posthog/core/utils'
// The Core Web Vitals measuring code, bundled rather than fetched: the page loads nothing from
// PostHog's servers at run time.
import 'posthog-js/dist/web-vitals.js'

// Public by design: a project token only accepts events and reads nothing back.
const TOKEN = 'phc_pTXUJ2Qh4fYGu6EmDiwZcAYj6i9htiEQETbYZxApGDaM'
const HOST = 'https://us.i.posthog.com'

// The visitor's own switch, on the privacy policy page. It is the one thing this file keeps
// in the browser, and only for someone who asked not to be measured.
const OPT_OUT = 'longbook.measure'
const optedOut = (): boolean => {
  try {
    return localStorage.getItem(OPT_OUT) === 'off'
  } catch {
    return false
  }
}

// A browser that asks not to be measured is not measured, and neither is any copy of the
// site that is not longbook.app itself: a preview, a fork, a developer's machine.
const signals = navigator as Navigator & { globalPrivacyControl?: boolean; doNotTrack?: string | null }
const declined = signals.globalPrivacyControl === true || signals.doNotTrack === '1' || optedOut()
const live = location.hostname === 'longbook.app' || location.hostname === 'www.longbook.app'

// An address is reported without its query or fragment, and what the library lifts out of
// a query on its own — a search keyword, the engine it came from — is dropped.
const bare = (value: unknown): unknown => (typeof value === 'string' ? value.split(/[?#]/)[0] : value)
const scrub = <E extends { properties?: Record<string, unknown> } | null>(event: E): E => {
  const properties = event?.properties
  if (!properties) return event
  for (const key of Object.keys(properties)) {
    if (/url$|referrer$|^\$pathname$/i.test(key)) properties[key] = bare(properties[key])
  }
  delete properties.ph_keyword
  delete properties.$search_engine
  Object.assign(properties, campaign)
  return event
}

const page = (): string => location.pathname

// Four campaign tags on the address a visit arrived by, and nothing else from its query, go with
// every event from that page. A value is kept only if it is a plain label: no address, link or query.
const CAMPAIGN_KEYS = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content']
const campaign: Record<string, string> = {}
try {
  const query = new URLSearchParams(location.search)
  for (const key of CAMPAIGN_KEYS) {
    const value = query.get(key)?.trim().slice(0, 100)
    if (value && /^[A-Za-z0-9._+ -]+$/.test(value)) campaign[key] = value
  }
} catch {
  // A malformed query carries no campaign.
}

// Which download button was pressed: a tagged row on the page, else the header or the footer.
const place = (link: Element): string =>
  link.closest('[data-cta]')?.getAttribute('data-cta') ??
  (link.closest('.top') ? 'header' : link.closest('footer') ? 'footer' : 'page')
const device = (link: Element): string | undefined => {
  const words = link.textContent ?? ''
  return /iphone/i.test(words) ? 'iphone' : /\bmac\b/i.test(words) ? 'mac' : undefined
}
const feature = (): string | undefined => /^\/features\/([a-z0-9-]+)\/?$/.exec(location.pathname)?.[1]

// The few clicks worth naming on their own: a store or TestFlight link, the source, the MCP page.
const onClick = (event: MouseEvent): void => {
  const link = (event.target as Element | null)?.closest?.('a[href]') as HTMLAnchorElement | null
  if (!link) return
  const href = link.href
  if (/testflight\.apple\.com|apps\.apple\.com/.test(href)) {
    const store = href.includes('testflight') ? 'testflight' : 'app store'
    capture('download_clicked', { page: page(), store, place: place(link), device: device(link), feature: feature() })
  } else if (/github\.com/.test(href) || link.pathname.startsWith('/source')) {
    capture('source_clicked', { page: page() })
  } else if (link.pathname.startsWith('/mcp')) {
    capture('mcp_clicked', { page: page() })
  }
}

// The site's own words, trimmed: a label, a heading, a question. Nothing a visitor types.
const words = (text: string | null | undefined, max: number): string => (text ?? '').replace(/\s+/g, ' ').trim().slice(0, max)
const question = (summary: Element | null): string => words(summary?.textContent, 120).replace(/\s*\+$/, '')

// Every click on something made to be clicked. It is named by its label, and by where it sits:
// the header, the footer, or under the nearest heading above it.
const CLICKABLE =
  'a[href], button, summary, select, label, [role="button"], [role="menuitem"], [role="tab"], [role="link"], input[type="checkbox"], input[type="radio"], input[type="submit"], input[type="button"]'
const kind = (el: Element): string => {
  const role = el.getAttribute('role')
  if (role === 'menuitem') return 'menu item'
  if (el.tagName === 'SUMMARY') return 'question'
  if (el.tagName === 'A' || role === 'link') return 'link'
  if (el.tagName === 'BUTTON' || role === 'button' || role === 'tab' || /button|submit/.test((el as HTMLInputElement).type ?? '')) return 'button'
  return 'control'
}
const label = (el: Element): string =>
  (el.tagName === 'SUMMARY' ? question(el) : '') ||
  words(el.getAttribute('aria-label'), 80) ||
  words((el as HTMLElement).innerText ?? el.textContent, 80) ||
  words(el.getAttribute('title'), 80) ||
  words(el.querySelector('img[alt]')?.getAttribute('alt'), 80) ||
  el.tagName.toLowerCase()
// A link's destination without its query: a path here, an address elsewhere, "email" for mail.
const destination = (el: Element): string | undefined => {
  if (!(el instanceof HTMLAnchorElement)) return undefined
  if (el.protocol === 'mailto:') return 'email'
  if (el.host === location.host) return el.pathname + (el.pathname === location.pathname ? el.hash : '')
  return el.host + el.pathname
}
const section = (el: Element): string => {
  if (el.closest('.top')) return 'header'
  if (el.closest('footer')) return 'footer'
  let found = ''
  for (const heading of Array.from(document.querySelectorAll('h1, h2'))) {
    if (heading !== el && !heading.contains(el) && !(heading.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING)) break
    found = words(heading.textContent, 80)
  }
  return found || 'page'
}
const onAnyClick = (event: MouseEvent): void => {
  const el = (event.target as Element | null)?.closest?.(CLICKABLE)
  if (!el) return
  capture('element_clicked', { page: page(), section: section(el), label: label(el), kind: kind(el), destination: destination(el) })
}

// How far down a page a visit reached: each section heading the first time all of it is in
// view, and the footer the first time any of it is.
const watchSections = (): void => {
  if (!('IntersectionObserver' in window)) return
  const headings = Array.from(document.querySelectorAll('h2'))
  const reached = (name: string, position: number): void => {
    capture('section_reached', { page: page(), section: name, position, of: headings.length + 1 })
  }
  const onHeading = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue
      onHeading.unobserve(entry.target)
      reached(words(entry.target.textContent, 80), headings.indexOf(entry.target as HTMLHeadingElement) + 1)
    }
  }, { threshold: 1 })
  headings.forEach((heading) => onHeading.observe(heading))
  const footer = document.querySelector('footer')
  if (!footer) return
  const onFooter = new IntersectionObserver((entries) => {
    if (!entries.some((entry) => entry.isIntersecting)) return
    onFooter.disconnect()
    reached('footer', headings.length + 1)
  })
  onFooter.observe(footer)
}

// Every event carries what PostHog's library would have added, named as it names them, so the
// dashboards read the same: the address, where the visit came from, the browser, system, device
// type and time zone, one id for this page view, and the user-agent the server's daily hash needs.
const pageviewId = crypto.randomUUID?.() ?? String(Math.random()).slice(2)

// The country, and the city when Cloudflare names one, from the site's own /visit-place,
// under PostHog's names: its cookieless mode looks up no location itself. Asked once a page.
let whereFrom: Record<string, string> = {}
const placeKnown: Promise<void> = live && !declined
  ? fetch('/visit-place', { cache: 'no-store' })
      .then((answer) => (answer.ok ? answer.json() : {}))
      .then((found: Record<string, unknown>) => {
        const text = (value: unknown): string | undefined =>
          typeof value === 'string' && value.length <= 80 ? value : undefined
        const code = text(found.country_code)
        if (!code || !/^[A-Z]{2}$/.test(code)) return
        whereFrom = { $geoip_country_code: code, $geoip_country_name: text(found.country) ?? code }
        const city = text(found.city)
        if (city) whereFrom.$geoip_city_name = city
      })
      .catch(() => {})
  : Promise.resolve()
const standard = (): Record<string, unknown> => {
  const agent = navigator.userAgent
  const [os, osVersion] = detectOS(agent)
  const referrer = document.referrer
  let referringDomain = '$direct'
  try {
    if (referrer) referringDomain = new URL(referrer).host
  } catch {
    // An unreadable referrer counts as none.
  }
  return {
    token: TOKEN,
    distinct_id: '$posthog_cookieless',
    $cookieless_mode: true,
    $process_person_profile: false,
    $lib: 'web',
    $lib_version: 'longbook-site',
    $current_url: location.href,
    $host: location.host,
    $pathname: location.pathname,
    $referrer: referrer || '$direct',
    $referring_domain: referringDomain,
    $raw_user_agent: agent,
    $browser: detectBrowser(agent, navigator.vendor),
    $browser_version: detectBrowserVersion(agent, navigator.vendor),
    $os: os,
    $os_version: osVersion,
    $device_type: detectDeviceType(agent),
    $timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    $pageview_id: pageviewId,
    $insert_id: Math.random().toString(36).slice(2, 18),
    $time: Date.now() / 1000,
    ...whereFrom,
  }
}
const event = (name: string, properties: Record<string, unknown>): Record<string, unknown> =>
  scrub({ event: name, properties: { ...standard(), ...properties }, timestamp: new Date().toISOString() })

// One event, sent at once. keepalive lets a click on a link out still arrive.
const capture = (name: string, properties: Record<string, unknown>): void => {
  fetch(`${HOST}/batch/`, {
    method: 'POST',
    keepalive: true,
    headers: { 'Content-Type': 'text/plain' },
    body: JSON.stringify({ api_key: TOKEN, batch: [event(name, properties)] }),
  }).catch(() => {})
}

// A page's last event goes by beacon, which the browser delivers after the page has gone.
const beacon = (name: string, properties: Record<string, unknown>): void => {
  if (typeof navigator.sendBeacon !== 'function') return capture(name, properties)
  const json = JSON.stringify(event(name, properties))
  const data = btoa(encodeURIComponent(json).replace(/%([0-9A-F]{2})/g, (_, hex: string) => String.fromCharCode(parseInt(hex, 16))))
  navigator.sendBeacon(`${HOST}/e/?compression=base64`, new Blob([`data=${encodeURIComponent(data)}`], { type: 'application/x-www-form-urlencoded' }))
}

// A page's last event, as it is left: how long it was open, how far down it was read, and its
// Core Web Vitals as the visitor's browser measured them, each at its latest value.
type Metric = { name: string; value: number }
type Report = (metric: Metric) => void
type Vitals = Partial<Record<'onLCP' | 'onINP' | 'onCLS' | 'onFCP', (report: Report, options?: { reportAllChanges?: boolean }) => void>>
const watchVisit = (): void => {
  const extensions = (window as unknown as { __PosthogExtensions__?: { postHogWebVitalsCallbacks?: Vitals } }).__PosthogExtensions__
  const vitals = extensions?.postHogWebVitalsCallbacks
  const seen: Record<string, number> = {}
  const keep: Report = (metric) => {
    seen[metric.name] = metric.value
  }
  for (const on of [vitals?.onLCP, vitals?.onINP, vitals?.onCLS, vitals?.onFCP]) on?.(keep, { reportAllChanges: true })
  let deepest = 0
  const measure = (): void => {
    const height = document.documentElement.scrollHeight
    deepest = Math.max(deepest, height > 0 ? Math.min(100, Math.round(((scrollY + innerHeight) / height) * 100)) : 100)
  }
  addEventListener('scroll', measure, { passive: true })
  addEventListener('load', measure)
  const ms = (value: number | undefined): number | undefined => (value === undefined ? undefined : Math.round(value))
  let left = false
  const leave = (): void => {
    if (left) return
    left = true
    measure()
    const cls = seen.CLS === undefined ? undefined : Math.round(seen.CLS * 1000) / 1000
    beacon('page_left', {
      page: page(),
      seconds: Math.round(performance.now() / 100) / 10,
      scroll_pct: deepest,
      lcp_ms: ms(seen.LCP),
      inp_ms: ms(seen.INP),
      fcp_ms: ms(seen.FCP),
      cls,
    })
  }
  addEventListener('pagehide', leave)
  addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') leave()
  })
}

// A script error from this site's own files: its message, the file and the line. An error from a
// browser extension or another site's script is not the site's, and is not sent.
const onError = (event: ErrorEvent): void => {
  const file = String(bare(event.filename ?? ''))
  if (!file.startsWith(location.origin)) return
  const message = words(event.message, 200).replace(/\?[^\s'"]*/g, '')
  capture('script_error', { page: page(), message, file: file.slice(location.origin.length) || '/', line: event.lineno })
}

// An FAQ question opened, by the site's own words for it.
const onToggle = (event: Event): void => {
  const details = event.target as HTMLDetailsElement | null
  if (!details || details.tagName !== 'DETAILS' || !details.open) return
  const asked = question(details.querySelector('summary'))
  if (asked) capture('faq_question_opened', { page: page(), question: asked })
}

// The switch on the policy page works whether or not measurement is running.
const wireSwitch = (): void => {
  const button = document.querySelector<HTMLButtonElement>('[data-measure-switch]')
  if (!button) return
  const say = (): void => {
    button.textContent = optedOut() ? 'Measure my visits again' : 'Do not measure my visits'
    button.setAttribute('aria-pressed', String(optedOut()))
  }
  button.hidden = false
  button.addEventListener('click', () => {
    try {
      if (optedOut()) localStorage.removeItem(OPT_OUT)
      else localStorage.setItem(OPT_OUT, 'off')
    } catch {
      return
    }
    say()
  })
  say()
}

const whenReady = (run: () => void): void => {
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run)
  else run()
}

if (live && !declined) {
  // The page view waits a moment for its place; later events carry whatever arrived.
  const title = document.title
  Promise.race([placeKnown, new Promise((done) => setTimeout(done, 800))]).then(() => capture('$pageview', { title }))
  document.addEventListener('click', onClick, { capture: true, passive: true })
  document.addEventListener('click', onAnyClick, { capture: true, passive: true })
  document.addEventListener('toggle', onToggle, { capture: true })
  addEventListener('error', onError)
  watchVisit()
  whenReady(watchSections)
}
whenReady(wireSwitch)
