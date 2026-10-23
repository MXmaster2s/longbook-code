#!/usr/bin/env -S npx tsx
// Every measured surface in one read: PostHog, Search Console, Bing, PageSpeed, the hosted
// MCP counts, Cloudflare's crawler traffic and the feedback board. A failing source never
// stops the rest. Keys come from the keychain, never printed.
// Run: npm run metrics [-- --days 90] [-- --json out.json] [-- --only site,app]
import { createSign } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'

const POSTHOG_QUERY = 'https://us.posthog.com/api/projects/537369/query/'
const SUPABASE_QUERY = 'https://api.supabase.com/v1/projects/xbrnijgctmovoqbbmgmb/database/query'
const SITE_URL = 'https://longbook.app/'
const SITE_HOSTS = ['longbook.app', 'www.longbook.app']
const GSC_PROPERTIES = ['sc-domain:longbook.app', 'https://longbook.app/']
const CLICK_EVENTS = ['download_clicked', 'source_clicked', 'mcp_clicked', 'faq_question_opened']
const BING_API = 'https://ssl.bing.com/webmaster/api.svc/json/'
const CLOUDFLARE_GRAPHQL = 'https://api.cloudflare.com/client/v4/graphql'
const CLOUDFLARE_ZONE = '94a06b6e20cefc740f62bc5d58f72cc9'
const FEEDBACK_BOARD = 'https://insigh.to/b/longbook'
const SOURCES = ['site', 'engagement', 'app', 'search', 'bing', 'speed', 'mcp', 'crawlers', 'feedback', 'packages'] as const
type Source = (typeof SOURCES)[number]

// ---- flags -------------------------------------------------------------------------------

const args = process.argv.slice(2)
const flag = (name: string): string | undefined => {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : undefined
}
const refuse = (message: string): never => {
  console.error(message)
  process.exit(2)
}

const DAYS = (() => {
  const raw = flag('--days')
  if (raw === undefined) return 90
  const n = Number(raw)
  return Number.isInteger(n) && n >= 1 && n <= 480 ? n : refuse('--days takes a whole number from 1 to 480.')
})()
const JSON_OUT = flag('--json')
if (args.includes('--json') && !JSON_OUT) refuse('--json takes a file path.')
const ONLY: Source[] = (() => {
  const raw = flag('--only')
  if (raw === undefined) return [...SOURCES]
  const picked = raw.split(',').map((s) => s.trim()).filter(Boolean)
  const unknown = picked.filter((s) => !(SOURCES as readonly string[]).includes(s))
  if (unknown.length || picked.length === 0) refuse(`--only takes a list from: ${SOURCES.join(', ')}.`)
  return SOURCES.filter((s) => picked.includes(s))
})()

// The window is whole UTC days, today included. Search Console alone counts its days in
// Pacific Time, so its series sits a few hours off the others.
const utcDay = (offsetDays: number): string => new Date(Date.now() - offsetDays * 86_400_000).toISOString().slice(0, 10)
const TODAY = utcDay(0)
const START = utcDay(DAYS - 1)
const everyDay = (): string[] => Array.from({ length: DAYS }, (_, i) => utcDay(DAYS - 1 - i))

// ---- plumbing ----------------------------------------------------------------------------

type Failure = { ok: false; error: string }
type Outcome<T> = ({ ok: true } & T) | Failure

const attempt = async <T extends object>(run: () => Promise<T>): Promise<Outcome<T>> => {
  try {
    return { ok: true, ...(await run()) }
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) }
  }
}

const keychain = (service: string): string => {
  try {
    return execFileSync('security', ['find-generic-password', '-s', service, '-w'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).replace(/\n$/, '')
  } catch {
    throw new Error(`No keychain item "${service}".`)
  }
}

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message)
  }
}

/** The service's own words for a refusal, from whichever field it uses. */
const reason = (json: unknown): string | undefined => {
  if (typeof json !== 'object' || json === null) return undefined
  const j = json as Record<string, unknown>
  const nested = typeof j.error === 'object' && j.error !== null ? (j.error as Record<string, unknown>).message : undefined
  const found = [nested, j.error_description, j.detail, j.message, j.error].find((v) => typeof v === 'string')
  return found as string | undefined
}

const request = async (what: string, url: string, init: RequestInit, timeoutMs = 60_000): Promise<unknown> => {
  const res = await fetch(url, { ...init, signal: AbortSignal.timeout(timeoutMs) })
  const text = await res.text()
  let json: unknown = null
  try {
    json = JSON.parse(text)
  } catch {
    // Not JSON; the text stands in below.
  }
  if (!res.ok) throw new HttpError(res.status, `${what} answered HTTP ${res.status}: ${(reason(json) ?? text).slice(0, 300)}`)
  return json
}

const num = (v: unknown): number => (typeof v === 'number' ? v : Number(v) || 0)
// Outside text reaches a terminal and a page: control characters become '?'.
const str = (v: unknown, empty = '(none)'): string =>
  v === null || v === undefined || v === '' ? empty : String(v).replace(/[\u0000-\u001f\u007f-\u009f]/g, '?')
const round = (v: number, places = 0): number => Math.round(v * 10 ** places) / 10 ** places

/** A per-day series with a zero wherever nothing happened, keyed by the given fields. */
const fillDays = <K extends string>(rows: unknown[][], keys: K[]): ({ day: string } & Record<K, number>)[] => {
  const seen = new Map(rows.map((r) => [String(r[0]).slice(0, 10), r.slice(1)]))
  return everyDay().map((day) => {
    const values = seen.get(day) ?? []
    return { day, ...Object.fromEntries(keys.map((k, i) => [k, num(values[i])])) } as { day: string } & Record<K, number>
  })
}

// ---- PostHog: the website and the apps ---------------------------------------------------

let posthogKey: string | undefined
const hogql = async (query: string): Promise<unknown[][]> => {
  posthogKey ??= keychain('PostHog Personal API Key')
  // PostHog caps concurrent queries per project; a 429 is waited out, up to four times.
  for (let attemptNo = 0; ; attemptNo++) {
    try {
      const json = (await request('PostHog', POSTHOG_QUERY, {
        method: 'POST',
        headers: { Authorization: `Bearer ${posthogKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ query: { kind: 'HogQLQuery', query } }),
      })) as { results?: unknown[][] }
      return json.results ?? []
    } catch (error) {
      if (!(error instanceof HttpError && error.status === 429) || attemptNo >= 4) throw error
      await new Promise((done) => setTimeout(done, 2_000 * (attemptNo + 1)))
    }
  }
}

const inWindow = `toDate(timestamp) >= toDate('${START}')`

// A day's visitor hash that arrived from a development server is a developer, so every
// event under that hash goes, not only the referred one.
const LOCAL = `'^(https?://)?(localhost|127[.]0[.]0[.]1|0[.]0[.]0[.]0|[^/:]*[.]local)(:[0-9]+)?(/|$)'`
const devVisitors = `select distinct_id from events where ${inWindow}
  and (match(coalesce(properties.$referring_domain, ''), ${LOCAL}) or match(coalesce(properties.$referrer, ''), ${LOCAL}))`
const siteEvents = `${inWindow} and properties.$host in (${SITE_HOSTS.map((h) => `'${h}'`).join(', ')})
  and distinct_id not in (${devVisitors})`

const site = () =>
  attempt(async () => {
    const [daily, pages, referrers, clicks, excluded, downloads, campaigns] = await Promise.all([
      hogql(`select toDate(timestamp) as day, countIf(event = '$pageview'), uniqIf(distinct_id, event = '$pageview'),
             countIf(event = 'download_clicked') from events where ${siteEvents} group by day order by day limit 1000`),
      hogql(`select properties.$pathname, count() from events where event = '$pageview' and ${siteEvents}
             group by 1 order by 2 desc limit 20`),
      hogql(`select properties.$referring_domain, count() from events where event = '$pageview' and ${siteEvents}
             group by 1 order by 2 desc limit 10`),
      hogql(`select event, count() from events where event in (${CLICK_EVENTS.map((e) => `'${e}'`).join(', ')})
             and ${siteEvents} group by 1`),
      hogql(`select uniq(distinct_id) from events where ${inWindow}
             and properties.$host in (${SITE_HOSTS.map((h) => `'${h}'`).join(', ')}) and distinct_id in (${devVisitors})`),
      hogql(`select properties.store, properties.device, properties.place, count() from events
             where event = 'download_clicked' and ${siteEvents} group by 1, 2, 3 order by 4 desc limit 20`),
      hogql(`select properties.utm_source, properties.utm_campaign, uniq(distinct_id), countIf(event = '$pageview')
             from events where ${siteEvents} and properties.utm_source is not null group by 1, 2 order by 3 desc limit 20`),
    ])
    const consent = await hogql(`select properties.client, countIf(event = 'consent_opened'), countIf(event = 'consent_approved'),
             countIf(event = 'consent_denied') from events where event like 'consent_%' and ${siteEvents} group by 1 order by 2 desc limit 20`)
    const series = fillDays(daily, ['pageviews', 'visitors', 'downloads'])
    const clickCounts = new Map(clicks.map((r) => [String(r[0]), num(r[1])]))
    return {
      pageviews_total: series.reduce((s, d) => s + d.pageviews, 0),
      visitors_total: series.reduce((s, d) => s + d.visitors, 0),
      visitors_note: 'Cookieless: a visitor is a daily hash, so one person returning on three days counts three times.',
      excluded_dev_visitors: num(excluded[0]?.[0]),
      daily: series,
      pages: pages.map((r) => ({ path: str(r[0]), views: num(r[1]) })),
      referrers: referrers.map((r) => ({ domain: str(r[0]), views: num(r[1]) })),
      clicks: CLICK_EVENTS.map((event) => ({ event, count: clickCounts.get(event) ?? 0 })),
      downloads: downloads.map((r) => ({ store: str(r[0]), device: str(r[1]), place: str(r[2]), count: num(r[3]) })),
      campaigns: campaigns.map((r) => ({ source: str(r[0]), campaign: str(r[1]), visitors: num(r[2]), pageviews: num(r[3]) })),
      consent: consent.map((r) => ({ client: str(r[0]), opened: num(r[1]), approved: num(r[2]), denied: num(r[3]) })),
    }
  })

// What visitors do on the pages: sessions, where they came from and went, every click, how far
// they read, how fast the page was, and its script errors. One query at a time, to stay inside
// PostHog's limit on concurrent queries.
const AI_REFERRERS: [string, string][] = [
  ['ChatGPT', 'chatgpt[.]com|chat[.]openai[.]com|openai'],
  ['Claude', 'claude[.]ai|anthropic'],
  ['Perplexity', 'perplexity'],
  ['Gemini', 'gemini[.]google|bard[.]google'],
  ['Copilot', 'copilot[.]microsoft|bing[.]com/chat|copilot'],
  ['Other AI', 'deepseek|mistral|you[.]com|poe[.]com|meta[.]ai|grok|x[.]ai|kagi'],
]
const engagement = () =>
  attempt(async () => {
    const ask = async (query: string): Promise<unknown[][]> => hogql(query)
    const pageviews = `event = '$pageview' and ${siteEvents}`
    const [sessions] = await ask(`select count(), countIf(views = 1), quantile(0.5)(duration), avg(views) from (
        select $session_id as sid, countIf(event = '$pageview') as views, dateDiff('second', min(timestamp), max(timestamp)) as duration
        from events where ${siteEvents} and $session_id != '' group by sid having views > 0)`)
    const entries = await ask(`select entry, count() from (select $session_id as sid, argMin(properties.$pathname, timestamp) as entry
        from events where ${pageviews} and $session_id != '' group by sid) group by entry order by 2 desc limit 10`)
    const exits = await ask(`select exit, count() from (select $session_id as sid, argMax(properties.$pathname, timestamp) as exit
        from events where ${pageviews} and $session_id != '' group by sid) group by exit order by 2 desc limit 10`)
    const source = `lower(concat(coalesce(properties.$referring_domain, ''), ' ', coalesce(properties.utm_source, '')))`
    const assistant = `multiIf(${AI_REFERRERS.map(([name, pattern]) => `match(${source}, '${pattern}'), '${name}'`).join(', ')}, '')`
    const referrals = await ask(`select a, uniq(distinct_id), count() from (select ${assistant} as a, distinct_id from events where ${pageviews})
        where a != '' group by a order by 2 desc`)
    const [funnel] = await ask(`select count(), countIf(f > 0), countIf(f > 0 and d > 0 and last_download > first_feature), countIf(d > 0) from (
        select distinct_id,
          countIf(event = '$pageview' and match(properties.$pathname, '^/(features|automations)/')) as f,
          minIf(timestamp, event = '$pageview' and match(properties.$pathname, '^/(features|automations)/')) as first_feature,
          countIf(event = 'download_clicked') as d, maxIf(timestamp, event = 'download_clicked') as last_download
        from events where ${siteEvents} group by distinct_id)`)
    const questions = await ask(`select properties.question, count() from events where event = 'faq_question_opened' and ${siteEvents}
        group by 1 order by 2 desc limit 60`)
    const clicks = await ask(`select properties.page, properties.section, properties.label, properties.kind, properties.destination, count()
        from events where event = 'element_clicked' and ${siteEvents} group by 1, 2, 3, 4, 5 order by 6 desc limit 150`)
    const views = new Map((await ask(`select properties.$pathname, count() from events where ${pageviews} group by 1`)).map((r) => [str(r[0]), num(r[1])]))
    const sections = await ask(`select properties.page, properties.section, min(toInt(properties.position)), max(toInt(properties.of)), count()
        from events where event = 'section_reached' and ${siteEvents} group by 1, 2 order by 1, 3 limit 300`)
    const leaving = `select count(), quantile(0.5)(toFloat(properties.seconds)), avg(toFloat(properties.scroll_pct)),
        quantile(0.75)(toFloat(properties.lcp_ms)), quantile(0.75)(toFloat(properties.inp_ms)), quantile(0.75)(toFloat(properties.cls)),
        quantile(0.75)(toFloat(properties.fcp_ms)) from events where event = 'page_left' and ${siteEvents}`
    const [overall] = await ask(leaving)
    const byPage = await ask(leaving.replace('select count()', 'select properties.page, count()') + ' group by properties.page order by 2 desc limit 30')
    const errors = await ask(`select properties.page, properties.message, properties.file, properties.line, count() from events
        where event = 'script_error' and ${siteEvents} group by 1, 2, 3, 4 order by 5 desc limit 30`)
    const opt = (v: unknown, places = 0): number | null => (v === null || v === undefined || Number.isNaN(Number(v)) ? null : round(Number(v), places))
    const leave = (r: unknown[] | undefined, offset = 0) => ({
      left: num(r?.[offset]),
      median_seconds: opt(r?.[offset + 1], 1),
      average_scroll_pct: opt(r?.[offset + 2]),
      p75_lcp_ms: opt(r?.[offset + 3]),
      p75_inp_ms: opt(r?.[offset + 4]),
      p75_cls: opt(r?.[offset + 5], 3),
      p75_fcp_ms: opt(r?.[offset + 6]),
    })
    const count = num(sessions?.[0])
    return {
      sessions: {
        count,
        bounce_rate: count ? round(num(sessions?.[1]) / count, 3) : null,
        median_seconds: opt(sessions?.[2], 1),
        pages_per_session: opt(sessions?.[3], 2),
        note: 'A session is PostHog\'s, assigned on its servers; a bounce is a session with one page view.',
        entry_pages: entries.map((r) => ({ path: str(r[0]), sessions: num(r[1]) })),
        exit_pages: exits.map((r) => ({ path: str(r[0]), sessions: num(r[1]) })),
      },
      ai_referrals: referrals.map((r) => ({ assistant: str(r[0]), visitors: num(r[1]), pageviews: num(r[2]) })),
      funnel: {
        visitors: num(funnel?.[0]),
        saw_a_feature_page: num(funnel?.[1]),
        then_clicked_download: num(funnel?.[2]),
        clicked_download_at_all: num(funnel?.[3]),
        note: 'Per daily visitor, the same day only: a feature or automations page, then a download click after it.',
      },
      faq_questions: questions.map((r) => ({ question: str(r[0]), opened: num(r[1]) })),
      clicks: clicks.map((r) => ({ page: str(r[0]), section: str(r[1]), label: str(r[2]), kind: str(r[3]), destination: str(r[4], ''), clicks: num(r[5]) })),
      sections: sections.map((r) => {
        const pageViews = views.get(str(r[0])) ?? 0
        return { page: str(r[0]), section: str(r[1]), position: num(r[2]), of: num(r[3]), reached: num(r[4]), page_views: pageViews, share: pageViews ? round(num(r[4]) / pageViews, 3) : null }
      }),
      leaving: { ...leave(overall), by_page: byPage.map((r) => ({ page: str(r[0]), ...leave(r, 1) })) },
      errors: errors.map((r) => ({ page: str(r[0]), message: str(r[1]), file: str(r[2]), line: num(r[3]), count: num(r[4]) })),
    }
  })

const appEvents = `${inWindow} and event like 'app.%' and event != 'app.selftest'`

const app = () =>
  attempt(async () => {
    const [daily, platforms, versions, screens, events, diagnostics] = await Promise.all([
      hogql(`select toDate(timestamp) as day, count(), uniq(distinct_id) from events
             where ${appEvents} and event = 'app.launched' group by day order by day limit 1000`),
      hogql(`select platform, sum(users) from (
               select toDate(timestamp) as day, properties.platform as platform, uniq(distinct_id) as users
               from events where ${appEvents} and event = 'app.launched' group by day, platform)
             group by platform order by 2 desc`),
      hogql(`select properties.app_version, count() from events where ${appEvents} and event = 'app.launched'
             group by 1 order by 2 desc limit 20`),
      hogql(`select properties.screen, count() from events where ${appEvents} and event = 'app.screen_viewed'
             group by 1 order by 2 desc limit 30`),
      hogql(`select event, count() from events where ${appEvents} group by 1 order by 2 desc limit 100`),
      hogql(`select properties.kind, count() from events where ${appEvents} and event = 'app.diagnostic'
             group by 1 order by 2 desc`),
    ])
    // Sessions, errors, changes and widgets, one query at a time like the engagement reader.
    const [sessions] = await hogql(`select count(), quantile(0.5)(toFloat(properties.seconds)), sum(toFloat(properties.seconds)),
             quantile(0.5)(toFloat(properties.screens)) from events where ${appEvents} and event = 'app.session_ended'`)
    const errors = await hogql(`select properties.place, properties.kind, count() from events where ${appEvents}
             and event = 'app.error' group by 1, 2 order by 3 desc limit 50`)
    const changes = await hogql(`select properties.source, properties.door, count(), sum(toInt(properties.rows)) from events
             where ${appEvents} and event = 'app.change_applied' group by 1, 2 order by 3 desc limit 50`)
    const devices = await hogql(`select properties.device_class, count(), countIf(toInt(properties.widgets_installed) > 0),
             max(toInt(properties.widgets_installed)) from events where ${appEvents} and event = 'app.launched'
             and properties.device_class is not null group by 1 order by 2 desc`)
    const opt = (v: unknown, places = 0): number | null => (v === null || v === undefined || Number.isNaN(Number(v)) ? null : round(Number(v), places))
    const series = fillDays(daily, ['launches', 'users'])
    return {
      launches_total: series.reduce((s, d) => s + d.launches, 0),
      users_total: series.reduce((s, d) => s + d.users, 0),
      users_note: 'From build 34 a user is one install, counted once across days; earlier builds count a daily hash, so one person on three days counts three times.',
      daily: series,
      platforms: platforms.map((r) => ({ platform: str(r[0]), users: num(r[1]) })),
      versions: versions.map((r) => ({ version: str(r[0]), launches: num(r[1]) })),
      screens: screens.map((r) => ({ screen: str(r[0]), views: num(r[1]) })),
      events: events.map((r) => ({ event: str(r[0]), count: num(r[1]) })),
      diagnostics: diagnostics.map((r) => ({ kind: str(r[0]), count: num(r[1]) })),
      sessions: {
        count: num(sessions?.[0]),
        median_seconds: opt(sessions?.[1]),
        total_minutes: opt(num(sessions?.[2]) / 60, 1),
        median_screens: opt(sessions?.[3], 1),
        note: 'From app.session_ended: time in front, rounded to five seconds, until the app leaves the screen or quits.',
      },
      errors: errors.map((r) => ({ place: str(r[0]), kind: str(r[1]), count: num(r[2]) })),
      changes: changes.map((r) => ({ source: str(r[0]), door: str(r[1]), changes: num(r[2]), rows: num(r[3]) })),
      devices: devices.map((r) => ({ device: str(r[0]), launches: num(r[1]), launches_with_widgets: num(r[2]), most_widgets: num(r[3]) })),
    }
  })

// ---- Search Console ----------------------------------------------------------------------

/** The service-account JSON, whether the keychain holds it as text or as hex. */
const serviceAccount = (): { client_email: string; private_key: string } => {
  const raw = keychain('Google Search Console API Key').trim()
  const text = /^[0-9a-fA-F]+$/.test(raw) && raw.length % 2 === 0 ? Buffer.from(raw, 'hex').toString('utf8') : raw
  let creds: { client_email?: unknown; private_key?: unknown }
  try {
    creds = JSON.parse(text)
  } catch {
    throw new Error('The keychain item "Google Search Console API Key" is not service-account JSON.')
  }
  if (typeof creds.client_email !== 'string' || typeof creds.private_key !== 'string') {
    throw new Error('The Search Console service-account JSON lacks client_email or private_key.')
  }
  return { client_email: creds.client_email, private_key: creds.private_key }
}

const googleToken = async (creds: { client_email: string; private_key: string }): Promise<string> => {
  const now = Math.floor(Date.now() / 1000)
  const part = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url')
  const unsigned = `${part({ alg: 'RS256', typ: 'JWT' })}.${part({
    iss: creds.client_email,
    scope: 'https://www.googleapis.com/auth/webmasters.readonly',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  })}`
  const signature = createSign('RSA-SHA256').update(unsigned).sign(creds.private_key, 'base64url')
  const json = (await request('Google sign-in', 'https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${signature}` }),
  })) as { access_token?: string }
  if (!json.access_token) throw new Error('Google sign-in returned no access token.')
  return json.access_token
}

type GscRow = { keys?: string[]; clicks: number; impressions: number; ctr: number; position: number }
type GscSitemap = {
  path?: string
  type?: string
  isPending?: boolean
  lastSubmitted?: string
  lastDownloaded?: string
  errors?: string | number
  warnings?: string | number
  contents?: { type?: string; submitted?: string | number }[]
}

const search = () =>
  attempt(async () => {
    const token = await googleToken(serviceAccount())
    const ask = async (property: string, body: object): Promise<GscRow[]> => {
      const url = `https://www.googleapis.com/webmasters/v3/sites/${encodeURIComponent(property)}/searchAnalytics/query`
      const json = (await request(`Search Console (${property})`, url, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ startDate: START, endDate: TODAY, dataState: 'all', ...body }),
      })) as { rows?: GscRow[] }
      return json.rows ?? []
    }

    // The domain property first; a URL-prefix property is the fallback when the service
    // account was added to that one instead.
    const refused: string[] = []
    let property = ''
    let totals: GscRow[] = []
    for (const candidate of GSC_PROPERTIES) {
      try {
        totals = await ask(candidate, {})
        property = candidate
        break
      } catch (err) {
        if (err instanceof HttpError && err.status === 403) {
          refused.push(err.message)
          continue
        }
        throw err
      }
    }
    if (!property) throw new Error(refused.join(' | '))

    const [daily, queries, pages] = await Promise.all([
      ask(property, { dimensions: ['date'], rowLimit: 500 }),
      ask(property, { dimensions: ['query'], rowLimit: 15 }),
      ask(property, { dimensions: ['page'], rowLimit: 10 }),
    ])
    const t = totals[0]
    const days = daily.map((r) => ({ day: r.keys?.[0] ?? '', clicks: r.clicks, impressions: r.impressions }))

    // The API gives counts and dates only; the text of an error is on the Search Console screen.
    let sitemaps: Record<string, unknown>[] | null = []
    let sitemapsError: string | null = null
    try {
      const listed = (await request('Search Console (sitemaps)', `https://www.googleapis.com/webmasters/v3/sites/${encodeURIComponent(property)}/sitemaps`, {
        headers: { Authorization: `Bearer ${token}` },
      })) as { sitemap?: GscSitemap[] }
      // A count the API leaves out is unknown, not zero.
      const count = (v: unknown): number | null => (v === undefined || v === null || v === '' || Number.isNaN(Number(v)) ? null : Number(v))
      const submitted = (sm: GscSitemap, type: string): number | null => count(sm.contents?.find((c) => c.type === type)?.submitted)
      sitemaps = (listed?.sitemap ?? []).map((sm) => ({
        path: str(sm.path),
        pending: sm.isPending === true,
        last_submitted: sm.lastSubmitted ?? null,
        last_downloaded: sm.lastDownloaded ?? null,
        errors: count(sm.errors),
        warnings: count(sm.warnings),
        pages: submitted(sm, 'web'),
        images: submitted(sm, 'image'),
      }))
    } catch (err) {
      sitemaps = null
      sitemapsError = err instanceof Error ? err.message : String(err)
    }
    return {
      property,
      sitemaps,
      ...(sitemapsError ? { sitemaps_error: sitemapsError } : {}),
      ...(refused.length ? { refused_properties: refused } : {}),
      clicks_total: t?.clicks ?? 0,
      impressions_total: t?.impressions ?? 0,
      ctr: t ? round(t.ctr, 4) : null,
      position: t ? round(t.position, 1) : null,
      latest_day: days.at(-1)?.day ?? null,
      lag_note: 'Search Console data arrives 2 to 3 days late, so the newest days are partial or missing; its days are Pacific Time.',
      daily: days,
      queries: queries.map((r) => ({ query: r.keys?.[0] ?? '', clicks: r.clicks, impressions: r.impressions, position: round(r.position, 1) })),
      pages: pages.map((r) => ({ page: r.keys?.[0] ?? '', clicks: r.clicks, impressions: r.impressions })),
    }
  })

// ---- Bing Webmaster Tools ----------------------------------------------------------------

/** Bing's JSON dates are "/Date(ms-0700)/"; the milliseconds are UTC. */
const bingDay = (v: unknown): string => {
  const m = /\/Date\((-?\d+)/.exec(String(v))
  return m ? new Date(Number(m[1])).toISOString().slice(0, 10) : ''
}

type BingStat = { Query?: string; Clicks?: number; Impressions?: number; AvgImpressionPosition?: number; Date?: string }

/** Rows per query (or page) per period, summed over the window; position weighted by impressions. */
const bingTop = (rows: BingStat[], limit: number) => {
  const by = new Map<string, { clicks: number; impressions: number; weighted: number }>()
  for (const r of rows) {
    if (bingDay(r.Date) < START) continue
    const k = str(r.Query)
    const t = by.get(k) ?? { clicks: 0, impressions: 0, weighted: 0 }
    t.clicks += num(r.Clicks)
    t.impressions += num(r.Impressions)
    t.weighted += num(r.Impressions) * num(r.AvgImpressionPosition)
    by.set(k, t)
  }
  return [...by.entries()]
    .map(([key, t]) => ({ key, clicks: t.clicks, impressions: t.impressions, position: t.impressions ? round(t.weighted / t.impressions, 1) : null }))
    .sort((a, b) => b.impressions - a.impressions || b.clicks - a.clicks)
    .slice(0, limit)
}

const bing = () =>
  attempt(async () => {
    const key = keychain('bing-api-key')
    // The API takes its key only in the query string, so no error may carry the address.
    const ask = async <T,>(method: string): Promise<T[]> => {
      const url = `${BING_API}${method}?siteUrl=${encodeURIComponent(SITE_URL)}&apikey=${encodeURIComponent(key)}`
      try {
        const json = (await request(`Bing Webmaster (${method})`, url, {})) as { d?: unknown }
        return (Array.isArray(json?.d) ? json.d : []) as T[]
      } catch (err) {
        throw new Error((err instanceof Error ? err.message : String(err)).split(key).join('[key]'))
      }
    }
    type Crawl = { Date?: string; InIndex?: number; CrawledPages?: number; CrawlErrors?: number }
    type Feed = { Url?: string; Status?: string; UrlCount?: number; LastCrawled?: string; Submitted?: string }
    const [traffic, queries, pages, crawl, feeds] = await Promise.all([
      ask<BingStat>('GetRankAndTrafficStats'),
      ask<BingStat>('GetQueryStats'),
      ask<BingStat>('GetPageStats'),
      ask<Crawl>('GetCrawlStats'),
      ask<Feed>('GetFeeds'),
    ])
    const series = fillDays(traffic.map((r) => [bingDay(r.Date), r.Clicks, r.Impressions]), ['clicks', 'impressions'])
    const crawlDays = crawl.map((r) => ({ ...r, day: bingDay(r.Date) })).sort((a, b) => (a.day < b.day ? -1 : 1))
    const inWindowCrawl = crawlDays.filter((r) => r.day >= START)
    const latest = crawlDays.at(-1)
    return {
      site: SITE_URL,
      clicks_total: series.reduce((s, d) => s + d.clicks, 0),
      impressions_total: series.reduce((s, d) => s + d.impressions, 0),
      latest_day: traffic.map((r) => bingDay(r.Date)).sort().at(-1) ?? null,
      lag_note: 'Bing reports whole days, two to three days late.',
      daily: series,
      queries: bingTop(queries, 15).map((q) => ({ query: q.key, clicks: q.clicks, impressions: q.impressions, position: q.position })),
      pages: bingTop(pages, 10).map((p) => ({ page: p.key, clicks: p.clicks, impressions: p.impressions })),
      index: {
        pages_in_index: latest ? num(latest.InIndex) : null,
        as_of: latest?.day ?? null,
        pages_crawled: inWindowCrawl.reduce((s, r) => s + num(r.CrawledPages), 0),
        crawl_errors: inWindowCrawl.reduce((s, r) => s + num(r.CrawlErrors), 0),
      },
      sitemaps: feeds.map((f) => ({
        url: str(f.Url),
        status: str(f.Status),
        urls: num(f.UrlCount),
        submitted: bingDay(f.Submitted) || null,
        last_read: bingDay(f.LastCrawled) || null,
      })),
    }
  })

// ---- PageSpeed Insights ------------------------------------------------------------------

type Audit = { numericValue?: number; errorMessage?: string }
type Psi = {
  lighthouseResult?: {
    runtimeError?: { code?: string; message?: string }
    categories?: { performance?: { score?: number } }
    audits?: Record<string, Audit>
  }
  loadingExperience?: { origin_fallback?: boolean; metrics?: Record<string, { percentile?: number }> }
}

const pagespeed = async (key: string, strategy: 'mobile' | 'desktop') => {
  const url = new URL('https://www.googleapis.com/pagespeedonline/v5/runPagespeed')
  url.searchParams.set('url', SITE_URL)
  url.searchParams.set('strategy', strategy)
  url.searchParams.set('category', 'performance')
  // The key travels as a header, so it never sits in a URL or a log line.
  const json = (await request(`PageSpeed Insights (${strategy})`, url.toString(), { headers: { 'X-goog-api-key': key } }, 150_000)) as Psi
  const audits = json.lighthouseResult?.audits ?? {}
  const LAB = ['largest-contentful-paint', 'cumulative-layout-shift', 'total-blocking-time', 'first-contentful-paint']
  const lab = (id: string, places = 0) => {
    const v = audits[id]?.numericValue
    return typeof v === 'number' ? round(v, places) : null
  }
  // A null lab value is Lighthouse refusing to measure, never a zero; its reason rides along.
  const labErrors = Object.fromEntries(
    LAB.flatMap((id) => (audits[id]?.errorMessage ? [[id, audits[id]?.errorMessage]] : [])),
  )
  const runtime = json.lighthouseResult?.runtimeError
  const score = json.lighthouseResult?.categories?.performance?.score
  const field = json.loadingExperience?.metrics
  const percentile = (metric: string) => {
    const v = field?.[metric]?.percentile
    return typeof v === 'number' ? v : null
  }
  return {
    score: typeof score === 'number' ? Math.round(score * 100) : null,
    lcp_ms: lab('largest-contentful-paint'),
    cls: lab('cumulative-layout-shift', 3),
    tbt_ms: lab('total-blocking-time'),
    fcp_ms: lab('first-contentful-paint'),
    field_inp_ms: percentile('INTERACTION_TO_NEXT_PAINT'),
    field_lcp_ms: percentile('LARGEST_CONTENTFUL_PAINT_MS'),
    field_scope: field && Object.keys(field).length ? (json.loadingExperience?.origin_fallback ? 'origin' : 'url') : null,
    lab_errors: Object.keys(labErrors).length ? labErrors : null,
    runtime_error: runtime?.code ? `${runtime.code}: ${runtime.message ?? ''}`.trim() : null,
  }
}

const speed = () =>
  attempt(async () => {
    const key = keychain('PageSpeed Insights API')
    const [mobile, desktop] = await Promise.all([
      attempt(() => pagespeed(key, 'mobile')),
      attempt(() => pagespeed(key, 'desktop')),
    ])
    if (!mobile.ok && !desktop.ok) throw new Error(`${mobile.error} | ${desktop.error}`)
    return {
      url: SITE_URL,
      lab_note: 'Lab values are one synthetic Lighthouse run; field values are real Chrome users over 28 days.',
      mobile,
      desktop,
    }
  })

// ---- the hosted MCP server's counts ------------------------------------------------------

const mcp = () =>
  attempt(async () => {
    const token = keychain('Supabase Personal-Access Token')
    // read_only runs the statement as the database's read-only role: it cannot write.
    const sql = async (query: string) =>
      (await request('Supabase', SUPABASE_QUERY, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ query, read_only: true }),
      })) as Record<string, unknown>[]

    const [present] = await sql(`select to_regclass('public.mcp_daily_counts') is not null as present,
      exists (select 1 from information_schema.columns where table_schema = 'public'
              and table_name = 'mcp_daily_counts' and column_name = 'connections') as connections`)
    if (present?.present !== true) return { deployed: false }
    // Connections are counted from the migration that added the column; before it, none.
    const conns = present.connections === true ? 'sum(connections)::bigint' : '0::bigint'

    const [daily, clients, first] = await Promise.all([
      sql(`select day::text as day, sum(calls)::bigint as calls, sum(edits)::bigint as edits, ${conns} as connections
           from public.mcp_daily_counts where day >= '${START}'::date group by day order by day`),
      sql(`select client, sum(calls)::bigint as calls, sum(edits)::bigint as edits, ${conns} as connections
           from public.mcp_daily_counts where day >= '${START}'::date group by client order by 2 desc, 1`),
      sql(`select min(day)::text as day from public.mcp_daily_counts`),
    ])
    // Door, surface and tool counts arrived later, in their own tables; before them, none.
    const [detail] = await sql(`select to_regclass('public.mcp_daily_surfaces') is not null as surfaces,
      to_regclass('public.mcp_daily_tools') is not null as tools`)
    const [surfaces, tools] = await Promise.all([
      detail?.surfaces === true
        ? sql(`select client, door, surface, sum(connections)::bigint as connections, min(day)::text as since
               from public.mcp_daily_surfaces where day >= '${START}'::date group by 1, 2, 3 order by 4 desc, 1, 3`)
        : Promise.resolve(null),
      detail?.tools === true
        ? sql(`select tool, client, door, sum(calls)::bigint as calls from public.mcp_daily_tools
               where day >= '${START}'::date group by 1, 2, 3 order by 4 desc, 1`)
        : Promise.resolve(null),
    ])
    // Standing connections today, as totals: AI connections not revoked, access keys live.
    const [active] = await sql(`select
      (select count(*) from auth.oauth_consents where revoked_at is null)::int as ai_connections,
      (select count(distinct user_id) from auth.oauth_consents where revoked_at is null)::int as ai_accounts,
      (select coalesce(json_agg(x), '[]'::json) from (select coalesce(c.client_name, 'unnamed') as client, count(*)::int as connections
         from auth.oauth_consents o left join auth.oauth_clients c on c.id = o.client_id where o.revoked_at is null
         group by 1 order by 2 desc) x) as ai_by_client,
      (select count(*) from public.access_keys where revoked_at is null and (expires_at is null or expires_at > now()))::int as live_keys,
      (select count(*) from public.access_keys where revoked_at is null and last_used_at > now() - interval '30 days')::int as keys_used_30d`)
    const series = fillDays(daily.map((r) => [r.day, r.calls, r.edits, r.connections]), ['calls', 'edits', 'connections'])
    return {
      active: {
        ai_connections: num(active?.ai_connections),
        ai_accounts: num(active?.ai_accounts),
        ai_by_client: ((active?.ai_by_client ?? []) as Row[]).map((r) => ({ client: str(r.client), connections: num(r.connections) })),
        live_keys: num(active?.live_keys),
        keys_used_30d: num(active?.keys_used_30d),
        note: 'Today, not over the window: AI connections an Account has allowed and not revoked, and access keys neither revoked nor expired.',
      },
      surfaces: surfaces?.map((r) => ({ client: str(r.client), door: str(r.door), surface: str(r.surface), connections: num(r.connections), since: str(r.since) })) ?? null,
      tools: tools?.map((r) => ({ tool: str(r.tool), client: str(r.client), door: str(r.door), calls: num(r.calls) })) ?? null,
      deployed: true,
      connections_counted: present.connections === true,
      counted_since: first[0]?.day ?? null,
      calls_total: series.reduce((s, d) => s + d.calls, 0),
      edits_total: series.reduce((s, d) => s + d.edits, 0),
      connections_total: series.reduce((s, d) => s + d.connections, 0),
      daily: series,
      clients: clients.map((r) => ({ client: str(r.client), calls: num(r.calls), edits: num(r.edits), connections: num(r.connections) })),
    }
  })

// ---- AI crawlers at the website (Cloudflare) ---------------------------------------------

// AI fetchers by the name their user agent carries. Purpose is the company's own label:
// training, search, or a fetch made while answering one person's question.
const CRAWLERS: { name: string; owner: string; purpose: string; match: RegExp }[] = [
  { name: 'GPTBot', owner: 'OpenAI', purpose: 'training', match: /GPTBot/i },
  { name: 'OAI-SearchBot', owner: 'OpenAI', purpose: 'search', match: /OAI-SearchBot/i },
  { name: 'ChatGPT-User', owner: 'OpenAI', purpose: 'user request', match: /ChatGPT-User/i },
  { name: 'ClaudeBot', owner: 'Anthropic', purpose: 'training', match: /ClaudeBot/i },
  { name: 'Claude-SearchBot', owner: 'Anthropic', purpose: 'search', match: /Claude-SearchBot/i },
  { name: 'Claude-User', owner: 'Anthropic', purpose: 'user request', match: /Claude-User/i },
  { name: 'PerplexityBot', owner: 'Perplexity', purpose: 'search', match: /PerplexityBot/i },
  { name: 'Perplexity-User', owner: 'Perplexity', purpose: 'user request', match: /Perplexity-User/i },
  { name: 'Googlebot', owner: 'Google', purpose: 'search', match: /Googlebot/i },
  { name: 'Bingbot', owner: 'Microsoft', purpose: 'search', match: /bingbot/i },
  { name: 'Applebot', owner: 'Apple', purpose: 'search', match: /Applebot/i },
  { name: 'Amazonbot', owner: 'Amazon', purpose: 'assistant', match: /Amazonbot/i },
  { name: 'Meta', owner: 'Meta', purpose: 'training', match: /meta-external|FacebookBot/i },
  { name: 'Bytespider', owner: 'ByteDance', purpose: 'training', match: /Bytespider/i },
  { name: 'CCBot', owner: 'Common Crawl', purpose: 'training', match: /CCBot/i },
  { name: 'DuckAssistBot', owner: 'DuckDuckGo', purpose: 'assistant', match: /DuckAssistBot/i },
  { name: 'MistralAI-User', owner: 'Mistral', purpose: 'user request', match: /MistralAI-User/i },
]

type CfGroup = { count: number; dimensions: { userAgent?: string; verifiedBotCategory?: string; edgeResponseStatus?: number } }
/** A group and the 24-hour step it came from; step 0 is the most recent. */
type Stepped = CfGroup & { step: number }

const crawlers = () =>
  attempt(async () => {
    const token = keychain('Cloudflare API Token')
    // One day per query, newest first, until Cloudflare says a day is past what this plan keeps.
    const day = async (from: Date, to: Date): Promise<CfGroup[]> => {
      const query = `{viewer{zones(filter:{zoneTag:"${CLOUDFLARE_ZONE}"}){httpRequestsAdaptiveGroups(limit:1000,
        filter:{datetime_geq:"${from.toISOString()}",datetime_lt:"${to.toISOString()}",requestSource:"eyeball"},
        orderBy:[count_DESC]){count dimensions{userAgent verifiedBotCategory edgeResponseStatus}}}}}`
      const json = (await request('Cloudflare', CLOUDFLARE_GRAPHQL, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ query }),
      })) as { data?: { viewer?: { zones?: { httpRequestsAdaptiveGroups?: CfGroup[] }[] } }; errors?: { message?: string }[] }
      if (json.errors?.length) throw new Error(`Cloudflare: ${str(json.errors[0]?.message).slice(0, 300)}`)
      return json.data?.viewer?.zones?.[0]?.httpRequestsAdaptiveGroups ?? []
    }
    const groups: Stepped[] = []
    let fullDays = 0
    let daysRead = 0
    let limit: string | null = null
    const now = Date.now()
    for (let i = 0; i < Math.min(DAYS, 7); i++) {
      try {
        const got = await day(new Date(now - (i + 1) * 86_400_000), new Date(now - i * 86_400_000))
        // A query that returns its full limit has dropped its smallest groups.
        if (got.length >= 1000) fullDays++
        groups.push(...got.map((g) => ({ ...g, step: i })))
        daysRead++
      } catch (err) {
        if (i === 0) throw err
        limit = err instanceof Error ? err.message : String(err)
        break
      }
    }
    const by = new Map<string, { name: string; owner: string; purpose: string; requests: number; refused: number; verified: number; verified_refused: number; verified_refused_24h: number; sample?: string }>()
    for (const g of groups) {
      const ua = g.dimensions.userAgent ?? ''
      const category = g.dimensions.verifiedBotCategory ?? ''
      const known = CRAWLERS.find((c) => c.match.test(ua))
      if (!known && !/^AI/i.test(category)) continue
      const name = known?.name ?? str(ua.split(/[\s/;(]/).find((w) => /bot|agent|crawl|user/i.test(w)) ?? category)
      const row = by.get(name) ?? { name, owner: known?.owner ?? '(unknown)', purpose: known?.purpose ?? category.toLowerCase(), requests: 0, refused: 0, verified: 0, verified_refused: 0, verified_refused_24h: 0, ...(known ? {} : { sample: str(ua).slice(0, 60) }) }
      row.requests += g.count
      const status = num(g.dimensions.edgeResponseStatus)
      const failed = status === 403 || status === 429 || status >= 500
      if (failed) row.refused += g.count
      // A user agent can be forged; a verified category means Cloudflare matched the real operator.
      if (category) {
        row.verified += g.count
        if (failed) row.verified_refused += g.count
        if (failed && g.step === 0) row.verified_refused_24h += g.count
      }
      by.set(name, row)
    }
    const rows = [...by.values()].sort((a, b) => b.requests - a.requests)
    return {
      days_read: daysRead,
      ...(limit ? { older_days: limit } : {}),
      window_note: `The last ${daysRead} day(s) to this run, in 24-hour steps; Cloudflare keeps only a short history on this plan. Rows that are not verified include any test requests made with a crawler's name.${fullDays ? ` ${fullDays} day(s) hit the 1000-group query limit, so their smallest groups are missing.` : ''}`,
      requests_total: rows.reduce((s, r) => s + r.requests, 0),
      verified_total: rows.reduce((s, r) => s + r.verified, 0),
      refused_total: rows.reduce((s, r) => s + r.refused, 0),
      verified_refused_total: rows.reduce((s, r) => s + r.verified_refused, 0),
      verified_refused_24h_total: rows.reduce((s, r) => s + r.verified_refused_24h, 0),
      crawlers: rows,
    }
  })

// ---- the feedback board (insigh.to) ------------------------------------------------------

/** The first JSON array after `"posts":` in text, read with strings respected. */
const postsArray = (text: string): unknown[] | null => {
  const at = text.indexOf('"posts":[')
  if (at < 0) return null
  const start = text.indexOf('[', at)
  let depth = 0
  let inString = false
  for (let i = start; i < text.length; i++) {
    const c = text[i]
    if (inString) {
      if (c === '\\') i++
      else if (c === '"') inString = false
    } else if (c === '"') inString = true
    else if (c === '[' || c === '{') depth++
    else if ((c === ']' || c === '}') && --depth === 0) return JSON.parse(text.slice(start, i + 1)) as unknown[]
  }
  return null
}

const feedback = () =>
  attempt(async () => {
    const res = await fetch(FEEDBACK_BOARD, { signal: AbortSignal.timeout(30_000) })
    if (!res.ok) throw new HttpError(res.status, `insigh.to answered HTTP ${res.status}`)
    const html = await res.text()
    // The board ships its posts inside the page's Next.js payload: string chunks pushed to
    // self.__next_f, each a JSON-encoded string once unwrapped.
    const chunks = [...html.matchAll(/self\.__next_f\.push\((\[[\s\S]*?\])\)<\/script>/g)].map((m) => {
      try {
        const v = JSON.parse(m[1]) as unknown[]
        return typeof v[1] === 'string' ? v[1] : ''
      } catch {
        return ''
      }
    })
    const posts = postsArray(chunks.join(''))
    if (!posts) throw new Error('The board page no longer carries its posts where this reader looks.')
    type Post = { title?: unknown; votes?: unknown; upvotes?: unknown; votesCount?: unknown; status?: unknown }
    return {
      board: FEEDBACK_BOARD,
      posts_total: posts.length,
      posts: (posts as Post[]).slice(0, 20).map((p) => ({
        title: str(p.title),
        votes: num(p.votes ?? p.upvotes ?? p.votesCount),
        status: str(p.status, ''),
      })),
    }
  })

// ---- the npm package and the Claude plugin repository ------------------------------------

const NPM_PACKAGE = '@longbook/mcp'
const PLUGIN_REPO = 'MXmaster2s/longbook-claude-plugin'

// npm's download counts are public and count every fetch: mirrors, registries, scanners, CI and
// each npx run, so they measure reach, not people. GitHub's clone and view figures cover the last
// 14 days and need push access, which the signed-in gh CLI holds; its token never leaves this process.
const packages = () =>
  attempt(async () => {
    const npmGet = async (url: string): Promise<Record<string, unknown>> =>
      (await request('npm', url, { headers: { Accept: 'application/json' } })) as Record<string, unknown>
    const name = encodeURIComponent(NPM_PACKAGE).replace('%40', '@')
    const range = (await npmGet(`https://api.npmjs.org/downloads/range/${START}:${TODAY}/${name}`)) as { downloads?: { day: string; downloads: number }[] }
    const versions = (await npmGet(`https://api.npmjs.org/versions/${encodeURIComponent(NPM_PACKAGE)}/last-week`).catch(() => ({}))) as { downloads?: Record<string, number> }
    const series = fillDays((range.downloads ?? []).map((r) => [r.day, r.downloads]), ['downloads'])
    const registry = (await npmGet(`https://registry.npmjs.org/${encodeURIComponent(NPM_PACKAGE)}`).catch(() => ({}))) as { time?: Record<string, string> }
    const published = Object.entries(registry.time ?? {})
      .filter(([k]) => /^\d/.test(k) && !k.includes('-'))
      .sort((a, b) => (a[1] < b[1] ? -1 : 1))
    const npm = {
      package: NPM_PACKAGE,
      created: registry.time?.created ?? null,
      total: series.reduce((t, d) => t + d.downloads, 0),
      daily: series,
      versions: Object.entries(versions.downloads ?? {})
        .map(([version, downloads]) => ({ version, downloads: num(downloads) }))
        .sort((a, b) => b.downloads - a.downloads)
        .slice(0, 8),
      releases: published.slice(-6).map(([version, at]) => ({ version, published: at.slice(0, 10) })),
      note: 'npm counts every fetch, including mirrors, registries, scanners and each npx run, so a download is not a person. Counts arrive a day or two late.',
    }

    let plugin: Record<string, unknown>
    try {
      const token = execFileSync('gh', ['auth', 'token'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
      const gh = async (path: string): Promise<Record<string, unknown>> =>
        (await request('GitHub', `https://api.github.com/repos/${PLUGIN_REPO}${path}`, {
          headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'User-Agent': 'longbook-metrics' },
        })) as Record<string, unknown>
      const [clones, views, repo] = (await Promise.all([gh('/traffic/clones'), gh('/traffic/views'), gh('')])) as [
        { count?: number; uniques?: number; clones?: { timestamp: string; count: number; uniques: number }[] },
        { count?: number; uniques?: number; views?: { timestamp: string; count: number }[] },
        { stargazers_count?: number; forks_count?: number },
      ]
      const byDay = new Map<string, { clones: number; unique_clones: number; views: number }>()
      for (const c of clones.clones ?? []) byDay.set(c.timestamp.slice(0, 10), { clones: num(c.count), unique_clones: num(c.uniques), views: 0 })
      for (const v of views.views ?? []) {
        const d = byDay.get(v.timestamp.slice(0, 10)) ?? { clones: 0, unique_clones: 0, views: 0 }
        byDay.set(v.timestamp.slice(0, 10), { ...d, views: num(v.count) })
      }
      plugin = {
        repo: PLUGIN_REPO,
        clones: num(clones.count),
        unique_cloners: num(clones.uniques),
        views: num(views.count),
        unique_viewers: num(views.uniques),
        stars: num(repo.stargazers_count),
        forks: num(repo.forks_count),
        daily: fillDays([...byDay].map(([day, v]) => [day, v.clones, v.unique_clones, v.views]), ['clones', 'unique_clones', 'views']),
        note: 'GitHub keeps 14 days of clone and view counts. A clone happens when /plugin marketplace add runs, and also when a bot or mirror copies the repository.',
      }
    } catch (error) {
      plugin = { repo: PLUGIN_REPO, error: error instanceof Error ? error.message : String(error) }
    }
    return { npm, plugin }
  })

// ---- run ---------------------------------------------------------------------------------

const readers: Record<Source, () => Promise<Outcome<object>>> = { site, engagement, app, search, bing, speed, mcp, crawlers, feedback, packages }
const results = await Promise.all(ONLY.map(async (s) => [s, await readers[s]()] as const))
const sources = Object.fromEntries(results) as Partial<Record<Source, Outcome<Record<string, unknown>>>>

if (JSON_OUT) {
  const path = resolve(JSON_OUT)
  mkdirSync(dirname(path), { recursive: true })
  const snapshot = { taken_at: new Date().toISOString().replace(/\.\d+Z$/, 'Z'), window_days: DAYS, window: { from: START, to: TODAY }, sources }
  writeFileSync(path, `${JSON.stringify(snapshot, null, 2)}\n`)
  console.log(`Snapshot written: ${path}`)
}

// A short readable summary, one block per source.
type Row = Record<string, unknown>
const list = (rows: unknown, name: string, value: string, limit = 6): string => {
  const r = (Array.isArray(rows) ? rows : []) as Row[]
  return r.length ? r.slice(0, limit).map((x) => `${str(x[name])} ${str(x[value], '0')}`).join(', ') : 'none'
}
const lines: string[] = [`Window: ${START} to ${TODAY} (${DAYS} days, UTC)`]
for (const [name, r] of results) {
  lines.push('')
  if (!r.ok) {
    lines.push(`${name}: failed. ${r.error}`)
    continue
  }
  const o = r as Row
  if (name === 'site') {
    lines.push(`site: ${o.pageviews_total} page views, ${o.visitors_total} daily visitors (summed); ${o.excluded_dev_visitors} development visitors excluded`)
    lines.push(`  pages: ${list(o.pages, 'path', 'views')}`)
    lines.push(`  referrers: ${list(o.referrers, 'domain', 'views')}`)
    lines.push(`  clicks: ${list(o.clicks, 'event', 'count')}`)
    lines.push(`  consent screen (opened): ${list(o.consent, 'client', 'opened')}`)
  } else if (name === 'engagement') {
    const sessions = o.sessions as Row
    const leaving = o.leaving as Row
    const rate = typeof sessions.bounce_rate === 'number' ? `${round(sessions.bounce_rate * 100)}%` : 'n/a'
    lines.push(`engagement: ${sessions.count} sessions, bounce rate ${rate}, ${str(sessions.pages_per_session, 'n/a')} pages per session`)
    lines.push(`  from AI assistants: ${list(o.ai_referrals, 'assistant', 'visitors')}`)
    lines.push(`  FAQ questions: ${list(o.faq_questions, 'question', 'opened', 5)}`)
    lines.push(`  clicks: ${list(o.clicks, 'label', 'clicks', 8)}`)
    lines.push(`  pages left: ${leaving.left}, median ${str(leaving.median_seconds, 'n/a')} s, scroll ${str(leaving.average_scroll_pct, 'n/a')}%, p75 LCP ${str(leaving.p75_lcp_ms, 'n/a')} ms`)
    lines.push(`  script errors: ${list(o.errors, 'message', 'count', 3)}`)
  } else if (name === 'app') {
    lines.push(`app: ${o.launches_total} launches, ${o.users_total} daily users (summed)`)
    lines.push(`  platforms: ${list(o.platforms, 'platform', 'users')}`)
    lines.push(`  versions: ${list(o.versions, 'version', 'launches')}`)
    lines.push(`  events: ${list(o.events, 'event', 'count', 10)}`)
    lines.push(`  diagnostics: ${list(o.diagnostics, 'kind', 'count')}`)
    const s = o.sessions as Row
    lines.push(`  sessions: ${s.count}, median ${str(s.median_seconds, 'n/a')} s, ${str(s.total_minutes, '0')} min in all`)
    lines.push(`  errors: ${list(o.errors, 'place', 'count')}`)
    lines.push(`  file changes: ${list(o.changes, 'source', 'changes')}`)
  } else if (name === 'search') {
    const ctr = typeof o.ctr === 'number' ? `${round(o.ctr * 100, 1)}%` : 'n/a'
    lines.push(`search (${o.property}): ${o.clicks_total} clicks, ${o.impressions_total} impressions, CTR ${ctr}, average position ${str(o.position, 'n/a')}`)
    lines.push(`  newest day with data: ${str(o.latest_day, 'none')} (${o.lag_note})`)
    lines.push(`  queries: ${list(o.queries, 'query', 'clicks')}`)
    if (Array.isArray(o.sitemaps) && o.sitemaps.length === 0) lines.push('  sitemap: none submitted to Google')
    for (const sm of (Array.isArray(o.sitemaps) ? o.sitemaps : []) as Row[]) {
      const read = typeof sm.last_downloaded === 'string' ? sm.last_downloaded.slice(0, 10) : 'never'
      lines.push(`  sitemap ${str(sm.path)}: read ${read}, ${str(sm.errors, 'n/a')} errors, ${str(sm.warnings, 'n/a')} warnings, ${str(sm.pages, 'n/a')} pages${sm.pending ? ' (re-read pending)' : ''}`)
    }
    if (o.sitemaps_error) lines.push(`  sitemap status unavailable: ${str(o.sitemaps_error)}`)
  } else if (name === 'speed') {
    for (const strategy of ['mobile', 'desktop'] as const) {
      const s = o[strategy] as Outcome<Row>
      if (!s.ok) {
        lines.push(`speed ${strategy}: failed. ${s.error}`)
        continue
      }
      lines.push(
        `speed ${strategy}: score ${str(s.score, 'n/a')}, LCP ${str(s.lcp_ms, 'n/a')} ms, CLS ${str(s.cls, 'n/a')}, ` +
          `TBT ${str(s.tbt_ms, 'n/a')} ms, FCP ${str(s.fcp_ms, 'n/a')} ms; field INP ${str(s.field_inp_ms, 'n/a')}, field LCP ${str(s.field_lcp_ms, 'n/a')}`,
      )
      if (s.lab_errors) lines.push(`  Lighthouse could not measure: ${Object.entries(s.lab_errors as Row).map(([k, v]) => `${k} (${str(v)})`).join(', ')}`)
      if (s.runtime_error) lines.push(`  Lighthouse runtime error: ${s.runtime_error}`)
    }
  } else if (name === 'bing') {
    const index = o.index as Row
    lines.push(`bing: ${o.clicks_total} clicks, ${o.impressions_total} impressions; ${str(index.pages_in_index, 'n/a')} pages in the index (${str(index.as_of, 'n/a')})`)
    lines.push(`  sitemaps: ${list(o.sitemaps, 'url', 'status')}`)
    lines.push(`  queries: ${list(o.queries, 'query', 'clicks')}`)
  } else if (name === 'mcp') {
    lines.push(
      o.deployed
        ? `mcp: ${o.calls_total} tool calls, ${o.edits_total} proposals filed, ` +
            `${o.connections_counted ? `${o.connections_total} connections` : 'connections not counted yet'}; by application: ${list(o.clients, 'client', 'calls')}`
        : 'mcp: not deployed yet (no mcp_daily_counts table).',
    )
    const a = o.active as Row | undefined
    if (a) lines.push(`  standing today: ${a.ai_connections} AI connections on ${a.ai_accounts} accounts (${list(a.ai_by_client, 'client', 'connections')}); ${a.live_keys} live access keys, ${a.keys_used_30d} used in 30 days`)
    if (Array.isArray(o.surfaces)) lines.push(`  connections by surface: ${list(o.surfaces, 'surface', 'connections')}`)
    if (Array.isArray(o.tools)) lines.push(`  tool calls: ${list(o.tools, 'tool', 'calls', 8)}`)
  } else if (name === 'crawlers') {
    lines.push(`crawlers: ${o.requests_total} requests carrying a listed crawler's name over ${o.days_read} day(s), ${o.verified_total} of them verified by Cloudflare; ${o.refused_total} refused (403, 429 or 5xx)`)
    lines.push(`  by crawler: ${list(o.crawlers, 'name', 'requests', 10)}`)
    const real = ((o.crawlers ?? []) as Row[]).filter((c) => num(c.verified_refused) > 0).sort((a, b) => num(b.verified_refused_24h) - num(a.verified_refused_24h) || num(b.verified_refused) - num(a.verified_refused))
    lines.push(`  verified crawlers refused: ${o.verified_refused_24h_total} in the last 24 hours, ${o.verified_refused_total} in ${o.days_read} day(s)`)
    if (real.length) lines.push(`    ${real.map((c) => `${str(c.name)} ${c.verified_refused_24h} in the last 24 hours (${c.verified_refused} in the window)`).join(', ')}`)
    lines.push('  Crawlers Cloudflare does not verify count in the totals only.')
  } else if (name === 'feedback') {
    lines.push(`feedback: ${o.posts_total} posts on ${o.board}`)
  } else if (name === 'packages') {
    const n = o.npm as Row
    const pl = o.plugin as Row
    lines.push(`packages: ${n.package} ${n.total} npm downloads in the window (every fetch counts, so not people); newest: ${list(n.daily && (n.daily as Row[]).slice(-3), 'day', 'downloads', 3)}`)
    lines.push(pl.error ? `  plugin repo: unavailable (${str(pl.error)})` : `  plugin repo: ${pl.clones} clones (${pl.unique_cloners} unique), ${pl.views} views, ${pl.stars} stars, ${pl.forks} forks, last 14 days`)
  }
}
console.log(lines.join('\n'))

// Any failed source fails the run, after everything that did answer is written.
process.exit(results.every(([, r]) => r.ok) ? 0 : 1)
