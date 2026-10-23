// The App Store's creative assets, a pair per product page: the header (3840 x 1646) and the search
// results image (3840 x 2560), each a feature claim at phone-readable size beside a slice of the real
// capture. Rendered by Google Chrome, headless. Run: npm run store:header
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const FONTS = pathToFileURL(join(ROOT, 'apps/longbook-site/fonts')).href
const BOOK = pathToFileURL(join(ROOT, 'images/brand/longbook_icon_nobackground.png')).href
const SOURCE = join(ROOT, 'images/screenshots/ios/appstore/source')
const OUT = join(ROOT, 'images/screenshots/creative-assets')

// One page per search intent: the default listing, then a custom product page for each keyword
// group. `top` is where the capture's slice starts, in capture pixels, chosen to show the rows.
interface Page { key: string; claim: string; source: string; top: number }
const PAGES: Page[] = [
  { key: 'default', claim: 'Every subscription, before it charges you', source: 'commitments', top: 1290 },
  { key: 'reminders', claim: 'Every bill, on the day it is due', source: 'calendar', top: 380 },
  { key: 'family', claim: 'Everyone’s bills, in one longbook', source: 'members', top: 560 },
  { key: 'ai', claim: 'Your AI keeps it current', source: 'automations', top: 1126 },
  { key: 'private', claim: 'Private by design, no bank login', source: 'dashboard', top: 350 },
]

const esc = (s: string): string => s.replace(/&/g, '&amp;').replace(/</g, '&lt;')

const base = (w: number, h: number): string => `
@font-face { font-family: 'Fraunces'; src: url('${FONTS}/Fraunces-Variable.woff2') format('woff2'); font-weight: 100 900; }
html, body { margin: 0; width: ${w}px; height: ${h}px; overflow: hidden; background: #0D1115; }
body { position: relative; -webkit-font-smoothing: antialiased; }
h1 { margin: 0; font-family: 'Fraunces', serif; font-weight: 520; font-variation-settings: 'opsz' 100, 'SOFT' 50;
  color: #EEF1F4; letter-spacing: -0.014em; text-wrap: balance; }
`

// Search results, 3:2. On an iPhone the whole image shows, so the claim fills the left half at a
// size that reads at phone width and the capture's rows fill the right, running off the bottom.
const search = (p: Page, shot: string): string => `<!doctype html><meta charset="utf-8"><style>${base(3840, 2560)}
.glow { position: absolute; inset: 0; background: radial-gradient(ellipse 34% 56% at 72% 50%, rgba(109, 90, 230, 0.32), transparent 70%); }
h1 { position: absolute; left: 240px; top: 50%; transform: translateY(-50%); width: 1640px; font-size: 300px; line-height: 1.04; }
.card { position: absolute; left: 2120px; top: 220px; width: 1480px; height: 2500px; overflow: hidden; border-radius: 110px;
  background: #050608; box-shadow: 0 0 0 5px #2B303A, 0 70px 160px rgba(0, 0, 0, 0.6); }
.card img { display: block; width: 1480px; margin-top: ${-Math.round(p.top * 1480 / 1320)}px; }
</style><div class="glow"></div><h1>${esc(p.claim)}</h1><div class="card"><img src="${shot}"></div>`

// The product page header, 21:9: the book mark and the claim side by side, filling the strip.
const header = (p: Page): string => `<!doctype html><meta charset="utf-8"><style>${base(3840, 1646)}
.glow { position: absolute; inset: 0; background: radial-gradient(ellipse 40% 70% at 50% 50%, rgba(109, 90, 230, 0.30), transparent 70%); }
.row { position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); display: flex; align-items: center; gap: 140px; }
img { display: block; height: 760px; }
h1 { width: 2200px; font-size: 250px; line-height: 1.04; }
</style><div class="glow"></div><div class="row"><img src="${BOOK}"><h1>${esc(p.claim)}</h1></div>`

if (!existsSync(CHROME)) {
  console.error('Google Chrome is not installed at /Applications; it renders the images.')
  process.exit(1)
}
const only = process.argv[2]
const work = mkdtempSync(join(tmpdir(), 'store-header-'))
try {
  mkdirSync(OUT, { recursive: true })
  for (const p of PAGES) {
    if (only && p.key !== only) continue
    const shot = join(SOURCE, `${p.source}.png`)
    if (!existsSync(shot)) {
      console.error(`Missing capture ${shot}.`)
      process.exit(1)
    }
    for (const [kind, w, h, html] of [
      ['header', 3840, 1646, header(p)], ['search', 3840, 2560, search(p, pathToFileURL(shot).href)],
    ] as const) {
      const file = join(work, `${kind}-${p.key}.html`)
      writeFileSync(file, html)
      const out = join(OUT, `${kind}-${p.key}.png`)
      execFileSync(CHROME, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
        '--allow-file-access-from-files', '--virtual-time-budget=4000', `--window-size=${w},${h}`, `--screenshot=${out}`,
        pathToFileURL(file).href], { stdio: 'ignore' })
      console.log(`creative-assets/${kind}-${p.key}.png`)
    }
  }
} finally {
  rmSync(work, { recursive: true, force: true })
}
