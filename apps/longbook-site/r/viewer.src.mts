// The shared-report viewer at longbook.app/r/<id>: a password gate, then the report drawn the
// way the app's report screen draws it. Bundled inline into index.html by
// scripts/gen-share-viewer.mts. Every string reaches the page through text nodes, never markup.
import {
  TITLE_CATEGORIES, TITLE_CHARGES, TITLE_REMOVED,
  categoryRanks, categoryWord, chargeSplit, commentMeta, donutView, emptyNarrowing, errorWords,
  expiryNote, filterOptions, genericHeading, genericWord, inkVar, isNarrowed, isObject, listedRows,
  moduleKey, modulesOf, moneyOf, narrow, rangeName, rowFacts, rowInkRank, rowName, scopeLine,
  shareIdFrom, statsView, writtenNote,
  type Json, type Narrowing, type RowFact, type SliceRow,
} from './report-view.mts'

const app = document.getElementById('app') as HTMLElement
const shareId = shareIdFrom(location.pathname)
// Kept after the gate opens, for the comments sent later from the same page.
let password = ''

type Child = Node | string | null | undefined | false

function el<K extends keyof HTMLElementTagNameMap>(tag: K, cls?: string | null, ...children: Child[]): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag)
  if (cls) node.className = cls
  for (const child of children) if (child) node.append(child)
  return node
}

const objects = (value: unknown): Json[] => (Array.isArray(value) ? value.filter(isObject) : [])
const words = (value: unknown): string => (typeof value === 'string' ? value : '')

// ---- glyphs ----------------------------------------------------------------------------

const SVG = 'http://www.w3.org/2000/svg'
const GLYPHS = {
  bubble: ['M2.5 3h11v7.5H8.5L5 13.5v-3H2.5z'],
  date: ['M2.5 4h11v9.5h-11z', 'M2.5 7h11', 'M5.5 2.5v3', 'M10.5 2.5v3'],
  category: ['M2.5 2.5h5l6 6-5 5-6-6z', 'M5.5 5.5h.01'],
  member: ['M8 7.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z', 'M3 13.5c.5-2.3 2.5-3.5 5-3.5s4.5 1.2 5 3.5'],
  account: ['M1.5 4h13v8.5h-13z', 'M1.5 6.75h13', 'M4 10h3'],
  currency: ['M8 1.5v13', 'M11 4.5H6.75a2 2 0 0 0 0 4h2.5a2 2 0 0 1 0 4H5'],
  search: ['M7 11.5a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9z', 'M10.5 10.5l3.5 3.5'],
  clear: ['M4 4l8 8', 'M12 4l-8 8'],
  chevron: ['M4.5 6.5L8 10l3.5-3.5'],
}

function glyph(paths: string[], size: number, label?: string): SVGSVGElement {
  const svg = document.createElementNS(SVG, 'svg')
  svg.setAttribute('viewBox', '0 0 16 16')
  svg.setAttribute('width', String(size))
  svg.setAttribute('height', String(size))
  svg.setAttribute('class', 'glyph')
  if (label) {
    svg.setAttribute('role', 'img')
    svg.setAttribute('aria-label', label)
  } else {
    svg.setAttribute('aria-hidden', 'true')
  }
  for (const d of paths) {
    const path = document.createElementNS(SVG, 'path')
    path.setAttribute('d', d)
    path.setAttribute('fill', 'none')
    path.setAttribute('stroke', 'currentColor')
    path.setAttribute('stroke-width', '1.5')
    path.setAttribute('stroke-linecap', 'round')
    path.setAttribute('stroke-linejoin', 'round')
    svg.append(path)
  }
  return svg
}

// ---- the server ------------------------------------------------------------------------

/** A refusal by the server's status; 0 when it could not be reached at all. */
class Refusal {
  constructor(readonly status: number) {}
}
const statusOf = (err: unknown): number => (err instanceof Refusal ? err.status : 0)

async function post(payload: Json): Promise<Json> {
  let res: Response
  try {
    res = await fetch('/share-report', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload),
    })
  } catch {
    throw new Refusal(0)
  }
  const body = await res.text().catch(() => '')
  if (!res.ok) throw new Refusal(res.status)
  try {
    const data: unknown = JSON.parse(body)
    if (isObject(data)) return data
  } catch {
    // An answer that is not JSON is the server going wrong, said below as that.
  }
  throw new Refusal(500)
}

// ---- the page's parts ------------------------------------------------------------------

/** A heading over its content, the way the report screen names its parts; a note ends the line. */
function section(heading: string | null, note: Node | null, ...children: Child[]): HTMLElement {
  const head = heading !== null || note
    ? el('div', 'module-head', heading !== null ? el('h2', 'lb-screen-title', heading) : null, note)
    : null
  return el('section', 'module', head, ...children)
}

const panel = (...children: Child[]): HTMLElement => el('div', 'panel', ...children)
const countNote = (count: string): HTMLElement => el('span', 'lb-footnote tertiary module-note', count)

/** The owner's own note on a module, worn under its card. */
function ownerNote(mod: Json): HTMLElement | null {
  const note = words(mod.comment)
  return note ? el('p', 'owner-note lb-footnote', glyph(GLYPHS.bubble, 11, 'Comment'), el('span', null, note)) : null
}

function commentItem(comment: Json): HTMLElement {
  return el('div', 'comment-item',
    el('div', 'lb-footnote tertiary', commentMeta(comment)),
    el('div', 'lb-body-sm comment-body', words(comment.body)))
}

/** A viewer's comments on one module, and one box to add another, kept under the module's key. */
function commentArea(moduleId: string, comments: Json[]): HTMLElement {
  const list = el('div', 'comment-list', ...comments.filter((c) => c.module_id === moduleId).map(commentItem))
  const toggle = el('button', 'comment-toggle lb-footnote', glyph(GLYPHS.bubble, 12), el('span', null, 'Comment'))
  toggle.type = 'button'
  toggle.setAttribute('aria-expanded', 'false')
  const name = el('input', 'field')
  name.placeholder = 'Name (optional)'
  name.setAttribute('aria-label', 'Name (optional)')
  name.maxLength = 80
  const box = el('textarea', 'field')
  box.placeholder = 'Comment'
  box.setAttribute('aria-label', 'Comment')
  box.maxLength = 2000
  box.required = true
  const send = el('button', 'btn', 'Send')
  send.type = 'submit'
  const note = el('p', 'form-note lb-footnote')
  note.setAttribute('role', 'alert')
  const form = el('form', 'comment-form', name, box, send, note)
  form.hidden = true

  toggle.addEventListener('click', () => {
    form.hidden = !form.hidden
    toggle.setAttribute('aria-expanded', String(!form.hidden))
    if (!form.hidden) box.focus()
  })
  // One comment per module per visit: a sent one takes its form and toggle away.
  form.addEventListener('submit', (event) => {
    event.preventDefault()
    if (!box.value.trim()) return
    send.disabled = true
    note.textContent = ''
    post({ action: 'comment', id: shareId, password, module_id: moduleId, author: name.value, body: box.value }).then(
      () => {
        list.append(commentItem({ author: name.value, body: box.value, created_at: new Date().toISOString() }))
        form.remove()
        toggle.remove()
      },
      (err: unknown) => {
        note.textContent = errorWords(statusOf(err), 'comment')
        send.disabled = false
      },
    )
  })
  return el('div', 'comments', list, toggle, form)
}

// ---- the total -------------------------------------------------------------------------

function statsBody(mod: Json): HTMLElement {
  const view = statsView(mod)
  const wrap = el('div', 'stats')
  if (view.lead !== null) {
    wrap.append(el('div', 'stat-top',
      el('span', 'lb-stat-number stat-figure', view.lead),
      view.companions ? el('span', 'lb-label brand-text', view.companions) : null,
      view.delta ? el('span', `lb-footnote ${view.delta.good ? 'delta-good' : 'delta-bad'}`, view.delta.text) : null))
  }
  if (view.line) wrap.append(el('p', 'lb-footnote tertiary', view.line))
  return wrap
}

// ---- rings and tiles -------------------------------------------------------------------

const RING_RADIUS = 56
const RING_LENGTH = 2 * Math.PI * RING_RADIUS

function legendRow(row: SliceRow, inked: boolean): HTMLElement {
  const swatch = el('span', inked ? 'swatch' : 'swatch swatch-hollow')
  if (inked) swatch.style.background = inkVar(row.rank)
  return el('div', 'legend-row lb-footnote', swatch,
    el('span', 'legend-name', row.label),
    el('span', 'legend-share', row.share ?? '—'),
    el('span', 'legend-amount', row.amountText))
}

/** A ring with its top slice's share at the centre, and a legend row per slice. */
function ringBody(mod: Json, currency: string): HTMLElement {
  const view = donutView(mod, currency)
  const svg = document.createElementNS(SVG, 'svg')
  svg.setAttribute('viewBox', '0 0 140 140')
  svg.setAttribute('class', 'ring')
  // Decorative: every slice is named, with its share, in the legend.
  svg.setAttribute('aria-hidden', 'true')
  for (const arc of view.arcs) {
    const length = arc.length * RING_LENGTH
    const circle = document.createElementNS(SVG, 'circle')
    circle.setAttribute('cx', '70')
    circle.setAttribute('cy', '70')
    circle.setAttribute('r', String(RING_RADIUS))
    circle.setAttribute('fill', 'none')
    circle.setAttribute('stroke-width', '18')
    circle.setAttribute('stroke-dasharray', `${length} ${RING_LENGTH - length}`)
    circle.setAttribute('stroke-dashoffset', String(-arc.offset * RING_LENGTH))
    circle.setAttribute('transform', 'rotate(-90 70 70)')
    // Through style: an SVG presentation attribute does not resolve var().
    circle.style.stroke = inkVar(arc.rank)
    svg.append(circle)
  }
  const centre = el('div', 'ring-center',
    el('div', 'lb-screen-title ring-title', view.centre.title),
    el('div', 'lb-footnote tertiary ring-note', view.centre.note))
  return el('div', 'donut',
    el('div', 'ring-wrap', svg, centre),
    el('div', 'legend', ...view.scoped.map((row) => legendRow(row, true)), ...view.foreign.map((row) => legendRow(row, false))))
}

/** The Categories donut as a strip of tiles: ink, name, amount, share. Another currency folds. */
function categoryTiles(mod: Json, currency: string): HTMLElement {
  const view = donutView(mod, currency)
  const tile = (row: SliceRow): HTMLElement => {
    const dot = el('span', 'tile-dot')
    dot.style.background = inkVar(row.rank)
    return el('div', 'tile',
      el('span', 'tile-glyph', dot),
      el('span', 'lb-footnote secondary tile-name', categoryWord(row.label)),
      el('span', 'lb-number-sm tile-amount', row.amountText),
      el('span', 'lb-footnote tertiary', row.share ?? '—'))
  }
  return el('div', 'tiles', ...view.scoped.map(tile), ...view.foreign.map(tile))
}

// ---- charges ---------------------------------------------------------------------------

const FACT_GLYPH: Record<RowFact['kind'], string[]> = {
  date: GLYPHS.date, category: GLYPHS.category, member: GLYPHS.member, account: GLYPHS.account,
}

function chargeRow(row: Json, rank: number | null, currency: string, removed: boolean): HTMLElement {
  const rail = el('span', 'rail')
  rail.style.background = inkVar(removed ? null : rank)
  const facts = rowFacts(row).map((fact) => el('span', 'fact', glyph(FACT_GLYPH[fact.kind], 10), el('span', null, fact.text)))
  return el('div', removed ? 'charge removed' : 'charge', rail,
    el('div', 'charge-body',
      el('div', 'lb-body charge-name', rowName(row)),
      el('div', 'facts lb-footnote', ...facts)),
    el('div', 'lb-number-sm charge-amount', moneyOf(row, currency)))
}

/** A chip that holds a native menu: it reads its title until a choice is made, then the choice. */
function filterChip(
  title: string, paths: string[], options: [string, string][], pick: (value: string | null) => void,
): { chip: HTMLElement; select: HTMLSelectElement } {
  const select = el('select', 'chip-select')
  select.setAttribute('aria-label', title)
  const resting = new Option(title, '', true, true)
  resting.hidden = true
  select.append(resting, new Option('Any', ''))
  for (const [value, label] of options) select.append(new Option(label, value))
  const chip = el('label', 'chip lb-body-sm', glyph(paths, 11), select, glyph(GLYPHS.chevron, 9))
  select.addEventListener('change', () => {
    chip.classList.toggle('picked', select.value !== '')
    pick(select.value === '' ? null : select.value)
  })
  return { chip, select }
}

/** The drawn charge list: searched and narrowed from its own rows, then what was taken out. */
function chargesSections(mod: Json, title: string, moduleId: string, ctx: Ctx): HTMLElement[] {
  const { kept, removed } = chargeSplit(ctx.report, mod)
  const currency = words(mod.currency) || ctx.currency
  const narrowing: Narrowing = emptyNarrowing()
  const count = countNote(String(kept.length))
  const list = el('div', 'charges')
  const empty = el('div', 'empty lb-footnote tertiary', 'No charges match. Clear the search or a filter.')

  const search = el('input', 'search-input')
  search.type = 'search'
  search.placeholder = 'Search'
  search.setAttribute('aria-label', 'Search')
  const controls = el('div', 'charge-controls', el('label', 'search', glyph(GLYPHS.search, 12), search))

  const options = filterOptions(kept)
  const chips: { chip: HTMLElement; select: HTMLSelectElement }[] = []
  // Each narrowing is on offer only when the rows give it a choice to make.
  const offer = (name: string, paths: string[], choices: [string, string][], key: 'category' | 'account' | 'member' | 'currency') => {
    if (choices.length > 1) chips.push(filterChip(name, paths, choices, (value) => { narrowing[key] = value; draw() }))
  }
  const pairs = (values: string[]): [string, string][] => values.map((value) => [value, value])
  offer('Category', GLYPHS.category, options.categories, 'category')
  offer('Account', GLYPHS.account, pairs(options.accounts), 'account')
  offer('Member', GLYPHS.member, pairs(options.members), 'member')
  offer('Currency', GLYPHS.currency, pairs(options.currencies), 'currency')
  const clear = el('button', 'chip lb-body-sm', glyph(GLYPHS.clear, 11), el('span', null, 'Clear'))
  clear.type = 'button'
  clear.addEventListener('click', () => {
    Object.assign(narrowing, emptyNarrowing(), { search: narrowing.search })
    for (const { chip, select } of chips) {
      select.value = ''
      chip.classList.remove('picked')
    }
    draw()
  })
  if (chips.length) controls.append(el('div', 'chips', ...chips.map((c) => c.chip), clear))
  search.addEventListener('input', () => {
    narrowing.search = search.value
    draw()
  })

  function draw(): void {
    const shown = narrow(kept, narrowing)
    count.textContent = shown.length === kept.length ? String(kept.length) : `${shown.length} of ${kept.length}`
    list.textContent = ''
    list.append(...shown.map((row) => chargeRow(row, rowInkRank(row, ctx.ranks), currency, false)))
    empty.textContent = kept.length === 0 ? 'Every charge was removed from this report.' : 'No charges match. Clear the search or a filter.'
    empty.hidden = shown.length > 0
    clear.hidden = !isNarrowed(narrowing)
  }
  draw()

  const out = [section(title, count, controls, empty, list, ownerNote(mod), commentArea(moduleId, ctx.comments))]
  // Part of the same module: it takes no comment box and no key of its own.
  if (removed.length) {
    out.push(section(TITLE_REMOVED, countNote(String(removed.length)),
      el('div', 'charges', ...removed.map((row) => chargeRow(row, null, currency, true)))))
  }
  return out
}

/** Any other list of charges: every row, neutral ink, no split. */
function plainCharges(mod: Json, ctx: Ctx): HTMLElement {
  const currency = words(mod.currency) || ctx.currency
  return el('div', 'charges', ...listedRows(ctx.report, mod).map((row) => chargeRow(row, null, currency, false)))
}

// ---- older and unknown kinds -----------------------------------------------------------

function barsBody(mod: Json, ctx: Ctx): HTMLElement {
  const bars = objects(mod.bars)
  const currency = words(mod.currency) || ctx.currency
  const top = Math.max(0, ...bars.map((b) => (typeof b.amount === 'number' && Number.isFinite(b.amount) ? b.amount : 0)))
  return el('div', 'bars', ...bars.map((bar) => {
    const fill = el('div', 'bar-fill')
    const share = top > 0 && typeof bar.amount === 'number' ? (bar.amount / top) * 100 : 0
    fill.style.width = `${Math.max(0, Math.min(100, share))}%`
    return el('div', 'bar-row',
      el('div', 'bar-top lb-body-sm', el('span', 'secondary', words(bar.label)), el('span', 'tertiary num', moneyOf(bar, currency))),
      el('div', 'bar-track', fill))
  }))
}

function proseBody(mod: Json): HTMLElement {
  const lines = String(words(mod.text) || words(mod.body)).split('\n').filter((line) => line.trim())
  return el('div', 'prose', ...lines.map((line) => el('p', 'lb-body secondary', line)))
}

const ROW_KEYS = ['name', 'label', 'date', 'category', 'amount', 'currency', 'value']

/** An older file's table: each row's words, then its amount; extra keys read as "key: value". */
function tableBody(mod: Json, ctx: Ctx): HTMLElement {
  const currency = words(mod.currency) || ctx.currency
  const rows = Array.isArray(mod.rows) ? mod.rows : []
  return el('div', 'table', ...rows.map((r: unknown) => {
    if (Array.isArray(r)) {
      return el('div', 'table-row', el('div', 'lb-body-sm', r.slice(0, -1).join('  ')),
        el('div', 'lb-body-sm num', r.length ? String(r[r.length - 1]) : ''))
    }
    if (!isObject(r)) return el('div', 'table-row', el('div', 'lb-body-sm', String(r)))
    const meta = [words(r.date), words(r.category)].filter(Boolean)
    for (const key of Object.keys(r)) {
      if (ROW_KEYS.includes(key)) continue
      const value = r[key]
      meta.push(`${key}: ${value && typeof value === 'object' ? JSON.stringify(value) : String(value)}`)
    }
    return el('div', 'table-row',
      el('div', null, el('div', 'lb-body-sm', rowName(r)), meta.length ? el('div', 'lb-footnote tertiary', meta.join(' · ')) : null),
      el('div', 'lb-body-sm num', moneyOf(r, currency)))
  }))
}

/** A kind this page does not know still shows its data, field by field. */
function genericBody(mod: Json): HTMLElement {
  const keys = Object.keys(mod).filter((key) => !['type', 'id', 'title', 'comment'].includes(key)).sort()
  return el('div', 'generic', ...keys.map((key) => {
    const value = mod[key]
    const label = el('div', 'lb-footnote tertiary', key.replace(/_/g, ' '))
    if (Array.isArray(value)) {
      return el('div', 'generic-list', label, ...value.map((item) => el('div', 'lb-body-sm secondary', genericWord(item))))
    }
    return el('div', 'generic-row', label, el('div', 'lb-body-sm generic-value', genericWord(value)))
  }))
}

// ---- the report ------------------------------------------------------------------------

interface Ctx {
  report: Json
  comments: Json[]
  currency: string
  ranks: Map<string, number>
}

function renderModule(mod: Json, index: number, ctx: Ctx): HTMLElement[] {
  const key = moduleKey(mod, index)
  const title = words(mod.title) || null
  const type = words(mod.type)
  const annotate = (heading: string | null, body: HTMLElement): HTMLElement[] =>
    [section(heading, null, body, ownerNote(mod), commentArea(key, ctx.comments))]
  switch (type) {
    case 'stats': return annotate(title, panel(statsBody(mod)))
    case 'donut':
      return annotate(title, panel(title === TITLE_CATEGORIES ? categoryTiles(mod, ctx.currency) : ringBody(mod, ctx.currency)))
    case 'transactions':
      return title === TITLE_CHARGES ? chargesSections(mod, title, key, ctx) : annotate(title, plainCharges(mod, ctx))
    case 'bars': return annotate(title, panel(barsBody(mod, ctx)))
    case 'table': return annotate(title, panel(tableBody(mod, ctx)))
    case 'text': case 'note': case 'prose': return annotate(title, panel(proseBody(mod)))
    default: return annotate(genericHeading(mod), panel(genericBody(mod)))
  }
}

function renderReport(report: Json, comments: Json[], expiresAt: unknown): void {
  const title = words(report.title) || 'Shared report'
  document.title = title
  app.textContent = ''
  const days = rangeName(report) ?? writtenNote(report)
  const scope = scopeLine(report)
  app.append(el('header', 'report-head',
    el('h1', 'lb-display-lg', title),
    days ? el('p', 'lb-body-sm secondary', days) : null,
    scope ? el('p', 'lb-footnote tertiary', scope) : null))

  const ctx: Ctx = { report, comments, currency: words(report.currency), ranks: categoryRanks(report) }
  // Every position counts, an entry that is not a module included: the comment keys are
  // module-<index> into this very array.
  modulesOf(report).forEach((mod, index) => {
    if (isObject(mod)) app.append(...renderModule(mod, index, ctx))
  })

  const home = el('a', null, 'longbook')
  home.href = '/'
  const expiry = expiryNote(expiresAt)
  app.append(el('footer', 'report-foot lb-footnote tertiary',
    el('span', null, 'Shared from ', home),
    expiry ? el('span', null, expiry) : null))
}

function renderGate(): void {
  app.textContent = ''
  const input = el('input', 'field')
  input.type = 'password'
  input.id = 'share-password'
  input.autocomplete = 'off'
  input.required = true
  const label = el('label', 'lb-label field-label', 'Password')
  label.htmlFor = input.id
  const open = el('button', 'btn', 'Open')
  open.type = 'submit'
  const note = el('p', 'form-note lb-footnote')
  note.setAttribute('role', 'alert')
  const form = el('form', 'gate-form', label, el('div', 'gate-row', input, open), note)
  app.append(el('div', 'gate',
    el('h1', 'lb-display-lg', 'Shared report'),
    el('p', 'lb-body-sm secondary', 'Enter the password that came with this link.'),
    form))
  input.focus()
  form.addEventListener('submit', (event) => {
    event.preventDefault()
    open.disabled = true
    note.textContent = ''
    post({ action: 'view', id: shareId, password: input.value }).then(
      (data) => {
        password = input.value
        renderReport(isObject(data.report) ? data.report : {}, objects(data.comments), data.expires_at)
        window.scrollTo(0, 0)
      },
      (err: unknown) => {
        note.textContent = errorWords(statusOf(err), 'view')
        open.disabled = false
      },
    )
  })
}

if (shareId) {
  renderGate()
} else {
  app.append(el('div', 'gate',
    el('h1', 'lb-display-lg', 'Shared report'),
    el('p', 'lb-body-sm secondary', 'This link is missing its report. Check the address.')))
}
