#!/usr/bin/env -S npx tsx
// The one-prompt import, run for real — on demand, since it spends an agent's time.
// A temp vault holding the fixture statements, a real claude session on the bundled
// server, the owner's own sentence, and then judgement of the FILE it leaves behind.
import { spawn } from 'node:child_process'
import { cpSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { CHECKS, rows } from '../packages/mcp/tests/importChecks.js'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const STATEMENTS = join(ROOT, 'packages/mcp/tests/fixtures/statements')
const SERVER = join(ROOT, 'packages/mcp/bin/longbook-mcp.mjs')
const CONTRACT = join(ROOT, 'packages/core/contract')

const PROMPT =
  'I have added my last year’s bank statements inside the longbook/documents folder. ' +
  'Update my longbook. Learn more from longbook.app/mcp'

function buildVault(): string {
  const dir = mkdtempSync(join(tmpdir(), 'longbook-agent-'))
  mkdirSync(join(dir, 'documents'), { recursive: true })
  cpSync(STATEMENTS, join(dir, 'documents'), { recursive: true })
  writeFileSync(join(dir, 'financial_memory.json'), JSON.stringify({ app: 'longbook', version: 2, commitments: [] }, null, 2))
  for (const name of ['llms.txt', 'longbook.schema.json', 'library.json']) {
    cpSync(join(CONTRACT, name), join(dir, name))
  }
  return dir
}

/** The agent runs headless, with the longbook server and nothing else. */
function runAgent(vault: string): Promise<{ code: number; text: string }> {
  const config = {
    mcpServers: { longbook: { command: process.execPath, args: [SERVER, '--vault', vault] } },
  }
  const configPath = join(vault, '.agent-mcp.json')
  writeFileSync(configPath, JSON.stringify(config, null, 2))

  return new Promise((resolve) => {
    const child = spawn(
      'claude',
      ['-p', PROMPT, '--mcp-config', configPath, '--allowedTools', 'mcp__longbook', '--permission-mode', 'bypassPermissions'],
      { cwd: vault, stdio: ['ignore', 'pipe', 'pipe'] },
    )
    let text = ''
    child.stdout.on('data', (chunk) => {
      text += chunk
      process.stdout.write(chunk)
    })
    child.stderr.on('data', (chunk) => process.stderr.write(chunk))
    child.on('close', (code) => resolve({ code: code ?? 1, text }))
  })
}

const vault = buildVault()
console.log(`vault: ${vault}\nprompt: ${PROMPT}\n`)
const { code } = await runAgent(vault)
console.log(`\n\nagent exited ${code}. Judging the file.\n`)

const written = JSON.parse(readFileSync(join(vault, 'financial_memory.json'), 'utf8'))

// An agent that never ran is not an agent that did badly, and reporting it as failures
// would be a lie about the product. Say which happened, and stop.
if (rows(written).length === 0) {
  console.error('The vault is empty: the agent wrote nothing.')
  console.error(
    code === 0
      ? 'It ran and chose not to write — read its transcript above before changing anything.'
      : 'It did not run. This needs a signed-in claude CLI (or ANTHROPIC_API_KEY) in a terminal of its own; a nested session cannot borrow one.',
  )
  process.exit(2)
}

let failed = 0
for (const check of CHECKS) {
  let ok = false
  try {
    ok = check.ok(written)
  } catch {
    ok = false
  }
  if (!ok) failed += 1
  console.log(`${ok ? '  ok  ' : ' FAIL '} ${check.what}`)
}

console.log(`\n${rows(written).length} rows written; ${CHECKS.length - failed}/${CHECKS.length} checks passed.`)
console.log(`The file is at ${join(vault, 'financial_memory.json')} — read it before believing any of this.`)
process.exit(failed === 0 ? 0 : 1)
