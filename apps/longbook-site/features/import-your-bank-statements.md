# Import your bank statements

> Bank and card statements read into charges, up to five at once. Repeating payments and people in them become commitments and members. The import is saved once, right after reading, and can be taken back whole.

- Page: https://longbook.app/features/import-your-bank-statements/
- Group: Import
- Platforms: iPhone and Mac

## On the screen

**Import a statement** after a statement is read. On iPhone, the account and its balance, eight charges and one money in from August 2026, and the person and the repeating payments offered as a member and commitments; on Mac, each line with its date, category, amount and the bank's own words, and a box to untick.

![Importing a bank statement in longbook on iPhone: eight charges and one money in read from an August 2026 statement, with the person and the repeating payments found in it offered as a member and commitments.](https://longbook.app/features/img/iphone-import-review.jpg)

![Importing a bank statement in longbook on Mac: each line read from the statement with its date, category, amount and the bank's own words, and a box to untick.](https://longbook.app/features/img/mac-import-review.jpg)

## What it does

### PDF, CSV and Excel

**Securely Upload Statement** takes up to five files at once, as the bank sends them: PDF, CSV, plain text or Excel, a scanned PDF included. They are read together, and each lands on its own account. A locked PDF opens with its password on the device, and the password is not kept. A copy of each file goes into your longbook's documents folder.

### What it found, one step at a time

Each line comes back with a name, date, amount and category. The steps then show what was saved: past expenses, people, accounts, commitments, transfers and earnings, up to four cards on a step and every card behind See All. A kind with nothing to show is left out, and a line an earlier statement already recorded is left out too. **Undo Import** on the first step takes the whole import back.

### Commitments and members

Payments that repeat become commitments, the people a statement pays become members, and the accounts that transfers and card payments go to become accounts, all matched to what longbook already holds. **Add accounts and people found in statements**, on unless turned off, decides whether those people and accounts are added. A line that belongs to a recurring commitment longbook already holds is recorded as that commitment's charge. Each month the statement fills gets a [monthly report](https://longbook.app/features/create-monthly-expense-reports.md).

## Why it exists

A year of bank statements already holds the rent, the subscriptions, the premiums and the salaries paid to people. Reading them fills longbook with that year's charges, and names the payments that repeat as commitments to fill in.

## Questions

### Where does the statement go?

longbook reads the file on your device first. When the lines it reads add up to the balances printed, only those lines and the top of the statement go to longbook's server, with long numbers cut to their last four digits. Otherwise the file goes a few pages or rows at a time, a PDF rebuilt page by page on your device so only the pages travel. From the server it goes to Anthropic's Claude, which first checks that it is a statement and then reads it. The server keeps neither the statement nor the charges. Reading a statement needs a signed-in longbook account; [longbook Cloud](https://longbook.app/features/what-is-longbook-cloud.md) reads more of them each month.

### Can my own AI read the statement instead?

Yes. **Use My Own AI** gives a prompt for Claude or another AI, which reads the statement and writes into longbook; what it writes waits in Proposals. The same route opens when longbook's server has read what it can for your account for now.

### Does longbook connect to my bank?

No. The statement is a file downloaded from the bank and picked in longbook. Nothing is read from a bank account directly.

## Related features

- [Create monthly expense reports](https://longbook.app/features/create-monthly-expense-reports.md): A report for every month with a confirmed charge: the total, accounts, categories and every charge.
- [Manage your expenses](https://longbook.app/features/manage-your-expenses.md): Every charge in one list, one-time or recurring, with its date, category and account.
- [Automate longbook with Claude](https://longbook.app/features/automate-longbook-with-claude.md): Claude reads your longbook and keeps it up to date through longbook's MCP server.
- [All features of longbook](https://longbook.app/features.md)

## About longbook

longbook is a memory for your financial commitments: subscriptions, insurance, rent, loans and every other payment that comes back. It runs on iPhone and Mac and keeps its records as plain files in your own iCloud.

The next payment stays in view on the iPhone widget and in the Mac menu bar. Your AI can read your longbook and update it through longbook's MCP server, and every change it makes shows in Proposals, to keep or undo.

- Download for Mac: https://github.com/MXmaster2s/longbook-code/releases/latest/download/longbook.dmg
- iPhone beta: https://testflight.apple.com/join/g66Nd3Na
