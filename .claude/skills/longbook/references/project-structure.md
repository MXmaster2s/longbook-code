# Project structure

The layout table is in `AGENTS.md`. What it does not say:

- **One data layer, two languages.** `packages/core` (TypeScript) and `packages/swift-core` (Swift)
  implement the same rules. A rule changed in one is changed in the other in the same pull
  request, with tests on both sides.
- **The vault contract** (`scripts/gen-vault-contract.mts`, `CONTRACT_REVISION`) generates
  `llms.txt` and the files beside it. A contract change bumps the revision; `npm run
  vault:contract:check` fails on drift. See `docs/vault-format.md`.
- **Design tokens** come from `scripts/gen-design-tokens.mts`; `npm run design:tokens:check` keeps
  app and site in step. Never hard-code a colour.
- **The app project is generated** from `apps/longbook/project.yml` with XcodeGen; the
  `.xcodeproj` is never committed. New Swift files under `apps/longbook/Sources` need no project edit.
- **The hosted MCP server** runs the same engine as `packages/mcp`; `npm run hosted:engine:check`
  fails when the hosted copy is stale.
- **Supabase**: functions in `supabase/functions/<name>`, shared code in `_shared/`, migrations in
  `supabase/migrations/` (timestamped, applied in order). `npm run guard:rls` checks the row-level
  security invariants. A function only the server may call revokes execute from `public`, `anon`
  and `authenticated` and grants it to `service_role`.
- **Telemetry names**: every screen, sheet, alert and button is measured by name;
  `npm run telemetry:names` and `telemetry:coverage` fail on a missing or renamed one.
- Architecture: `docs/architecture.md`. Agent tools: `docs/agentic-tools.md`.
