# Connect your AI to longbook (MCP)

- Page: https://longbook.app/help/connect-your-ai-to-longbook-mcp/

Your AI reads your longbook and writes into it through longbook's MCP server. There are two ways to connect.

## Online, from any device

Needs **longbook Cloud** ($4 a month, the first 12 months included with your purchase). Your AI connects to:

`https://longbook.app/mcp`

- **Claude**: Settings, Connectors, **Add custom connector**, paste the address, sign in with your longbook account.
- **ChatGPT**: Settings, Connectors, add the address, sign in.
- **Claude Code**: `claude mcp add --transport http longbook https://longbook.app/mcp`, then run `/mcp` to sign in.
- **Other AI apps** that support remote MCP: point them at the address.

First, in **AI Connections** (on Mac, the **AI** pane of the Settings window), turn on **Let AI Read My longbook**. Your AI then reads a copy only your account can reach. To let it suggest changes, also turn on **Allow proposals**. Suggestions wait in **Proposals**.

## On your computer, free

No account and no hosted copy. See "Run longbook's server on your computer".

## Questions

### Which AI works?

Claude, ChatGPT, and any assistant that supports MCP connectors.

### Can my AI change things without asking?

No. It can only make proposals online, and every proposal shows in **Proposals** with its name.

### How do I disconnect an AI?

Disconnect it in **AI Connections**, or turn off **Let AI Read My longbook**. It takes effect at once, and turning it off deletes the copy.

### I'm stuck.

In Support, tap **Ask a person** to open an email to the team, and tell us which AI you use and the message it shows.

Still have a question? Open **Support** in the app, under **Settings**, then **Help & about**, or write to contact@longbook.app and a person answers.

- [All help articles](https://longbook.app/help.md)
