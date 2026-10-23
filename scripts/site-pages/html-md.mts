// A small HTML-to-Markdown converter for the site's own hand-written pages: headings, paragraphs,
// links, emphasis, lists, code, tables and FAQ disclosures. Scripts, styles, icons, controls and
// anything marked data-md="skip" (the drawn app mockups) are left out.
import { ORIGIN } from './content.mts'

interface Node {
  tag: string
  attrs: Record<string, string>
  kids: (Node | string)[]
}

const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr'])
const RAW = new Set(['script', 'style'])
const DROP = new Set(['script', 'style', 'svg', 'button', 'noscript', 'template', 'select', 'input', 'form', 'nav', 'head'])
const BLOCK = new Set(['p', 'div', 'section', 'article', 'main', 'header', 'aside', 'figure', 'figcaption', 'ul', 'ol',
  'li', 'table', 'details', 'summary', 'pre', 'blockquote', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'dl', 'dt', 'dd'])

const ENTITIES: Record<string, string> = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“',
  mdash: '—', ndash: '–', hellip: '…', middot: '·', rarr: '→', larr: '←', times: '×', copy: '©', thinsp: ' ',
}
const decode = (s: string): string => s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e: string) => {
  if (e[0] === '#') return String.fromCodePoint(e[1]!.toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : Number(e.slice(1)))
  return ENTITIES[e.toLowerCase()] ?? m
})

export function parse(html: string): Node {
  const root: Node = { tag: 'root', attrs: {}, kids: [] }
  const stack: Node[] = [root]
  const re = /<!--[\s\S]*?-->|<(\/?)([a-zA-Z][a-zA-Z0-9-]*)((?:\s+[^\s=>/]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?)*)\s*(\/?)>|([^<]+|<)/g
  for (let m = re.exec(html); m; m = re.exec(html)) {
    if (m[0].startsWith('<!--')) continue
    const top = stack[stack.length - 1]!
    if (m[5] !== undefined) {
      top.kids.push(m[5])
      continue
    }
    const tag = m[2]!.toLowerCase()
    if (m[1]) {
      const at = stack.map((n) => n.tag).lastIndexOf(tag)
      if (at > 0) stack.length = at
      continue
    }
    const attrs: Record<string, string> = {}
    for (const a of (m[3] ?? '').matchAll(/([^\s=>/]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g)) {
      attrs[a[1]!.toLowerCase()] = decode(a[2] ?? a[3] ?? a[4] ?? '')
    }
    const node: Node = { tag, attrs, kids: [] }
    top.kids.push(node)
    if (RAW.has(tag)) {
      const end = html.indexOf(`</${tag}`, re.lastIndex)
      re.lastIndex = end < 0 ? html.length : end
      continue
    }
    if (!VOID.has(tag) && !m[4]) stack.push(node)
  }
  return root
}

const skipped = (n: Node): boolean =>
  DROP.has(n.tag) || n.attrs['data-md'] === 'skip' || 'hidden' in n.attrs || n.attrs['aria-hidden'] === 'true'

const absolute = (href: string): string => (href.startsWith('/') ? `${ORIGIN}${href}` : href)

function text(n: Node | string): string {
  if (typeof n === 'string') return decode(n)
  if (skipped(n)) return ''
  return n.kids.map(text).join('')
}

// Inline content: text, links and emphasis, whitespace folded. Two elements laid side by side with
// nothing between them, like two links or two labels, get a space so their words stay apart.
function inline(kids: (Node | string)[]): string {
  let out = ''
  let afterElement = false
  for (const k of kids) {
    if (typeof k === 'string') {
      out += decode(k).replace(/\s+/g, ' ')
      afterElement = false
      continue
    }
    if (skipped(k)) continue
    const before = out.length
    if (afterElement && out && !/\s$/.test(out) && !BLOCK.has(k.tag) && k.tag !== 'br') out += ' '
    const spaced = out.length
    afterElement = true
    if (k.tag === 'br') out += '\n'
    else if (k.tag === 'a') {
      const label = inline(k.kids).trim()
      const href = k.attrs.href ?? ''
      out += !label ? '' : !href || href.startsWith('#') ? label : `[${label}](${absolute(href)})`
    } else if (k.tag === 'strong' || k.tag === 'b') {
      const t = inline(k.kids).trim()
      out += t ? `**${t}**` : ''
    } else if (k.tag === 'em' || k.tag === 'i') {
      const t = inline(k.kids).trim()
      out += t ? `*${t}*` : ''
    } else if (k.tag === 'span' && /(^|\s)k(\s|$)/.test(k.attrs.class ?? '')) {
      // A label and its value laid out as two columns: the label gets its own emphasis and a colon.
      const t = inline(k.kids).trim()
      out += t ? `**${t}**: ` : ''
    } else if (k.tag === 'code') out += `\`${text(k).trim()}\``
    else if (k.tag === 'img') out += k.attrs.alt ? `![${k.attrs.alt}](${absolute(k.attrs.src ?? '')})` : ''
    else if (BLOCK.has(k.tag)) out += `\n\n${blocks(k).join('\n\n')}\n\n`
    else out += inline(k.kids)
    // An element that printed nothing, or only punctuation, takes its space back.
    if (out.length === spaced) out = out.slice(0, before)
    else if (spaced > before && /^[.,;:!?)]/.test(out.slice(spaced))) out = out.slice(0, before) + out.slice(spaced)
  }
  return out
}

function tableMd(n: Node): string {
  const rows: string[][] = []
  const walk = (x: Node): void => {
    for (const k of x.kids) {
      if (typeof k === 'string') continue
      if (k.tag === 'tr') rows.push(k.kids.filter((c): c is Node => typeof c !== 'string' && (c.tag === 'td' || c.tag === 'th'))
        .map((c) => inline(c.kids).replace(/\s+/g, ' ').replace(/\|/g, '\\|').trim()))
      else walk(k)
    }
  }
  walk(n)
  if (!rows.length) return ''
  const width = Math.max(...rows.map((r) => r.length))
  const line = (r: string[]): string => `| ${[...r, ...Array(width - r.length).fill('')].join(' | ')} |`
  return [line(rows[0]!), line(Array(width).fill('---')), ...rows.slice(1).map(line)].join('\n')
}

// Block content: each child block becomes one Markdown block; runs of inline content between
// blocks become paragraphs.
export function blocks(n: Node): string[] {
  const out: string[] = []
  let run: (Node | string)[] = []
  const flush = (): void => {
    const t = inline(run).replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim()
    if (t) out.push(...t.split(/\n{2,}/))
    run = []
  }
  for (const k of n.kids) {
    if (typeof k === 'string' || !BLOCK.has(k.tag)) {
      run.push(k)
      continue
    }
    flush()
    if (skipped(k)) continue
    const h = /^h([1-6])$/.exec(k.tag)
    if (h) {
      const t = inline(k.kids).replace(/\s+/g, ' ').trim()
      if (t) out.push(`${'#'.repeat(Number(h[1]))} ${t}`)
    } else if (k.tag === 'p' || k.tag === 'figcaption' || k.tag === 'dt' || k.tag === 'dd') {
      const t = inline(k.kids).replace(/[ \t]+/g, ' ').replace(/ *\n */g, '\n').trim()
      if (t) out.push(t)
    } else if (k.tag === 'ul' || k.tag === 'ol') {
      const items = k.kids.filter((c): c is Node => typeof c !== 'string' && c.tag === 'li' && !skipped(c))
      // Continuation lines are indented by the marker's width, so a step's text stays in its step.
      const lines = items.map((li, i) => {
        const marker = k.tag === 'ol' ? `${i + 1}.` : '-'
        const pad = ' '.repeat(marker.length + 1)
        const body = blocks(li).join('\n\n').split('\n').map((l, j) => (j === 0 || !l ? l : pad + l)).join('\n')
        return `${marker} ${body}`
      }).filter((l) => !/^(-|\d+\.) ?$/.test(l.trim()))
      if (lines.length) out.push(lines.join('\n'))
    } else if (k.tag === 'pre') {
      out.push(`\`\`\`\n${text(k).replace(/\n+$/, '')}\n\`\`\``)
    } else if (k.tag === 'details') {
      const summary = k.kids.find((c): c is Node => typeof c !== 'string' && c.tag === 'summary')
      const q = summary ? inline(summary.kids).replace(/\s*\+\s*$/, '').replace(/\s+/g, ' ').trim() : ''
      if (q) out.push(`### ${q}`)
      out.push(...blocks({ ...k, kids: k.kids.filter((c) => c !== summary) }))
    } else if (k.tag === 'table') {
      const t = tableMd(k)
      if (t) out.push(t)
    } else if (k.tag === 'blockquote') {
      out.push(blocks(k).map((b) => b.replace(/^/gm, '> ')).join('\n>\n'))
    } else if (k.tag === 'hr') {
      out.push('---')
    } else {
      out.push(...blocks(k))
    }
  }
  flush()
  return out
}

export function htmlToMarkdown(html: string): string {
  return `${blocks(parse(html)).join('\n\n').replace(/\n{3,}/g, '\n\n').trim()}\n`
}
