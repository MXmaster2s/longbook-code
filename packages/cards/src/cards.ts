// The four cards. Inputs are the MCP tools' own answers, rendered without arithmetic:
// a card lays numbers out, it never makes them.
import { escapeHtml as esc, messageCard, shell } from './shell.js'

export interface Money {
  currency: string
  amount: number
  text: string
}

/** "in" for money that arrives, "transfer" for a movement in no total; null or absent for a charge. */
export type Direction = 'in' | 'transfer' | null

export interface ChargeRow {
  commitment_id: string
  name: string
  date: string
  due: string
  amount: number
  currency: string
  amount_text: string
  tag: string | null
  member: string | null
  account: string | null
  paid: boolean
  direction?: Direction
}

/** A list's transfers, figured apart from its total; absent when the list holds none. */
export interface TransferFigures {
  transfer_count?: number
  transfers_total_text?: string
}

export interface NextPaymentDay extends TransferFigures {
  date: string
  due: string
  /** Spending only. Empty on a day that holds nothing but transfers. */
  total: Money[]
  total_text: string
  charges: ChargeRow[]
}
export type NextPaymentData = NextPaymentDay | { message: string }

export interface UpcomingData extends TransferFigures {
  window_days: number
  /** Every row listed, transfers among them. */
  count: number
  total: Money[]
  total_text: string
  charges: ChargeRow[]
}

export interface CashflowMonth {
  month: string
  total: number
  total_text: string
  /** The month is ahead of today's: its rows are the plan as written. */
  planned: boolean
}
export interface CashflowData {
  note: string
  series: { currency: string; months: CashflowMonth[] }[]
}

export interface CommitmentRow {
  id: string
  name: string
  amount: number
  currency: string
  amount_text: string
  cycle: string
  status: string
  tag: string | null
  member: string | null
  account: string | null
  next_charge: { date: string; due: string; amount: number; amount_text: string } | null
  planned_through: string | null
  charges: number
  direction?: Direction
}
export interface CommitmentsData {
  count: number
  commitments: CommitmentRow[]
  plans_running_short: { commitment_id: string; name: string; planned_through: string }[]
}

/** Rows a card shows before folding the rest into one honest line. */
const FOLD = 12

const foldNote = (shown: number, total: number) =>
  total > shown ? `<p class="note" style="margin-top: var(--lb-space-s2)">and ${total - shown} more</p>` : ''

/** The word a row wears when it is not a charge: beside the name, in the quiet ink "paid" uses. */
const flag = (direction: Direction | undefined) =>
  direction === 'transfer' ? '<span class="paid">transfer</span>' : direction === 'in' ? '<span class="paid">money in</span>' : ''

const chargeLine = (c: ChargeRow) => `
<div class="row">
  <span class="when">${esc(c.due)}</span>
  <span class="name">${esc(c.name)}</span>
  ${flag(c.direction)}
  <span class="spacer"></span>
  ${c.paid ? '<span class="paid">paid</span>' : ''}
  <span class="money amount">${esc(c.amount_text)}</span>
</div>`

const transferWord = (count: number) => `${count} transfer${count === 1 ? '' : 's'}`

/** The list's transfers on a line of their own, as handed over: beside the total, never in it. */
const transfersLine = (data: TransferFigures, counted = true) =>
  data.transfer_count
    ? `<p class="note" style="margin-bottom: var(--lb-space-s2)">${counted ? `${transferWord(data.transfer_count)}, ` : ''}${esc(data.transfers_total_text ?? '')} · between your own accounts, in no total</p>`
    : ''

export function nextPaymentCard(data: NextPaymentData): string {
  if (!('date' in data)) return messageCard(data.message)
  const rows = data.charges.map(chargeLine).join('')
  // A day that holds only transfers leads with what is due, never with an empty total.
  const transfersOnly = data.total.length === 0 && !!data.transfer_count
  const headline = transfersOnly ? transferWord(data.transfer_count ?? 0) : data.total_text
  return shell(
    'next payment',
    `<div class="panel">
  <p class="eyebrow">NEXT PAYMENT</p>
  <p style="font-size: var(--lb-type-stat-number-size); font-weight: var(--lb-type-stat-number-weight)" class="amount">${esc(headline)}</p>
  <p class="note" style="margin-bottom: var(--lb-space-s2)">${esc(data.due)} · ${esc(data.date)}</p>
  ${transfersLine(data, !transfersOnly)}
  ${rows}
</div>`,
  )
}

export function upcomingStrip(data: UpcomingData): string {
  const shown = data.charges.slice(0, FOLD)
  const rows = shown.map(chargeLine).join('')
  const total = data.total.length ? ` · ${esc(data.total_text)}` : ''
  // The count handed over lists transfers too; the payments are the rest.
  const payments = data.count - (data.transfer_count ?? 0)
  return shell(
    'upcoming',
    `<div class="panel">
  <p class="eyebrow">NEXT ${data.window_days} DAYS</p>
  <p class="note" style="margin-bottom: var(--lb-space-s2)">${payments} payment${payments === 1 ? '' : 's'}${total}</p>
  ${transfersLine(data)}
  ${rows}
  ${foldNote(shown.length, data.charges.length)}
</div>`,
  )
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const monthWord = (iso: string) => MONTHS[Number(iso.slice(5, 7)) - 1] ?? iso

/** One bar per month per currency — real charges in their months, never smoothed. */
export function cashflowChart(data: CashflowData): string {
  const blocks = data.series
    .map(({ currency, months }) => {
      const peak = Math.max(...months.map((m) => m.total), 1)
      const barW = 18
      const gap = 6
      const height = 96
      const width = months.length * (barW + gap) - gap
      const bars = months
        .map((m, i) => {
          const h = Math.max(m.total > 0 ? 3 : 0, Math.round((m.total / peak) * height))
          return `<rect x="${i * (barW + gap)}" y="${height - h}" width="${barW}" height="${h}" rx="3" style="fill: var(--lb-chart-bar)"${m.planned ? ' opacity="0.45"' : ''}><title>${esc(`${monthWord(m.month)}: ${m.total_text}`)}</title></rect>`
        })
        .join('')
      const peakText = months.find((m) => m.total === peak)?.total_text ?? ''
      return `
  <p class="eyebrow">CASH FLOW · ${esc(currency)}</p>
  <p class="note" style="margin-bottom: var(--lb-space-s2)">Peak month ${esc(peakText)} — solid is the record, faded is the plan as written</p>
  <svg viewBox="0 0 ${width} ${height}" width="100%" height="${height}" role="img" aria-label="monthly cash flow in ${esc(currency)}">${bars}</svg>
  <div style="display: flex; justify-content: space-between" class="note">
    <span>${esc(monthWord(months[0]?.month ?? ''))}</span><span>${esc(monthWord(months[months.length - 1]?.month ?? ''))}</span>
  </div>`
    })
    .join('<div style="height: var(--lb-space-s4)"></div>')
  return shell(
    'cash flow',
    `<div class="panel">${blocks}
  <p class="note" style="margin-top: var(--lb-space-s3)">${esc(data.note)}</p>
</div>`,
  )
}

const commitmentLine = (c: CommitmentRow) => {
  const state = c.status !== 'active' ? c.status : ''
  return `
<div class="row">
  <span class="name">${esc(c.name)}</span>
  ${flag(c.direction)}
  ${state ? `<span class="paid">${esc(state)}</span>` : ''}
  <span class="when">${esc(c.cycle)}${c.next_charge ? ` · ${esc(c.next_charge.due)}` : ''}</span>
  <span class="spacer"></span>
  <span class="money amount">${esc(c.amount_text)}</span>
</div>`
}

export function commitmentsList(data: CommitmentsData): string {
  const shown = data.commitments.slice(0, FOLD)
  return shell(
    'commitments',
    `<div class="panel">
  <p class="eyebrow">COMMITMENTS</p>
  <p class="note" style="margin-bottom: var(--lb-space-s2)">${data.count} in the memory</p>
  ${shown.map(commitmentLine).join('')}
  ${foldNote(shown.length, data.commitments.length)}
</div>`,
  )
}
