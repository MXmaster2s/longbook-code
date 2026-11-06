# longbook MCP server

[![longbook MCP server](https://mcprush.com/badge/longbook-mcp/card.svg)](https://mcprush.com/to/longbook-mcp?ref=badge)

Your financial memory, readable by the AI you already use. longbook keeps every
recurring commitment — subscriptions, insurance, EMIs, rent, fees — as a plain folder
of files you own. This MCP server lets any AI answer from that memory with real
arithmetic: next payment day, upcoming charges, cash flow, spending by tag, account,
or member. Amounts are per-currency and never converted or blended.

There are two ways to connect. Both serve the same tools from the same engine.

## The hosted server (works with any AI, no install)

Address: `https://longbook.app/mcp`

Sign-in happens in your browser through OAuth; the server reads the hosted copy of
your memory, which you switch on inside the longbook app (Settings → MCP server).
A signed-in AI reads. It can also *suggest* changes once you turn on "Let signed-in
AIs suggest changes" in the app — suggestions wait for your app and land in its
Changes screen, to keep or undo as one batch. Nothing in the cloud ever edits your
memory itself. Disconnecting an AI or turning the switch off takes effect immediately.

The simplest setup: copy the connect prompt from the app or from
[longbook.app/mcp](https://longbook.app/mcp) and paste it into your AI.

| Client | Where to add it |
|---|---|
| Claude (web, desktop, mobile) | Settings → Connectors → Add custom connector → paste the address |
| ChatGPT | Settings → Connectors → Advanced → Developer mode → add MCP server |
| Grok | Settings → Connectors → add remote MCP server |
| Anything else that speaks remote MCP | Point it at the address; OAuth does the rest |

Clients that cannot open a browser — schedulers, CLIs — use an access key from the
app instead (Settings → MCP server → Access keys) as a bearer token. A key made with
"Read and suggest changes" can file suggestions the same way. On a Mac, save the key
to the keychain when it is shown; an agent then reads it without a file:

```bash
security find-generic-password -s "longbook access key" -w
```

Hand it to a connector config through the environment (`"Authorization": "Bearer
${LONGBOOK_KEY}"`), never by pasting the key into a file.

## The local server (reads the folder directly)

```bash
npx -y @longbook/mcp@latest --vault "/path/to/your/longbook folder"
```

`@latest` makes npx fetch the newest release each time instead of reusing an older copy
it kept. It needs Node 18 or later.

Without `--vault` (or the `LONGBOOK_VAULT_PATH` environment variable) it looks in
the iCloud Drive folder the longbook app uses on a Mac. On Windows and Linux, name your
longbook folder with `--vault`. The local server reads your files
directly — no account, no network — reads the bank statements in your documents
folder (PDF, .xlsx, CSV), reads the reports longbook drew into your `reports/` folder with
their comments, and carries the write tools: adding and changing commitments, charges, accounts, people
and tags, marking paid, promoting to recurring and leaving an insight. Every write is schema-validated, scanned by
the data policy, stamped with provenance, and lands in the app's Changes screen for
you to keep or undo.

### Claude Desktop

The Mac app writes this for you in one click (Settings → MCP server). By hand:

```json
{
  "mcpServers": {
    "longbook": { "command": "npx", "args": ["-y", "@longbook/mcp@latest"] }
  }
}
```

### Cursor

Add to `~/.cursor/mcp.json` with the same JSON as above, or use the one-click link:

[Add to Cursor](cursor://anysphere.cursor-deeplink/mcp/install?name=longbook&config=eyJjb21tYW5kIjoibnB4IiwiYXJncyI6WyIteSIsIkBsb25nYm9vay9tY3BAbGF0ZXN0Il19)

### VS Code and GitHub Copilot

Add to `.vscode/mcp.json` (or user settings):

```json
{
  "servers": {
    "longbook": { "command": "npx", "args": ["-y", "@longbook/mcp@latest"] }
  }
}
```

### Codex CLI

Add to `~/.codex/config.toml`:

```toml
[mcp_servers.longbook]
command = "npx"
args = ["-y", "@longbook/mcp@latest"]
```

### Gemini CLI

Add to `~/.gemini/settings.json`:

```json
{
  "mcpServers": {
    "longbook": { "command": "npx", "args": ["-y", "@longbook/mcp@latest"] }
  }
}
```

## What the tools return

Fourteen read tools (next payment, upcoming, charges, cash flow, spending by tag, account
and member, the commitment list, search, accounts, members, tags, whoami and the guide),
every number computed by the engine the apps themselves trust. The vault's own `llms.txt` and JSON Schema travel with the
connection as resources, and four self-contained HTML cards render the answers.
All read tools declare `readOnlyHint`; nothing here can change your files except
the two review-gated local write tools described above.

## More about longbook

- [longbook.app](https://longbook.app/): the app for Mac and iPhone
- [This package on longbook.app](https://longbook.app/features/longbook-npm-package/)
- [Every feature](https://longbook.app/features/) and [automations with your AI](https://longbook.app/automations/)
- [Automate longbook with Claude](https://longbook.app/features/automate-longbook-with-claude/)
- [Review every change your AI makes](https://longbook.app/features/review-every-change-your-ai-makes/)
- [Get insights about your expenses from your AI](https://longbook.app/features/get-insights-about-your-expenses-from-your-ai/)
- [Import your bank statements](https://longbook.app/features/import-your-bank-statements/)
- [Why we built longbook](https://longbook.app/why-we-built-longbook/) and the [FAQ](https://longbook.app/faq/)

## Privacy

The memory's format cannot hold card numbers, CVVs, expiries, PINs, or credentials —
there is no field for them, and a save containing one is refused. The privacy policy
is at [longbook.app/privacy-policy](https://longbook.app/privacy-policy/).

## License

GPL-3.0-only. longbook itself is a paid app ($38 one-time, with a 7-day refund);
this server is free software either way.

## Versions

The server reports its version to every AI that connects: `1.<rulebook revision>.<patch>`,
the same number as this package, its MCP registry entry and the longbook plugin for Claude.
The rulebook is longbook's `llms.txt` and the files beside it; its revision says which
version of them the server speaks.
