---
slug: log-expenses-from-gmail
order: 13
group: import
title: Log expenses from Gmail
seo_title: Log expenses from Gmail with Claude
description: Claude reads your Gmail every morning at 6am and records bank alerts, receipts and bills in longbook, each one waiting in Changes to keep or undo.
card: Claude reads your email every morning and records the charges it finds, each one waiting in Changes.
platforms: iphone, mac
iphone: iphone-automations
mac: mac-automations
aliases: import-expenses-from-gmail, daily-email-round
related: automate-longbook-with-claude, review-every-change-your-ai-makes, import-your-bank-statements
labels: Automations, Claude automation, Copy the prompt, Keep All, Undo All, Allow suggested changes
---

Claude reads your Gmail every morning and records what it finds in longbook: bank alerts, receipts, bills that are due and money in. Each entry waits in Changes.

## On the screen

**Automations** on iPhone and Mac: the **Claude automation** card with its one-line prompt and **Copy the prompt**, below the longbook MCP server switch. The Mac also shows the Shortcuts action for bank messages and the Siri and Spotlight commands.

## What it does

### One prompt, once

**Copy the prompt** gives one line to paste into Claude, with the longbook and mail connectors on. Claude schedules itself for 6am each day and runs the first round at once.

### Each morning's mail

Each round reads the last day of mail for bank and card alerts, receipts, bills that are due, money in, renewal notices and card statements. A payment for a commitment longbook already holds is recorded as that commitment's charge, and a card bill as a transfer, kept out of spending. One-time passwords, sign-in alerts and offers are skipped.

### Waiting in Changes

Every entry keeps a reference to the email it came from and waits in [Changes](/features/review-every-change-your-ai-makes/), with **Keep All** and **Undo All**, or an edit or delete per row. Each month backed by email gets a [monthly report](/features/create-monthly-expense-reports/).

## Why it exists

Most payments leave an email behind: a bank alert, a receipt, a bill. A daily round turns that mail into records without typing, and every entry stays open to review in Changes.

## Questions

### Does longbook read my email?

No. Claude reads it through its own mail connector, such as Gmail, and writes to longbook through the longbook connector. longbook itself never connects to a mailbox.

### What does the round need?

A signed-in longbook account with the MCP server on and **Allow suggested changes** turned on, and Claude with the longbook connector, a mail connector and scheduled tasks. Without scheduled tasks, Claude can run the same round on request. The setup is on [Automate longbook with Claude](/features/automate-longbook-with-claude/).

### Can the same payment be recorded twice?

The round reads what longbook already holds before it writes, and skips an email whose amount and day are already recorded. Claude makes the check, and anything that slips through shows in Changes, to undo.
