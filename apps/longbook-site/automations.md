# Automations

> longbook can keep itself up to date. Your AI reads your email and records the charges it finds, Siri adds expenses by voice, and every change waits in Proposals for you to keep or undo.

- Page: https://longbook.app/automations/

## Automate longbook with Claude

Claude reads your longbook and writes into it through longbook's MCP server. It answers what is due and what a month cost, and adds the charges it finds.

- Answers from your own records
- Writes that wait for you
- Two ways to connect

![Importing a statement through Claude in longbook on iPhone: the steps to enable the longbook MCP server, add the connector in Claude and paste the prompt with the statements attached.](https://longbook.app/features/img/iphone-own-ai.jpg)

![The Automations screen of longbook on Mac with the MCP server on: a hosted copy for AI connectors, AI suggestions, and one-click setup of Claude Desktop on the same Mac.](https://longbook.app/features/img/mac-mcp-server.jpg)

Read more: [Automate longbook with Claude](https://longbook.app/features/automate-longbook-with-claude.md)

## Use your longbook in any AI app on your computer

Want the AI app you already have open all day to know what you owe this month? Run longbook's MCP server on your own computer with one command, and Cursor, VS Code, Claude Code or any other MCP app reads your longbook folder directly. Add it in your AI app and consider it done.

`npx -y @longbook/mcp@latest`

- Works in the AI apps you already use
- Free and private
- The same answers and the same rules
- Any computer that has your folder

![The Automations screen of longbook on Mac with the MCP server on: a hosted copy for AI connectors, AI suggestions, and one-click setup of Claude Desktop on the same Mac.](https://longbook.app/features/img/mac-mcp-server.jpg)

Read more: [Use your longbook in any AI app on your computer](https://longbook.app/features/longbook-npm-package.md)

## Log expenses from Gmail

Claude reads your Gmail every morning and records what it finds in longbook: bank alerts, receipts, bills that are due and money in. Each entry waits in Proposals.

- One prompt, once
- Each morning's mail
- Waiting in Proposals

![The Automations screen of longbook on iPhone: the longbook MCP server switched on, AI suggestions allowed, and the Claude email automation with its prompt.](https://longbook.app/features/img/iphone-automations.jpg)

![The Automations screen of longbook on Mac: the longbook MCP server switched on, the Claude email automation, the Shortcuts action for bank messages, and the Siri and Spotlight commands.](https://longbook.app/features/img/mac-automations.jpg)

Read more: [Log expenses from Gmail](https://longbook.app/features/log-expenses-from-gmail.md)

## Automate longbook with Siri and Shortcuts

Siri adds expenses and commitments to longbook by voice and says what is due next. A Shortcuts action records charges from a bank's messages.

- Expenses and commitments by voice
- The next payment, spoken
- Charges from bank messages

![The Automations screen of longbook on iPhone: the longbook MCP server switched on, AI suggestions allowed, and the Claude email automation with its prompt.](https://longbook.app/features/img/iphone-automations.jpg)

![The Automations screen of longbook on Mac: the longbook MCP server switched on, the Claude email automation, the Shortcuts action for bank messages, and the Siri and Spotlight commands.](https://longbook.app/features/img/mac-automations.jpg)

Read more: [Automate longbook with Siri and Shortcuts](https://longbook.app/features/automate-longbook-with-siri-and-shortcuts.md)

## Get insights about your expenses from your AI

Your AI reads your longbook and leaves short notes on the cards they concern. longbook shows each note beside its card and gathers them all on one screen.

- A note on the card it concerns
- Every note in one place
- Notes from your AI alone

![The Insights screen of longbook on iPhone: the notes an AI has left on the dashboard, an account and a member.](https://longbook.app/features/img/iphone-insights.jpg)

![The Insights screen of longbook on Mac: the notes an AI has left on the dashboard, an account and a member.](https://longbook.app/features/img/mac-insights.jpg)

Read more: [Get insights about your expenses from your AI](https://longbook.app/features/get-insights-about-your-expenses-from-your-ai.md)

## Review every change your AI makes

Every row an AI, Siri or a statement import writes into longbook shows in Proposals, with the name of its writer, to keep or undo.

- Each row with its writer
- One answer for the whole change
- Every version, kept

![The Proposals screen of longbook on iPhone: charges, a commitment, an account and a member suggested by Claude, with Keep all and Undo all.](https://longbook.app/features/img/iphone-changes.jpg)

![The Proposals screen of longbook on Mac: charges proposed by Claude with Keep all and Undo all, and the history of earlier versions.](https://longbook.app/features/img/mac-changes.jpg)

Read more: [Review every change your AI makes](https://longbook.app/features/review-every-change-your-ai-makes.md)

## Reorganise my longbook

One pass over the whole book, the way you would keep it if you had an afternoon: names as you would say them, every row in a category, people and accounts linked, doubles merged, nothing lost. Amounts and dates are never touched. The pass lands in [Proposals](https://longbook.app/features/review-every-change-your-ai-makes.md) as one change, to keep or undo at once.

In the app, **Reorganise my longbook** on the AI Connections screen runs it with longbook's own AI: your longbook goes to longbook's server for the one pass and is not kept, and Anthropic's Claude reads it. Twice a month without longbook Cloud, more with it. With your own AI connected, paste the prompt **Reorganise my longbook** instead; it follows the same written method, as often as you like.

## Connect your AI

Connect your AI to longbook and it reads the same commitments the apps read, and writes through the same rules. Connect online from any device, or on your own computer for free.

### Online, from any device

**Needs longbook Cloud**, $4 a month, with the first 12 months included when you buy longbook: [what longbook Cloud is](https://longbook.app/features/what-is-longbook-cloud.md). Your AI connects to longbook's address. Opened in a browser, the address explains itself: the tools, and a worked example.

`https://longbook.app/mcp`

#### Claude

Settings → Connectors → **Add custom connector** → paste the address → sign in with your longbook account.

#### ChatGPT

Settings → Connectors → **Add** → paste the address → sign in.

#### Claude Code

`claude mcp add --transport http longbook https://longbook.app/mcp`

Then run `/mcp` to sign in.

#### Claude plugin

Adds every longbook prompt as a command, such as `/longbook:whats-due` and `/longbook:weekly-page`.

`/plugin marketplace add MXmaster2s/longbook-claude-plugin`

`/plugin install longbook@longbook`

Sign in with your longbook account when Claude asks, then type `/longbook:start`. It checks the connection, starts setup when your longbook is empty, and lists every prompt. The email prompts also need Gmail connected.

### On your computer, free

**No longbook Cloud needed.** Your AI reads your longbook folder on your computer directly, with no hosted copy. The [longbook npm package](https://longbook.app/features/longbook-npm-package.md) runs the server in any app that starts MCP servers, with Node.js 18 or later. On Windows or Linux, add `--vault` and your longbook folder's path after `@longbook/mcp@latest`.

#### Claude Desktop

**Set up Claude Desktop** in the Mac app connects Claude to your longbook folder directly. Without the app's setup, add the server below as in any other app.

#### Claude Code on your computer

`claude mcp add longbook -- npx -y @longbook/mcp@latest`

#### Cursor

Add to `~/.cursor/mcp.json`:

`{"mcpServers":{"longbook":{"command":"npx","args":["-y","@longbook/mcp@latest"]}}}`

#### VS Code

`code --add-mcp '{"name":"longbook","command":"npx","args":["-y","@longbook/mcp@latest"]}'`

#### Any other app

Add a server named longbook that runs this command:

`npx -y @longbook/mcp@latest`

## Prompts for your AI

Paste a prompt into Claude or ChatGPT with the longbook connector on. Each one has written steps your AI reads from longbook, so the same words get the same result, and what it adds or changes in your commitments and charges waits in [Proposals](https://longbook.app/features/review-every-change-your-ai-makes.md).

The same list, with every step, is at [longbook.app/prompts.json](https://longbook.app/prompts.json).

### Setting up

- "Read my 12-month bank statement and help me set up my longbook": Your longbook filled from your statements: every charge on record, the names you picked in setup filled in where your statements or your answers show them, each account's closing balance set, the charges that clearly repeat planned ahead, and the rest set to repeat once you confirm them. It waits in the Proposals screen for you to keep.
- "Add my statement in my longbook": Every charge on the statement recorded as paid, money in kept apart, the account's balance updated, the charges that clearly repeat set to continue, and the rest once you confirm them.
- "Categorise my longbook": Every commitment without a category gets one. Your AI shows you the ones it guessed, so you can correct any.
- "Add September month report in my longbook": The month's statements recorded, the charges they prove confirmed, and each account's balance set. longbook draws that month's report, with "Not yet confirmed" beside the total until every charge in it is confirmed.

### Keeping it current

- "Add email invoices in my longbook": This month's bank alerts, receipts, bills and money in from your mail, each recorded once, with nothing doubled. Needs a mail connector in your AI.
- "Go to longbook.app/mcp and set up a daily email round for my longbook, as longbook recommends": Your AI reads your mail every morning at 6 and records the money that moved, so your longbook stays current without you asking. Needs a mail connector and scheduled tasks in your AI.
- "Add document invoices in my longbook": The invoices, receipts and bills you attach, or keep in the longbook documents folder, recorded as charges with the file's name in their notes, without doubling what your statements or mail already recorded.
- "Add a commitment in my longbook": A new commitment planned ahead, or a one-time expense recorded, on the account and for the person you name.

### Reading it

- "What's my next commitment in my longbook": The next day you owe something, and what is due that day. Nothing in your longbook changes.
- "What is coming in my longbook in the next 30 days?": Everything due in the next 30 days, or the period you name, by day, with the total per currency. Nothing in your longbook changes.
- "What did I spend in July in my longbook?": What you spent in that month, and what is not yet confirmed. Through the Mac connection this comes from longbook's report; otherwise from your charges, including ones nobody has confirmed yet. Nothing in your longbook changes.
- "What renews this year in my longbook?": Your yearly, half-yearly and quarterly payments due in the next 12 months, or before the day you name, in date order. Nothing in your longbook changes.
- "Make my weekly longbook page": One page for the week: what is due in the next 7 days, what you spent last week, what renews in the next 30 days, and anything waiting for you. Nothing in your longbook changes.

### Reports

- "Create a report in my longbook": A report over the days, accounts, people and categories you choose, on the Reports screen the next time the app is open. It counts confirmed charges only.
- "Make a report of my Goa trip in my longbook": A report of your trip's spending on the Reports screen, filling in as the trip's charges are confirmed.

### Housekeeping

- "Tidy my longbook": Doubled charges, bank-style names and odd categories found, and fixed once you approve each change.
- "Reorganise my longbook": Your whole longbook, once over: names as you would say them, every row categorised, people and accounts linked, doubles merged, nothing lost. The whole pass waits in Proposals.
- "Set up a morning brief for my longbook": A short summary every morning of what is due today and in the next 30 days. Nothing in your longbook changes. Needs scheduled tasks in your AI.

### From your email

- "Find subscriptions from my email and add them in my longbook": Your subscriptions found in the last 12 months of your mail: each one with its receipts as charges, the ones that clearly repeat planned ahead, and trials and price changes as the mails state them. Needs a mail connector in your AI.
- "Find expenses from my email and add them in my longbook": This month's spending from your mail's bank alerts and receipts, each recorded once as a paid charge. Needs a mail connector in your AI.
- "Find invoices from my email and add them in my longbook": The invoices and receipts in the last 12 months of your mail, each recorded once as a charge, paid or due. Needs a mail connector in your AI.
- "Find insurances from my email and add them in my longbook": Your insurance policies found in your mail: each with its premiums as charges, its next premium planned, and its policy details in its notes. Needs a mail connector in your AI.
- "Find purchases from my email and add them in my longbook": Your orders from the last 3 months of your mail, each recorded once as a paid charge named for what you bought. Needs a mail connector in your AI.
- "Find bills from my email and add them in my longbook": Your bills from the last 3 months of your mail: what you paid recorded, what is due planned, and each card's monthly bill kept apart from spending. Needs a mail connector in your AI.
- "Find loans and EMIs from my email and add them in my longbook": Your loans and EMIs found in your mail: each loan with its EMIs as charges, planned ahead to its end when the mails state it. Needs a mail connector in your AI.
- "Find travel bookings from my email and add them in my longbook": Your bookings from the last 12 months of your mail: flights, trains, hotels and cabs, each recorded as a paid charge with where and when. Needs a mail connector in your AI.
- "Find money in from my email and add them in my longbook": Your salary, refunds, interest and other money in from the last 12 months of your mail, kept apart from spending. Needs a mail connector in your AI.

## All of the MCP server's tools

Every write goes through the same validator the apps use and lands in [Proposals](https://longbook.app/features/review-every-change-your-ai-makes.md) with its writer named. The folder also carries a schema and a guide, `longbook.schema.json` and `llms.txt`, so any AI reads and writes it correctly.

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

`create_report` asks longbook to draw a report over the days, accounts, people and categories you name. It appears on the Reports screen the next time the app is open, not in Proposals.

## About longbook

longbook is a memory for your financial commitments: subscriptions, insurance, rent, loans and every other payment that comes back. It runs on iPhone and Mac and keeps its records as plain files in your own iCloud.

The next payment stays in view on the iPhone widget and in the Mac menu bar. Your AI can read your longbook and update it through longbook's MCP server, and every change it makes shows in Proposals, to keep or undo.

- Download for Mac: https://longbook.app/download/
- Download for iPhone: https://testflight.apple.com/join/g66Nd3Na
