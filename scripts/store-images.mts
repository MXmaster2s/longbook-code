// The App Store images: each real capture in images/screenshots/<platform>/appstore/source, framed
// under its headline, at the size Apple asks for. Rendered by the installed Google Chrome, headless.
// Run: npm run store:images, after npm run store:captures has taken them on the US demo household.
import { execFileSync } from 'node:child_process'
import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const FONTS = pathToFileURL(join(ROOT, 'apps/longbook-site/fonts')).href

interface Frame { file: string; source: string; title: string; line: string }

// The order a shopper sees them, the same on both: the first three carry the case on their own.
const FRAMES: Frame[] = [
  { file: '01-turn-statements-into-money-memory', source: 'dashboard', title: 'Turn statements into money memory',
    line: 'Drop in a bank statement. AI reads every charge into your longbook.' },
  { file: '02-see-who-you-pay', source: 'charges', title: 'See who you pay and how much',
    line: 'Every charge with its person, account and category.' },
  { file: '03-know-where-your-money-goes', source: 'reports', title: 'Know where your money goes',
    line: 'A report of every month by category, account and person.' },
  { file: '04-every-commitment-in-one-place', source: 'commitments', title: 'Every commitment in one place',
    line: 'Bills, premiums, EMIs and subscriptions, found and kept in your longbook.' },
  { file: '05-works-with-your-ai', source: 'proposals', title: 'Works with your AI',
    line: 'Claude or ChatGPT updates your longbook. Nothing changes until you keep it.' },
  { file: '06-share-it-with-your-family', source: 'people', title: 'Share it with your family',
    line: 'Family Sharing included, on iPhone and Mac.' },
]
const IPHONE = FRAMES
const MAC = FRAMES

const esc = (s: string): string => s.replace(/&/g, '&amp;').replace(/</g, '&lt;')

// One sheet for both: white behind the dark app, the brand's serif for the claim and its sans for
// the line, both in its light-mode ink.
const base = (w: number, h: number): string => `
@font-face { font-family: 'Fraunces'; src: url('${FONTS}/Fraunces-Variable.woff2') format('woff2'); font-weight: 100 900; }
@font-face { font-family: 'Public Sans'; src: url('${FONTS}/PublicSans-Variable.woff2') format('woff2'); font-weight: 100 900; }
html, body { margin: 0; width: ${w}px; height: ${h}px; overflow: hidden; background: #FFFFFF; }
body { position: relative; -webkit-font-smoothing: antialiased; }
.glow { position: absolute; inset: 0; background: radial-gradient(ellipse 60% 42% at 50% 62%, rgba(109, 90, 230, 0.07), transparent 70%); }
h1 { margin: 0; font-family: 'Fraunces', serif; font-weight: 520; font-variation-settings: 'opsz' 60, 'SOFT' 50; color: #26241F; letter-spacing: -0.012em; text-wrap: balance; }
p { margin: 0; font-family: 'Public Sans', sans-serif; font-weight: 400; color: #57524A; text-wrap: pretty; }
`

const iphone = (f: Frame, shot: string): string => `<!doctype html><meta charset="utf-8"><style>${base(1320, 2868)}
.head { position: absolute; left: 112px; right: 112px; top: 210px; }
h1 { font-size: 116px; line-height: 1.04; }
p { font-size: 50px; line-height: 1.32; margin-top: 34px; max-width: 1096px; }
.phone { position: absolute; left: 50%; top: 860px; transform: translateX(-50%); width: 1000px; padding: 30px; border-radius: 156px;
  background: #050608; box-shadow: 0 0 0 4px #2B303A, 0 60px 140px rgba(20, 18, 40, 0.22); }
.phone img { display: block; width: 1000px; border-radius: 126px; }
</style><div class="glow"></div><div class="head"><h1>${esc(f.title)}</h1><p>${esc(f.line)}</p></div>
<div class="phone"><img src="${shot}"></div>`

const mac = (f: Frame, shot: string): string => `<!doctype html><meta charset="utf-8"><style>${base(2880, 1800)}
.head { position: absolute; left: 320px; right: 320px; top: 150px; }
h1 { font-size: 112px; line-height: 1.04; }
p { font-size: 46px; line-height: 1.3; margin-top: 26px; }
.window { position: absolute; left: 320px; top: 480px; width: 2240px; border-radius: 28px; overflow: hidden;
  box-shadow: 0 0 0 3px #2B303A, 0 60px 160px rgba(20, 18, 40, 0.22); }
.window img { display: block; width: 2240px; }
.lights { position: absolute; left: 30px; top: 28px; display: flex; gap: 14px; }
.lights i { width: 20px; height: 20px; border-radius: 50%; }
</style><div class="glow"></div><div class="head"><h1>${esc(f.title)}</h1><p>${esc(f.line)}</p></div>
<div class="window"><img src="${shot}"><div class="lights"><i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i></div></div>`

if (!existsSync(CHROME)) {
  console.error('Google Chrome is not installed at /Applications; it renders the images.')
  process.exit(1)
}
const work = mkdtempSync(join(tmpdir(), 'store-images-'))
try {
  for (const [platform, frames, w, h, page] of [
    ['ios', IPHONE, 1320, 2868, iphone], ['mac', MAC, 2880, 1800, mac],
  ] as const) {
    const folder = join(ROOT, 'images/screenshots', platform, 'appstore')
    for (const f of frames) {
      const shot = join(folder, 'source', `${f.source}.png`)
      if (!existsSync(shot)) {
        console.error(`Missing capture ${shot}.`)
        process.exit(1)
      }
      const html = join(work, `${platform}-${f.file}.html`)
      writeFileSync(html, page(f, pathToFileURL(shot).href))
      const out = join(folder, `${f.file}.png`)
      rmSync(out, { force: true })
      // Chrome can exit non-zero from its teardown watchdog after the picture is written, so the
      // file decides.
      try {
        execFileSync(CHROME, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
          '--allow-file-access-from-files', '--virtual-time-budget=4000', `--window-size=${w},${h}`, `--screenshot=${out}`,
          pathToFileURL(html).href], { stdio: 'ignore' })
      } catch (e) {
        if (!existsSync(out)) throw e
      }
      console.log(`${platform}/appstore/${f.file}.png`)
    }
  }
} finally {
  rmSync(work, { recursive: true, force: true })
}
