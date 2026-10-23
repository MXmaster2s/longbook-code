#!/usr/bin/env -S npx tsx
// Generates the data behind longbook.app/mcp — the router's tool lists and stable links —
// straight from the catalog both servers use, so the page can never advertise a tool that
// does not exist or miss one that does. Run with --check to verify. Regenerate: npm run site:router.
import { writeFileSync, readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { TOOLS } from '../packages/mcp/src/catalog'
import { WRITE_TOOLS } from '../packages/mcp/src/proposal'
import { LIST_DOCUMENTS_SPEC, READ_DOCUMENT_SPEC } from '../packages/mcp/src/documents'
import { REPORTS_SPEC } from '../packages/mcp/src/reportRead'
import { CONTRACT_REVISION } from '../packages/core/src/contract'
import { guideSection } from '../packages/core/src/guide'
import { PROMPTS, PROMPT_GROUPS } from '../packages/core/src/prompts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
// lib/, not the directory root: Netlify deploys every top-level file in
// netlify/edge-functions as an edge function, and a data module has no handler to run.
const OUT = join(ROOT, 'apps/longbook-site/netlify/edge-functions/lib/mcp-router.gen.ts')
const CHECK = process.argv.includes('--check')

const shorten = (text: string): string => {
  const first = text.split(/(?<=\.)\s/)[0] ?? text
  return first.trim()
}

const read = TOOLS.map((tool) => ({ name: tool.name, says: shorten(tool.description) }))
const write = WRITE_TOOLS.map((tool) => ({ name: tool.name, says: shorten(tool.description) }))
const promptOf = (id: string) => {
  const found = PROMPTS.find((p) => p.id === id)
  if (!found) {
    console.error(`the prompt catalogue has no ${id}`)
    process.exit(1)
  }
  return found
}
// The catalogue's words, the same ones the app's Automations section copies.
const DAILY_ROUND = promptOf('set-up-a-daily-longbook-email-round')
const ADD_STATEMENT = promptOf('add-my-statement')
const groupTitle = (id: string) => PROMPT_GROUPS.find((g) => g.id === id)?.title ?? id
// In the catalogue's group order, so a page grouping them never depends on how the list runs.
const prompts = PROMPT_GROUPS.flatMap((g) => PROMPTS.filter((p) => p.group === g.id)).map((p) => ({
  id: p.id,
  title: p.title,
  group: groupTitle(p.group),
  phrase: p.phrases[0]!,
  result: p.result,
  needs: p.needs ?? [],
}))
const round = guideSection(readFileSync(join(ROOT, 'apps/longbook-site/llms.txt'), 'utf8'), 'daily-email-round')
if (!round) {
  console.error('llms.txt has no daily-email-round chapter — run: npm run vault:contract')
  process.exit(1)
}

const local = [
  { name: 'list_documents', says: shorten(LIST_DOCUMENTS_SPEC.description) },
  { name: 'read_document', says: shorten(READ_DOCUMENT_SPEC.description) },
  { name: 'reports', says: shorten(REPORTS_SPEC.description) },
]

const doc = {
  name: 'longbook',
  description:
    "The owner's financial memory, over MCP. Two doors: the server inside the longbook app, which reads and writes the folder on their own machine, and this hosted one, which reads the copy they chose to push and takes writes as proposals their app applies.",
  contract_revision: CONTRACT_REVISION,
  endpoint: 'https://longbook.app/mcp',
  transport: 'streamable-http',
  doors: [
    {
      id: 'local',
      title: 'On the owner’s own machine',
      how: 'The server built into the longbook app, also on npm for any computer: npx -y @longbook/mcp@latest, with --vault <folder> where the app\u2019s iCloud folder is not. On the Mac, Set up Claude Desktop writes the client config in one click, and Copy configuration hands it to any other MCP client.',
      auth: 'none — it is their own folder',
      reads: true,
      writes: 'straight to the folder; every batch lands in the app’s Changes screen for review',
      documents: true,
    },
    {
      id: 'hosted-oauth',
      title: 'A browser AI, signed in',
      how: 'Add https://longbook.app/mcp as an MCP connector; sign-in opens in the browser.',
      auth: 'oauth',
      reads: true,
      writes:
        'as suggestions, once the owner ticks "Let signed-in AIs suggest changes" on the app\u2019s Automations screen — they wait for the app and land in its Changes screen, to keep or undo',
      documents: false,
    },
    {
      id: 'hosted-key',
      title: 'A scheduled agent, with a key',
      how: 'Create a key on the longbook app\u2019s Automations screen (More on iPhone, Settings on the Mac) with "Read and suggest changes", and send it as a bearer token. On a Mac, save it to the keychain when shown and read it with `security find-generic-password -s "longbook access key" -w`. Clients that cannot send a header — claude.ai among them — use the signed-in door above instead.',
      auth: 'bearer lbk_… with scope memory:propose',
      reads: true,
      writes: 'as proposals — they wait in the owner’s app and land in Changes the next time it opens',
      documents: false,
    },
  ],
  tools: { read, write, local_only: local },
  contract: {
    guide: 'https://longbook.app/llms.txt',
    schema: 'https://longbook.app/schema/longbook.schema.json',
    tag_library: 'https://longbook.app/library.json',
    prompts: 'https://longbook.app/prompts.json',
    read_guide_tool: 'read_guide — the same guide, by chapter, through a tool call; a prompt\u2019s name returns its procedure',
  },
  prompts,
  recipes: {
    import_statement: {
      title: ADD_STATEMENT.title,
      the_owner_says: ADD_STATEMENT.phrases[0]!,
      from_the_documents_folder: ADD_STATEMENT.phrases[1] ?? ADD_STATEMENT.phrases[0]!,
      same_text: `read_guide "${ADD_STATEMENT.id}"`,
    },
    daily_email_round: {
      title: 'The daily longbook email round',
      the_owner_says: DAILY_ROUND.phrases[0]!,
      needs: ['this longbook connector, with suggestions switched on', 'a connector that reads the owner\u2019s mail', 'a scheduled task, daily at 06:00 in the owner\u2019s time zone'],
      same_text: 'read_guide "daily-email-round"',
      instructions: round.text,
    },
  },
  first_call: 'whoami — who you are, what you may do, what is waiting, what failed to apply, and where the schemas live',
  idempotency: 'Send idempotency_key on every hosted write, built from the source and the write — {source id}:{tool}:{short payload hash}. Never put a date in it.',
}

const body = [
  '// generated by scripts/gen-mcp-router.mts — do not edit. Regenerate: npm run site:router.',
  '// The router\'s own facts, from the servers\' catalog, so the page cannot drift from the tools.',
  `export const ROUTER = ${JSON.stringify(doc, null, 2)} as const`,
  '',
].join('\n')

if (CHECK) {
  if (!existsSync(OUT) || readFileSync(OUT, 'utf8') !== body) {
    console.error('mcp router data drifted — run: npm run site:router')
    process.exit(1)
  }
  console.log('mcp router data — in sync.')
} else {
  writeFileSync(OUT, body)
  console.log(`wrote ${OUT.slice(ROOT.length)} (${read.length} read, ${write.length} write, ${local.length} local-only, ${prompts.length} prompts).`)
}
