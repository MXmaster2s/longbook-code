---
slug: import-your-bank-statements
order: 12
group: import
title: Import your bank statements
seo_title: Import bank statements to track expenses
description: Import bank and card statements as PDF, CSV or Excel, five at once. longbook reads the charges, finds repeating payments and people, and shows every line.
card: Bank statements read into charges, repeating payments and people, five at once, every line reviewed first.
platforms: iphone, mac
iphone: iphone-import-review
mac: mac-import-review
aliases: import-your-reports-from-your-bank-statements, import-bank-statements, bank-statement-import
related: create-monthly-expense-reports, manage-your-expenses, automate-longbook-with-claude
labels: Import a statement, Securely Upload Statement, Select All, Deselect All, Use My Own AI
---

Bank and card statements read into charges, up to five at once. Repeating payments and people in them are offered as commitments and members, and nothing is recorded before the review.

## On the screen

**Import a statement** after a statement is read. On iPhone, the account and its balance, eight charges and one money in from August 2026, and the person and the repeating payments offered as a member and commitments; on Mac, each line with its date, category, amount and the bank's own words, and a box to untick.

## What it does

### PDF, CSV and Excel

**Securely Upload Statement** takes up to five files at once, as the bank sends them: PDF, CSV, plain text or Excel, a scanned PDF included. They are read together, and each lands on its own account. A locked PDF opens with its password on the device, and the password is not kept. A copy of each file goes into your longbook's documents folder.

### Every line, reviewed

Each line comes back with a name, date, amount and category, and money in is marked as money in. Transfers between your own accounts and card bill payments start unticked, and a line an earlier statement already recorded is left out. A name, a category or a person can be corrected and any line unticked, or **Select All** and **Deselect All** answer every line at once.

### Commitments and members

Payments that repeat are offered as commitments to fill in, and the people a statement pays as members. A line that belongs to a recurring commitment longbook already holds is recorded as that commitment's charge. What is recorded shows in [Proposals](/features/review-every-change-your-ai-makes/), and each month the statement fills gets a [monthly report](/features/create-monthly-expense-reports/).

## Why it exists

A year of bank statements already holds the rent, the subscriptions, the premiums and the salaries paid to people. Reading them fills longbook with that year's charges, and names the payments that repeat as commitments to fill in.

## Questions

### Where does the statement go?

To longbook's server, a few pages or rows at a time, and from there to Anthropic's Claude, which first checks that the file is a statement and then reads it. A PDF is rebuilt page by page on your device before it goes, so only the pages travel. The server keeps neither the statement nor the charges. Reading a statement needs a signed-in longbook account; [longbook Cloud](/features/what-is-longbook-cloud/) reads more of them each month.

### Can my own AI read the statement instead?

Yes. **Use My Own AI** gives a prompt for Claude or another AI, which reads the statement and writes into longbook; what it writes waits in Proposals. The same route opens when longbook's server has read what it can for your account for now.

### Does longbook connect to my bank?

No. The statement is a file downloaded from the bank and picked in longbook. Nothing is read from a bank account directly.
