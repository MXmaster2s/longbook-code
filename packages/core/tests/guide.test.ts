// The curriculum as chapters, and the revision line every contract file carries.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  CONTRACT_REVISION,
  LIBRARY_JSON,
  LLMS_TXT,
  PROMPTS,
  findPrompt,
  SCHEMA_JSON,
  contractRevisionOf,
  guideSection,
  guideSections,
  guideSlug,
} from '../src/index'

test('all three contract files name the same revision; an unmarked copy names none', () => {
  assert.equal(contractRevisionOf(LLMS_TXT), CONTRACT_REVISION)
  assert.equal(contractRevisionOf(SCHEMA_JSON), CONTRACT_REVISION)
  assert.equal(contractRevisionOf(LIBRARY_JSON), CONTRACT_REVISION)
  assert.equal(contractRevisionOf('Hello. If you are an AI reading this…'), null)
})

test('chapter ids come from the heading before its dash, without a leading "the"', () => {
  assert.equal(guideSlug('The working method'), 'working-method')
  assert.equal(guideSlug('Importing statements — the method, with examples'), 'importing-statements')
  assert.equal(guideSlug('Two ways in: the tools, or the file'), 'two-ways-in')
})

test('the bundled guide splits into the chapters the tools promise, each whole', () => {
  const ids = guideSections(LLMS_TXT).map((s) => s.id)
  for (const must of ['importing-statements', 'reading-reports', 'unattended-runs', 'tags', 'documents-folder']) {
    assert.ok(ids.includes(must), `missing chapter ${must}`)
  }
  assert.equal(new Set(ids).size, ids.length, 'chapter ids are unique')
  const importing = guideSection(LLMS_TXT, 'importing-statements')!
  assert.match(importing.text, /^## Importing statements/)
  assert.match(importing.text, /NETFLIX\.COM/)
  assert.doesNotMatch(importing.text, /## How the numbers/)
})

test('a word from a title finds its chapter; nothing matches nothing', () => {
  assert.equal(guideSection(LLMS_TXT, 'import')?.id, 'importing-statements')
  assert.equal(guideSection(LLMS_TXT, 'reports')?.id, 'reading-reports')
  assert.equal(guideSection(LLMS_TXT, 'Unattended')?.id, 'unattended-runs')
  assert.equal(guideSection(LLMS_TXT, 'astrology'), null)
})

test("the app's phrases find their chapters whole, month name and all", () => {
  // Four phrases contain their chapter's id; the email phrase names none and is tabled.
  assert.equal(guideSection(LLMS_TXT, 'Categorise my longbook')?.id, 'categorise-my-longbook')
  assert.equal(guideSection(LLMS_TXT, 'Add September month report in my longbook')?.id, 'month-report')
  assert.equal(guideSection(LLMS_TXT, 'Create a report in my longbook')?.id, 'create-a-report')
  assert.equal(guideSection(LLMS_TXT, 'Add document invoices in my longbook')?.id, 'document-invoices')
  assert.equal(guideSection(LLMS_TXT, 'Add email invoices in my longbook')?.id, 'daily-email-round')
  const round = guideSection(LLMS_TXT, 'daily-email-round')!.text.replace(/\s+/g, ' ')
  assert.match(round, /\*\*One month, on request\.\*\* "Add email invoices in my longbook"/)
  // The search step is 2, so a month on request runs from it, never from step 3.
  assert.match(round, /`whoami`, then steps 2 to 7 of "Each run", with the search window the month's first day to today/)
  assert.doesNotMatch(round, /from step 3/)
})

test("the onboarding's phrase for the owner's AI finds the first-run chapter", () => {
  for (const phrase of ['Set up my longbook', 'setup my longbook']) {
    assert.equal(guideSection(LLMS_TXT, phrase)?.id, 'first-run', phrase)
  }
})

test("a prompt's words find the chapter it builds on: a phrase, an alias, a month, an id; a stranger finds none", () => {
  assert.equal(guideSection(LLMS_TXT, 'Find subscriptions from my email and add them in my longbook')?.id, 'daily-email-round')
  assert.equal(guideSection(LLMS_TXT, 'Read the bank statement and add it as charges and reports in my longbook')?.id, 'importing-statements')
  assert.equal(guideSection(LLMS_TXT, 'Add October month report in my longbook')?.id, 'month-report')
  assert.equal(guideSection(LLMS_TXT, 'set-up-a-morning-brief')?.id, 'unattended-runs')
  assert.equal(guideSection(LLMS_TXT, 'Tidy my longbook')?.id, 'working-method')
  assert.equal(guideSection(LLMS_TXT, 'Find horoscopes from my email'), null)
  // A chapter's own id still names that chapter, never a prompt's.
  assert.equal(guideSection(LLMS_TXT, 'prompts')?.id, 'prompts')
})

test('every word of every prompt with a chapter reaches that chapter in the bundled guide', () => {
  const ids = new Set(guideSections(LLMS_TXT).map((s) => s.id))
  for (const prompt of PROMPTS.filter((p) => p.chapter)) {
    assert.ok(ids.has(prompt.chapter!), `${prompt.id}: no chapter ${prompt.chapter}`)
    const words = [prompt.id, prompt.title, ...prompt.phrases, ...(prompt.aliases ?? [])]
    if (prompt.template) words.push(prompt.template.replace('{month}', 'March'))
    for (const w of words) assert.equal(guideSection(LLMS_TXT, w)?.id, prompt.chapter, `${prompt.id}: "${w}"`)
  }
})

test("the owner's own words for an import find the importing chapter, and the closing balance is a step of it", () => {
  for (const phrase of ['add my statement', 'Add my statements', 'import my statement', 'Import my statements', 'update my longbook from my statements']) {
    assert.equal(guideSection(LLMS_TXT, phrase)?.id, 'importing-statements', phrase)
  }
  // The sample summary is a blockquote: its line markers go so a sentence can be matched whole.
  const flat = (id: string) => guideSection(LLMS_TXT, id)!.text.replace(/^> /gm, '').replace(/\s+/g, ' ')
  const importing = flat('importing-statements')
  assert.match(importing, /"Update my longbook from my statements" or "Add September month report in my longbook"/)
  assert.match(importing, /then, when the statement prints a closing balance, one `update_account` on the statement's account — `balance` the closing figure, `balance_date` the statement's last day — so the account reads as the statement left it;/)
  assert.match(importing, /what you skipped and why, and the balance you set with its day — or that the statement printed none\./)
  assert.match(importing, /HDFC savings now stands at ₹1,23,456 as of 30 June, the statement's closing balance\. Review it in the Changes screen/)
  assert.match(flat('working-method'), /A statement's closing balance is its account's `balance`, dated the statement's last day: set it with `update_account` after the statement's charges are written — the app's own importer does the same — and skip it only when the statement prints none\./)
  assert.match(flat('month-report'), /Each statement's closing balance goes on its account — `update_account` with `balance` and `balance_date` the statement's last day — so the Accounts module shows the month's end rather than an older day; skip it when the statement prints none\./)
  assert.match(LLMS_TXT.replace(/\s+/g, ' '), /write it after importing any statement that prints one, dated the statement's last day, and never compute anything from it; `accounts` and `whoami` say when the balance held is older than the newest confirmed charge on that account, and `add_commitments` and `add_charges` answer with a `balance_note` when the rows just written outrun it\./)
})

test('a card bill payment is told one way in both chapters, and a bill row names its month', () => {
  const flat = (id: string) => guideSection(LLMS_TXT, id)!.text.replace(/\s+/g, ' ')
  const importing = flat('importing-statements')
  // Skipped as a movement — unless the memory holds that bill as a transfer row to settle.
  assert.equal((importing.match(/unless the memory holds that bill as a transfer row/g) ?? []).length, 2, 'step 1 and the tree')
  assert.match(importing, /`add_charges` on it, paid, basis "statement"/)
  assert.match(importing, /CREDIT CARD PAYMENT 42,310\.00 → skip \(the memory holds no bill row for it/)
  const round = flat('daily-email-round')
  assert.match(round, /"<Card> bill, <month> <year>"/)
  assert.match(round, /"Coral card bill, October 2026"/)
  assert.match(round, /find it with `search`, and address it by id/)
})

test('the notes chapter gives every commitment tag its three, and says what the scan refuses', () => {
  const notes = guideSection(LLMS_TXT, 'notes')!.text
  // Each example line names its tags before the dash; every library commitment tag has one.
  const examples = notes.split('\n').filter((line) => line.startsWith('- ') && line.includes(' — '))
  const named = new Set(examples.flatMap((line) => line.slice(2, line.indexOf(' — ')).split(', ')))
  const library = JSON.parse(LIBRARY_JSON) as { tags: { kind: string; name: string }[] }
  for (const tag of library.tags.filter((t) => t.kind === 'commitment')) {
    assert.ok(named.has(tag.name), `no example line for ${tag.name}`)
  }
  assert.ok(examples.includes('- travel — Destination; Dates; Booked through'))
  assert.ok(examples.includes('- home — Kind; Vendor; Invoice, the file name in `documents/`'))
  assert.equal(examples.at(-1), '- any other tag — the three the owner would look for first')
  // "Since" is the product's word for the earliest row; a salary's start is "Started".
  assert.ok(examples.includes('- salary — Role; Paid by (UPI, cash, bank transfer); Started'))

  const flat = notes.replace(/\s+/g, ' ')
  assert.match(flat, /A number of 13 to 19 digits can read as a card number and be refused: write its last four digits, and name the document that holds it in full\./)
  assert.match(flat, /Dates in notes are written YYYY-MM-DD/)
  assert.doesNotMatch(SCHEMA_JSON, /Longbook's library/)
  assert.match(SCHEMA_JSON, /Seeded entries come from longbook's library/)
})

test('the guide says what longbook keeps of a tag, what an account holds, and what a write refuses', () => {
  const flat = LLMS_TXT.replace(/\s+/g, ' ')
  assert.match(flat, /longbook keeps only tag structures — each tag's kind, name and icon, never a name, amount, date, or note —/)
  assert.doesNotMatch(flat, /their templates/)
  const rule = guideSection(LLMS_TXT, 'data-minimization-rule')!.text.replace(/\s+/g, ' ')
  assert.match(rule, /For an account, write only: .*, a tag \(credit card \/ bank account \/ UPI \/ wallet \/ cash…\), and its notes\./)
  assert.match(flat, /`update_account` and `update_person` refuse a non-empty `card_name` or `details` by name/)
  assert.match(SCHEMA_JSON, /never write it — a write sending a non-empty card_name or details is refused\./)
  assert.match(SCHEMA_JSON, /never write it — a write sending non-empty details is refused\./)
})

test('the curriculum teaches only what exists and keeps its load-bearing rules', () => {
  assert.match(LLMS_TXT, /documents\//)
  assert.doesNotMatch(LLMS_TXT, /paperwork\//)
  assert.doesNotMatch(LLMS_TXT, /self-contained HTML/)
  // Every charge is a row: a cancelled commitment keeps what happened, and nothing is computed.
  assert.match(LLMS_TXT, /keeps every charge that\s+happened/)
  assert.match(LLMS_TXT, /nothing is computed|Nothing is computed/)
  assert.doesNotMatch(LLMS_TXT, /started_on|next_due_date|payment_records/)
  assert.match(LLMS_TXT, /read_guide/)
  // The hosted door writes now, as proposals — the curriculum must not still call it read-only.
  assert.doesNotMatch(LLMS_TXT, /read-only in this revision/)
  assert.match(LLMS_TXT, /memory:propose/)
  assert.match(LLMS_TXT, /idempotency_key/)
  assert.match(LLMS_TXT, /whoami/)
})

test('owner words that start with a prompt, or fill its slot, still find it', () => {
  assert.equal(findPrompt('Add my statement — the folder is iCloud Drive at ~/longbook')?.id, 'add-my-statement')
  assert.equal(findPrompt('Update my longbook from my statements through the longbook connector.')?.id, 'add-my-statement')
  assert.equal(findPrompt('Make a report of my Bali trip')?.id, 'make-a-report-of-my-trip')
  assert.equal(findPrompt('Set yourself up for a daily longbook email round')?.id, 'set-up-a-daily-longbook-email-round')
  assert.equal(findPrompt('importing-statements'), null, 'a chapter id is not a prompt')
})

test('a prompt that names a month never names one in its procedure', () => {
  const months = /\b(January|February|March|April|May|June|July|August|September|October|November|December)\b/
  for (const p of PROMPTS.filter((x) => x.template)) {
    for (const line of p.procedure) assert.doesNotMatch(line, months, `${p.id}: ${line}`)
  }
})
