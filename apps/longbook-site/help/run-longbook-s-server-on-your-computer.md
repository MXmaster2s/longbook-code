# Run longbook's server on your computer

- Page: https://longbook.app/help/run-longbook-s-server-on-your-computer/

The longbook MCP server also runs on your own computer. It reads your longbook folder directly. It is free, needs no account, no hosted copy and no longbook Cloud, and works offline.

`npx -y @longbook/mcp@latest`

You need Node.js 18 or later. `npx` comes with it and fetches the newest release each time. You also need the longbook app, which creates the folder.

## Add it to your AI app

Add a server named **longbook** with the command `npx` and the arguments `-y` and `@longbook/mcp@latest`, then restart the app.

- **Claude Desktop** on Mac: **Set Up Claude Desktop** in the app does it in one click.
- **Claude Code**: `claude mcp add longbook -- npx -y @longbook/mcp@latest`
- **Cursor**: add it to `~/.cursor/mcp.json`.
- **VS Code**: `code --add-mcp '{"name":"longbook","command":"npx","args":["-y","@longbook/mcp@latest"]}'`
- **Codex CLI** and **Gemini CLI** take the same command in their settings files.

On a Mac it finds your folder in iCloud Drive by itself. On Windows or Linux, add `--vault` and the path to your longbook folder.

## Questions

### Is it open source?

Yes, GPL-3.0. longbook itself is a paid app. The server doesn't check for a licence, but buying longbook is what keeps it improving.

### When do I need Cloud instead?

For Claude on the web, the Claude phone app, or ChatGPT. They run on other computers and can only reach the hosted connector.

### Where do changes go?

Into your folder at once, and into **Proposals** with your AI's name.

Still have a question? Open **Support** in the app, under **Settings**, then **Help & about**, or write to contact@longbook.app and a person answers.

- [All help articles](https://longbook.app/help.md)
