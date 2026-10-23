// The App Store images: each real capture in images/screenshots/<platform>/appstore/source, framed
// under its headline, at the size Apple asks for. Rendered by the installed Google Chrome, headless.
// Run: npm run store:images. The captures come from the snapshot harness on the US demo household.
import { execFileSync } from 'node:child_process'
import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const FONTS = pathToFileURL(join(ROOT, 'apps/longbook-site/fonts')).href

interface Frame { file: string; source: string; title: string; line: string }

// The order a shopper sees them: the first three carry the case on their own.
const IPHONE: Frame[] = [
  { file: '01-remember-your-money', source: 'dashboard', title: 'Remember your money',
    line: 'Every subscription, bill and premium, before it charges you.' },
  { file: '02-nothing-changes-without-you', source: 'changes', title: 'Nothing changes without you',
    line: 'Every edit your AI makes waits here to keep or undo.' },
  { file: '03-your-ai-keeps-it-current', source: 'automations', title: 'Let your AI keep it current',
    line: 'Connect Claude or ChatGPT to add what your mail and statements show.' },
  { file: '04-know-where-it-goes', source: 'commitments', title: 'Know where your money goes',
    line: 'Each commitment with its account, its person and its next date.' },
  { file: '05-every-payment-on-its-day', source: 'calendar', title: 'See every payment on its day',
    line: 'The month ahead, with what leaves on each date.' },
  { file: '06-the-whole-household', source: 'members', title: 'Run the whole household',
    line: 'Members, accounts and who each payment is for.' },
]

const MAC: Frame[] = [
  { file: '01-remember-your-money', source: 'dashboard', title: 'Remember your money',
    line: 'Every subscription, bill and premium, before it charges you.' },
  { file: '02-nothing-changes-without-you', source: 'changes', title: 'Nothing changes without you',
    line: 'Every edit your AI makes waits here to keep or undo.' },
  { file: '03-your-ai-keeps-it-current', source: 'automations', title: 'Let your AI keep it current',
    line: 'Connect Claude or ChatGPT to add what your mail and statements show.' },
  { file: '04-every-month-reported', source: 'reports', title: 'Every month, already reported',
    line: 'Spending by category, account and person, month after month.' },
  { file: '05-know-where-it-goes', source: 'commitments', title: 'Know where your money goes',
    line: 'Each commitment with its account, its person and its next date.' },
  { file: '06-the-whole-household', source: 'members', title: 'Run the whole household',
    line: 'Members, accounts and who each payment is for.' },
]

const esc = (s: string): string => s.replace(/&/g, '&amp;').replace(/</g, '&lt;')

// One sheet for both: the brand's dark canvas, its serif for the claim, its sans for the line.
const base = (w: number, h: number): string => `
@font-face { font-family: 'Fraunces'; src: url('${FONTS}/Fraunces-Variable.woff2') format('woff2'); font-weight: 100 900; }
@font-face { font-family: 'Public Sans'; src: url('${FONTS}/PublicSans-Variable.woff2') format('woff2'); font-weight: 100 900; }
html, body { margin: 0; width: ${w}px; height: ${h}px; overflow: hidden; background: #0D1115; }
body { position: relative; -webkit-font-smoothing: antialiased; }
.glow { position: absolute; inset: 0; background: radial-gradient(ellipse 60% 42% at 50% 62%, rgba(109, 90, 230, 0.26), transparent 70%); }
h1 { margin: 0; font-family: 'Fraunces', serif; font-weight: 520; font-variation-settings: 'opsz' 60, 'SOFT' 50; color: #EEF1F4; letter-spacing: -0.012em; text-wrap: balance; }
p { margin: 0; font-family: 'Public Sans', sans-serif; font-weight: 400; color: #A3ACB7; text-wrap: pretty; }
`

const iphone = (f: Frame, shot: string): string => `<!doctype html><meta charset="utf-8"><style>${base(1320, 2868)}
.head { position: absolute; left: 112px; right: 112px; top: 210px; }
h1 { font-size: 132px; line-height: 1.03; }
p { font-size: 52px; line-height: 1.32; margin-top: 40px; max-width: 1040px; }
.phone { position: absolute; left: 50%; top: 820px; transform: translateX(-50%); width: 1000px; padding: 30px; border-radius: 156px;
  background: #050608; box-shadow: 0 0 0 4px #2B303A, 0 70px 160px rgba(0, 0, 0, 0.6); }
.phone img { display: block; width: 1000px; border-radius: 126px; }
</style><div class="glow"></div><div class="head"><h1>${esc(f.title)}</h1><p>${esc(f.line)}</p></div>
<div class="phone"><img src="${shot}"></div>`

const mac = (f: Frame, shot: string): string => `<!doctype html><meta charset="utf-8"><style>${base(2880, 1800)}
.head { position: absolute; left: 320px; right: 320px; top: 150px; }
h1 { font-size: 112px; line-height: 1.04; }
p { font-size: 46px; line-height: 1.3; margin-top: 26px; }
.window { position: absolute; left: 320px; top: 480px; width: 2240px; border-radius: 28px; overflow: hidden;
  box-shadow: 0 0 0 3px #2B303A, 0 70px 180px rgba(0, 0, 0, 0.6); }
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
      execFileSync(CHROME, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
        '--allow-file-access-from-files', '--virtual-time-budget=4000', `--window-size=${w},${h}`, `--screenshot=${out}`,
        pathToFileURL(html).href], { stdio: 'ignore' })
      console.log(`${platform}/appstore/${f.file}.png`)
    }
  }
} finally {
  rmSync(work, { recursive: true, force: true })
}
