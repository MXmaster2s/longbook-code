# View expenses from multiple bank accounts

> Every bank account, card and wallet in one place, with its balance, the commitments it pays and the next charge due from it.

- Page: https://longbook.app/features/view-expenses-from-multiple-bank-accounts/
- Group: Track
- Platforms: iPhone and Mac

## On the screen

**Accounts** on iPhone and Mac: two savings accounts and a credit card, one row each with its type and balance. A tap on iPhone, or a click in the Mac's table, opens the account's card: the balance and its date, the person it belongs to, the account it is linked to, and the next commitment with the total for the next 12 months.

![The Accounts screen of longbook on iPhone: a bank account and a credit card, each with its balance, owner, linked account and next commitment.](https://longbook.app/features/img/iphone-accounts.jpg)

![The Accounts screen of longbook on Mac: two savings accounts and a credit card side by side, with balances, owners, linked accounts and the next twelve months of commitments.](https://longbook.app/features/img/mac-accounts.jpg)

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

Yes. [Importing a statement](https://longbook.app/features/import-your-bank-statements.md) files its lines under the account the statement is from, and adds that account if it is missing. When the statement shows a closing balance, the account takes it, with its date.

### Can Claude answer questions about my accounts?

Yes. Through longbook's MCP server, Claude, ChatGPT or another assistant reads each account and the spending from it over any dates. The setup is on [Automate longbook with Claude](https://longbook.app/features/automate-longbook-with-claude.md).

## Related features

- [Add your accounts and members](https://longbook.app/features/add-your-accounts-and-members.md): The people your commitments are for, and the accounts that pay them.
- [Get spending insights](https://longbook.app/features/get-spending-insights.md): The next payment, the month's total expenses, and the split by account and by category.
- [Import your bank statements](https://longbook.app/features/import-your-bank-statements.md): Bank statements read into charges, repeating payments and people, five at once, every line reviewed first.
- [All features of longbook](https://longbook.app/features.md)

## About longbook

longbook is a memory for your financial commitments: subscriptions, insurance, rent, loans and every other payment that comes back. It runs on iPhone and Mac and keeps its records as plain files in your own iCloud.

The next payment stays in view on the iPhone widget and in the Mac menu bar. Your AI can read your longbook and update it through longbook's MCP server, and every change it makes shows in Proposals, to keep or undo.

- Download for Mac: https://longbook.app/download/
- Download for iPhone: https://testflight.apple.com/join/g66Nd3Na
