# the vault format

A longbook vault is a plain folder:

```
<chosen folder>/
  financial_memory.json     the data — the only file that matters
  longbook.schema.json      formal JSON Schema for the data file (machines validate against it)
  llms.txt                  prose contract for humans and AI tools — the trainer curriculum lives here
  library.json              the seeded tag library: names and icons
  longbook.workspace.json   UI preferences sidecar (home currency, etc.) — not part of the memory
  documents/                statements, policies, invoices — the source of past truth, referenced from rows
  reports/                  what longbook draws: a report per month with a confirmed charge, trips, and spans an AI asked for
  requests/                 longbook's own: create_report requests from the Mac's MCP server, waiting for the app
  insights.json             AI notes shown on the app's own modules
```

The folder is **self-describing on purpose**: any tool pointed at it can learn the exact contract
from the schema and the etiquette from `llms.txt`, with no involvement from us. The app rewrites
the contract files when they're missing or stale; it never touches the data file while doing so.

## generating the contract set

`longbook.schema.json`, `llms.txt` and `library.json` are generated, not hand-edited:
`scripts/gen-vault-contract.mts` is the single source of truth, and it writes byte-identical
copies to `packages/core/contract` (for Node/MCP-server use) and
`packages/swift-core/Sources/LongbookCore/Resources` (bundled into the app, so a Mac-made vault
and a phone-made vault carry identical contract files). Run `npm run vault:contract` after any
change; `npm run vault:contract:check` verifies nothing has drifted, and CI runs it on every push.

## the data file

Top-level shape (see `longbook.schema.json` in any vault for the authoritative version):

- `app` — `"longbook"`.
- `version` — the file **format**, currently `3`. Not a revision counter; leave it alone.
- `commitments[]` — the only required list, and only what every charge of a commitment shares:
  name, `amount` (the price now — what a newly planned charge is written at), `currency`,
  `billing_cycle` (`monthly | yearly | custom | once`, shown as Commitment Type), `status`, `tag`,
  `notes` (its three details that matter, one per line — see **tags**, below), `details`
  (longbook's own: `statement_line`, the words a statement printed), `ends_on`, `direction`,
  and two foreign keys: `member_id`, `account_id`. Nothing about an occurrence lives here.
  `direction` is `in` for money that arrives, `transfer` for a movement between the owner's
  own accounts they still want to see (a card bill due, a standing move to savings), and
  absent or `out` for a charge. Only a charge is spending: money in and transfers are shown on
  the timeline and summed into nothing. A word a newer contract names is kept as written
  through an edit, and read as a charge until a version names it. A promotion never mixes
  directions.
- `charges[]` — every charge, past and planned, one row per commitment per due date, and the
  only place an occurrence exists: `commitment_id`, `date`, `amount`, `paid`, and optionally
  `currency` (when it differs from the commitment's), `paid_on`, `basis`, `note`, `written_at`.
  Nothing is computed from a rule: history is exactly the rows before today, the plan is exactly
  the rows from today on, and rows are written only when someone asks — the person creating a
  commitment, their AI, a mark. `basis` says what backs a row: `statement` / `email` (a
  document), `user` (the owner's word or hand), `mark_paid` (the app's own tap), or `plan`
  (written ahead at the commitment's price). Anything but `plan` is a fact, and nothing reprices
  a fact; an `amount` change on a commitment reaches only unpaid planned charges from today on.
  Decoding is element-lossy — a malformed row drops alone instead of failing the vault.
- `members[]` — who a commitment is for: family, team, staff, anyone. Carries `tag` — their
  role in the owner's finances, set on the owner's word — `email`, and `details`, longbook's
  own: read as stored, never written. A member is a name, a tag, an email and linked accounts.
- `accounts[]` — what a commitment is billed to: a display name, `nickname`, `institution`,
  `last4` (schema-constrained to exactly 4 digits), `tag`, `notes` — what is particular about
  it, one detail per line; on a card, "Card name: Platinum Reserve", the product printed on
  it, never a number — `details` (longbook's own, read as stored, never written), an optional
  owning `member_id`, and `parent_account_id` — the **linked account**, a card to the bank
  account that pays it, one level only (the key keeps its older name; every tool and screen
  reads it as "linked account"). See **data minimization**, below.
- `tags[]` — the vault's own vocabulary: `kind` (`commitment | member | account`), name and
  an SF Symbol `icon`. Seeded entries copy in from the library on first use; the owner and
  their AI add more the same way.
- `groups[]` — optional; the owner's labels over what already exists (never records themselves).
  `kind` is `account` (holds `account_ids`), `member` (holds `member_ids`), or `tag` (holds
  `tag_keys`). A `tag` group sits above tags — "business", "household" — and longbook totals
  spending by it. A tag belongs to at most one group; ungrouped is ungrouped.
- `_provenance` — optional map keyed by record id: who last edited it, when, from what source.
  This is what lets the app attribute an outside edit to a tool instead of "unknown edit".

Three neighbours in the folder are the app's own, never for outside tools to edit:
`longbook.workspace.json` (display preferences — home currency, bookmarks, live share ids,
the open trip), `requests/` and `.longbook/history/` (content-addressed snapshots of the data
file plus a `log.jsonl`, which power the outside-change review and revert). Editing history
would defeat the owner's ability to review and undo changes.

`requests/` holds one file per thing an AI asked longbook to do on this machine — today only
`create_report`, written by the app's own MCP server as `create_report-<uuid>.json`:
`{id, kind, payload, source_ref, client, origin: "local", created_at}`. The app applies each
like a hosted proposal and deletes it; one it cannot apply gains a `failure` sentence and
shows in Changes. No tool or AI writes the folder by hand. `reports/` likewise holds what
longbook draws, and `create_report` is how an AI asks for one: a file placed there by
anything else is not a report longbook drew.

## tags — structured, never rigid

A tag names what kind of thing a row is; it never gives a row a shape. No tag carries a
template: what is particular about a commitment — an insurance policy's number, its official
name, the policy's file in `documents/` — is its `notes`, three lines at most, each
`Label: value`. The category decides which three; `llms.txt` lists them by category. What is
particular about an account — a card's printed name — is the lines of its `notes` too, and a
member carries a name, a tag, an email and linked accounts. A template a vault still holds on
any tag is read as none, and nothing rewrites the file to drop it.

`details` are longbook's own on every row — a commitment's `statement_line`, written when it
reads a statement — readable by anything that opens the file, and taken by no write tool: an
account or member write sending a non-empty `card_name` or `details` is refused by name, and an
empty one is answered as ignored. A card name an account's `details` hold opens in Edit Account
as a line of its notes, unless the notes already hold that line, and the owner's Save writes it
there. Values stay scalar (or a flat list) so the file remains greppable. Totals read
only the structural spine — the rows in `charges[]` and the attributes a commitment shares —
never `details` or `notes`; a detail earns its way into the spine only through a format bump.

## data minimization — the memory cannot hold secrets

The schema has **no field**, anywhere, for a full card or account number, a CVV, an expiry, a
PIN, or a credential. `accounts[].last4` is pattern-constrained to exactly 4 digits, so the
schema itself cannot hold more even if something tried. Free-text fields (`notes`, names, every
`details` value) are additionally pattern-scanned before every write —
`packages/core/src/domain/dataPolicy.ts`, mirrored in
`packages/swift-core/Sources/LongbookCore/DataPolicy.swift` — so a value the schema was never
meant to hold cannot slip in through prose either. A save containing one is refused, never
silently accepted. This is what makes hosting a copy of the memory, and sharing an AI-written
report built from it, an acceptable design rather than a liability.

## what longbook keeps server-side

longbook never reads the memory. Two things can live in the owner's account row, both behind
owner-only row-level security: the **hosted copy** (opt-in, deleted the moment it's switched
off — see `hosted_memories`) and the **structure store** (`structures`) — the vault's tag
definitions, as `tags[]` holds them: kind, name and icon, never a template. Never a commitment
name, an amount, a date, a note, or a `details` value; `StructureSyncTests` fails the build if
the sync payload ever carries more.
Aggregate patterns across these definitions are how the shipped library grows.

## one format, read strictly

The app, the servers and the npm bin read format 3 and nothing else: any other `version` is
refused as "not a financial memory this version can read" rather than read with the wrong
shape. There is no upgrader in the product. A pre-release vault is converted once, on the
owner's own machine, by `scripts/vault-convert-v3.mts` — dev tooling that runs today's walk a
last time and writes what it says down as rows.

## two version numbers, deliberately separate

- **`DATA_FORMAT_VERSION`** (in the file as `version`) moves only when a vault written today would
  be *misread* by yesterday's reader. Growing a new optional field is not that; storing every
  charge as a row was.
- **`CONTRACT_REVISION`** is bookkeeping for the documents beside the data — "have we revised the
  schema, llms.txt or the library since this vault last saw them?" It never appears in the data
  file.

## invariants the validator enforces

- Foreign keys must resolve (a dangling `member_id` blocks saves, not silently).
- Amounts are finite and non-negative; dates are real calendar dates.
- `name_key` (trimmed + lowercased name) is the dedup key for members, accounts and tags.
- `details` values are scalars or flat lists — never nested objects.
- An invalid file on disk is **preserved and reported**, never overwritten with a fresh vault.
- No free-text field may contain a card number, CVV, expiry, PIN, or credential — see above.

## rules for anything that writes

1. Preserve `id`s — they're UUIDs and they're load-bearing.
2. Never convert or blend currencies. Totals are per-currency, always.
3. Never write a charge nobody asked for; plan as far as the owner said, and say how far.
4. Sign your work in `_provenance`.
5. Prefer `status: "cancelled"` over deleting — a cancelled commitment keeps every charge that
   happened and drops only the plan ahead.
6. Never write a full card number, CVV, expiry, PIN, or credential anywhere in this file.
7. Keep source documents in `documents/` and name them by path in a commitment's `notes` —
   don't paste their contents into the memory.
