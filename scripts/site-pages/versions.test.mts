// The Products menu's versions: each read from the file that ships the product, never typed.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { macVersion, iphoneBeta, products, productsMenu, productsBurger, versionOf, versionsJson } from './versions.mts'
import { DOWNLOAD, DOWNLOAD_MAC, DOWNLOAD_MAC_PAGE } from './content.mts'

const item = (version: string, build: number): string =>
  `<item><title>${version}</title><sparkle:version>${build}</sparkle:version><sparkle:shortVersionString>${version}</sparkle:shortVersionString></item>`

test('the Mac version is the newest appcast item, and project.yml before the first release', () => {
  const feed = `<rss><channel>${item('1.4.1', 52)}${item('1.5.0', 66)}${item('1.4.9', 60)}</channel></rss>`
  assert.deepEqual(macVersion(feed, 'MARKETING_VERSION: "9.9.9"'), { version: '1.5.0', build: 66 })
  assert.deepEqual(macVersion('<rss><channel></channel></rss>', '    MARKETING_VERSION: "1.6.0"'), { version: '1.6.0', build: null })
  assert.throws(() => macVersion('', ''))
})

test('the iPhone beta is the newest build the ledger sent to TestFlight', () => {
  const ledger = JSON.stringify({
    9: { version: '1.4.0', testflight: '2026-10-01' },
    10: { version: '1.5.0', testflight: '2026-10-31' },
    11: { version: '1.5.0' },
  })
  assert.deepEqual(iphoneBeta(ledger), { version: '1.5.0', build: 10 })
  assert.equal(iphoneBeta(JSON.stringify({ 3: { version: '1.0.0' } })), null)
})

const list = products({ mac: { version: '1.5.0', build: 66 }, iphone: { version: '1.5.0', build: 66 }, release: '1.50.0' })

test('the Products menu lists every product by its short name with its version', () => {
  assert.equal(versionOf(list, 'mac'), '1.5.0')
  assert.equal(versionOf(list, 'iphone'), '1.5.0 (66)')
  assert.equal(versionOf(list, 'app-store'), null, 'no App Store entry until the app is there')
  const menu = productsMenu(list)
  assert.match(menu, /aria-haspopup="menu" aria-expanded="false" aria-controls="products">Products/)
  assert.ok(menu.includes(`href="${DOWNLOAD_MAC_PAGE}">`), 'Mac opens the download page')
  assert.ok(!menu.includes(DOWNLOAD_MAC), 'the menu never links the disk image itself')
  assert.ok(productsBurger(list).includes(`href="${DOWNLOAD_MAC_PAGE}">Mac<small>`))
  assert.ok(menu.includes(`href="${DOWNLOAD}" rel="noopener"`), 'iPhone is the TestFlight beta')
  assert.ok(!menu.includes('Coming soon') && !menu.includes('aria-disabled'))
  assert.ok(menu.includes('<span>Mac</span><small>Download · Version 1.5.0</small>'))
  assert.ok(!menu.includes('longbook for'), 'the name is not repeated on every line')
  assert.equal((menu.match(/role="menuitem"/g) ?? []).length, 5)
})

test('versions.json carries the same list with absolute links', () => {
  const json = JSON.parse(versionsJson(list)) as { products: { id: string; link: string | null; version: string | null }[] }
  assert.deepEqual(json.products.map((p) => p.id), ['mac', 'iphone', 'claude', 'chatgpt', 'mcp'])
  for (const p of json.products) assert.ok(p.link === null || p.link.startsWith('https://'), p.id)
  assert.equal(json.products.find((p) => p.id === 'mcp')?.version, '1.50.0')
  assert.equal(json.products.find((p) => p.id === 'mac')?.link, DOWNLOAD_MAC, 'tools are given the disk image')
})
