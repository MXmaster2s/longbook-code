#!/usr/bin/env -S npx tsx
// Converts one format-2 vault to format 3, once: every occurrence the old rule computed is
// written down as a row. Dev tooling; nothing ships with it.
// Run: npm run vault:convert -- <folder> [--dry-run]
//
// The walk below is the format-2 engine, kept whole so the conversion is exact.
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { parseDate, toISO, todayMid, daysBetween, addMonthsClamped } from '@longbook/core'

const DAY_MS = 86400000
const PLAN_MONTHS = 24

type Raw = Record<string, any>

const folder = process.argv.slice(2).find((a) => !a.startsWith('--'))
const dryRun = process.argv.includes('--dry-run')
if (!folder) {
  console.error('Usage: npm run vault:convert -- <vault folder> [--dry-run]')
  process.exit(1)
}
const file = join(folder, 'financial_memory.json')
const copy = join(folder, 'financial_memory.v2.json')
if (!existsSync(file)) {
  console.error(`No financial_memory.json in ${folder}`)
  process.exit(1)
}
const text = readFileSync(file, 'utf8')
const vault = JSON.parse(text) as Raw
if (vault.app !== 'longbook') {
  console.error('Not a longbook financial memory.')
  process.exit(1)
}
if (vault.version !== 2) {
  console.error(`This file is format ${String(vault.version)}; only format 2 converts.`)
  process.exit(1)
}

// ---- the format-2 walk, verbatim in behaviour ------------------------------------------

function effectiveNext(sub: Raw, today: Date): { date: Date; isTrial: boolean } {
  let anchor: Date
  if (sub.has_trial && sub.trial_end_date) {
    const te = parseDate(sub.trial_end_date)
    if (te.getTime() >= today.getTime()) return { date: te, isTrial: true }
    anchor = te
  } else {
    anchor = parseDate(sub.next_due_date)
  }
  if (sub.billing_cycle === 'once') return { date: anchor, isTrial: false }
  if (anchor.getTime() >= today.getTime()) return { date: anchor, isTrial: false }
  if (sub.billing_cycle === 'custom') {
    const days = Math.max(1, sub.custom_cycle_days || 30)
    const k = Math.max(1, Math.ceil(daysBetween(anchor, today) / days))
    let cand = new Date(anchor.getTime() + k * days * DAY_MS)
    while (cand.getTime() < today.getTime()) cand = new Date(cand.getTime() + days * DAY_MS)
    return { date: cand, isTrial: false }
  }
  const step = sub.billing_cycle === 'yearly' ? 12 : 1
  for (let k = 1; k < 100000; k++) {
    const c = addMonthsClamped(anchor, k * step)
    if (c.getTime() >= today.getTime()) return { date: c, isTrial: false }
  }
  return { date: anchor, isTrial: false }
}

function stepFrom(sub: Raw, anchor: Date, k: number): Date {
  if (k === 0) return anchor
  if (sub.billing_cycle === 'custom') return new Date(anchor.getTime() + k * Math.max(1, sub.custom_cycle_days || 30) * DAY_MS)
  return addMonthsClamped(anchor, k * (sub.billing_cycle === 'yearly' ? 12 : 1))
}

interface Occurrence {
  date: string
  amount: number
  record: Raw | null
}

function occurrences(sub: Raw, records: Raw[], today: Date, to: Date): Occurrence[] {
  const lapsed = sub.ends_on && daysBetween(today, parseDate(sub.ends_on)) < 0
  const status = sub.status === 'active' && lapsed ? 'cancelled' : sub.status
  // A cancelled or paused commitment computed nothing in format 2 — but its records are
  // facts, and those are carried whatever the status.
  const mine = records.filter((r) => r.commitment_id === sub.id)
  const byDate = new Map(mine.map((r) => [String(r.date), r]))
  if (status !== 'active') {
    return mine.map((r) => ({ date: String(r.date), amount: recordAmount(r, sub) ?? (Number(sub.amount) || 0), record: r }))
  }
  const nx = effectiveNext(sub, today)
  const anchor = nx.isTrial ? (sub.trial_end_date ? parseDate(sub.trial_end_date) : null) : nx.date
  if (!anchor) return []
  const amount = Number(sub.amount) || 0
  const steps = ((sub.amounts ?? []) as Raw[])
    .map((s) => ({ t: parseDate(String(s.from)).getTime(), amount: Number(s.amount) || 0 }))
    .filter((s) => Number.isFinite(s.t))
    .sort((a, b) => a.t - b.t)
  const priceOn = (t: number): number => {
    if (!steps.length) return amount
    let price = steps[0]!.amount
    for (const step of steps) if (step.t <= t) price = step.amount
    return price
  }
  const cancel = sub.ends_on ? parseDate(sub.ends_on) : null
  const start = sub.started_on ? parseDate(sub.started_on) : null
  const trialEnd = sub.has_trial && sub.trial_end_date ? parseDate(sub.trial_end_date) : null
  const bounded = Math.max(start?.getTime() ?? -Infinity, trialEnd?.getTime() ?? -Infinity)
  let floor = Number.isFinite(bounded) ? bounded : today.getTime()
  for (const r of mine) {
    const t = parseDate(String(r.date)).getTime()
    if (Number.isFinite(t) && t < floor) floor = t
  }
  if (steps.length && steps[0]!.t < floor) floor = steps[0]!.t
  const lo = addMonthsClamped(today, -240).getTime()
  const hi = Math.min(to.getTime(), addMonthsClamped(today, 240).getTime())

  // A record is evidence and the walk was the guess. A record on the walked day is that
  // occurrence's; one within half a cycle of it, with no exact match, is the same charge
  // paid on another day — the fact is kept, the projection is not written beside it.
  const halfCycle = sub.billing_cycle === 'yearly' ? 182 : sub.billing_cycle === 'custom' ? Math.max(1, sub.custom_cycle_days || 30) / 2 : 15
  const unclaimed = new Set(mine.map((r) => String(r.date)))
  const out: Occurrence[] = []
  const take = (date: Date, floored = true) => {
    const t = date.getTime()
    if (floored && t < floor) return
    if (cancel && t > cancel.getTime()) return
    if (t < lo || t > hi) return
    const iso = toISO(date)
    let record = byDate.get(iso) ?? null
    if (!record) {
      const near = mine.find((r) => unclaimed.has(String(r.date)) && Math.abs(daysBetween(date, parseDate(String(r.date)))) <= halfCycle)
      if (near) {
        unclaimed.delete(String(near.date))
        out.push({ date: String(near.date), amount: recordAmount(near, sub) ?? priceOn(t), record: near })
        return
      }
    } else {
      unclaimed.delete(iso)
    }
    out.push({ date: iso, amount: (record && recordAmount(record, sub)) ?? priceOn(t), record })
  }
  if (sub.billing_cycle === 'once') {
    take(anchor, false)
  } else {
    for (let k = 0; k < 4000; k++) {
      const date = stepFrom(sub, anchor, k)
      if (date.getTime() > hi) break
      take(date)
    }
    for (let k = -1; k > -4000; k--) {
      const date = stepFrom(sub, anchor, k)
      if (date.getTime() < lo || date.getTime() < floor) break
      take(date)
    }
  }
  // A record on a day the walk never reached is still a fact.
  for (const r of mine) {
    if (unclaimed.has(String(r.date))) out.push({ date: String(r.date), amount: recordAmount(r, sub) ?? amount, record: r })
  }
  return out.sort((a, b) => a.date.localeCompare(b.date))
}

function recordAmount(record: Raw, sub: Raw): number | null {
  if (typeof record.amount !== 'number' || !Number.isFinite(record.amount)) return null
  if (record.currency && record.currency !== sub.currency) return null
  return record.amount
}

// ---- the conversion ------------------------------------------------------------------------

const today = todayMid()
const horizon = addMonthsClamped(today, PLAN_MONTHS)
const records = (vault.payment_records ?? []) as Raw[]
const commitments = (vault.commitments ?? []) as Raw[]
const charges: Raw[] = []
let facts = 0
let plans = 0

for (const sub of commitments) {
  for (const o of occurrences(sub, records, today, horizon)) {
    const row: Raw = { commitment_id: sub.id, date: o.date, amount: o.amount, paid: o.record !== null }
    if (o.record) {
      if (o.record.currency && o.record.currency !== sub.currency) { row.currency = o.record.currency; row.amount = o.record.amount }
      if (o.record.paid_on) row.paid_on = o.record.paid_on
      row.basis = o.record.basis ?? 'mark_paid'
      if (o.record.paid_at) row.written_at = o.record.paid_at
      facts += 1
    } else {
      row.basis = 'plan'
      plans += 1
    }
    charges.push(row)
  }
  for (const key of ['next_due_date', 'started_on', 'has_trial', 'trial_end_date', 'trial_kept', 'amounts']) delete sub[key]
}

const converted: Raw = { ...vault, version: 3, commitments, charges }
delete converted.payment_records

// The proof: totals per currency over the last and next twelve months read the same from
// the rows as the old walk gave — by construction, and printed so nobody has to trust it.
const window = (from: Date, to: Date) => {
  const totals = new Map<string, number>()
  for (const row of charges) {
    const t = parseDate(row.date).getTime()
    if (t < from.getTime() || t > to.getTime()) continue
    const sub = commitments.find((s) => s.id === row.commitment_id)!
    const cur = row.currency ?? sub.currency
    totals.set(cur, (totals.get(cur) ?? 0) + row.amount)
  }
  return [...totals].map(([c, a]) => `${c} ${a.toLocaleString('en-IN')}`).join(', ') || 'nothing'
}
console.log(`${commitments.length} commitments → ${charges.length} charges (${facts} from records, ${plans} planned to ${toISO(horizon)})`)
console.log(`last 12 months: ${window(addMonthsClamped(today, -12), new Date(today.getTime() - DAY_MS))}`)
console.log(`next 12 months: ${window(today, addMonthsClamped(today, 12))}`)
const bytes = JSON.stringify(sortKeys(converted), null, 2) + '\n'
console.log(`file: ${(text.length / 1024).toFixed(0)} KB → ${(bytes.length / 1024).toFixed(0)} KB`)

if (dryRun) {
  console.log('dry run — nothing written.')
  process.exit(0)
}
if (!existsSync(copy)) writeFileSync(copy, text)
writeFileSync(file, bytes)
console.log(`written: ${file}\ncopy of the format-2 file: ${copy}`)

function sortKeys(value: any): any {
  if (Array.isArray(value)) return value.map(sortKeys)
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((k) => [k, sortKeys(value[k])]))
  }
  return value
}
