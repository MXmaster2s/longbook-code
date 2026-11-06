---
slug: automate-longbook-with-siri-and-shortcuts
order: 15
group: automate
title: Automate longbook with Siri and Shortcuts
seo_title: Log expenses with Siri and Shortcuts
description: Add an expense or a bill by voice with Siri, hear your next payment, and record charges from bank messages with a Shortcuts action. On iPhone and Mac.
card: Siri adds expenses and commitments by voice; a Shortcuts action records charges from a bank's messages.
platforms: iphone, mac
iphone: iphone-automations
mac: mac-automations
aliases: automate-your-longbook-with-your-siri-and-shortcuts, siri-and-shortcuts, siri-shortcuts
related: add-longbook-widget-to-your-iphone, manage-your-expenses, review-every-change-your-ai-makes
labels: Automations, Add an expense in my longbook, Add a commitment in my longbook, What do I pay next in my longbook, Record a charge from a message
---

Siri adds expenses and commitments to longbook by voice and says what is due next. A Shortcuts action records charges from a bank's messages.

## On the screen

**Automations** on iPhone and Mac: the longbook MCP server switched on, then the Claude email automation with its prompt to copy. The Mac shows the whole screen: the **Record a charge from a message** action for the Shortcuts app, and the three commands that work with Siri and Spotlight.

## What it does

### Expenses and commitments by voice

**Add an expense in my longbook** records a payment already made; **Add a commitment in my longbook** adds a one-time payment due on a day. Siri asks for the name, the amount and the day. An amount said in rupees, dollars, pounds, euros, dirhams or yen keeps that currency; any other amount takes the currency most of your commitments use.

### The next payment, spoken

**What do I pay next in my longbook** names each commitment due on the next day anything is owed, with its amount, and says whether that day is today, tomorrow or how many days away.

### Charges from bank messages

The **Record a charge from a message** action reads a bank's message on the device: the amount, the day, the payee, and the account whose name holds the same last four digits. A credit is recorded as money in. One-time passwords, declined payments and balance alerts record nothing, and the same message handed over twice records one charge.

## Why it exists

Many payments are made away from a computer: a cab fare, a shop bill, a transfer from the phone. Siri and the Shortcuts action record them there, without opening longbook. Everything they add shows in [Proposals](/features/review-every-change-your-ai-makes/) under the name Siri or bank message, to keep or undo.

## Questions

### Can Siri add a monthly or yearly commitment?

No. Siri adds a one-time commitment due on the day you name. A monthly, yearly or custom rhythm is set in the commitment's form in the app.

### Does the Shortcuts action read my messages on its own?

No. The action reads only the text a shortcut hands it. Combined with a Messages or Mail action in the Shortcuts app, it runs as part of an automation you build.

### Which longbook do Siri and Shortcuts write to?

The longbook folder in iCloud Drive. They read and write it without opening the app, so iCloud Drive has to be on for that iPhone or Mac. A longbook kept in a folder chosen elsewhere, or only on the device, is out of their reach.
