// Every longbook product, where it comes from and its live version, read at build time from the
// files that ship each one, so no version on the site is typed by hand. The header's Products
// menu, the download page and versions.json are all drawn from this one list.
import { ORIGIN, DOWNLOAD, DOWNLOAD_MAC, DOWNLOAD_MAC_PAGE } from './content.mts'
import { attr, esc } from './render.mts'

export interface Product {
  id: string
  name: string
  // Shown as the menu item's second line, before the version.
  where: string
  version: string | null
  // A path on the site or an https address; null for a product that has no page yet.
  link: string | null
  // Where the menus send a person, when that differs from the link versions.json gives tools.
  page?: string
}

export interface Versions {
  mac: { version: string; build: number | null }
  iphone: { version: string; build: number } | null
  release: string
}

/** The Mac app: the newest item in the Sparkle appcast, else the version project.yml names. */
export function macVersion(appcast: string, projectYml: string): Versions['mac'] {
  const items = [...appcast.matchAll(/<item>([\s\S]*?)<\/item>/g)].map((m) => ({
    version: /<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>/.exec(m[1]!)?.[1]?.trim() ?? '',
    build: Number(/<sparkle:version>(\d+)<\/sparkle:version>/.exec(m[1]!)?.[1] ?? NaN),
  })).filter((i) => i.version && Number.isFinite(i.build))
  const newest = items.sort((a, b) => b.build - a.build)[0]
  if (newest) return newest
  const marketing = /MARKETING_VERSION: "([^"]+)"/.exec(projectYml)?.[1]
  if (!marketing) throw new Error('the appcast has no item and project.yml names no MARKETING_VERSION')
  return { version: marketing, build: null }
}

/** The iPhone beta: the newest build in the device ledger that went to TestFlight. */
export function iphoneBeta(ledgerJson: string): Versions['iphone'] {
  const ledger = JSON.parse(ledgerJson) as Record<string, { version: string; testflight?: string }>
  const shipped = Object.entries(ledger).filter(([, e]) => e.testflight).map(([b, e]) => ({ version: e.version, build: Number(b) }))
  return shipped.sort((a, b) => b.build - a.build)[0] ?? null
}

export const CLAUDE_PAGE = '/features/automate-longbook-with-claude/'
export const CHATGPT_PAGE = '/help/connect-claude-or-chatgpt/'
export const NPM_PAGE = '/features/longbook-npm-package/'

export function products(v: Versions): Product[] {
  return [
    { id: 'mac', name: 'Mac', where: 'Download', version: v.mac.version, link: DOWNLOAD_MAC, page: DOWNLOAD_MAC_PAGE },
    { id: 'iphone', name: 'iPhone', where: 'Beta on TestFlight', version: v.iphone ? `${v.iphone.version} (${v.iphone.build})` : null, link: DOWNLOAD },
    { id: 'claude', name: 'Claude', where: 'Plugin and connector', version: v.release, link: CLAUDE_PAGE },
    { id: 'chatgpt', name: 'ChatGPT', where: 'Connector', version: v.release, link: CHATGPT_PAGE },
    { id: 'mcp', name: 'MCP server', where: 'npm package', version: v.release, link: NPM_PAGE },
  ]
}

/** The version a page names in a <span data-version="…">, by product id. */
export function versionOf(list: Product[], id: string): string | null {
  return list.find((p) => p.id === id)?.version ?? null
}

/** versions.json: the same list, with every link absolute, for other pages and tools to read. */
export function versionsJson(list: Product[]): string {
  return `${JSON.stringify({
    products: list.map((p) => ({
      id: p.id,
      name: p.name,
      version: p.version,
      link: p.link === null ? null : p.link.startsWith('/') ? `${ORIGIN}${p.link}` : p.link,
      where: p.where,
    })),
  }, null, 2)}\n`
}

const APPLE = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M17.05 12.04c-.02-2.2 1.8-3.26 1.88-3.31-1.02-1.5-2.61-1.7-3.18-1.72-1.35-.14-2.64.8-3.33.8-.69 0-1.75-.78-2.87-.76-1.48.02-2.84.86-3.6 2.18-1.53 2.66-.39 6.6 1.1 8.76.73 1.06 1.6 2.25 2.74 2.2 1.1-.04 1.51-.71 2.84-.71 1.33 0 1.7.71 2.86.69 1.18-.02 1.93-1.08 2.65-2.14.83-1.23 1.18-2.42 1.2-2.48-.03-.01-2.3-.88-2.32-3.5zM14.9 5.5c.6-.74 1.01-1.76.9-2.78-.87.04-1.93.58-2.56 1.31-.56.65-1.05 1.69-.92 2.68.97.08 1.96-.49 2.58-1.21z"/></svg>'
const TERMINAL = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="3"/><path d="M7.5 9.5l3 2.5-3 2.5M12.5 15h4"/></svg>'
const ICONS: Record<string, string> = {
  mac: APPLE,
  iphone: APPLE,
  claude: '<img src="/claude-mark.png" width="15" height="15" alt="">',
  chatgpt: '<img src="/chatgpt-mark.png" width="15" height="15" alt="">',
  mcp: TERMINAL,
}

const detail = (p: Product): string => esc(p.version ? `${p.where} · Version ${p.version}` : p.where)
const outward = (href: string): string => (href.startsWith('https://') ? ' rel="noopener"' : '')

/** The header's Products dropdown: a button and a menu of every product, each with its version. */
export function productsMenu(list: Product[]): string {
  const items = list.map((p) => {
    const body = `${ICONS[p.id] ?? ''}<span class="pmi"><span>${esc(p.name)}</span><small>${detail(p)}</small></span>`
    const href = p.page ?? p.link
    return href
      ? `          <a role="menuitem" href="${attr(href)}"${outward(href)}>${body}</a>`
      : `          <span role="menuitem" aria-disabled="true" class="pmoff">${body}</span>`
  })
  return [
    '<div class="dl">',
    '        <button class="btn sm dlb" type="button" aria-haspopup="menu" aria-expanded="false" aria-controls="products">Products',
    '          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true" style="width:12px;height:12px"><path d="M6 9l6 6 6-6"/></svg>',
    '        </button>',
    '        <div class="dlm" id="products" role="menu" aria-label="Products" hidden>',
    ...items,
    '        </div>',
    '      </div>',
  ].join('\n')
}

/** The same products in the burger menu, under their own heading. */
export function productsBurger(list: Product[]): string {
  const rows = list.map((p) => {
    const body = `${esc(p.name)}<small>${detail(p)}</small>`
    const href = p.page ?? p.link
    return href ? `<a href="${attr(href)}"${outward(href)}>${body}</a>` : `<span class="bsoon">${body}</span>`
  })
  return `<p class="bmh">Products</p>${rows.join('')}`
}
