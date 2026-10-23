---
title: Automations
seo_title: Automations for your expenses and subscriptions
description: Claude and ChatGPT through longbook's MCP server, prompts to copy, Gmail read every morning, Siri, Shortcuts and AI notes, each change waiting for your review.
features: automate-longbook-with-claude, longbook-npm-package, log-expenses-from-gmail, automate-longbook-with-siri-and-shortcuts, get-insights-about-your-expenses-from-your-ai, review-every-change-your-ai-makes
---

longbook can keep itself up to date. Your AI reads your email and records the charges it finds, Siri adds expenses by voice, and every change waits in Changes for you to keep or undo.

## Reorganise my longbook

One pass over the whole book, the way you would keep it if you had an afternoon: names as you would say them, every row in a category, people and accounts linked, doubles merged, nothing lost. Amounts and dates are never touched. The pass lands in [Changes](/features/review-every-change-your-ai-makes/) as one change, to keep or undo at once.

In the app, **Reorganise my longbook** on the AI Connections screen runs it with longbook's own AI: your longbook goes to longbook's server for the one pass and is not kept, and Anthropic's Claude reads it. Twice a month without longbook Cloud, more with it. With your own AI connected, paste the prompt **Reorganise my longbook** instead; it follows the same written method, as often as you like.

## Connect your AI

Connect your AI to longbook and it reads the same commitments the apps read, and writes through the same rules. Connect online from any device, or on your own computer for free.

#### Online, from any device

**Needs longbook Cloud**, $4 a month, with the first 12 months included when you buy longbook: [what longbook Cloud is](/features/what-is-longbook-cloud/). Your AI connects to longbook's address. Opened in a browser, the address explains itself: the tools, and a worked example.

`https://longbook.app/mcp`

### Claude

Settings → Connectors → **Add custom connector** → paste the address → sign in with your longbook account.

### ChatGPT

Settings → Connectors → **Add** → paste the address → sign in.

### Claude Code

`claude mcp add --transport http longbook https://longbook.app/mcp`

Then run `/mcp` to sign in.

### Claude plugin

Adds every longbook prompt as a command, such as `/longbook:whats-due` and `/longbook:weekly-page`.

`/plugin marketplace add MXmaster2s/longbook-claude-plugin`

`/plugin install longbook@longbook`

Sign in with your longbook account when Claude asks, then type `/longbook:start`. It checks the connection, starts setup when your longbook is empty, and lists every prompt. The email prompts also need Gmail connected.

#### On your computer, free

**No longbook Cloud needed.** Your AI reads your longbook folder on your computer directly, with no hosted copy. The [longbook npm package](/features/longbook-npm-package/) runs the server in any app that starts MCP servers, with Node.js 18 or later. On Windows or Linux, add `--vault` and your longbook folder's path after `@longbook/mcp@latest`.

### Claude Desktop

**Set up Claude Desktop** in the Mac app connects Claude to your longbook folder directly. Without the app's setup, add the server below as in any other app.

### Claude Code on your computer

`claude mcp add longbook -- npx -y @longbook/mcp@latest`

### Cursor

Add to `~/.cursor/mcp.json`:

`{"mcpServers":{"longbook":{"command":"npx","args":["-y","@longbook/mcp@latest"]}}}`

### VS Code

`code --add-mcp '{"name":"longbook","command":"npx","args":["-y","@longbook/mcp@latest"]}'`

### Any other app

Add a server named longbook that runs this command:

`npx -y @longbook/mcp@latest`

## Prompts for your AI

Paste a prompt into Claude or ChatGPT with the longbook connector on. Each one has written steps your AI reads from longbook, so the same words get the same result, and what it adds or changes in your commitments and charges waits in [Changes](/features/review-every-change-your-ai-makes/).

The same list, with every step, is at [longbook.app/prompts.json](https://longbook.app/prompts.json).

## All of the MCP server's tools

Every write goes through the same validator the apps use and lands in [Changes](/features/review-every-change-your-ai-makes/) with its writer named. The folder also carries a schema and a guide, `longbook.schema.json` and `llms.txt`, so any AI reads and writes it correctly.

### Reading

- `next_payment`
- `upcoming`
- `cashflow`
- `commitments`
- `charges`
- `spending_by_category`
- `spending_by_account`
- `spending_by_person`
- `accounts`
- `people`
- `tags`
- `search`
- `whoami`
- `read_guide`

### On a Mac

- `list_documents`
- `read_document`
- `reports`

The statements in the folder, and the reports longbook drew there with the comments left on them. They read files, so they work only where the folder is in reach.

### Writing

- `add_commitments`
- `update_commitment`
- `mark_paid`
- `add_charges`
- `remove_charges`
- `cancel_commitment`
- `promote_to_recurring`
- `leave_insight`
- `update_account`
- `update_person`
- `update_charge`
- `set_planned_count`
- `add_person`
- `add_account`
- `rename_tag`
- `delete_tag`
- `delete_commitment`
- `create_report`

`create_report` asks longbook to draw a report over the days, accounts, people and categories you name. It appears on the Reports screen the next time the app is open, not in Changes.
