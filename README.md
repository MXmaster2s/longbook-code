# longbook

[![longbook MCP server](https://mcprush.com/badge/longbook-mcp/card.svg)](https://mcprush.com/to/longbook-mcp?ref=badge)

**A financial memory for your AI.** longbook keeps your recurring money — subscriptions,
insurance, EMIs, school fees, domains, renewals — as a meticulous, machine-readable memory that
the AI you already use can read, fill, and build on. Your AI gathers from your statements and
emails; longbook remembers, checks, and shows you every change for approval.

- **Native apps** for iPhone and Mac (SwiftUI), one $38 purchase with a 7-day refund, one
  purchase unlocks every platform; longbook Cloud, $4 a month, covers what uses the server.
- **Your data is a folder of plain files you own** — self-describing (`llms.txt` + a JSON
  Schema), synced through your own iCloud Drive.
- **Designed so it cannot hold secrets**: no card numbers, no CVVs, no credentials — the schema
  and validators refuse them, which is what makes everything else safe.
- **Connects to your AI** over MCP — locally for desktop AI apps, hosted for ChatGPT and phones.

**Site:** [longbook.app](https://longbook.app) · **Contact:** contact@longbook.app

## Status

The domain engine (`packages/core`), the Swift data layer (`packages/swift-core`), the
accounts and entitlements backend (`supabase/`) and the native app (`apps/longbook`) are
all in place; the app runs on both platforms and ships through App Store Connect. Docs
describe what exists today.

## Layout

| Path | What it is |
|---|---|
| `packages/core` | The domain engine — dates, money, selectors, insights, the data-policy scanner; pure TypeScript, no runtime deps |
| `packages/swift-core` | The same data layer in Swift, as a multiplatform package (iOS 17+, macOS 14+) shared by both app targets |
| `packages/swift-design` | The design system — colour, type, spacing, and the SwiftUI pieces both apps draw with |
| `packages/mcp` | The MCP server — the memory's read and write tools over stdio for the AI on the owner's machine, and the engine behind the hosted twin at `longbook.app/mcp`, which reads the pushed copy and takes writes as proposals |
| `packages/cards` | Self-contained HTML cards over the same numbers — the design system's tokens, exported once, feeding a second renderer |
| `supabase/` | Accounts, trial clock, entitlements, purchases, the hosted MCP and hosted copy, statement reading, report sharing |
| `apps/longbook` | The native SwiftUI app — one target building for iOS and macOS, with the Home Screen widget |
| `apps/longbook-site` | The static site at longbook.app — the pages, the guide and schema at stable addresses, and the edge functions behind `/mcp` and shared reports |
| `docs/` | [Architecture](docs/architecture.md) · [Vault format](docs/vault-format.md) · [Agentic tools](docs/agentic-tools.md) · [Building](docs/building-from-source.md) · [Contributing](docs/contributing.md) |

## License

[GPL-3.0](LICENSE). Copyright © 2026 Rohit Kundliwal. Contributions are accepted under the
licence grant in [contributing](docs/contributing.md). The longbook name and mark identify this
project's own releases.
