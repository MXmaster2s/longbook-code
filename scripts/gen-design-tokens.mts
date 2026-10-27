// One design source, three renderers: reads the reviewed Swift tokens (colour, radius,
// spacing, type) out of packages/swift-design and writes the copies packages/cards and
// the site render with. `--check` refuses drift instead of writing.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = fileURLToPath(new URL('..', import.meta.url))
const DESIGN = join(ROOT, 'packages/swift-design/Sources/DesignSystem')
const OUT_DIR = join(ROOT, 'packages/cards/src')
const SITE_DIR = join(ROOT, 'apps/longbook-site')
const CHECK = process.argv.includes('--check')

const kebab = (name: string) => name.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase()

// ---- colours ----------------------------------------------------------------

interface Palette {
  colors: [string, string][]
  dataRamp: string[]
}

// Both palettes, read the same way. LBColorLight names every token LBColor does, which is
// what lets the site emit one set of names and swap only the values under a media query.
function palette(file: string): Palette {
  const src = readFileSync(join(DESIGN, file), 'utf8')

  const colors: [string, string][] = []
  for (const m of src.matchAll(/public static let (\w+) = LBColorValue\(0x([0-9A-Fa-f]{6})\)/g)) {
    colors.push([m[1] as string, `#${(m[2] as string).toUpperCase()}`])
  }
  // State washes are black or white at an opacity, so they travel as rgba.
  for (const m of src.matchAll(/public static let (\w+) = LBWash\(0x([0-9A-Fa-f]{6}), opacity: ([\d.]+)\)/g)) {
    const n = parseInt(m[2] as string, 16)
    colors.push([m[1] as string, `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${Number(m[3])})`])
  }

  const rampBlock = src.match(/dataRamp: \[LBColorValue\] = \[([\s\S]*?)\]/)?.[1] ?? ''
  const dataRamp = [...rampBlock.matchAll(/0x([0-9A-Fa-f]{6})/g)].map((m) => `#${(m[1] as string).toUpperCase()}`)
  if (dataRamp.length !== 12) throw new Error(`${file}: expected 12 ramp inks, parsed ${dataRamp.length}`)
  if (colors.length < 20) throw new Error(`${file}: parsed only ${colors.length} colour tokens — moved?`)

  return { colors, dataRamp }
}

const dark = palette('LBColor.swift')
const light = palette('LBColorLight.swift')

// The site's dark block only holds while the two palettes agree name for name and in order.
const names = (p: Palette) => p.colors.map(([n]) => n).join(',')
if (names(dark) !== names(light)) throw new Error('palettes disagree on token names or order')

// The cards keep the dark canvas they were authored on; the site takes the light one.
const { colors, dataRamp } = dark

// ---- radius & spacing -------------------------------------------------------

const layoutSrc = readFileSync(join(DESIGN, 'LBLayout.swift'), 'utf8')

function scale(enumName: string): [string, number][] {
  const block = layoutSrc.match(new RegExp(`enum ${enumName} \\{([\\s\\S]*?)\\}`))?.[1] ?? ''
  const entries = [...block.matchAll(/static let (\w+): CGFloat = ([\d.]+)/g)]
    .map((m): [string, number] => [m[1] as string, Number(m[2])])
  if (!entries.length) throw new Error(`no entries parsed from ${enumName}`)
  return entries
}
const radius = scale('LBRadius')
const spacing = scale('LBSpacing')

// ---- type roles -------------------------------------------------------------

const typeSrc = readFileSync(join(DESIGN, 'LBTypography.swift'), 'utf8')

// The iOS block is the quieter register and the `#else` under it is the desktop one. Cards
// take the phone's step down; a page takes the desktop's. The `#else` is searched from the
// block's own start: the imports' `#elseif` above carries the same prefix.
const iosStart = typeSrc.indexOf('#if os(iOS)')
const elseAt = typeSrc.indexOf('#else', iosStart)
const endAt = typeSrc.indexOf('#endif', elseAt)

function roleSizes(from: number, to: number): Map<string, number> {
  const out = new Map<string, number>()
  for (const m of typeSrc.slice(from, to).matchAll(/case \.(\w+): return (\d+)/g)) {
    out.set(m[1] as string, Number(m[2]))
  }
  if (!out.size) throw new Error('type roles parsed empty — LBTypography.swift moved?')
  return out
}
const phoneSizes = roleSizes(iosStart, elseAt)
const deskSizes = roleSizes(elseAt, endAt)

function switchEntries(from: string, to: string): Map<string, number> {
  const block = typeSrc.slice(typeSrc.indexOf(from), typeSrc.indexOf(to))
  const out = new Map<string, number>()
  for (const m of block.matchAll(/case ([^:\n]+): ([\d.]+)\n/g)) {
    for (const name of (m[1] as string).matchAll(/\.(\w+)/g)) out.set(name[1] as string, Number(m[2]))
  }
  return out
}
const weights = switchEntries('var weight', 'var tracking')
const trackings = switchEntries('var tracking', 'var tabularFigures')

if (weights.size === 0) throw new Error('type weights parsed empty — LBTypography.swift moved?')

const roles = (sizes: Map<string, number>) =>
  [...sizes.entries()].map(([role, size]) => ({
    role,
    size,
    weight: weights.get(role) ?? 400,
    tracking: trackings.get(role) ?? 0,
  }))

// The Swift roles are parsed to prove the file still reads; the web takes its own tables below.
const swiftRoles = new Set([...roles(phoneSizes), ...roles(deskSizes)].map((r) => r.role))
// ---- the web's own type scale ---------------------------------------------------------
// The apps follow Apple's scale per platform; a page or a card is read in a browser, where
// 15 px body is the measure. These tables stay put when the Swift scale moves.
const CARD_TYPE: Record<string, { size: number; weight: number; tracking: number }> = {
  displayXL: { size: 56, weight: 480, tracking: 0 },
  displayLG: { size: 28, weight: 460, tracking: 0 },
  title: { size: 19, weight: 440, tracking: 0 },
  screenTitle: { size: 20, weight: 700, tracking: 0 },
  eyebrow: { size: 10, weight: 600, tracking: 0.9 },
  heroSans: { size: 30, weight: 700, tracking: 0 },
  statNumber: { size: 24, weight: 700, tracking: 0 },
  tabLabel: { size: 10, weight: 500, tracking: 0.2 },
  body: { size: 14, weight: 400, tracking: 0.16 },
  bodySM: { size: 12, weight: 400, tracking: 0.14 },
  footnote: { size: 11, weight: 400, tracking: 0.26 },
  label: { size: 11, weight: 500, tracking: 0.13 },
  numberDisplay: { size: 44, weight: 500, tracking: 0 },
  numberMD: { size: 22, weight: 500, tracking: 0 },
  numberSM: { size: 14, weight: 500, tracking: 0 },
}
const WEB_TYPE: Record<string, { size: number; weight: number; tracking: number }> = {
  displayXL: { size: 64, weight: 480, tracking: 0 },
  displayLG: { size: 32, weight: 460, tracking: 0 },
  title: { size: 22, weight: 440, tracking: 0 },
  screenTitle: { size: 22, weight: 700, tracking: 0 },
  eyebrow: { size: 11, weight: 600, tracking: 0.9 },
  heroSans: { size: 34, weight: 700, tracking: 0 },
  statNumber: { size: 27, weight: 700, tracking: 0 },
  tabLabel: { size: 11, weight: 500, tracking: 0.2 },
  body: { size: 15, weight: 400, tracking: 0.16 },
  bodySM: { size: 13, weight: 400, tracking: 0.14 },
  footnote: { size: 12, weight: 400, tracking: 0.26 },
  label: { size: 12, weight: 500, tracking: 0.13 },
  numberDisplay: { size: 50, weight: 500, tracking: 0 },
  numberMD: { size: 26, weight: 500, tracking: 0 },
  numberSM: { size: 16, weight: 500, tracking: 0 },
}
const fromTable = (table: Record<string, { size: number; weight: number; tracking: number }>) =>
  Object.entries(table).map(([role, rest]) => ({ role, ...rest }))
for (const role of [...Object.keys(CARD_TYPE), ...Object.keys(WEB_TYPE)]) {
  if (!swiftRoles.has(role)) throw new Error(`web type role ${role} is not a Swift role any more`)
}
const type = fromTable(CARD_TYPE)
const siteType = fromTable(WEB_TYPE)

// The two faces, named once in Swift. The file keeps its axis suffix; the web family is the
// name before it, with the camel hump read back as a space.
interface Face { family: string; file: string }
const faces = new Map<string, Face>(
  [...typeSrc.matchAll(/case (\w+) = "(\w+)-Variable"/g)].map((m) => [
    m[1] as string,
    { family: (m[2] as string).replace(/([a-z])([A-Z])/g, '$1 $2'), file: `${m[2]}-Variable` },
  ]),
)
const serif = faces.get('fraunces')
const sans = faces.get('publicSans')
if (!serif || !sans) throw new Error('typeface names not parsed — LBTypeface moved?')

// Which face a role is set in, and which roles stack in a column and so take tabular figures.
function caseMap(from: string, to: string): Map<string, string> {
  const block = typeSrc.slice(typeSrc.indexOf(from), typeSrc.indexOf(to))
  const out = new Map<string, string>()
  for (const m of block.matchAll(/case ([^:\n]+): ([^\n]+)/g)) {
    for (const name of (m[1] as string).matchAll(/\.(\w+)/g)) out.set(name[1] as string, (m[2] as string).trim())
  }
  return out
}
const roleFace = caseMap('var face', 'var size')
const roleTabular = caseMap('var tabularFigures', 'var textStyle')
if (roleFace.size !== phoneSizes.size) throw new Error('a role has a size but no face — LBTextStyle moved?')

// ---- emit: the cards --------------------------------------------------------

const css = [
  '/* generated by scripts/gen-design-tokens.mts from packages/swift-design — do not edit.',
  ' * Regenerate: npm run design:tokens. Dark only, like the system it mirrors. */',
  ':root {',
  ...colors.map(([name, hex]) => `  --lb-${kebab(name)}: ${hex};`),
  ...dataRamp.map((hex, i) => `  --lb-data-${i}: ${hex};`),
  ...radius.map(([name, v]) => `  --lb-radius-${name}: ${v}px;`),
  ...spacing.map(([name, v]) => `  --lb-space-${name}: ${v}px;`),
  ...type.flatMap(({ role, size, weight, tracking }) => [
    `  --lb-type-${kebab(role)}-size: ${size}px;`,
    `  --lb-type-${kebab(role)}-weight: ${weight};`,
    `  --lb-type-${kebab(role)}-tracking: ${tracking}px;`,
  ]),
  '}',
  '',
].join('\n')

const json = `${JSON.stringify(
  {
    colors: Object.fromEntries(colors),
    dataRamp,
    radius: Object.fromEntries(radius),
    spacing: Object.fromEntries(spacing),
    type: Object.fromEntries(type.map(({ role, ...rest }) => [role, rest])),
  },
  null,
  2,
)}\n`

// The same CSS as a module, so the cards stay pure and bundle anywhere — no fs read.
const ts = `// generated by scripts/gen-design-tokens.mts — do not edit. Regenerate: npm run design:tokens.
export const TOKENS_CSS = ${JSON.stringify(css)}
`

// ---- emit: the site ---------------------------------------------------------

const hexOf = (p: Palette, name: string) => {
  const found = p.colors.find(([n]) => n === name)?.[1]
  if (!found) throw new Error(`token ${name} missing from a palette`)
  return found
}
const rgbOf = (hex: string) => {
  const n = parseInt(hex.slice(1), 16)
  return `${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}`
}

// The page's own layer. The app separates surfaces by tone on a screen it owns; a page
// separates them by lift on a canvas it does not, so elevation and measure live here.
const inkRGB = rgbOf(hexOf(light, 'textPrimary'))
const SITE_ONLY = {
  light: [
    `  --lb-elev-1: 0 0 0 0.5px rgba(${inkRGB}, 0.06), 0 4px 16px rgba(${inkRGB}, 0.08);`,
    `  --lb-elev-2: 0 0 0 0.5px rgba(${inkRGB}, 0.08), 0 14px 40px rgba(${inkRGB}, 0.12);`,
  ],
  dark: [
    '  --lb-elev-1: 0 0 0 0.5px rgba(0, 0, 0, 0.50), 0 4px 16px rgba(0, 0, 0, 0.55);',
    '  --lb-elev-2: 0 0 0 0.5px rgba(0, 0, 0, 0.60), 0 14px 40px rgba(0, 0, 0, 0.70);',
  ],
}

// The names the site's pages still use, each pointing at the token that owns it now.
// A row leaves when its pages are converted; nothing new may take one.
const BRIDGE: [string, string][] = [
  ['bg', 'canvas'], ['card', 'card'], ['surface-sunken', 'sunken'],
  ['ink', 'text-primary'], ['ink2', 'text-secondary'],
  ['ink3', 'text-tertiary'], ['ink4', 'text-quaternary'],
  ['accent', 'brand'], ['accent-ink', 'brand-text'],
  ['soon', 'urgent'], ['ok', 'mint-tint'],
  ['border', 'hairline'], ['border2', 'hairline'], ['hairline', 'hairline'],
  ['chrome-rail', 'rail'], ['chrome-fg', 'rail-fg'], ['chrome-fg-muted', 'rail-fg-muted'],
  ['r-sm', 'radius-xs'], ['r-md', 'radius-sm'], ['r-lg', 'radius-md'],
  ['r-xl', 'radius-lg'], ['r-xxl', 'radius-xl'],
  ['elev-1', 'elev-1'], ['elev-2', 'elev-2'], ['wrap', 'wrap'],
]

const paletteVars = (p: Palette, indent: string) => [
  ...p.colors.map(([name, hex]) => `${indent}--lb-${kebab(name)}: ${hex};`),
  ...p.dataRamp.map((hex, i) => `${indent}--lb-data-${i}: ${hex};`),
]

// Both faces carry a wght axis over the same 100-900 range, so one rule covers every weight
// a role asks for. Cut by npm run site:fonts.
const fontFace = ({ family, file }: Face) => [
  '@font-face {',
  `  font-family: '${family}';`,
  `  src: url('/fonts/${file}.woff2') format('woff2');`,
  '  font-weight: 100 900;',
  '  font-style: normal;',
  '  font-display: swap;',
  '}',
  '',
]

// A role as a class, the way lbText() hands one over: the face, size, weight and the tracking
// measured with them, together, so a page cannot take one and drop the rest. Fraunces sets
// its optical size from the size it is drawn at.
const roleClass = ({ role, size: _s, weight: _w, tracking: _t }: { role: string; size: number; weight: number; tracking: number }) => {
  const serifRole = roleFace.get(role) === '.fraunces'
  const name = kebab(role)
  return [
    `.lb-${name} {`,
    `  font-family: var(--lb-font-${serifRole ? 'serif' : 'sans'});`,
    `  font-size: var(--lb-type-${name}-size);`,
    `  font-weight: var(--lb-type-${name}-weight);`,
    `  letter-spacing: var(--lb-type-${name}-tracking);`,
    ...(serifRole ? ['  font-optical-sizing: auto;'] : []),
    ...(roleTabular.get(role) === 'true' ? ['  font-variant-numeric: tabular-nums;'] : []),
    '}',
  ]
}

const siteCss = [
  '/* generated by scripts/gen-design-tokens.mts from packages/swift-design — do not edit.',
  ' * Regenerate: npm run design:tokens. Light is the page\'s canvas; dark is authored, not yet worn. */',
  ...fontFace(serif),
  ...fontFace(sans),
  ':root {',
  `  --lb-font-serif: '${serif.family}', ui-serif, Georgia, serif;`,
  `  --lb-font-sans: '${sans.family}', ui-sans-serif, system-ui, -apple-system, sans-serif;`,
  '',
  ...paletteVars(light, '  '),
  '',
  '  /* The rail keeps the dark palette in both appearances: the mark sits on one surface only. */',
  `  --lb-rail: ${hexOf(dark, 'chrome')};`,
  `  --lb-rail-fg: ${hexOf(dark, 'textPrimary')};`,
  `  --lb-rail-fg-muted: ${hexOf(dark, 'textSecondary')};`,
  '',
  '  /* Brand washes. Mixed, not picked, so they follow the brand into either appearance. */',
  '  --lb-brand-soft: color-mix(in oklab, var(--lb-brand) 12%, var(--lb-card));',
  '  --lb-brand-soft-2: color-mix(in oklab, var(--lb-brand) 6%, var(--lb-card));',
  '',
  ...radius.map(([name, v]) => `  --lb-radius-${name}: ${v}px;`),
  ...spacing.map(([name, v]) => `  --lb-space-${name}: ${v}px;`),
  ...siteType.flatMap(({ role, size, weight, tracking }) => [
    `  --lb-type-${kebab(role)}-size: ${size}px;`,
    `  --lb-type-${kebab(role)}-weight: ${weight};`,
    `  --lb-type-${kebab(role)}-tracking: ${tracking}px;`,
  ]),
  '',
  ...SITE_ONLY.light,
  '  --lb-wrap: 1080px;',
  '}',
  '',
  '/* Dark, carried but not worn: no page has been checked in it yet, so nothing follows the',
  ' * system until one has. Setting the attribute on <html> is what turns it on. */',
  ':root[data-appearance="dark"] {',
  ...paletteVars(dark, '  '),
  ...SITE_ONLY.dark,
  '}',
  '',
  '/* The type roles as classes. A page takes a role, not four separate custom properties. */',
  ...siteType.flatMap((r) => [...roleClass(r), '']),
  '/* Selection. The page answers in its own colour rather than the browser default grey, and',
  ' * the ink on it lifts: light gets a lavender wash under deep brand ink, dark a saturated',
  ' * brand block under near-white. */',
  '::selection {',
  '  background: color-mix(in oklab, var(--lb-brand) 30%, var(--lb-canvas));',
  '  color: var(--lb-brand-pressed);',
  '  text-shadow: none;',
  '}',
  ':root[data-appearance="dark"] ::selection {',
  '  background: color-mix(in oklab, var(--lb-brand) 78%, var(--lb-canvas));',
  '  color: var(--lb-on-brand);',
  '}',
  '',
  '/* The names the pages still use. Each leaves as its pages convert; none may be added. */',
  ':root {',
  ...BRIDGE.map(([from, to]) => `  --${from}: var(--lb-${to});`),
  '  --accent-soft: var(--lb-brand-soft);',
  '  --accent-soft2: var(--lb-brand-soft-2);',
  '}',
  '',
].join('\n')

// ---- write ------------------------------------------------------------------

const targets: [string, string][] = [
  [join(OUT_DIR, 'tokens.css'), css],
  [join(OUT_DIR, 'tokens.json'), json],
  [join(OUT_DIR, 'tokens.ts'), ts],
  [join(SITE_DIR, 'tokens.css'), siteCss],
]

if (CHECK) {
  const drifted = targets.filter(
    ([path, wanted]) => !existsSync(path) || readFileSync(path, 'utf8') !== wanted,
  )
  if (drifted.length) {
    console.error(`design tokens drifted: ${drifted.map(([p]) => p.slice(ROOT.length)).join(', ')}`)
    console.error('run: npm run design:tokens')
    process.exit(1)
  }
  console.log('design tokens — in sync.')
} else {
  mkdirSync(OUT_DIR, { recursive: true })
  for (const [path, content] of targets) writeFileSync(path, content)
  console.log(`wrote ${targets.length} files from ${colors.length} colours, ${dataRamp.length} inks, ${type.length} type roles.`)
}
