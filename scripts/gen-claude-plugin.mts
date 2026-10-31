#!/usr/bin/env -S npx tsx
// Generates longbook's Claude plugin in apps/claude-plugin from the prompt catalogue: a skill
// per prompt group, the hosted connector, a README and a marketplace file. Skills send Claude
// to read_guide for procedures. --check verifies; --out <dir> writes the plugin there instead.
// Regenerate: npm run plugin:claude.
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { PROMPTS, PROMPT_GROUPS } from '../packages/core/src/prompts'
import type { LongbookPrompt, PromptGroupId } from '../packages/core/src/prompts'
import { CONTRACT_REVISION } from '../packages/core/src/contract'
import { RELEASE_VERSION } from './release.mts'
import { MCP_URL, SKILLS, quote, skill, wrap } from './plugin-skills.mts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const OUT_AT = process.argv.indexOf('--out')
const OUT = OUT_AT > 0 && process.argv[OUT_AT + 1] ? resolve(process.argv[OUT_AT + 1]!) : join(ROOT, 'apps/claude-plugin')
const CHECK = process.argv.includes('--check')
const SHOWN = relative(ROOT, OUT).startsWith('..') ? OUT : relative(ROOT, OUT)
const GMAIL_URL = 'https://gmailmcp.googleapis.com/mcp/v1'
// The public repository the marketplace is published to; longbook-code itself is private.
const REPO = 'MXmaster2s/longbook-claude-plugin'
// longbook's one release number (release.json): a new one is what installed copies update to.
const VERSION = RELEASE_VERSION
/** Each prompt's slash command, as /longbook:<name>. A prompt without one stops the build. */
const COMMANDS: Record<string, string> = {
  'set-up-my-longbook': 'set-up',
  'add-my-statement': 'add-statement',
  'categorise-my-longbook': 'categorise',
  'add-a-month-report-in-my-longbook': 'month-report',
  'add-email-invoices-in-my-longbook': 'email-invoices',
  'set-up-a-daily-longbook-email-round': 'email-round',
  'add-document-invoices-in-my-longbook': 'document-invoices',
  'add-a-commitment-or-an-expense': 'add',
  'what-do-i-pay-next': 'whats-next',
  'what-is-coming-in-the-next-30-days': 'whats-due',
  'what-did-i-spend-in-a-month': 'month-spend',
  'what-renews-this-year': 'renewals',
  'make-my-weekly-longbook-page': 'weekly-page',
  'create-a-report-in-my-longbook': 'report',
  'make-a-report-of-my-trip': 'trip-report',
  'tidy-my-longbook': 'tidy',
  'reorganise-my-longbook': 'reorganise',
  'set-up-a-morning-brief': 'morning-brief',
  'find-subscriptions-from-my-email': 'find-subscriptions',
  'find-expenses-from-my-email': 'find-expenses',
  'find-invoices-from-my-email': 'find-invoices',
  'find-insurances-from-my-email': 'find-insurances',
  'find-purchases-from-my-email': 'find-purchases',
  'find-bills-from-my-email': 'find-bills',
  'find-loans-and-emis-from-my-email': 'find-loans',
  'find-travel-bookings-from-my-email': 'find-travel',
  'find-money-in-from-my-email': 'find-money-in',
}
for (const p of PROMPTS) if (!COMMANDS[p.id]) throw new Error(`prompt ${p.id} has no slash command: add it to COMMANDS`)
const slash = (p: LongbookPrompt): string => `/longbook:${COMMANDS[p.id]}`
const titled = (p: LongbookPrompt): string => (/[.?!]$/.test(p.title) ? p.title : `${p.title}.`)
const firstSentence = (text: string): string => (text.match(/^.*?[.!?](\s|$)/)?.[0] ?? text).trim()

const SKILL_CONNECT =
  'If no longbook tools are available, say the longbook connector is needed: in Claude, Settings, then ' +
  `Connectors, then Add custom connector, with the address ${MCP_URL}, signing in with the longbook ` +
  'account. Installing this plugin adds the connector too.'

const CONNECT_STEP =
  'If no longbook tools are available, the longbook connector needs signing in: in Claude Code run ' +
  '/mcp and sign in to longbook; in the Claude apps, Settings, then Connectors, then longbook. Sign in ' +
  `with the longbook account. Without the plugin, add a custom connector with the address ${MCP_URL}.`

function command(p: LongbookPrompt): string {
  const hint = p.template ? '[month]' : p.id === 'make-a-report-of-my-trip' ? '[trip name and days]' : '[anything to add]'
  const steps = [
    `1. Call the longbook connector's \`read_guide\` with "${p.id}". It returns the procedure, step by step, and the guide chapter it builds on.`,
    `2. Follow that procedure and the guide's rules.${p.template ? ' Use the month the user named above, or the month in progress.' : ''}`,
  ]
  if (p.needs?.includes('mail')) {
    steps.push("3. This prompt reads the user's mail through a mail connector; the plugin bundles Gmail. If none is signed in, say so and stop.")
  }
  steps.push(`${steps.length + 1}. ${CONNECT_STEP}`)
  return `---
description: ${JSON.stringify(`${titled(p)} ${firstSentence(p.result)}`)}
argument-hint: ${JSON.stringify(hint)}
---

Run longbook's prompt "${p.title}" for the user. What they added: $ARGUMENTS

${steps.map((s) => wrap(s).replace(/\n/g, '\n   ')).join('\n')}
`
}

const commandList = (): string =>
  PROMPT_GROUPS.map(
    (g) =>
      `**${g.title}**\n\n` +
      PROMPTS.filter((p) => p.group === g.id)
        .map((p) => wrap(`- \`${slash(p)}\`: ${titled(p)} ${firstSentence(p.result)}`).replace(/\n/g, '\n  '))
        .join('\n'),
  ).join('\n\n')

const START = `---
name: longbook-start
description: >
${wrap(
  'Use when the user has just installed longbook, asks what longbook can do, or says "help me with my ' +
    'longbook", "where do I start with longbook", "what should I do in longbook" or "longbook start". ' +
    'Checks the longbook connection, starts setup when the longbook is empty, shows every longbook ' +
    'prompt with its slash command, and offers the morning brief, the daily email round and the weekly ' +
    'page on a schedule.',
  '  ',
)}
---

# longbook: Start here

${wrap("longbook is the user's financial memory: every commitment they pay, its charges past and planned, their accounts and the people payments are for. This is the front door: check the connection, start where the user is, and point to the one prompt that helps most now.")}

## Steps

${[
  `1. Call the longbook connector's \`whoami\`. ${CONNECT_STEP} Then stop.`,
  "2. If whoami says this connection cannot write, say its how_to_enable sentence: the user switches it on in the longbook app.",
  '3. If the longbook holds no commitments yet, offer `/longbook:set-up`: attach bank and card statements, ideally the last 6 months. Stop there unless the user wants the list.',
  '4. Otherwise, say in two lines what it holds (commitments, accounts, members) and what is waiting: names to fill in from setup, and suggestions the app could not apply.',
  '5. Show the prompts below, by group, each with its slash command. The user can also just ask in their own words.',
  "6. Check for a mail connector. If none is signed in, say the email prompts need one: the plugin bundles Gmail, signed in with the user's Google account.",
  '7. Offer, and set up only what the user picks, each by its own procedure: `/longbook:morning-brief`, `/longbook:email-round` and `/longbook:weekly-page` every Monday.',
  '8. End with the single best next step for this user.',
]
  .map((s) => wrap(s).replace(/\n/g, '\n   '))
  .join('\n')}

## The prompts

${commandList()}
`

const START_COMMAND = `---
description: "Start here: check the longbook connection, set up, and see every longbook prompt."
---

Follow the longbook-start skill's steps now, from step 1.
`

// Same licence as longbook-code; the app icon is the directory listing's icon.
const LICENSE = readFileSync(join(ROOT, 'LICENSE'), 'utf8')
const ICON = readFileSync(join(ROOT, 'apps/longbook/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png'))
const PRIVACY_URL = 'https://longbook.app/privacy-policy/'

const plugin = {
  name: 'longbook',
  displayName: 'longbook',
  version: VERSION,
  description:
    "longbook's prompts for Claude: set up your longbook from your statements, keep it current from " +
    'your email and files, ask what is due and what a month cost, and draw reports. Bundles the ' +
    'longbook connector and Gmail; sign in with your longbook account.',
  author: { name: 'longbook', url: 'https://longbook.app' },
  homepage: 'https://longbook.app/automations/',
  repository: `https://github.com/${REPO}`,
  license: 'GPL-3.0-only',
  privacyPolicyUrl: PRIVACY_URL,
  termsOfServiceUrl: 'https://longbook.app/terms/',
  supportUrl: 'https://longbook.app/contact/',
  documentationUrl: 'https://longbook.app/mcp/',
  keywords: ['longbook', 'finance', 'subscriptions', 'bills', 'expenses', 'statements', 'personal-finance'],
}

const marketplace = {
  $schema: 'https://anthropic.com/claude-code/marketplace.schema.json',
  name: 'longbook',
  description: "longbook's plugins for Claude.",
  owner: { name: 'longbook', url: 'https://longbook.app' },
  plugins: [
    {
      name: 'longbook',
      description: plugin.description,
      version: VERSION,
      author: plugin.author,
      category: 'productivity',
      source: './plugins/longbook',
      homepage: plugin.homepage,
    },
  ],
}

const listOf = (items: string[]): string =>
  items.length < 2 ? items.join('') : `${items.slice(0, -1).join(', ')} and ${items.at(-1)}`
const MAIL_COMMANDS = listOf(PROMPTS.filter((p) => p.needs?.includes('mail')).map((p) => `\`${slash(p)}\``))
const SCHEDULED_COMMANDS = listOf([
  ...PROMPTS.filter((p) => p.needs?.includes('scheduler')).map((p) => `\`${slash(p)}\``),
  '`/longbook:start` (for the weekly page)',
])

const readme = `# longbook for Claude

${wrap("longbook remembers every commitment you pay: subscriptions, bills, rent, salaries, insurance and loans, with their charges past and planned. This plugin brings longbook's prompts to Claude as skills and slash commands, and connects Claude to your longbook. Ask in your own words, or type a command.")}

## Install

In Claude Code or the Claude desktop app:

\`\`\`
/plugin marketplace add ${REPO}
/plugin install longbook@longbook
\`\`\`

Then sign in to the longbook connector with your longbook account, and to Gmail if you want the
email prompts. Start with \`/longbook:start\`.

## Commands

${commandList()}

## Skills

${PROMPT_GROUPS.map((g) => `- **${SKILLS[g.id].name}**: ${SKILLS[g.id].does}`).join('\n')}
- **longbook-start**: checks the connection, starts setup, and shows every prompt.

## What it runs, sends and fetches

${wrap('The plugin is text only: skills and slash commands that tell Claude what to do. It installs no hooks, scripts or local servers, runs no code on your machine, and collects no analytics. What it reaches, it reaches through the two connectors it bundles:')}

${wrap(`- **longbook** (${MCP_URL}), longbook's own MCP server, signed in with your longbook account. It reads the hosted copy of your longbook that the app uploads when you turn on its MCP server: your commitments and their charges past and planned, your accounts and balances, the people payments are for, your tags and categories, and your reports. Each skill and command also fetches its procedure from it with read_guide, so the steps are always the server's current ones. What Claude reads through it goes into your conversation with Claude.`).replace(/\n/g, '\n  ')}
${wrap('- **Writes wait as proposals.** When Claude adds a commitment or a charge, marks one paid, cancels one or leaves an insight, the change is sent to longbook as a proposal, and only after you turn on Allow proposals in the app. Nothing is in your longbook until you keep it in the app\'s Proposals screen, where you can also undo it. A report request shows on the Reports screen instead.').replace(/\n/g, '\n  ')}
${wrap(`- **Gmail** (${GMAIL_URL}), Google's Gmail MCP server, bundled for the email prompts and signed in with your Google account. Only ${MAIL_COMMANDS} read it: they search and read your mail for payments, bills, receipts and money in. No prompt sends, deletes or labels mail. Without a Gmail sign-in every other command works.`).replace(/\n/g, '\n  ')}
${wrap(`- **Scheduled tasks.** ${SCHEDULED_COMMANDS} set up a scheduled task in your Claude app, only when you ask for one, and it runs the same prompt through the same connectors.`).replace(/\n/g, '\n  ')}

${wrap('Statements and files you attach go to Claude in the conversation; what Claude records from them is sent to longbook as proposals. The plugin sends nothing anywhere else. Privacy: ' + PRIVACY_URL + '. Generated from the longbook prompt catalogue (contract revision ' + CONTRACT_REVISION + ', version ' + VERSION + ').')}

## More about longbook

- [longbook.app](https://longbook.app/): the app for Mac and iPhone
- [Automate longbook with Claude](https://longbook.app/features/automate-longbook-with-claude/)
- [Every automation](https://longbook.app/automations/) and [every feature](https://longbook.app/features/)
- [Review every change your AI makes](https://longbook.app/features/review-every-change-your-ai-makes/)
- [Log expenses from Gmail](https://longbook.app/features/log-expenses-from-gmail/)
- [Why we built longbook](https://longbook.app/why-we-built-longbook/)

## License

GPL-3.0, the same licence as longbook. See LICENSE.
`

// The directory lists only a plugin whose folder holds a README of 40 words or more, outside code
// blocks, and a licence; it re-scans on every push, so the version is release.json's.
const proseWords = readme.replace(/```[\s\S]*?```/g, '').split(/\s+/).filter((w) => /[a-z0-9]/i.test(w)).length
if (proseWords < 40) throw new Error(`plugin README has ${proseWords} words; the directory needs 40`)
if (!/GNU GENERAL PUBLIC LICENSE/.test(LICENSE)) throw new Error('LICENSE is not the GPL text')
if (!/^\d+\.\d+\.\d+$/.test(VERSION)) throw new Error(`version ${VERSION} is not x.y.z`)

const files = new Map<string, string | Buffer>([
  ['.claude-plugin/marketplace.json', JSON.stringify(marketplace, null, 2) + '\n'],
  ['plugins/longbook/.claude-plugin/plugin.json', JSON.stringify(plugin, null, 2) + '\n'],
  [
    'plugins/longbook/.mcp.json',
    JSON.stringify({ mcpServers: { longbook: { type: 'http', url: MCP_URL }, gmail: { type: 'http', url: GMAIL_URL } } }, null, 2) + '\n',
  ],
  ['plugins/longbook/.claude-plugin/icon.png', ICON],
  ['plugins/longbook/README.md', readme],
  ['plugins/longbook/LICENSE', LICENSE],
  ['README.md', readme],
  ['LICENSE', LICENSE],
  // mcprush.com proves the skills listing is ours by reading this line; keep it until they confirm.
  ['.well-known/mcprush.com-claim.txt', 'mcprush-publish-longbook-f8437fa24fac553e8e821682\n'],
  ['plugins/longbook/skills/longbook-start/SKILL.md', START],
  ['plugins/longbook/commands/start.md', START_COMMAND],
  ...PROMPTS.map((p) => [`plugins/longbook/commands/${COMMANDS[p.id]}.md`, command(p)] as [string, string]),
  ...PROMPT_GROUPS.map((g) => [`plugins/longbook/skills/${SKILLS[g.id].name}/SKILL.md`, skill(g.id, SKILLS[g.id].heading, SKILL_CONNECT)] as [string, string]),
])

const listed = (dir: string): string[] =>
  existsSync(dir)
    ? readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
        e.isDirectory() ? listed(join(dir, e.name)) : [relative(OUT, join(dir, e.name))],
      )
    : []

let drift = 0
for (const [path, content] of files) {
  const at = join(OUT, path)
  if (existsSync(at) && readFileSync(at).equals(Buffer.from(content))) continue
  drift += 1
  if (CHECK) console.error(`drift: ${SHOWN}/${path}`)
  else {
    mkdirSync(dirname(at), { recursive: true })
    writeFileSync(at, content)
  }
}
for (const path of listed(OUT)) {
  if (files.has(path)) continue
  drift += 1
  if (CHECK) console.error(`stray: ${SHOWN}/${path}`)
  else rmSync(join(OUT, path))
}
if (CHECK && drift) {
  console.error('\nclaude plugin is stale — run: npm run plugin:claude')
  process.exit(1)
}
console.log(
  CHECK
    ? `claude plugin — in sync (${PROMPT_GROUPS.length} skills, ${PROMPTS.length} prompts, version ${VERSION}).`
    : `wrote ${SHOWN} (${PROMPT_GROUPS.length} skills, ${PROMPTS.length} prompts, version ${VERSION}, ${drift} file(s) changed).`,
)
