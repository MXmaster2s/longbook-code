#!/usr/bin/env -S npx tsx
// Generates longbook's Claude plugin in apps/claude-plugin from the prompt catalogue: a skill
// per prompt group, the hosted connector, a README and a marketplace file. Skills send Claude
// to read_guide for procedures. --check verifies. Regenerate: npm run plugin:claude.
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'
import { PROMPTS, PROMPT_GROUPS } from '../packages/core/src/prompts'
import type { LongbookPrompt, PromptGroupId } from '../packages/core/src/prompts'
import { CONTRACT_REVISION } from '../packages/core/src/contract'
import { RELEASE_VERSION } from './release.mts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const OUT = join(ROOT, 'apps/claude-plugin')
const PLUGIN = join(OUT, 'plugins/longbook')
const CHECK = process.argv.includes('--check')
const MCP_URL = 'https://longbook.app/mcp'
const GMAIL_URL = 'https://gmailmcp.googleapis.com/mcp/v1'
// The public repository the marketplace is published to; longbook-code itself is private.
const REPO = 'MXmaster2s/longbook-claude-plugin'
// longbook's one release number (release.json): a new one is what installed copies update to.
const VERSION = RELEASE_VERSION
const WIDTH = 95
// Claude reads at most this many characters of a skill's description.
const DESCRIPTION_LIMIT = 1024

/** Each group as a skill: its name, and what it is for, said the way a person asks. */
const SKILLS: Record<PromptGroupId, { heading: string; name: string; does: string; asks: string[] }> = {
  setup: {
    heading: 'Set up',
    name: 'longbook-setup',
    does:
      "Sets up the user's longbook, their record of subscriptions, bills, rent, salaries, loans and " +
      'other commitments, from bank and card statements; adds later statements, categorises it, and ' +
      'completes a month so longbook can draw its report.',
    asks: ["set up my longbook", "import my bank statement", "add last month's statement", "categorise my expenses", "complete September in my longbook"],
  },
  current: {
    heading: 'Keep it current',
    name: 'longbook-keep-current',
    does:
      "Keeps the user's longbook current: this month's invoices, bills and money in from their email, " +
      'a daily email round, invoices and receipts kept as files, and a new commitment or expense.',
    asks: ["add this month's bills from my email", "check my email every morning for payments", "add these invoices", "add my new gym membership", "I spent 2,000 on groceries"],
  },
  reading: {
    heading: 'Answers',
    name: 'longbook-answers',
    does:
      "Answers questions about the user's bills, subscriptions, payments and spending from their " +
      'longbook: what is due next or this week, what is coming ' +
      'in the next 30 days, what a month cost, and what renews this year.',
    asks: ["what bills are coming up this week", "what do I pay next", "how much did I spend in September", "which premiums renew this year", "what subscriptions renew this month", "give me my week in longbook"],
  },
  reports: {
    heading: 'Reports',
    name: 'longbook-reports',
    does: 'Asks longbook to draw a report over the days, accounts, people or categories the user chooses, or for a trip.',
    asks: ["make a report of my Goa trip", "a report of what we spent on the kids this quarter", "create a report for my business card"],
  },
  housekeeping: {
    heading: 'Housekeeping',
    name: 'longbook-housekeeping',
    does:
      "Tidies the user's longbook (doubled charges, bank-style names, odd categories) and sets up a " +
      'morning brief of what is due.',
    asks: ["clean up duplicates in my longbook", "fix the weird names in my expenses", "give me a morning summary of what's due"],
  },
  email: {
    heading: 'From your email',
    name: 'longbook-from-email',
    does:
      "Finds subscriptions, expenses, invoices, insurances, purchases, bills, loans and EMIs, travel " +
      "bookings or money in in the user's email, and adds them to their longbook.",
    asks: ["find my subscriptions in my email", "find my insurance policies in my email", "pull my Amazon orders from Gmail", "add my salary credits from email", "find my EMI payments in my mail"],
  },
}

const NEEDS: Record<string, string> = {
  mail: "the user's mail connected to their AI",
  scheduler: "scheduled tasks in the AI's app",
}

const wrap = (text: string, indent = ''): string => {
  const lines: string[] = []
  let line = indent
  for (const word of text.split(' ')) {
    if (line.length + word.length + 1 > WIDTH && line.trim()) {
      lines.push(line.trimEnd())
      line = indent
    }
    line += (line.trim() ? ' ' : '') + word
  }
  lines.push(line.trimEnd())
  return lines.join('\n')
}

const quote = (words: string[]): string => words.map((w) => `"${w}"`).join(', ')

function description(group: PromptGroupId, prompts: LongbookPrompt[]): string {
  const key = (w: string) => w.toLowerCase().replace(/[^a-z0-9 ]/g, '')
  const all = [...SKILLS[group].asks, ...prompts.flatMap((p) => p.phrases)]
  const asks = all.filter((w, i) => all.findIndex((x) => key(x) === key(w)) === i).slice(0, 9)
  const text =
    `Use for requests like ${quote(asks)}, even when the user does not name longbook. ` +
    `${SKILLS[group].does} Works through the longbook connector (${MCP_URL}).`
  if (text.length > DESCRIPTION_LIMIT) throw new Error(`${SKILLS[group].name}: description is ${text.length} characters`)
  return text
}

function skill(group: PromptGroupId, title: string): string {
  const prompts = PROMPTS.filter((p) => p.group === group)
  const entries = prompts.map((p) => {
    const lines = [`### ${p.title}`, '', `Name: \`${p.id}\``, '', wrap(`The user says: ${quote(p.phrases)}.`, ''), '']
    lines.push(wrap(`Result: ${p.result}`), '')
    lines.push(wrap(`Attachments: ${p.attachments}`), '')
    if (p.needs?.length) lines.push(wrap(`Needs: ${p.needs.map((n) => NEEDS[n]).join(', and ')}.`), '')
    lines.push(p.writes ? 'Writes to the longbook: yes; it waits in the app\'s Changes screen.' : 'Writes to the longbook: no.')
    return lines.join('\n')
  })
  return `---
name: ${SKILLS[group].name}
description: >
${wrap(description(group, prompts), '  ')}
---

# longbook: ${title}

${wrap(`longbook is the user's financial memory: every commitment they pay, its charges past and planned, their accounts and the people payments are for. ${SKILLS[group].does} Each prompt below has a procedure on the longbook server; follow it rather than improvising one.`)}

## How to run one

1. Pick the prompt below that matches what the user asked, in our words or theirs.
2. Call the longbook connector's \`read_guide\` with the prompt's name, for example
   \`read_guide("${prompts[0]!.id}")\`. It returns the procedure, step by step, and the guide
   chapter it builds on.
3. Follow that procedure and the guide's rules. Never write a card number, a full account
   number, a PIN or a password.
${wrap(`4. If no longbook tools are available, say the longbook connector is needed: in Claude, Settings, then Connectors, then Add custom connector, with the address ${MCP_URL}, signing in with the longbook account. Installing this plugin adds the connector too.`).replace(/\n/g, '\n   ')}

## The prompts

${entries.join('\n\n')}
`
}

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
  '3. If the longbook holds no commitments yet, offer `/longbook:set-up`: attach bank and card statements, ideally the last 12 months. Stop there unless the user wants the list.',
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

${wrap("Each skill and command asks the longbook server for the prompt's procedure with read_guide, so the steps are always the server's current ones.")}

## What it connects to

${wrap(`- **longbook** (${MCP_URL}), signed in with your longbook account. Claude reads your longbook through it; what Claude writes waits in the longbook app's Changes screen, where you keep it or undo it.`).replace(/\n/g, '\n  ')}
${wrap(`- **Gmail** (${GMAIL_URL}), signed in with your Google account. Only the email prompts read it, to find payments, bills and receipts.`).replace(/\n/g, '\n  ')}

${wrap('The plugin runs no code on your machine and sends nothing anywhere else. Privacy: ' + PRIVACY_URL + '. Generated from the longbook prompt catalogue (contract revision ' + CONTRACT_REVISION + ').')}

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
  ...PROMPT_GROUPS.map((g) => [`plugins/longbook/skills/${SKILLS[g.id].name}/SKILL.md`, skill(g.id, SKILLS[g.id].heading)] as [string, string]),
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
  if (CHECK) console.error(`drift: apps/claude-plugin/${path}`)
  else {
    mkdirSync(dirname(at), { recursive: true })
    writeFileSync(at, content)
  }
}
for (const path of listed(OUT)) {
  if (files.has(path)) continue
  drift += 1
  if (CHECK) console.error(`stray: apps/claude-plugin/${path}`)
  else rmSync(join(OUT, path))
}
if (CHECK && drift) {
  console.error('\nclaude plugin is stale — run: npm run plugin:claude')
  process.exit(1)
}
console.log(
  CHECK
    ? `claude plugin — in sync (${PROMPT_GROUPS.length} skills, ${PROMPTS.length} prompts, version ${VERSION}).`
    : `wrote apps/claude-plugin (${PROMPT_GROUPS.length} skills, ${PROMPTS.length} prompts, version ${VERSION}, ${drift} file(s) changed).`,
)
