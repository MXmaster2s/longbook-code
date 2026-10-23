#!/usr/bin/env -S npx tsx
// Publishes @longbook/mcp after installing the packed package in an empty folder and calling
// every read tool. The token comes from the keychain, never printed; npm asks for any authenticator code.
// Run: npm run npm:publish [-- --dry-run]
import { execFileSync } from 'node:child_process'
import { chmodSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { Client } from '@modelcontextprotocol/sdk/client/index.js'
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js'
import { NPM_NAME, RELEASE_VERSION, ROOT } from './release.mts'

const DRY = process.argv.includes('--dry-run')
const run = (cmd: string, args: string[], cwd = ROOT, env: NodeJS.ProcessEnv = process.env): string =>
  execFileSync(cmd, args, { cwd, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
const stop = (message: string): never => {
  console.error(message)
  process.exit(1)
}

for (const check of ['release:check', 'local:server:check']) {
  try { run('npm', ['run', '-s', check]) } catch { stop(`npm run ${check} fails. Regenerate before publishing.`) }
}
const published = (() => {
  try { return JSON.parse(run('npm', ['view', NPM_NAME, 'versions', '--json'])) as string[] | string } catch { return [] }
})()
if ([published].flat().includes(RELEASE_VERSION)) stop(`${NPM_NAME}@${RELEASE_VERSION} is already on npm. Raise patch in release.json.`)

const work = mkdtempSync(join(tmpdir(), 'longbook-npm-'))
try {
  console.log(`1/3 packing ${NPM_NAME}@${RELEASE_VERSION}…`)
  run('npm', ['pack', '--pack-destination', work], join(ROOT, 'packages/mcp'))
  const tarball = join(work, readdirSync(work).find((n) => n.endsWith('.tgz'))!)

  console.log('2/3 installing it in an empty folder and calling every tool…')
  const app = join(work, 'app')
  const vault = join(work, 'vault')
  run('mkdir', ['-p', app])
  run('npm', ['init', '-y'], app)
  run('npm', ['install', '--no-audit', '--no-fund', tarball], app)
  run('npx', ['tsx', 'scripts/demo-vault.mts', vault])
  const transport = new StdioClientTransport({ command: join(app, 'node_modules/.bin/longbook-mcp'), args: ['--vault', vault] })
  const client = new Client({ name: 'longbook publish check', version: RELEASE_VERSION })
  await client.connect(transport)
  const server = client.getServerVersion()
  if (server?.version !== RELEASE_VERSION) stop(`The packed server reports ${server?.version}, not ${RELEASE_VERSION}.`)
  const { tools } = await client.listTools()
  // Every read tool that can answer without a name to look up; search gets one.
  const reads = tools.filter((t) => t.annotations?.readOnlyHint && (t.name === 'search' || !(t.inputSchema.required ?? []).length))
  for (const tool of reads) {
    const answer = await client.callTool({ name: tool.name, arguments: tool.name === 'search' ? { query: 'rent' } : {} })
    if (answer.isError) stop(`${tool.name} failed in the packed package: ${JSON.stringify(answer.content).slice(0, 300)}`)
  }
  await client.close()
  console.log(`   ${tools.length} tools listed, ${reads.length} read tools answered, server reports ${server.version}.`)

  if (DRY) {
    console.log('3/3 skipped (--dry-run). Nothing was published.')
  } else {
    console.log('3/3 publishing…')
    const token = run('security', ['find-generic-password', '-s', 'NPM Access Token', '-w']).trim()
    const npmrc = join(work, '.npmrc')
    writeFileSync(npmrc, `//registry.npmjs.org/:_authToken=${token}\n`)
    chmodSync(npmrc, 0o600)
    const otp = process.env.NPM_OTP?.trim()
    const args = ['publish', tarball, '--access', 'public', '--loglevel', 'error', '--userconfig', npmrc, ...(otp ? [`--otp=${otp}`] : [])]
    try {
      if (!otp && process.stdin.isTTY) {
        // In a terminal npm asks for the authenticator code itself, at this moment, so it is fresh.
        console.log('   npm may ask for the code from your authenticator app now.')
        execFileSync('npm', args, { cwd: ROOT, stdio: 'inherit' })
      } else {
        run('npm', args)
      }
    } catch (error) {
      const said = `${(error as { stderr?: string }).stderr ?? ''}`
      if (/EOTP|one-time password/i.test(said)) {
        stop('npm asks for the code from your authenticator app. Run again with it: NPM_OTP=123456 npm run npm:publish')
      }
      stop(said.trim() ? `npm refused the publish:\n${said.trim()}`
        : 'npm refused the publish without a message; its log is the newest file in ~/.npm/_logs. If your account ' +
          'asks for an authenticator code, run again with it: NPM_OTP=123456 npm run npm:publish')
    }
    const now = run('npm', ['view', `${NPM_NAME}@${RELEASE_VERSION}`, 'version']).trim()
    if (now !== RELEASE_VERSION) stop(`npm does not show ${NPM_NAME}@${RELEASE_VERSION} yet.`)
    console.log(`Published ${NPM_NAME}@${RELEASE_VERSION}. Next: npm run registry:publish.`)
  }
} finally {
  rmSync(work, { recursive: true, force: true })
}
