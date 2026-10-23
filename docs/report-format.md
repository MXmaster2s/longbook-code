# The report format (v2)

The same format, in the words an AI actually reads, is in the vault's `llms.txt`
("Reading reports"). This page is the developer's reference; the two describe one format.

A report is a JSON file in the vault's `reports/` folder. **longbook draws every one**: one
per calendar month holding a confirmed charge, named for that month (`july-2026.json`),
subtitle "Drawn by longbook", redrawn when the month's rows change; a trip the owner adds in
the app; and a span an AI asks for with the `create_report` MCP tool. An AI reads a report
with the `reports` tool, and changes the rows behind it when the owner wants the report to
say something different — it never writes a report file.

A report is defined by six things: a **name** (`title`), the **days** it covers (`start_date`,
`end_date`), the **accounts**, **members** and **categories** it was narrowed to (`scope`), and
its **sharing**, which lives beside the file in the workspace sidecar. A calendar month is the
draw the app makes on its own; any other span of days with a scope — a trip, one member's
quarter — is drawn by `MonthlyReport.draw(vault:id:title:from:to:scope:currency:)` on the same
terms and has the same shape (see "Spans" below).

**Version 1 files still read.** They name only `period`; their days are derived from it, their
scope is everything, and their labels are the old ones ("Total for July", "Confirmed in
August", "1 of 3"). The app redraws its own files at version 2 the next time the Reports
screen opens.

## Confirmed charges, and nothing else

One rule decides both which months are drawn and what each report counts:
`MonthlyReport.confirmed(_:_:)` keeps a charge dated today or earlier whose `basis` is
anything but `"plan"` — a statement, a mail, the owner's own word, the app's paid-tap. A row
with no `basis` at all reads as `"plan"`, as it does everywhere else in the ledger.

`months(in:today:)` returns the first of every month holding at least one such charge. So a
month of projection alone draws nothing, the month ahead never draws, and a transfer draws
nothing: a card bill on its own is not a month to report on. No statement is required — a
month the owner typed by hand draws its report like any other.

`build(vault:month:currency:today:)` then counts confirmed charges **in every figure**: the
total, the `Charges` count, `Money in`, both rings, the transactions list, and the prior
month behind `delta_pct`. The two must not diverge — a month that qualified on one confirmed
row and then reported the whole month's projections would publish money that never moved,
which is what the honesty rules below forbid.

## A part-covered month says so

A month is **part-covered** when at least one of its charges in the report's own currency has
passed (`date <= today`) and is not confirmed. `MonthlyReport.coverage(_:first:currency:today:)`
returns the passed set, the confirmed subset, and that flag. A part-covered month is drawn — it
holds real money — but it is labelled, because a figure short of the month's own rows read as
the month's total is a false statement about the month even when every number under it is true.

| | whole month | part-covered |
|---|---|---|
| `Total expenses` stat | the total | the total of what is confirmed |
| `Charges` `value` | `2` | `1` |
| `Not yet confirmed` stat | absent | `1` — passed charges nobody has confirmed |

The extra stat stands beside the total, so a reader who looks at the big number sees the
count of what is missing next to it. The labels are `MonthlyReport.Labels`; a screen reads
each figure by its label.

**Coverage is measured in the report's scope currency**, as are the total, the label, the count
and both rings — the whole stats module describes one currency, which is the currency its money
stats declare. Only the transactions list is cross-currency: it is the record, and each row
carries its own `currency`. So a report's `Charges` count can be smaller than the number of
rows listed beneath it in a multi-currency month, and an unconfirmed dollar row does not make a
rupee report part-covered. The dollar month is its own report with its own coverage.

### When `delta_pct` is absent

`delta_pct` and `delta_is_good` are drawn only when a change can be stated honestly, which
means **all** of: the month is over, neither it nor the month before is part-covered, and the
month before holds confirmed spending in this currency. Three distinct reasons for absence,
and a reader must not distinguish between them:

1. **The month is not over** (`last < today` in `build`). The current month's figures cover its
   passed days only, so comparing them with a whole prior month reports the calendar as a fall
   — five days of September against the whole of August is −98.5%, flagged as good news. The
   month gets its change on the first draw after it ends.
2. **Either month is part-covered** — missing evidence would read as thrift.
3. **`priorTotal` is zero** — the vault's earliest month, or a prior month whose spending was
   all in another currency. Nothing to compare with, which is not nothing having been spent.

Since `delta_pct` was already optional, its absence has one meaning across all three:
longbook would not say. It never means the month before was empty.

**What the flag does not cover.** `Money in` sits outside it, because income is not in the
`Charges` count: a month whose salary row is still `plan` omits `Money in` silently. And a
running month with all its passed days confirmed carries no `Not yet confirmed` stat, yet its
`Total expenses` is the month **so far** — `end_date` against `created_at` is what tells a
reader which; the absent `delta_pct` is the other signal that the month is not finished.

**The divergence with the dashboard is deliberate.** The dashboard and the MCP spending tools
count a past row whatever its basis (`Charge.paid` is `row.paid || date < today`), so the same
month can read higher there than in its report. A live view may estimate; a document that can
be shared may not. The `Not yet confirmed` stat is what explains that gap to a reader who
notices it.

The format follows the vault's own conventions (see
[vault-format.md](vault-format.md)): snake_case keys, dates are ISO `YYYY-MM-DD` calendar
days, and an amount is always a number **with** its currency code — never a bare figure,
never a blend across currencies.

A renderer must tolerate what it doesn't know: an unknown module `type` still shows its
data — the fields render generically inside longbook's design. Older files in a vault may
hold module types no draw produces any more, and they still read.

## Envelope

```json
{
  "version": 2,
  "id": "july-2026",
  "title": "July 2026",
  "subtitle": "Drawn by longbook",
  "start_date": "2026-07-01",
  "end_date": "2026-07-31",
  "period": "2026-07",
  "scope": { "accounts": ["Amex 1007"], "members": [], "categories": [] },
  "hidden_ids": [],
  "created_at": "2026-08-07",
  "currency": "INR",
  "modules": []
}
```

- `version` (int, required) — format version; this document describes 2.
- `id` (string, required) — stable identity, unique within the vault; it is the filename.
  A month is written as `<month>-<year>`, so the folder reads as a run of months; a trip as
  `trip-<slug(title)>-<start ISO>` and a span asked for with `create_report` as
  `report-<slug(title)>-<start ISO>` (see "Spans").
- `title` (string, required) — the report's name: the month ("July 2026") or what the owner
  called it ("Goa"). `subtitle` (optional) — `"Drawn by longbook"` marks a report as the
  app's own, so a later draw may replace it. Neither is shown as a subtitle on screen.
- `start_date`, `end_date` (ISO days, optional) — the first and last day covered. The
  screen names them "1 October 2026" (a single day, never "1–1 October 2026"), "1–31 July
  2026", "28 September – 3 October 2026" or "30 December 2025 – 2 January 2026".
- `period` (`YYYY-MM`, optional) — set only when the report is one calendar month.
- `scope` (optional) — the `accounts`, `members` and `categories` names the report was
  narrowed to. A list left out or empty narrows nothing; a report over everything omits it.
  The lists intersect: a charge is in the report when it matches the accounts AND the
  members AND the categories. The account name "No account" matches charges billed to no
  account, and the category "No category" matches untagged charges.
- `hidden_ids` (optional) — charge ids the owner dropped for good: in no figure, on no list.
- `created_at` (ISO day, optional) — the day the file was written. Not the days covered.
- `currency` (optional) — default scope for modules that don't declare their own.

## Months

A month report covers one calendar month, and each file is named for its month —
`july-2026.json`, `june-2026.json`. The displayed form is the long month, "July 2026".

`period` is optional because reports written before the field exist and stay valid. Where a
file names no days of its own, its month is derived, in this order:

1. `period`, when present and well-formed;
2. else, when the report has a transactions module and every dated row in it falls inside
   one calendar month, that month;
3. else nothing — and where nothing is known, the app states the authoring date as the
   authoring date. It is never presented as the period.

## Spans: trips and requested reports

A span report is drawn by longbook (subtitle "Drawn by longbook") over its own `start_date`
and `end_date`, with no `period`. Two kinds exist, and the file format is the same for both:

- **A trip** — added in the app under Settings → Trips. Its id is
  `trip-<slug(title)>-<start ISO>`, e.g. `trip-goa-2026-09-28`. A trip still running
  (started with "Start trip mode", not yet ended with "End trip") is named in the workspace
  sidecar, `longbook.workspace.json`, under `openTrip` (the report id); its `end_date`
  advances to today on each redraw until it ends.
- **A requested span** — asked for by an AI with `create_report`
  (`{title, start_date, end_date, accounts?, members?, categories?}`; no id, no currency). Its
  id is `report-<slug(title)>-<start ISO>`. The hosted door files it in `mcp_pending_writes`;
  the Mac's own server leaves it in the vault's `requests/` folder. The app draws it with the
  same code as a trip.

When another definition (other days or another scope) already holds an id, the new report
takes `-2`, then `-3`. The same title, days and scope asked again redraws the same file, so a
retried request is harmless. A span's `currency` is the currency most of its confirmed
charges are in, falling back to the home currency. Whenever the app redraws its months it
also redraws every span it drew, from the file's own title, days, scope, removed rows and
`hidden_ids`, carrying the comments across.

## List order

The Reports screen and the `reports` tool list reports in one order: by the report's last
covered day (`end_date`, else the last day of its month from `period` or its rows), newest
first; then `created_at`, newest first; then filename A→Z. A report with no known days lists
last.

## The modules a draw produces

Every module has a `type` (string, required) and may carry `id`, `title`, and `comment`.
A draw writes no `id` and no `comment`, so a module's position is its identity: a shared
report's comments come back keyed `module-<index>`, and merging finds the module that way.
`comment` is where the owner's own note and the lines pulled back from a shared link live.

A draw produces these, in this order. The stats and the charge list are always drawn. Both
rings are drawn from the report's own currency, so a month holding no charge in that currency
holds neither ring: a drawn report is one, two or four modules, never three.

### 1. Stats — "Total expenses"

```json
{ "type": "stats", "title": "Total expenses", "stats": [
  { "label": "Total expenses", "amount": 43849, "currency": "INR",
    "delta_pct": 9.6, "delta_is_good": false, "delta_label": "vs June" },
  { "label": "Charges", "value": "3" },
  { "label": "Money in", "amount": 150000, "currency": "INR" }
]}
```

A stat is money (`amount` + `currency`) or free text (`value`). `delta_pct` is the change
against the span the file names in `delta_label`; `delta_is_good` says which way is good
news. A rising spend and a rising income point the same way and mean opposite things, so the
file must say. "Money in" appears only when the month had any. `delta_pct` is absent for any
of the three reasons above — a draw omits it more often than it writes it.

Money in another currency is a further "Total expenses" stat in that currency, never blended
into the first; "Charges" counts every row the list holds, whatever its currency. The screen
draws the first money stat as the figure, the dashboard's way, any same-label sums beside it
("+$20"), then the change; every other stat reads as one line under it: "3 charges · Money in
₹1,50,000".

A part-covered month (above) draws the same module with one stat more:

```json
{ "type": "stats", "title": "Total expenses", "stats": [
  { "label": "Total expenses", "amount": 649, "currency": "INR" },
  { "label": "Charges", "value": "1" },
  { "label": "Not yet confirmed", "value": "1" }
]}
```

The module `title` stays "Total expenses"; screens match on it, and a renderer needs no
knowledge of coverage to draw the stats correctly.

### 2. Donut — "Accounts"

```json
{ "type": "donut", "title": "Accounts", "currency": "INR", "slices": [
  { "label": "Savings account", "amount": 42000, "currency": "INR" },
  { "label": "No account", "amount": 1200, "currency": "INR" }
]}
```

One slice per paying account, amount descending with the label as the tiebreak, uncapped.
A charge billed to no account becomes a slice labelled "No account". Drawn whenever there is
at least one slice, so a one-account month is a legitimate single-slice ring at 100%.

### 3. Donut — "Categories"

```json
{ "type": "donut", "title": "Categories", "currency": "INR", "slices": [
  { "label": "rent", "amount": 42000, "currency": "INR" },
  { "label": "No category", "amount": 1200, "currency": "INR" }
]}
```

The same shape over tags, on the same terms: one slice per tag, amount descending with the
label as the tiebreak, uncapped, and drawn whenever there is at least one slice. A charge with
no tag becomes a slice labelled "No category", so a month of untagged charges is a
single-slice ring at 100%. Capping the slices would label a partial sum "Total expenses".

**Casing.** A slice label is rendered with its first character uppercased and the rest
verbatim **only** when the module's `title` is exactly `"Categories"` — a tag is a word a
screen shows capitalised. Every other donut's labels, "Accounts" among them, are the owner's
own data and are rendered exactly as stored. The module heading is never re-cased. The app
and the shared-report viewer gate on that exact title, so the two surfaces agree.

**Currency.** Slices in the module's scope currency form the ring and its shares, computed
over the slices present. A slice in any other currency is listed beside the ring with its own
sum and no share; it never enters the ring. A *drawn* donut never exercises this — a draw
derives its slices from the scope currency alone — but a file written by hand or by an AI may,
and both renderers hold the rule.

**What takes a share.** Only a finite amount above zero. A negative, a text amount and a zero
keep their legend row and their colour, take no part of the total, and are shown with no
percentage — a slice that draws no arc cannot be a percent of the ring. Both renderers decide
the total, the arcs and the shares with that one rule, so no two of the three disagree.

**The gap.** Each arc is shaved by 0.004 of a turn and offset by half of that, so adjacent
arcs are parted and a single-slice ring reads as a ring rather than a closed disc.

### 4. Transactions — "All charges"

```json
{ "type": "transactions", "title": "All charges", "rows": [
  { "id": "rent-2026-07-01", "name": "House rent", "date": "2026-07-01", "amount": 42000,
    "currency": "INR", "category": "rent", "account": "HDFC savings", "member": "Rohit" },
  { "id": "shop-2026-07-09", "name": "Corner shop", "date": "2026-07-09", "amount": 1200,
    "currency": "INR" },
  { "id": "hotel-2026-07-12", "name": "Taj Holiday Village", "date": "2026-07-12", "amount": 18000,
    "currency": "INR", "category": "travel", "account": "Amex 1007", "removed": true }
]}
```

Every confirmed charge in the span, amount descending, uncapped; then the rows the owner took
out, marked `removed: true`, in the same order. The title stays "All charges" — "all" means
uncapped, not "including the plan". `id` is the charge as the vault names it (`<commitment
id>-<date>`), so a redraw keeps a removed row out; `category`, `account` and `member` are
omitted where the commitment has none. A row's `name` is the owner's own word and is never
re-cased; its `category` is shown the way a tag is. The screen lists a row the way the
charges screen does — date, category, member, account, the category's ink — and its search
and filters answer from these fields alone, so a shared link lists the same charges.

**Taking a charge out.** "Remove from report" marks the row `removed` and, for the app's own
report, redraws every figure without it; "Put back" clears the mark; "Remove for good" moves
the id to `hidden_ids`, and the row is listed nowhere. An AI-written report keeps its own
figures and only marks or drops the row.

Rows also carry the fallback: with no `period`, a transactions module whose dated rows all
land in one calendar month is what tells longbook which month the report is about.

## Kinds an older file may hold

No draw produces these, and both renderers still read them.

```json
{ "type": "prose", "text": "Spending held steady; the yearly insurances land in March." }
{ "type": "bars", "title": "Monthly spend", "currency": "INR", "bars": [
  { "label": "Jun", "amount": 148200 }, { "label": "Jul", "amount": 161420 } ]}
```

`prose` is `text`, capped at 320 characters. `bars` is one currency per module. A `type`
neither renderer names shows its fields generically.

## Honesty rules (bind every module)

- Amounts come from real charges in the months they fall — never a monthly average of a
  yearly price, never an invented price history.
- Only confirmed charges are counted: a row longbook wrote ahead at the commitment's price
  is nobody's word yet, and back-dating one is exactly the invented price history above.
- Currencies never blend: a total is per-currency or it is not written.
- User data (names, categories) is reproduced exactly as typed; only a Categories slice
  label and a charge row's category take a leading capital.
- A report is derived *from* the vault; it never contradicts it. It is not edited into
  agreement with the owner — the rows are changed, and the next draw follows.

## The fixture

`packages/core/tests/fixtures/report-golden.json` is one file read by both decoders: the
TypeScript `reports` tool (`packages/mcp/tests/reportRead.test.ts`) and the Swift `Report`
decoder (`McpWriteConformanceTests`).

Modules 0–3 are the four drawn modules in their drawn order, and each is a shape
`MonthlyReport.build` really emits — both donuts are single-currency, because a draw derives
its rings from the scope currency alone.

Modules 4–6 are **not** drawn shapes. They are what an older file may hold: a donut under a
title of its own that mixes currencies — which is what holds the "listed beside the ring,
never in it" rule and the verbatim-label rule under test — then `prose` and `bars`. Reading
them proves "an older file still reads" rather than promising it. Nothing in the fixture past
module 3 should be taken as an example of what longbook writes.
