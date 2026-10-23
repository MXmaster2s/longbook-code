---
slug: view-expenses-from-multiple-bank-accounts
order: 4
group: track
title: View expenses from multiple bank accounts
seo_title: Track expenses across multiple bank accounts
description: Every bank account and card in one place, with its balance, the commitments it pays and its next charge. longbook for iPhone and Mac, with no bank connection.
card: Every bank account and card with its balance, the commitments it pays and its next charge.
platforms: iphone, mac
iphone: iphone-accounts
mac: mac-accounts
aliases: multiple-bank-accounts, track-multiple-bank-accounts
related: add-your-accounts-and-members, get-spending-insights, import-your-bank-statements
labels: Accounts, Balance, Owner, Linked to, Show All
---

Every bank account, card and wallet in one place, with its balance, the commitments it pays and the next charge due from it.

## On the screen

**Accounts** on iPhone and Mac: two savings accounts and a credit card, one row each with its type and balance. A tap on iPhone, or a click in the Mac's table, opens the account's card: the balance and its date, the person it belongs to, the account it is linked to, and the next commitment with the total for the next 12 months.

## What it does

### One card per account

Each account card counts its commitments and past charges, shows its balance on a given day, and names the next commitment due. The total for the next 12 months is per currency and counts spending only, not money in or transfers.

### Cards and the accounts that pay them

A card links to the bank account that pays it and is listed right after it. Each account has one **Owner** at most. The name printed on a card goes in the account's notes as a line such as `Card name: Platinum Reserve`, never the card's number.

### Spending by account

The dashboard's **ACCOUNTS** card splits a month's spending by account, and each account in it opens that month's list for the account. **Show All** lists an account's commitments; **Past** lists every charge made from it.

## Why it exists

Recurring payments come out of several places: a salary account, two or three cards, a UPI app. longbook groups them by account, so it is clear which one pays what and what each one's commitments come to over the next 12 months.

## Questions

### Does longbook connect to my bank?

No. Accounts are ticked at setup, typed in, read from a statement, or filled in by your AI. A balance changes only when you, a statement or your AI records one.

### Can a statement fill in an account?

Yes. [Importing a statement](/features/import-your-bank-statements/) files its lines under the account the statement is from, and adds that account if it is missing. When the statement shows a closing balance, the account takes it, with its date.

### Can Claude answer questions about my accounts?

Yes. Through longbook's MCP server, Claude, ChatGPT or another assistant reads each account and the spending from it over any dates. The setup is on [Automate longbook with Claude](/features/automate-longbook-with-claude/).
