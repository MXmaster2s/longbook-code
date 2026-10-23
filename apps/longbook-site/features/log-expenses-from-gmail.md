# Log expenses from Gmail

> Claude reads your Gmail every morning and records what it finds in longbook: bank alerts, receipts, bills that are due and money in. Each entry waits in Changes.

- Page: https://longbook.app/features/log-expenses-from-gmail/
- Group: Import
- Platforms: iPhone and Mac

## On the screen

**Automations** on iPhone and Mac: the **Claude automation** card with its one-line prompt and **Copy the prompt**, below the longbook MCP server switch. The Mac also shows the Shortcuts action for bank messages and the Siri and Spotlight commands.

![The Automations screen of longbook on iPhone: the longbook MCP server switched on, AI suggestions allowed, and the Claude email automation with its prompt.](https://longbook.app/features/img/iphone-automations.jpg)

![The Automations screen of longbook on Mac: the longbook MCP server switched on, the Claude email automation, the Shortcuts action for bank messages, and the Siri and Spotlight commands.](https://longbook.app/features/img/mac-automations.jpg)

## What it does

### One prompt, once

**Copy the prompt** gives one line to paste into Claude, with the longbook and mail connectors on. Claude schedules itself for 6am each day and runs the first round at once.

### Each morning's mail

Each round reads the last day of mail for bank and card alerts, receipts, bills that are due, money in, renewal notices and card statements. A payment for a commitment longbook already holds is recorded as that commitment's charge, and a card bill as a transfer, kept out of spending. One-time passwords, sign-in alerts and offers are skipped.

### Waiting in Changes

Every entry keeps a reference to the email it came from and waits in [Changes](https://longbook.app/features/review-every-change-your-ai-makes.md), with **Keep All** and **Undo All**, or an edit or delete per row. Each month backed by email gets a [monthly report](https://longbook.app/features/create-monthly-expense-reports.md).

## Why it exists

Most payments leave an email behind: a bank alert, a receipt, a bill. A daily round turns that mail into records without typing, and every entry stays open to review in Changes.

## Questions

### Does longbook read my email?

No. Claude reads it through its own mail connector, such as Gmail, and writes to longbook through the longbook connector. longbook itself never connects to a mailbox.

### What does the round need?

A signed-in longbook account with the MCP server on and **Allow suggested changes** turned on, and Claude with the longbook connector, a mail connector and scheduled tasks. Without scheduled tasks, Claude can run the same round on request. The setup is on [Automate longbook with Claude](https://longbook.app/features/automate-longbook-with-claude.md).

### Can the same payment be recorded twice?

The round reads what longbook already holds before it writes, and skips an email whose amount and day are already recorded. Claude makes the check, and anything that slips through shows in Changes, to undo.

## Related features

- [Automate longbook with Claude](https://longbook.app/features/automate-longbook-with-claude.md): Claude reads your longbook and keeps it up to date through longbook's MCP server.
- [Review every change your AI makes](https://longbook.app/features/review-every-change-your-ai-makes.md): Every row your AI, Siri or an import writes shows in Changes, to keep, edit or undo.
- [Import your bank statements](https://longbook.app/features/import-your-bank-statements.md): Bank statements read into charges, repeating payments and people, five at once, every line reviewed first.
- [All features of longbook](https://longbook.app/features.md)

## About longbook

longbook is a memory for your financial commitments: subscriptions, insurance, rent, loans and every other payment that comes back. It runs on iPhone and Mac and keeps its records as plain files in your own iCloud.

The next payment stays in view on the iPhone widget and in the Mac menu bar. Your AI can read your longbook and update it through longbook's MCP server, and every change it makes shows in Changes, to keep or undo.

- Download for Mac: https://testflight.apple.com/join/g66Nd3Na
- Download for iPhone: https://testflight.apple.com/join/g66Nd3Na
