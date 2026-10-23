# Architecture

What exists, present tense.

## The shape

One vault, many readers, one honest engine.

- **The vault** is a folder of plain JSON the user owns, usually in their iCloud Drive:
  `financial_memory.json` plus its own `llms.txt` and JSON Schema, so any AI pointed at the
  folder can understand and safely edit it. The full on-disk contract: [vault format](vault-format.md).
- **`packages/core`** is the engine — every date, money, and status computation, plus the
  data-minimization scanner. Pure TypeScript, zero runtime dependencies. The honesty rules live
  here as code: per-currency totals are never blended, multi-month amounts are never amortised,
  insights return nothing rather than a guess.
- **`packages/swift-core`** is the same data layer in Swift, as a proper multiplatform SPM
  package (iOS 17+, macOS 14+) — the native app's iOS and macOS builds depend on it
  directly, rather than each carrying their own copy. `Vault` models patch raw JSON so unknown
  fields survive a write round-trip; coordinated atomic file IO does byte-level compare-and-swap
  against outside edits; iCloud materialization happens on every read; a widget-safe read mirror
  and the auth/entitlement clients live here too. `Selectors.swift` and `DataPolicy.swift` mirror
  core's renewal engine and scanner in behaviour.
- **Conformance fixtures** (`packages/core/tests/fixtures/*.json`) are the one place renewal and
  data-policy test vectors are written down; both `packages/core`'s and `packages/swift-core`'s
  test suites load the same files, so the two implementations cannot silently drift apart.
- **`supabase/`** is the entire backend: `profiles` (server-set trial clock), `entitlements` (the
  one-time licence) and `cloud_subscriptions` (the monthly longbook Cloud subscription, with
  `cloud_grants` for grants made by hand) tables behind row-level security with no client write
  policy; `has_cloud(uid)`, the one rule for whether an account may use the server — a live
  trial, an active or grace subscription, or a grant — which every hosted door, statement
  reading and report creation calls; `apple-purchase`, which verifies the App Store's signed
  transaction, licence or subscription, and binds it to a verified JWT, and emails a licence
  buyer one confirmation through Resend, with `apple-notifications` for refunds and for the
  subscription's renewals, lapses and grace periods; `auth-email`,
  which Supabase Auth's Send Email hook hands every sign-in code to: it caps one address at five
  codes an hour and every address together at a hundred, keeping only a hash of each address for
  that hour, and sends through Resend
  (`npm run auth-hook` turns the hook on or off; with it off, Auth sends the same emails from its
  own templates in `supabase/auth-emails`, generated and deployed by `npm run auth-emails`);
  `account-notice`, which emails an account's owner about a
  sign-in, the hosted copy turned on or off, and a shared report, from an outbox table that
  database triggers, a once-a-minute scan of new sessions and `share-report` write; the hosted MCP
  function over the hosted copy the app pushes; report sharing; and `statement-extract`, which
  receives the pages of a statement the owner picks, asks Claude whether it is a statement and
  then to read it (OpenAI stands in when Claude cannot answer), and keeps a ledger of calls and
  tokens per import, with the account's monthly share — never the content. The backend never
  sees vault data; the statement reader sees statement pages transiently.

## The website

longbook.app is static files in `apps/longbook-site`, published to Netlify behind Cloudflare by
`npm run site:deploy`, which exports the committed tree, fills in the git-ignored images and
films by the hashes in `apps/longbook-site-content/built.json`, deploys, and reads the live site
back byte for byte. Most pages are hand-written HTML; `scripts/gen-site-pages.mts` stamps their
shared header and footer and builds everything generated from `apps/longbook-site-content`: the
feature pages, the blog, the Markdown copy of every page, `sitemap.xml`, `_redirects`, and
`_headers` (security headers on every response; a year's caching only for files every link
reaches with `?v=<hash>`; pages never cached). CI runs it with `--check`. `/mcp` is the hosted MCP door: `_redirects` proxies
its requests to the Supabase `mcp` function, and the Netlify edge function `mcp-explainer` answers
a plain GET with the page or JSON that explains it; a second edge function keeps staging out of
search. The shared-report viewer is the static page `/r/`. The content README,
`apps/longbook-site-content/README.md`, says how each part is edited and built.

## The boundaries that matter

1. **The vault is the only truth.** Servers hold identity, trial state, the licence and the Cloud
   subscription's status — and, only when a user opts in, a hosted copy of the memory for AI
   access and sharing, which needs Cloud once the trial ends.
2. **The memory cannot hold secrets.** The schema has no field for card numbers, CVVs, expiries,
   PINs, or credentials, and validators refuse pattern-matched secrets in free text. Every
   downstream capability rests on this property.
3. **Writes are reviewable.** Outside edits are detected, attributed via signed `_provenance`,
   and land in a review queue with per-change undo.

## Where the rest is described

The SwiftUI app (`apps/longbook`) is one target for iOS and macOS on `packages/swift-core` and
`packages/swift-design` — [building from source](building-from-source.md). The MCP server
(`packages/mcp`) and its hosted twin — [agentic tools](agentic-tools.md).
