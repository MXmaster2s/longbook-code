// What a correct import concludes from the fixture statements — the judgement the agent
// run applies, kept here so a test can prove the checks are not vacuous. Facts, not
// routes: an agent may reach them any way it likes.
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const CONTRACT = join(import.meta.dirname, '../../core/contract')

// ---------------------------------------------------------------------------------------------
// The judgement: facts the statements support, whatever route the agent took.

export interface Check {
  what: string
  ok: (vault: any) => boolean
}

export const rows = (vault: any): any[] => vault.commitments ?? []
const charges = (vault: any): any[] => vault.charges ?? []
const named = (vault: any, pattern: RegExp): any[] => rows(vault).filter((row) => pattern.test(String(row.name)))
const chargesOf = (vault: any, row: any): any[] => charges(vault).filter((c) => c.commitment_id === row.id)

export const CHECKS: Check[] = [
  { what: 'the file still parses as a longbook memory', ok: (v) => v.app === 'longbook' && v.version === 3 },
  { what: 'a year of statements produced more than ten rows', ok: (v) => rows(v).length > 10 },
  {
    what: 'every commitment has at least one charge — a row with none is a name without a fact',
    ok: (v) => rows(v).every((row) => chargesOf(v, row).length >= 1),
  },
  {
    what: 'the monthly rhythms are monthly: rent, the cook, the phone plan, Netflix, society dues',
    ok: (v) =>
      [/rent/i, /sunita|cook/i, /airtel/i, /netflix/i, /society|maintenance|greenwood/i].every((pattern) =>
        named(v, pattern).some((row) => row.billing_cycle === 'monthly'),
      ),
  },
  {
    what: 'every monthly row carries its history: a paid charge in the months the statement covered',
    ok: (v) =>
      rows(v)
        .filter((row) => row.billing_cycle === 'monthly' && !row.ends_on)
        .every((row) => chargesOf(v, row).some((c) => c.paid && c.basis === 'statement' && c.date < '2026-09-01')),
  },
  {
    what: 'what the statement proved is proved, and what is only planned says so',
    ok: (v) =>
      charges(v).every((c) => (c.date <= '2026-08-31' ? c.paid && c.basis === 'statement' : !c.paid && c.basis === 'plan')),
  },
  {
    what: 'the yearly premiums are yearly, charged in the month the statement showed them',
    ok: (v) =>
      named(v, /ergo|health premium/i).some((row) => row.billing_cycle === 'yearly' && chargesOf(v, row).some((c) => String(c.date).startsWith('2026-03'))) &&
      named(v, /lic|term/i).some((row) => row.billing_cycle === 'yearly' && chargesOf(v, row).some((c) => String(c.date).startsWith('2026-05'))),
  },
  {
    what: 'the half-yearly premium is a custom cycle of roughly six months',
    ok: (v) =>
      named(v, /star health/i).some(
        (row) => row.billing_cycle === 'custom' && Number(row.custom_cycle_days) >= 175 && Number(row.custom_cycle_days) <= 190,
      ),
  },
  {
    what: 'the repeat that ended did not become an active monthly row with a plan ahead',
    ok: (v) => !named(v, /spotify/i).some((row) => row.billing_cycle === 'monthly' && row.status === 'active' && !row.ends_on && chargesOf(v, row).some((c) => !c.paid)),
  },
  {
    what: 'the money it spent is still in the file: Spotify appears as charges, not as nothing',
    ok: (v) => named(v, /spotify/i).some((row) => chargesOf(v, row).length >= 6),
  },
  {
    what: 'one-time spends are once, with one charge at their real dates',
    ok: (v) =>
      named(v, /irctc/i).some((row) => row.billing_cycle === 'once' && chargesOf(v, row).map((c) => c.date).join() === '2026-06-10') &&
      named(v, /tanishq/i).some((row) => row.billing_cycle === 'once'),
  },
  {
    what: 'money in was written apart: every salary credit row carries direction "in", and no ATM or card-payment row exists',
    ok: (v) => {
      const credits = named(v, /salary credit|vertex/i)
      return credits.length > 0 && credits.every((row) => row.direction === 'in') && named(v, /atm|card payment/i).length === 0
    },
  },
  {
    what: 'no amount was invented: every amount on every charge appears in the statements',
    ok: (v) => {
      const seen = new Set(
        [42000, 9000, 899, 649, 3500, 119, 18450, 24600, 9200, 4560, 1240, 32000, 1699, 179, 640, 3597, 1760, 20, 214000],
      )
      return rows(v).every((row) => seen.has(Number(row.amount))) && charges(v).every((c) => seen.has(Number(c.amount)))
    },
  },
  {
    what: 'tags come from the library, not from imagination',
    ok: (v) => {
      const library = new Set(
        (JSON.parse(readFileSync(join(CONTRACT, 'library.json'), 'utf8')).tags as any[])
          .filter((tag) => tag.kind === 'commitment')
          .map((tag) => tag.name_key),
      )
      const worn = rows(v)
        .map((row) => String(row.tag ?? '').trim().toLowerCase())
        .filter(Boolean)
      const declared = new Set(((v.tags ?? []) as any[]).map((tag) => String(tag.name_key)))
      return worn.every((tag) => library.has(tag) || declared.has(tag))
    },
  },
  {
    what: 'no member was invented — the statements name no one the owner named',
    ok: (v) => (v.members ?? []).length <= 1,
  },
  {
    what: 'every row it wrote is signed, so the owner can see whose work it was',
    ok: (v) => {
      const provenance = v._provenance ?? {}
      return rows(v).every((row) => provenance[row.id]?.edited_by)
    },
  },
  {
    what: 'nothing that must never be stored got in',
    ok: (v) => !/\b(?:\d[ -]?){12,18}\d\b/.test(JSON.stringify(v)),
  },
]
