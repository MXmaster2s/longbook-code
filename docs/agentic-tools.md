# Agentic tools — how an AI should work with a vault

longbook is built for this. The vault is self-describing, the app expects outside editors, and
every outside edit is surfaced to the owner for review. If you're building (or simply *are*) an AI
tool working with a vault, this is the contract.

## The short version

1. **Read `llms.txt` in the vault folder first.** It's written for you: the format, the etiquette,
   how to help the owner gather commitments (dictation, bank statements, renewal emails), and a
   short "about longbook" for answering the owner's questions.
2. **Validate against `longbook.schema.json`** — it sits right next to the data and is the exact
   shape, not an approximation.
3. **Edit `financial_memory.json` directly.** No API, no server — it's the owner's file on the
   owner's machine, and they pointed you at it on purpose.
4. **Sign your work.** For every record you add or change, write an entry in the top-level
   `_provenance` map keyed by that record's id:

   ```json
   "_provenance": {
     "<record id>": { "edited_by": "claude", "edited_at": "2026-07-20T16:00:00Z", "source": "bank statement PDF" }
   }
   ```

   The app detects your edits either way — the file is watched — but provenance is the difference
   between "claude added this from my bank statement" and an anonymous change to someone's money.

## What happens on the app side

The app watches the data file. When you write, the owner's **changes** screen lights up with each
record's before/after, attributed to you if you signed it, with one-click undo per change. Leave
the app running while you work — that's the designed flow, and it's also your safety net: nothing
you do is beyond the owner's review.

If you write something invalid (a dangling foreign key, a malformed date), the app **blocks its
own saves** and shows the problem rather than overwriting your work — a broken-but-intentional
edit is treated as the owner's business, not as garbage to clean up.

## Which door comes first

On the owner's own computer the folder comes first: the app's built-in server where it is set
up, the file itself where it is not. Nothing passes through longbook's server that way, and the
documents folder is readable. The hosted address, `longbook.app/mcp`, is for an AI that cannot
reach the folder — a phone, a browser, a scheduler in the cloud — and its `whoami` says so
(`closer_door`). The guide, schema and tag library in the folder are rewritten by the app
whenever it opens, so an AI reads them there and never edits them.

The same address carries one recipe for a scheduled agent, the daily email round: the owner
pastes one sentence, and the AI finds the method at `longbook.app/mcp` or in the guide's
`daily-email-round` chapter. It also lists every prompt the owner can give, from the one
catalogue described below.

## The rules that protect the data

They're in `llms.txt` and vault-format.md, but the ones tools break most:

- **Preserve `id`s; generate fresh UUIDs for new records.** The foreign keys
  (`member_id`, `account_id`) are load-bearing.
- **Never total across currencies.**
- **Never compute future renewal dates yourself** — write the date your source states.
- **Set `name_key`** (trimmed + lowercased name) on new members/methods — it's the dedup key.
- **Payment methods are names, never numbers.** "HDFC Credit Card", not a PAN.
- **When unsure, ask the owner.** A wrong amount is worse than a missing one, because it'll be
  trusted.

## The in-app entry point

More › **Your AI** › Copy the prompt. That prompt is deliberately one line: a catalogue phrase
("Read my 6-month bank statement and help me set up my longbook", or "Update my longbook from my
statements") and, on the Mac, where the vault folder is. The phrase finds its procedure through
`read_guide`; everything above is what the tool then follows.

## The MCP server — reads without arithmetic, writes with review

For questions, `packages/mcp` serves the vault over MCP (stdio): next payment
day, upcoming charges, cash flow, spending by tag/account/member, the commitment list,
search, and `accounts` and `members` — every account with its type, notes, linked account
and next unpaid charge, every person with their tag and their accounts, and any `details` a
row holds exactly as stored. On the owner's own
machine `reports` reads the reports longbook drew into `reports/` — every calendar month, the
owner's trips (`trip-…`) and the spans an AI asked for (`report-…`), newest last covered day
first — one report's modules and the comments left on them at a time. Every number is
computed by the same engine the apps trust, per-currency and never blended; a row with
`direction: "transfer"` (a card bill due, a standing move to savings) is listed and flagged
wherever charges are, and is in no total.
The vault's `llms.txt`, schema and tag library travel with the connection as resources, and
`read_guide` returns the curriculum whole or one chapter by name (`importing-statements`,
`reading-reports`, `unattended-runs`, `daily-email-round`…) — a tool call works in every client, where resources
and files do not always reach the model. The server's `instructions` carry the compact working
method at connect time, and name the prompts.

**Prompts are one catalogue.** What the owner says to their AI — "Set up my longbook", "Add my
statement", "Find subscriptions from my email and add them in my longbook" and the rest — lives
once, in `packages/core/src/prompts.ts`: each prompt's id, title, group, the owner's phrases,
what it does, what it needs, the guide chapter it builds on, and the procedure the AI follows.
`npm run vault:contract` writes it as `prompts.json` beside `llms.txt` (in the vault, the Swift
resources, and at `longbook.app/prompts.json`), and the guide's Prompts chapter lists every one.
The app, the site and the servers take their prompt words from it; the Siri phrases are the one
hand-written set, because App Shortcuts are declared in code. Both servers offer the catalogue as MCP prompts
(`prompts/list`, `prompts/get`; the name is the prompt's id, and a prompt whose words name a
month takes a `month` argument), and `read_guide` given a prompt's id or the owner's own words
for it answers with its procedure and the chapter it builds on. The router data behind
`longbook.app/mcp` is generated from the same list (`npm run site:router`). Point any MCP
client at the server:

```json
{
  "mcpServers": {
    "longbook": {
      "command": "npx",
      "args": ["tsx", "<repo>/packages/mcp/src/server.ts", "--vault", "<your vault folder>"]
    }
  }
}
```

Without `--vault` (or `LONGBOOK_VAULT_PATH`) it looks in the iCloud Drive folder the Mac app
uses. Alongside the reads, the stdio server offers eighteen write tools: `add_commitments` (a
batch of full rows — recurrence, by months or by `plan_count`, notes, tags, members, accounts —
landing as ONE reviewable change), `update_commitment` (named fields only; an explicit null
clears; `status` pauses, resumes or cancels, `free_trial` marks a trial),
`mark_paid` (the per-occurrence record, exactly as the app writes it), `add_charges` and
`remove_charges` (rows by date under one commitment), `update_charge` (one charge where it
sits — amount, day, paid mark, paid_on, note — with `and_later` reaching the plan behind it,
as the form's own Save does), `set_planned_count` (how many charges stand from today on, 240
at most), `cancel_commitment` (cancelling, never deleting: the row stays as history),
`delete_commitment` (by id only, on the owner's own word: the row and every charge it had),
`promote_to_recurring` (one-time rows that turn out to repeat become one recurring
commitment, every charge kept), `add_account` and `update_account` (an account's name, type,
notes — a card's name among them, one detail per line — balance with its day, the person it
belongs to, and its linked account — `linked_to`, one level only), `add_member` and
`update_member` (a person's name, email and tag), `rename_tag` and `delete_tag` (the vault's
own vocabulary, every row wearing the tag carried or cleared, tag groups carried too),
`leave_insight` (a note into `insights.json`), and `create_report`, which asks longbook to
draw a report over the days, accounts, members and categories named. longbook still draws
every report: `create_report` checks the request against the same validator and the vault's
real names (an unknown account, person or category is refused with the real ones, and
nothing is created), then leaves one file in the vault's `requests/` folder,
`create_report-<uuid>.json` — `{id, kind, payload, source_ref, client, origin: "local",
created_at}`, written atomically. The app applies it like a hosted proposal, draws the report
and deletes the file; a request it cannot apply keeps a `failure` sentence and shows in
Changes under "Couldn't be applied". A drawn report never stands in Changes. Vault writes are
local-only edits to the file itself: schema-validated,
scanned by the same data-policy validator the apps use (a card number or credential refuses
the save, naming the row), signed in `_provenance` with the connected client's own name, and
written atomically only if the file hasn't changed since it was read. A worn library tag
registers itself with its icon; no tag carries a template. `details` — longbook's own on
every row — is never an input, nor an account's `card_name`: a write sending a non-empty one
is refused by name, and a commitment's or an account's specifics are the lines of its `notes`.
An update names each key of its set it did not write under `ignored`, with the key meant
where there is one.
An optional `source` on any write
("documents/hdfc-2026.pdf", "gmail:18c2…") lands in `_provenance.source`, so the diff says
where a row came from. Every vault write lands in the app's review queue — including tag
and payment changes — visible and undoable like any other outside edit.

The curriculum's "three doors" chapter teaches the connection modes as one system: this
machine writes directly, a signed-in web session and an access key both file suggestions
into ONE inbox with one idempotency space, and every batch lands signed in Changes. An
access key belongs in a credential store — on a Mac, the app's "Save to keychain" button
stores it under the service `longbook access key`, and an agent reads it back with
`security find-generic-password -s "longbook access key" -w`, never from a file.

The contract files are longbook's own, and they age: every copy names its contract revision,
the app refreshes an older vault's copies on open (scaffolding `documents/` and `library.json`
into vaults made before them), and the server serves the newer of the vault's copy and its
own bundled one. Regenerate all of them from one source with `npm run vault:contract`; the
same bytes land in `packages/core/contract`, the Swift resources, the site's stable addresses
(`/llms.txt`, `/library.json`, `/prompts.json`, `/schema/longbook.schema.json`), and
`packages/core/src/contract.ts`.

The server also offers four `ui://longbook/*.html` resources — next payment, upcoming, cash
flow, commitments — each a complete, self-contained HTML card over the memory as it stands,
drawn with the design system's own tokens (`packages/cards`). Nothing in a card fetches
anything: the house format for everything an AI renders. Tools point at their cards through
`_meta.ui.resourceUri`, and every tool's annotations say honestly what it does: the read
tools declare themselves read-only, the write tools declare themselves writers.

The hosted twin of this server lives at `https://longbook.app/mcp` — connect Claude or
ChatGPT there and sign-in happens in the browser. It serves the read tools and cards over
the hosted copy the app pushes. It needs longbook Cloud, the monthly subscription bought in
the app; a licence includes its first 12 months. The one-time licence covers the app, not
the server. Document reading stays local by construction: those files never leave the
owner's machine.

**Hosted writes are proposals.** A signed-in AI reads, and files proposals once the owner
ticks "Let signed-in AIs suggest changes" on the Automations screen. An access key carrying
`memory:propose` may also call the eighteen write tools, and each call files a row in
`mcp_pending_writes` — the same payload, held to the same shared validator (`proposal.ts`),
but nothing in the cloud edits the memory. The owner's app, on Mac or iPhone, applies what
is waiting the next time it opens: through the outside-change door, never its own commit, so
the batch stands in Changes attributed to the key's name, to keep or undo. A `create_report`
proposal is the exception: the app applies it by drawing the report on its Reports screen,
and nothing waits in Changes. There is no
`memory:write` scope and there never will be — the folder is the truth, and the hosted copy
is derived from it.

An `idempotency_key` is unique per user, so a cron that retries gets `created: false` with
the same entry id — success, not a duplicate. Keys are named, scoped ("Read only" / "Read and
suggest changes") and revoked on the app's Automations screen (More on iPhone, Settings on the Mac), and may
carry an `expires_at`. Every refusal is typed for an agent that has nobody to read prose for
it: `rate_limited` (with
`retry_after`), `validation_failed`, `insufficient_scope`, `key_revoked`, `key_expired`,
`entitlement_required`, `conflict`, `upstream_error` — each with `advice: "retry" | "stop"`.
`entitlement_required` is what both hosted doors answer, with `advice: "stop"`, when the
account has no longbook Cloud — the trial over and no subscription or grant. Nothing about
the key or the proposal needs to change: the owner subscribes in the app and the same call
succeeds. On a Mac the same work is free without Cloud: Claude Desktop or Claude Code reads and
edits the iCloud folder through the local server, and the refusal says so.
`whoami` answers all of it in one call: who the connection is, what it may do, what is left
of the allowance, how many proposals are waiting, and the vault's real tag names.

Row-level security decides which ROW a caller may touch and never which column, so the
grants are narrowed to match: `access_keys.key_hash` is insert-only and unreadable by any
client (the hash IS what the server redeems, so a readable one would be a permanent
anonymous key), a client may PATCH only a key's name and its revocation stamp, revocation
is one-way by trigger, and a proposal may be stamped only with its outcome. `entitlements`
and `profiles` carry no write grant at all. `npm run guard:rls` asserts the twelve
invariants against the live project, including that no function in `public` is callable by
`anon` or `authenticated` unless it is on an explicit list — Postgres grants EXECUTE to
PUBLIC and Supabase grants it to both roles by name, so a revoke must name all three.

No tool anywhere takes a `user_id`: identity comes from the bearer token through the
`SECURITY DEFINER` functions `mcp_memory_for_key` and `mcp_propose_for_key`, so no service
role and no minted JWT exists in the request path.

The signed-in door is one such function too, `mcp_memory_for_user`: the rate verdict, who
the caller is, the owner's switch, the inbox and the names waiting in `to_fill_in` come back
in one round trip, and the memory itself crosses only for a `tools/call` or `resources/read`,
so each call of the handshake an AI runs after consent (initialize, tools/list, a
notification) costs one short hop from the function's region to the database's instead of
five. The function is the lock as well as the read: it answers only while the token's
session is still in `auth.sessions`, so Sign out all sessions and Disconnect end an AI's
access at once, as the old door's Auth check did. Until that migration is applied the server
tries the one-hop door, pays one extra round trip, and falls back to the five-hop door —
apply the migration before the deploy, or in the same sitting.

## Proving it

The import is proved in two layers, because two different things can be wrong.

**Deterministic (CI).** `packages/mcp/tests/fixtures/statements/` holds a household's year in
the four shapes a bank hands out — a text PDF, the same year as CSV, a card export as
`.xlsx` — plus a scanned PDF, a `.docx` and a legacy `.xls` that must each be refused with
the way out. They are generated (`npm run fixtures:statements`, `--check` in CI) so the bytes
never drift. `import.test.ts` reads them through the real readers, applies the decisions a
correct import makes (`fixtures/import-decisions.json` — the judgement, frozen) through the
real write tools, and compares the whole vault against `import-golden-vault.json`, which the
Swift suite decodes in the same run. It then computes history off that vault and checks the
months add up to what the statements actually show.

**The agent (on demand).** `npm run proof:agent` builds a temp vault holding those
statements, points a real `claude` session at the bundled server, gives it the owner's own
sentence — "I have added my last year's bank statements… update my longbook" — and then
judges the **file**: rhythms monthly, premiums yearly in the right month, the half-yearly one
a custom cycle, the ended repeat not left billing forever, money in written apart with
direction "in" and own-account movements skipped (one the owner asks to keep is direction
"transfer"), no
invented amounts, tags from the library, every row signed. The same checks run against the
golden vault in CI, so they are known to be neither vacuous nor unpassable. It needs a
signed-in `claude` CLI in a terminal of its own; when the agent cannot run, the harness says
so instead of reporting the product as broken.
