---
slug: keep-your-longbook-in-your-own-icloud
order: 20
group: devices
title: Keep your longbook in your own iCloud
seo_title: Private expense tracker with iCloud sync
description: longbook keeps your subscriptions, bills and expenses as plain JSON files in your own iCloud Drive, synced by Apple to your iPhone and Mac.
card: Plain JSON files in a longbook folder in your own iCloud Drive, synced by Apple to your iPhone and Mac.
platforms: iphone, mac
iphone: iphone-data-privacy
mac: mac-data-privacy
aliases: icloud, your-data, data-and-privacy
related: review-every-change-your-ai-makes, automate-longbook-with-claude, manage-your-subscriptions
labels: Data & privacy, Move to iCloud, Back Up Now, Choose Folder, Delete Account
---

Your subscriptions, bills and charges live in one folder of plain JSON files in your own iCloud Drive, synced by Apple to your iPhone and Mac.

## On the screen

**Data & privacy** on iPhone and Mac, for a folder kept on the device: the data file, the history kept, where the folder lives, **Move to iCloud** and **Back Up Now**. The Mac also shows what the file cannot hold and what longbook keeps in your account.

## What it does

### One folder of plain files

The data is kept in `financial_memory.json`, next to the monthly reports, your AI's insights and a history of earlier versions. Any tool that reads JSON can open it. **Back Up Now** creates a copy of the file exactly as stored, to share or keep.

### Synced by Apple

The folder appears in iCloud Drive as longbook and syncs to every iPhone and Mac signed in to the same iCloud account. It opens in Files on iPhone and in Finder on Mac. **Move to iCloud** moves a folder kept on one device into iCloud Drive, and checks the copy before anything is removed.

### No card numbers

The format has no field for a full card number, a CVV, an expiry, a PIN or a password, and a save carrying one is refused. An account keeps at most the last four digits of its number.

## Why it exists

A record of every payment is personal, and it outlasts any one app. longbook keeps it as plain files in storage you already own, readable by your AI and by any tool that opens JSON. longbook never connects to a bank, and the folder stays yours to copy, move or delete.

## Questions

### Does anything leave the folder?

Only what a feature needs. The hosted copy for AI connectors exists while the longbook MCP server is on, and turning the server off deletes it. A shared report stays online until it expires or sharing stops. An imported statement is read by Anthropic's Claude through longbook's server, with OpenAI only when Claude can't answer, and neither keeps it. Each tag's kind, name and icon is kept in your account, never a commitment's name, amount, date or note. An AI you connect reads what it asks for, under its own provider's terms.

### Does longbook need iCloud?

No. At setup, **Choose Folder** keeps longbook in a folder you pick instead. Syncing between iPhone and Mac comes from iCloud Drive.

### What happens to the folder when the account is deleted?

It stays where it is. **Delete Account** removes your email and anything hosted. The folder itself is deleted in Files or Finder, like any other folder.
