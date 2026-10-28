// The skills both plugins carry, one per prompt group, generated from the prompt catalogue
// (packages/core/src/prompts.ts). Each plugin says in its own words how its app connects.
import { PROMPTS } from '../packages/core/src/prompts'
import type { LongbookPrompt, PromptGroupId } from '../packages/core/src/prompts'

export const MCP_URL = 'https://longbook.app/mcp'

const WIDTH = 95
// Claude reads at most this many characters of a skill's description.
const DESCRIPTION_LIMIT = 1024

/** Each group as a skill: its name, and what it is for, said the way a person asks. */
export const SKILLS: Record<PromptGroupId, { heading: string; name: string; does: string; asks: string[] }> = {
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

export const wrap = (text: string, indent = ''): string => {
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

export const quote = (words: string[]): string => words.map((w) => `"${w}"`).join(', ')

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

/** A group's SKILL.md; `connect` says what to do when no longbook tools are available. */
export function skill(group: PromptGroupId, title: string, connect: string): string {
  const prompts = PROMPTS.filter((p) => p.group === group)
  const entries = prompts.map((p) => {
    const lines = [`### ${p.title}`, '', `Name: \`${p.id}\``, '', wrap(`The user says: ${quote(p.phrases)}.`, ''), '']
    lines.push(wrap(`Result: ${p.result}`), '')
    lines.push(wrap(`Attachments: ${p.attachments}`), '')
    if (p.needs?.length) lines.push(wrap(`Needs: ${p.needs.map((n) => NEEDS[n]).join(', and ')}.`), '')
    lines.push(p.writes ? 'Writes to the longbook: yes; it waits in the app\'s Proposals screen.' : 'Writes to the longbook: no.')
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
${wrap(`4. ${connect}`).replace(/\n/g, '\n   ')}

## The prompts

${entries.join('\n\n')}
`
}
