# Import your bank statements

> Bank and card statements read into charges, up to five at once. Repeating payments and people in them are offered as commitments and members, and nothing is recorded before the review.

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

### Every line, reviewed

Each line comes back with a name, date, amount and category, and money in is marked as money in. Transfers between your own accounts and card bill payments start unticked, and a line an earlier statement already recorded is left out. A name, a category or a person can be corrected and any line unticked, or **Untick all** answers a whole group at once.

### Commitments and members

Payments that repeat are offered as commitments to fill in, the people a statement pays as members, and the accounts that transfers and card payments go to as accounts, all on one list of the app's own cards, every item ticked and matched to what longbook already holds. **Add accounts and people found in statements**, on unless turned off, decides whether those people and accounts start ticked. A line that belongs to a recurring commitment longbook already holds is recorded as that commitment's charge. What is recorded shows in [Proposals](https://longbook.app/features/review-every-change-your-ai-makes.md), and each month the statement fills gets a [monthly report](https://longbook.app/features/create-monthly-expense-reports.md).

## Why it exists

A year of bank statements already holds the rent, the subscriptions, the premiums and the salaries paid to people. Reading them fills longbook with that year's charges, and names the payments that repeat as commitments to fill in.

## Questions

### Where does the statement go?

To longbook's server, a few pages or rows at a time, and from there to Anthropic's Claude, which first checks that the file is a statement and then reads it. A PDF is rebuilt page by page on your device before it goes, so only the pages travel. The server keeps neither the statement nor the charges. Reading a statement needs a signed-in longbook account; [longbook Cloud](https://longbook.app/features/what-is-longbook-cloud.md) reads more of them each month.

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

- Download for Mac: https://testflight.apple.com/join/g66Nd3Na
- Download for iPhone: https://testflight.apple.com/join/g66Nd3Na
