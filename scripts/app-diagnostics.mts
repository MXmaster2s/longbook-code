#!/usr/bin/env -S npx tsx
// The apps' MetricKit diagnostics (app.diagnostic events in PostHog) as one markdown page:
// grouped by kind, newest first, identical signatures counted once, each with its raw payload.
// The key comes from the keychain and is never printed.
// Run: npm run diagnostics:pull [-- --days 30] [-- --out page.md] [-- --owner name] [-- --created YYYY-MM-DD]
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'

const POSTHOG_QUERY = 'https://us.posthog.com/api/projects/537369/query/'
const ROW_LIMIT = 2000
const KINDS: Record<string, string> = {
  crash: 'Crashes',
  hang: 'Hangs',
  cpu_exception: 'CPU exceptions',
  disk_write_exception: 'Disk write exceptions',
  launch: 'Launch diagnostics',
}

const args = process.argv.slice(2)
const flag = (name: string): string | undefined => {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : undefined
}
const refuse = (message: string): never => {
  console.error(message)
  process.exit(2)
}

const DAYS = (() => {
  const raw = flag('--days')
  if (raw === undefined) return 30
  const n = Number(raw)
  return Number.isInteger(n) && n >= 1 && n <= 480 ? n : refuse('--days takes a whole number from 1 to 480.')
})()
const OUT = flag('--out')
if (args.includes('--out') && !OUT) refuse('--out takes a file path.')
const CREATED = flag('--created')
if (CREATED !== undefined && !/^\d{4}-\d{2}-\d{2}$/.test(CREATED)) refuse('--created takes a date, YYYY-MM-DD.')

// Frontmatter values the page already carries survive a rewrite unless a flag replaces them.
const previous = (key: string): string | undefined => {
  if (!OUT || !existsSync(resolve(OUT))) return undefined
  const head = readFileSync(resolve(OUT), 'utf8').match(/^---\n([\s\S]*?)\n---/)
  return head?.[1]?.match(new RegExp(`^${key}:\\s*(.+)$`, 'm'))?.[1]?.trim()
}
const pad = (n: number) => String(n).padStart(2, '0')
const now = new Date()
const localDate = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`
const localStamp = `${localDate}T${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`
const owner = flag('--owner') ?? previous('owner') ?? 'unassigned'
const created = CREATED ?? previous('created') ?? localDate
const start = new Date(Date.now() - (DAYS - 1) * 86_400_000).toISOString().slice(0, 10)

// ---- the events ----------------------------------------------------------------------------

const keychain = (service: string): string => {
  try {
    return execFileSync('security', ['find-generic-password', '-s', service, '-w'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).replace(/\n$/, '')
  } catch {
    return refuse(`No keychain item "${service}".`)
  }
}

const FIELDS = [
  'kind',
  'platform',
  'app_version',
  'app_build',
  'os_version',
  'os_version_full',
  'device_type',
  'exception_type',
  'exception_code',
  'signal',
  'termination_reason',
  'payload',
] as const
type Field = (typeof FIELDS)[number]
type Diagnostic = { at: string } & Record<Field, string | null>

const fetchDiagnostics = async (): Promise<Diagnostic[]> => {
  const key = keychain('PostHog Personal API Key')
  const query = `select timestamp, ${FIELDS.map((f) => `properties.${f}`).join(', ')} from events
    where event = 'app.diagnostic' and toDate(timestamp) >= toDate('${start}')
    order by timestamp desc limit ${ROW_LIMIT}`
  const res = await fetch(POSTHOG_QUERY, {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: { kind: 'HogQLQuery', query } }),
    signal: AbortSignal.timeout(60_000),
  })
  const text = await res.text()
  if (!res.ok) throw new Error(`PostHog answered HTTP ${res.status}: ${text.slice(0, 300)}`)
  const rows = ((JSON.parse(text) as { results?: unknown[][] }).results ?? []) as unknown[][]
  return rows.map((r) => {
    // Control characters from outside text never reach the page.
    const cell = (i: number) =>
      r[i] === null || r[i] === undefined || r[i] === '' ? null : String(r[i]).replace(/[\u0000-\u001f\u007f-\u009f]/g, '?')
    return { at: String(r[0]), ...Object.fromEntries(FIELDS.map((f, i) => [f, cell(i + 1)])) } as Diagnostic
  })
}

// ---- reading a payload ----------------------------------------------------------------------

type Frame = {
  binaryName?: string
  address?: number
  offsetIntoBinaryTextSegment?: number
  subFrames?: Frame[]
}

const parsePayload = (raw: string | null): unknown => {
  if (!raw) return null
  try {
    return JSON.parse(raw)
  } catch {
    return null
  }
}

/** The innermost frames of the attributed thread, with each binary's load address for atos. */
const topFrames = (payload: unknown, depth = 6): string[] => {
  if (typeof payload !== 'object' || payload === null) return []
  const p = payload as Record<string, unknown>
  const tree = (p.callStackTree ?? p) as { callStacks?: { threadAttributed?: boolean; callStackRootFrames?: Frame[] }[] }
  const stacks = Array.isArray(tree.callStacks) ? tree.callStacks : []
  const stack = stacks.find((s) => s.threadAttributed) ?? stacks[0]
  const out: string[] = []
  let frame = stack?.callStackRootFrames?.[0]
  while (frame && out.length < depth) {
    const { binaryName, address, offsetIntoBinaryTextSegment: offset } = frame
    if (typeof address === 'number' && typeof offset === 'number') {
      out.push(`${binaryName ?? '?'} 0x${address.toString(16)} (load address 0x${(address - offset).toString(16)})`)
    } else {
      out.push(`${binaryName ?? '?'} (no address)`)
    }
    frame = frame.subFrames?.[0]
  }
  return out
}

/** A fence longer than any backtick run inside the text, so a payload cannot close it early. */
const fence = (text: string): string => '`'.repeat(Math.max(3, ...[...text.matchAll(/`+/g)].map((m) => m[0].length + 1)))

// ---- rendering ------------------------------------------------------------------------------

const frontmatter = ['---', 'kind: guide', `owner: ${owner}`, `created: ${created}`, `last_edit: ${localStamp}`, '---', ''].join('\n')
const howMade =
  `Made by \`npm run diagnostics:pull\` from the app.diagnostic events of the last ${DAYS} days (${start} onward), ` +
  'grouped by kind, newest first, identical signatures counted once. Addresses are unsymbolicated: ' +
  '`atos -arch arm64 -o <dSYM of that build>/Contents/Resources/DWARF/<binary> -l <load address> <address>`.'

const render = (events: Diagnostic[]): string => {
  const parts = [frontmatter, '# App diagnostics', '', howMade, '']
  if (events.length === 0) return [...parts, 'No diagnostics yet.', ''].join('\n')
  if (events.length >= ROW_LIMIT) parts.push(`Only the newest ${ROW_LIMIT} events are read; shorten --days to see a narrower window whole.`, '')

  // Same kind, build, exception and innermost frames: the same problem, counted once.
  type Group = { newest: Diagnostic; oldest: Diagnostic; count: number; frames: string[]; payload: unknown }
  const groups = new Map<string, Group>()
  for (const e of events) {
    const payload = parsePayload(e.payload)
    const frames = topFrames(payload)
    const signature = JSON.stringify([
      e.kind, e.platform, e.app_version, e.app_build, e.exception_type, e.exception_code, e.signal, e.termination_reason,
      frames.map((f) => f.replace(/ \(load address.*$/, '')),
    ])
    const g = groups.get(signature)
    if (g) {
      g.count += 1
      g.oldest = e
    } else {
      groups.set(signature, { newest: e, oldest: e, count: 1, frames, payload })
    }
  }

  const kinds = [...new Set([...Object.keys(KINDS), ...events.map((e) => e.kind ?? 'unknown')])]
  for (const kind of kinds) {
    const inKind = [...groups.values()].filter((g) => (g.newest.kind ?? 'unknown') === kind)
    if (inKind.length === 0) continue
    const total = inKind.reduce((s, g) => s + g.count, 0)
    parts.push(`## ${KINDS[kind] ?? kind} (${total})`, '')
    for (const g of inKind) {
      const e = g.newest
      const when = e.at.replace('T', ' ').replace(/\.\d+Z?$|Z$/, '').slice(0, 16)
      const os = e.os_version_full ?? [e.platform === 'ios' ? 'iOS' : e.platform === 'macos' ? 'macOS' : e.platform, e.os_version].filter(Boolean).join(' ')
      parts.push(`### ${when} UTC · longbook ${e.app_version ?? '?'} (${e.app_build ?? '?'}) · ${os || 'unknown OS'} · ${e.device_type ?? 'unknown device'}`, '')
      parts.push(
        g.count > 1
          ? `- **Seen:** ${g.count} times, first ${g.oldest.at.slice(0, 16).replace('T', ' ')} UTC`
          : '- **Seen:** once',
      )
      parts.push(
        `- **Exception type:** ${e.exception_type ?? '—'} · **Exception code:** ${e.exception_code ?? '—'} · ` +
          `**Signal:** ${e.signal ?? '—'} · **Termination reason:** ${e.termination_reason ?? '—'}`,
      )
      if (g.frames.length) {
        parts.push('- **Innermost frames:**')
        for (const f of g.frames) parts.push(`  - ${f}`)
      }
      const body = g.payload === null ? (e.payload ?? 'No payload.') : JSON.stringify(g.payload, null, 2)
      const f = fence(body)
      parts.push('', `${f}json`, body, f, '')
    }
  }
  return parts.join('\n')
}

let events: Diagnostic[]
try {
  events = await fetchDiagnostics()
} catch (err) {
  refuse(err instanceof Error ? err.message : String(err))
  process.exit(2)
}
const page = render(events)
if (OUT) {
  const path = resolve(OUT)
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, page)
  console.log(`Written: ${path} (${events.length} events)`)
} else {
  console.log(page)
}
