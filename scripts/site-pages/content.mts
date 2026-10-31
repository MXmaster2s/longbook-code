// The features section's source: one Markdown file per feature, a short frontmatter and a fixed
// set of sections. Parsing is strict, so a missing section or a dead link fails the build
// instead of shipping a half page.
import { readFileSync, readdirSync } from 'node:fs'
import { basename, join } from 'node:path'

export const ORIGIN = 'https://longbook.app'
export const DOWNLOAD = 'https://testflight.apple.com/join/g66Nd3Na'
// The Mac app is a direct download from longbook.app; the iPhone app is TestFlight's.
export const DOWNLOAD_MAC = `${ORIGIN}/download/`

export const GROUPS = [
  { id: 'track', name: 'Track' },
  { id: 'understand', name: 'Understand' },
  { id: 'import', name: 'Import' },
  { id: 'automate', name: 'Automations & AI' },
  { id: 'devices', name: 'iPhone and Mac' },
] as const
export type GroupId = (typeof GROUPS)[number]['id']

export type Platform = 'iphone' | 'mac'

export interface Block {
  title: string
  body: string[]
  // A #### heading: a group that the blocks after it belong to, shown as a heading over its rows.
  group?: true
}

export interface Feature {
  slug: string
  order: number
  group: GroupId
  title: string
  seoTitle: string
  description: string
  card: string
  platforms: Platform[]
  iphone: string | null
  mac: string | null
  iphoneAlt: string | null
  macAlt: string | null
  aliases: string[]
  related: string[]
  labels: string[]
  /** A film of the feature at features/media/<slug>.mp4, named by its spoken description. */
  film: string | null
  summary: string[]
  screen: string[]
  does: Block[]
  why: string[]
  questions: Block[]
}

export interface Screen {
  key: string
  platform: Platform
  source: string | null
  title: string
  description: string
}

export interface About {
  body: string[]
}

// The automations page: the feature pages it shows, in order, and sections of short blocks for
// connecting an AI. A section's text before its first ### is its introduction.
export interface Section {
  title: string
  intro: string[]
  blocks: Block[]
}

// The section under which the page lists the prompt catalogue from packages/core/src/prompts.ts,
// after the section's own introduction.
export const PROMPTS_SECTION = 'Prompts for your AI'

export interface Automations {
  title: string
  seoTitle: string
  description: string
  features: string[]
  summary: string[]
  sections: Section[]
}

const SECTIONS: Record<string, 'screen' | 'does' | 'why' | 'questions'> = {
  'On the screen': 'screen',
  'What it does': 'does',
  'Why it exists': 'why',
  Questions: 'questions',
}

const list = (v: string | undefined): string[] =>
  (v ?? '').split(',').map((s) => s.trim()).filter(Boolean)

export function frontmatter(text: string, file: string): { data: Record<string, string>; body: string } {
  const m = /^---\n([\s\S]*?)\n---\n/.exec(text)
  if (!m) throw new Error(`${file}: no frontmatter`)
  const data: Record<string, string> = {}
  for (const line of m[1]!.split('\n')) {
    if (!line.trim()) continue
    const kv = /^([a-z_]+):\s*(.*)$/.exec(line)
    if (!kv) throw new Error(`${file}: bad frontmatter line "${line}"`)
    if (kv[1]! in data) throw new Error(`${file}: "${kv[1]}" given twice`)
    data[kv[1]!] = kv[2]!.trim()
  }
  return { data, body: text.slice(m[0].length) }
}

// Paragraphs are runs of lines; a run whose every line starts with "- " is a list and keeps
// its markers, so renderers can tell the two apart.
export function paragraphs(lines: string[]): string[] {
  const out: string[] = []
  let run: string[] = []
  const flush = (): void => {
    if (!run.length) return
    out.push(run.every((l) => l.startsWith('- ')) ? run.join('\n') : run.join(' '))
    run = []
  }
  for (const raw of lines) {
    const line = raw.trim()
    if (line) run.push(line)
    else flush()
  }
  flush()
  return out
}

function blocks(lines: string[], file: string, section: string): Block[] {
  const out: Block[] = []
  let current: { title: string; lines: string[]; group: boolean } | null = null
  const close = (): void => {
    if (current) out.push({ title: current.title, body: paragraphs(current.lines), ...(current.group ? { group: true as const } : {}) })
  }
  for (const line of lines) {
    const h = /^(###|####) (.+)$/.exec(line)
    if (h) {
      close()
      current = { title: h[2]!.trim(), lines: [], group: h[1] === '####' }
    } else if (current) current.lines.push(line)
    else if (line.trim()) throw new Error(`${file}: text before the first ### in "${section}"`)
  }
  close()
  for (const b of out) if (!b.body.length) throw new Error(`${file}: "${b.title}" has no text`)
  return out
}

export function parseFeature(text: string, file: string): Feature {
  const { data, body } = frontmatter(text, file)
  const lines = body.split('\n')
  const parts: Record<string, string[]> = { summary: [] }
  let at = 'summary'
  for (const line of lines) {
    if (/^# /.test(line)) throw new Error(`${file}: the title lives in the frontmatter, not a # heading`)
    const h = /^## (.+)$/.exec(line)
    if (h) {
      const key = SECTIONS[h[1]!.trim()]
      if (!key) throw new Error(`${file}: unknown section "${h[1]}"`)
      if (key in parts) throw new Error(`${file}: section "${h[1]}" given twice`)
      at = key
      parts[at] = []
    } else parts[at]!.push(line)
  }
  const need = (k: string): string => {
    const v = data[k]
    if (!v) throw new Error(`${file}: frontmatter needs "${k}"`)
    return v
  }
  const group = need('group') as GroupId
  if (!GROUPS.some((g) => g.id === group)) throw new Error(`${file}: unknown group "${group}"`)
  const platforms = list(need('platforms')) as Platform[]
  for (const p of platforms) if (p !== 'iphone' && p !== 'mac') throw new Error(`${file}: unknown platform "${p}"`)
  const feature: Feature = {
    slug: need('slug'),
    order: Number(need('order')),
    group,
    title: need('title'),
    seoTitle: need('seo_title'),
    description: need('description'),
    card: need('card'),
    platforms,
    iphone: data.iphone || null,
    mac: data.mac || null,
    iphoneAlt: data.iphone_alt || null,
    macAlt: data.mac_alt || null,
    aliases: list(data.aliases),
    related: list(data.related),
    labels: list(data.labels),
    film: data.film || null,
    summary: paragraphs(parts.summary ?? []),
    screen: paragraphs(parts.screen ?? []),
    does: blocks(parts.does ?? [], file, 'What it does'),
    why: paragraphs(parts.why ?? []),
    questions: blocks(parts.questions ?? [], file, 'Questions'),
  }
  const known = new Set(Object.keys(data))
  for (const k of ['slug', 'order', 'group', 'title', 'seo_title', 'description', 'card', 'platforms',
    'iphone', 'mac', 'iphone_alt', 'mac_alt', 'aliases', 'related', 'labels', 'film']) known.delete(k)
  if (known.size) throw new Error(`${file}: unknown frontmatter ${[...known].join(', ')}`)
  if (!Number.isInteger(feature.order)) throw new Error(`${file}: order must be a whole number`)
  if (!feature.summary.length) throw new Error(`${file}: no summary before the first section`)
  if (!feature.screen.length) throw new Error(`${file}: no "On the screen" section`)
  if (feature.does.length < 2 || feature.does.length > 4) throw new Error(`${file}: "What it does" needs 2 to 4 blocks`)
  if (!feature.why.length) throw new Error(`${file}: no "Why it exists" section`)
  return feature
}

export function loadFeatures(dir: string): Feature[] {
  const files = readdirSync(dir).filter((f) => f.endsWith('.md')).sort()
  const features = files.map((f) => {
    const feature = parseFeature(readFileSync(join(dir, f), 'utf8'), f)
    if (`${feature.slug}.md` !== f) throw new Error(`${f}: slug "${feature.slug}" must match the file name`)
    return feature
  })
  return features.sort((a, b) => a.order - b.order || a.slug.localeCompare(b.slug))
}

export function loadScreens(file: string): Map<string, Screen> {
  const raw = JSON.parse(readFileSync(file, 'utf8')) as Record<string, Omit<Screen, 'key'>>
  const screens = new Map<string, Screen>()
  for (const [key, s] of Object.entries(raw)) {
    if (s.platform !== 'iphone' && s.platform !== 'mac') throw new Error(`screens: ${key} has no platform`)
    if (!key.startsWith(`${s.platform}-`)) throw new Error(`screens: ${key} must start with ${s.platform}-`)
    screens.set(key, { key, ...s })
  }
  return screens
}

export function loadAbout(file: string): About {
  return { body: paragraphs(readFileSync(file, 'utf8').split('\n')) }
}

export function loadAutomations(file: string): Automations {
  const name = basename(file)
  const { data, body } = frontmatter(readFileSync(file, 'utf8'), name)
  const need = (k: string): string => {
    const v = data[k]
    if (!v) throw new Error(`${name}: frontmatter needs "${k}"`)
    return v
  }
  const unknown = Object.keys(data).filter((k) => !['title', 'seo_title', 'description', 'features'].includes(k))
  if (unknown.length) throw new Error(`${name}: unknown frontmatter ${unknown.join(', ')}`)
  const summary: string[] = []
  const parts: { title: string; lines: string[] }[] = []
  for (const line of body.split('\n')) {
    if (/^# /.test(line)) throw new Error(`${name}: the title lives in the frontmatter, not a # heading`)
    const h = /^## (.+)$/.exec(line)
    if (h) parts.push({ title: h[1]!.trim(), lines: [] })
    else if (parts.length) parts[parts.length - 1]!.lines.push(line)
    else summary.push(line)
  }
  const sections = parts.map((p): Section => {
    const first = p.lines.findIndex((l) => /^#{3,4} /.test(l))
    return {
      title: p.title,
      intro: paragraphs(first < 0 ? p.lines : p.lines.slice(0, first)),
      blocks: first < 0 ? [] : blocks(p.lines.slice(first), name, p.title),
    }
  })
  const automations: Automations = {
    title: need('title'),
    seoTitle: need('seo_title'),
    description: need('description'),
    features: list(need('features')),
    summary: paragraphs(summary),
    sections,
  }
  if (!automations.summary.length) throw new Error(`${name}: no summary before the first section`)
  for (const s of sections) if (!s.intro.length && !s.blocks.length) throw new Error(`${name}: "${s.title}" has no text`)
  return automations
}

export const LIMITS = { seoTitle: 60, description: 160, card: 120 }

// Cross-file rules: unique slugs and aliases, related pages that exist, screens that exist and
// match their platform, and lengths search engines will show without cutting.
export function validate(features: Feature[], screens: Map<string, Screen>): string[] {
  const problems: string[] = []
  const slugs = new Set(features.map((f) => f.slug))
  const taken = new Map<string, string>()
  for (const f of features) {
    for (const name of [f.slug, ...f.aliases]) {
      const other = taken.get(name)
      if (other) problems.push(`${f.slug}: "${name}" is also used by ${other}`)
      taken.set(name, f.slug)
    }
    if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(f.slug)) problems.push(`${f.slug}: slug is not lowercase-hyphenated`)
    const titleLength = `${f.seoTitle} — longbook`.length
    if (titleLength > LIMITS.seoTitle) problems.push(`${f.slug}: title is ${titleLength} characters, over ${LIMITS.seoTitle}`)
    if (f.description.length > LIMITS.description) problems.push(`${f.slug}: description is ${f.description.length} characters`)
    if (f.card.length > LIMITS.card) problems.push(`${f.slug}: card text is ${f.card.length} characters`)
    if (f.related.length !== 3) problems.push(`${f.slug}: needs exactly three related features`)
    for (const r of f.related) {
      if (!slugs.has(r)) problems.push(`${f.slug}: related "${r}" does not exist`)
      if (r === f.slug) problems.push(`${f.slug}: relates to itself`)
    }
    for (const p of ['iphone', 'mac'] as const) {
      const key = f[p]
      if (!key) continue
      const s = screens.get(key)
      if (!s) problems.push(`${f.slug}: screen "${key}" is not in screens.json`)
      else if (s.platform !== p) problems.push(`${f.slug}: screen "${key}" is not an ${p} screen`)
      if (!f.platforms.includes(p)) problems.push(`${f.slug}: has a ${p} screen but ${p} is not a platform`)
    }
  }
  return problems
}
