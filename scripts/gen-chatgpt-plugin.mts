#!/usr/bin/env -S npx tsx
// Builds dist/chatgpt-plugin/longbook.zip in OpenAI's Agent Plugins format: plugin.json, mcp.json,
// a skill per prompt group, and the icons. The listing's words come from
// apps/chatgpt-plugin/listing.json. --check builds and validates without writing; --release also
// refuses a [LISTING] placeholder. Regenerate: npm run plugin:chatgpt.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { zipSync } from 'fflate'
import { PROMPTS, PROMPT_GROUPS } from '../packages/core/src/prompts'
import type { LongbookPrompt } from '../packages/core/src/prompts'
import { TOOLS } from '../packages/mcp/src/catalog'
import { WRITE_TOOLS } from '../packages/mcp/src/proposal'
import { RELEASE_VERSION } from './release.mts'
import { MCP_URL, SKILLS, skill, wrap } from './plugin-skills.mts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const OUT = join(ROOT, 'dist/chatgpt-plugin/longbook.zip')
const CHECK = process.argv.includes('--check')
const RELEASE = process.argv.includes('--release')
const PLACEHOLDER = '[LISTING]'
const SITE = 'https://longbook.app'

const listing = JSON.parse(readFileSync(join(ROOT, 'apps/chatgpt-plugin/listing.json'), 'utf8')) as {
  shortDescription: string
  longDescription: string
  test_cases: {
    positive: { description: string; prompt: string; tools_triggered: string; expected_behavior: string }[]
    negative: { description: string; prompt: string }[]
  }
  release_notes: string
}

// The design tokens, generated from packages/swift-design: the brand on white, the brand's text
// colour on dark.
const tokens = JSON.parse(readFileSync(join(ROOT, 'packages/cards/src/tokens.json'), 'utf8')) as { colors: Record<string, string> }
const BRAND = tokens.colors.brand!
const BRAND_DARK = tokens.colors.brandText!

// The app icon is the listing's logo; the book alone, on no background, sits in the composer.
// Both read on light and dark, so the dark versions are the same art.
const ICON = readFileSync(join(ROOT, 'apps/longbook/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png'))
const BOOK = readFileSync(join(ROOT, 'images/brand/longbook_icon_nobackground.png'))

/** Three prompts as the composer offers them, by id from the prompt catalogue. */
const DEFAULT_PROMPTS = ['set-up-my-longbook', 'what-is-coming-in-the-next-30-days', 'what-did-i-spend-in-a-month']
const prompt = (id: string): LongbookPrompt => PROMPTS.find((p) => p.id === id) ?? fail(`no prompt ${id} in prompts.ts`)

function fail(message: string): never {
  console.error(`chatgpt plugin — ${message}`)
  process.exit(1)
}

const SKILL_CONNECT =
  'If no longbook tools are available, say the longbook app needs connecting: in ChatGPT, open ' +
  'the longbook plugin and sign in with the longbook account.'

const START = `---
name: longbook-start
description: >
${wrap(
  'Use when the user has just added longbook, asks what longbook can do, or says "help me with my ' +
    'longbook", "where do I start with longbook" or "what should I do in longbook". Checks the ' +
    'longbook connection, starts setup when the longbook is empty, and lists every longbook prompt.',
  '  ',
)}
---

# longbook: Start here

${wrap("longbook is the user's financial memory: every commitment they pay, its charges past and planned, their accounts and the people payments are for. This is the front door: check the connection, start where the user is, and point to the one prompt that helps most now.")}

## Steps

${[
  `1. Call longbook's \`whoami\`. ${SKILL_CONNECT} Then stop.`,
  "2. If whoami says this connection cannot write, say its how_to_enable sentence: the user switches it on in the longbook app.",
  '3. If the longbook holds no commitments yet, offer "Set up my longbook": attach bank and card statements, ideally the last 6 months. Stop there unless the user wants the list.',
  '4. Otherwise, say in two lines what it holds (commitments, accounts, members) and what is waiting: names to fill in from setup, and suggestions the app could not apply.',
  "5. Show the prompts below, by group. The user can say them as written or in their own words; for each, call `read_guide` with its name and follow the procedure it returns.",
  '6. End with the single best next step for this user.',
]
  .map((s) => wrap(s).replace(/\n/g, '\n   '))
  .join('\n')}

## The prompts

${PROMPT_GROUPS.map(
  (g) =>
    `**${g.title}**\n\n` +
    PROMPTS.filter((p) => p.group === g.id)
      .map((p) => wrap(`- ${p.title} (\`${p.id}\`)`).replace(/\n/g, '\n  '))
      .join('\n'),
).join('\n\n')}
`

const plugin = {
  $schema: 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json',
  name: 'longbook',
  version: RELEASE_VERSION,
  description:
    "longbook's financial memory in ChatGPT: what is due and when, what a month cost, and changes " +
    "from your statements and email that wait in the longbook app's Proposals screen for you to keep.",
  author: { name: 'longbook', email: 'contact@longbook.app', url: SITE },
  homepage: `${SITE}/`,
  repository: 'https://github.com/MXmaster2s/longbook-code',
  license: 'GPL-3.0-only',
  keywords: ['longbook', 'finance', 'subscriptions', 'bills', 'expenses', 'statements', 'personal-finance'],
  extensions: {
    'com.openai': {
      interface: {
        displayName: 'longbook',
        shortDescription: listing.shortDescription,
        longDescription: listing.longDescription,
        developerName: 'longbook',
        category: 'Finance',
        capabilities: [
          'Answer what is due next and in the next 30 days',
          'Report what a month cost, by category, account and person',
          'List renewals, accounts, people and charges',
          'Add statements, bills and expenses as suggestions to review in the app',
          'Ask longbook to draw a report',
        ],
        websiteURL: `${SITE}/`,
        supportURL: `${SITE}/support/`,
        privacyPolicyURL: `${SITE}/privacy-policy/`,
        termsOfServiceURL: `${SITE}/terms/`,
        defaultPrompt: DEFAULT_PROMPTS.map((id) => prompt(id).title),
        brandColor: BRAND,
        brandColorDark: BRAND_DARK,
        composerIcon: './assets/composer-icon.png',
        composerIconDark: './assets/composer-icon.png',
        logo: './assets/logo.png',
        logoDark: './assets/logo.png',
      },
      onboardingSkill: './skills/longbook-start/SKILL.md',
      review: { test_cases: listing.test_cases, commerce: false },
      publication: { release_notes: listing.release_notes },
    },
  },
}

// One server, signed in through OAuth with dynamic client registration: discovery from
// /.well-known/oauth-protected-resource names the registration endpoint. No headers, no hooks.
const mcp = {
  $schema: 'https://agent-plugins.org/schemas/1.0.0/mcp.schema.json',
  mcpServers: {
    longbook: {
      type: 'streamable-http',
      url: MCP_URL,
      extensions: { 'com.openai': { auth: { type: 'oauth', client: { mode: 'dcr' } } } },
    },
  },
}

const files = new Map<string, Uint8Array>([
  ['plugin.json', Buffer.from(JSON.stringify(plugin, null, 2) + '\n')],
  ['mcp.json', Buffer.from(JSON.stringify(mcp, null, 2) + '\n')],
  ['assets/logo.png', ICON],
  ['assets/composer-icon.png', BOOK],
  ['skills/longbook-start/SKILL.md', Buffer.from(START)],
  ...PROMPT_GROUPS.map((g) => [`skills/${SKILLS[g.id].name}/SKILL.md`, Buffer.from(skill(g.id, SKILLS[g.id].heading, SKILL_CONNECT))] as [string, Uint8Array]),
])

// ---- the submission rules, checked before anything is written -------------------------------

const problems: string[] = []
const need = (ok: boolean, message: string): void => {
  if (!ok) problems.push(message)
}
const ui = plugin.extensions['com.openai'].interface
const within = (field: string, value: string, max: number): void =>
  need(value.trim().length > 0 && value.length <= max, `${field} must be 1 to ${max} characters (is ${value.length})`)

need(/^(?!.*--)[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(plugin.name) && plugin.name.length <= 64, 'name: lowercase letters, numbers, single hyphens')
need(/^\d+\.\d+\.\d+$/.test(plugin.version), 'version must be semantic')
within('displayName', ui.displayName, 30)
within('shortDescription', ui.shortDescription, 30)
within('longDescription', ui.longDescription, 4000)
within('developerName', ui.developerName, 80)
need(ui.capabilities.length <= 20 && ui.capabilities.every((c) => c.length <= 120), 'capabilities: at most 20, 120 characters each')
for (const key of ['websiteURL', 'supportURL', 'privacyPolicyURL', 'termsOfServiceURL'] as const) {
  need(/^https:\/\/longbook\.app\//.test(ui[key]), `${key} must be an https longbook.app address`)
}
need(ui.defaultPrompt.length <= 3 && new Set(ui.defaultPrompt).size === ui.defaultPrompt.length, 'defaultPrompt: up to three, unique')
for (const p of ui.defaultPrompt) need(p.length <= 128 && !p.includes('@'), `defaultPrompt "${p}": 128 characters, no @mention`)

const luminance = (hex: string): number => {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4))
  return 0.2126 * r! + 0.7152 * g! + 0.0722 * b!
}
const contrast = (a: string, b: string): number => {
  const [x, y] = [luminance(a), luminance(b)].sort((m, n) => n - m)
  return (x! + 0.05) / (y! + 0.05)
}
need(/^#[0-9A-Fa-f]{6}$/.test(BRAND) && contrast(BRAND, '#FFFFFF') >= 2, `brandColor ${BRAND} needs 2:1 against white`)
need(/^#[0-9A-Fa-f]{6}$/.test(BRAND_DARK) && contrast(BRAND_DARK, '#212121') >= 2, `brandColorDark ${BRAND_DARK} needs 2:1 against #212121`)

for (const key of ['composerIcon', 'composerIconDark', 'logo', 'logoDark'] as const) {
  const path = ui[key].replace(/^\.\//, '')
  const png = files.get(path)
  if (!png) {
    problems.push(`${key} names ${ui[key]}, which is not in the package`)
    continue
  }
  const view = Buffer.from(png)
  const [w, h] = [view.readUInt32BE(16), view.readUInt32BE(20)]
  need(view.subarray(1, 4).toString() === 'PNG', `${key}: a PNG`)
  need(w === h && w >= 48 && w <= 4096, `${key}: square, 48 to 4096 px (is ${w}x${h})`)
  need(png.length <= 5 * 1024 * 1024, `${key}: at most 5 MiB`)
}

const servers = Object.entries(mcp.mcpServers)
need(servers.length === 1, 'mcp.json holds exactly one server')
for (const [name, server] of servers) {
  need(server.type === 'streamable-http' && server.url.startsWith('https://'), `${name}: a streamable-http https server`)
  need(!('headers' in server), `${name}: no headers`)
  need(!JSON.stringify(server).includes('clientSecret') && !JSON.stringify(server).includes('clientId'), `${name}: no client credentials`)
}
const manifest = JSON.stringify(plugin)
for (const banned of ['"hooks"', '"apps"', 'test_credentials', 'reviewer_instructions']) need(!manifest.includes(banned), `plugin.json carries ${banned}`)
need(!files.has('.app.json'), 'no .app.json')

need(plugin.extensions['com.openai'].onboardingSkill.replace(/^\.\//, '') in Object.fromEntries(files), 'onboardingSkill names a packaged skill')
for (const [path, body] of files) {
  if (!path.endsWith('SKILL.md')) continue
  const head = Buffer.from(body).toString().match(/^---\n([\s\S]*?)\n---\n/)?.[1] ?? ''
  need(/^name: [a-z0-9-]+$/m.test(head) && /^description: /m.test(head), `${path}: name and description in its header`)
}

const cases = listing.test_cases
need(cases.positive.length === 5 && cases.negative.length === 3, 'test cases: exactly five positive and three negative')
const tools = new Set([...TOOLS, ...WRITE_TOOLS].map((t) => t.name))
for (const c of cases.positive) {
  need(!!(c.description && c.prompt && c.tools_triggered && c.expected_behavior), `positive case "${c.description}": every field`)
  if (c.tools_triggered.includes(PLACEHOLDER)) continue
  for (const t of c.tools_triggered.split(',').map((s) => s.trim())) need(tools.has(t), `positive case "${c.description}": no tool ${t}`)
}
for (const c of cases.negative) need(!!(c.description && c.prompt), `negative case "${c.description}": every field`)

const placeholders = [...files.values()].reduce((n, b) => n + Buffer.from(b).toString('latin1').split(PLACEHOLDER).length - 1, 0)
if (RELEASE) need(placeholders === 0, `${placeholders} ${PLACEHOLDER} placeholder(s) left in apps/chatgpt-plugin/listing.json`)

if (problems.length) fail(`not ready:\n  ${problems.join('\n  ')}`)

// A fixed time on every entry, so the same sources build the same bytes.
const when = new Date('2026-01-01T00:00:00Z')
const zip = zipSync(Object.fromEntries([...files].map(([path, body]) => [path, [body, { mtime: when }]])), { level: 9 })
const waiting = placeholders ? `; ${placeholders} ${PLACEHOLDER} placeholder(s) wait for the listing text` : ''
const summary = `${files.size} files, ${PROMPT_GROUPS.length + 1} skills, ${Math.round(zip.length / 1024)} KB, version ${RELEASE_VERSION}${waiting}`
if (CHECK) {
  console.log(`chatgpt plugin — builds (${summary}).`)
} else {
  mkdirSync(dirname(OUT), { recursive: true })
  writeFileSync(OUT, zip)
  console.log(`wrote dist/chatgpt-plugin/longbook.zip (${summary}).`)
}
