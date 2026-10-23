---
name: longbook-setup
description: >
  Use for requests like "set up my longbook", "import my bank statement", "add last month's
  statement", "categorise my expenses", "complete September in my longbook", "Read my 12-month
  bank statement and help me set up my longbook", "Add my statement in my longbook", "Update my
  longbook from my statements", "Add my statement", even when the user does not name longbook.
  Sets up the user's longbook, their record of subscriptions, bills, rent, salaries, loans and
  other commitments, from bank and card statements; adds later statements, categorises it, and
  completes a month so longbook can draw its report. Works through the longbook connector
  (https://longbook.app/mcp).
---

# longbook: Set up

longbook is the user's financial memory: every commitment they pay, its charges past and
planned, their accounts and the people payments are for. Sets up the user's longbook, their
record of subscriptions, bills, rent, salaries, loans and other commitments, from bank and card
statements; adds later statements, categorises it, and completes a month so longbook can draw
its report. Each prompt below has a procedure on the longbook server; follow it rather than
improvising one.

## How to run one

1. Pick the prompt below that matches what the user asked, in our words or theirs.
2. Call the longbook connector's `read_guide` with the prompt's name, for example
   `read_guide("set-up-my-longbook")`. It returns the procedure, step by step, and the guide
   chapter it builds on.
3. Follow that procedure and the guide's rules. Never write a card number, a full account
   number, a PIN or a password.
4. If no longbook tools are available, say the longbook connector is needed: in Claude,
   Settings, then Connectors, then Add custom connector, with the address
   https://longbook.app/mcp, signing in with the longbook account. Installing this plugin adds the
   connector too.

## The prompts

### Set up my longbook

Name: `set-up-my-longbook`

The user says: "Read my 12-month bank statement and help me set up my longbook", "Set up my
longbook".

Result: Your longbook filled from your statements: every charge on record, the names you picked
in setup filled in where your statements or your answers show them, each account's closing
balance set, the charges that clearly repeat planned ahead, and the rest set to repeat once you
confirm them. It waits in the Changes screen for you to keep.

Attachments: bank and card statements, ideally the last 12 months, as a PDF with text, an .xlsx
or a CSV. Card statements matter too: a bank statement shows only the card bill payment, not
what the card was spent on.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Add my statement

Name: `add-my-statement`

The user says: "Add my statement in my longbook", "Update my longbook from my statements", "Add
my statement".

Result: Every charge on the statement recorded as paid, money in kept apart, the account's
balance updated, the charges that clearly repeat set to continue, and the rest once you confirm
them.

Attachments: bank or card statements, as a PDF with text, an .xlsx or a CSV. A scanned PDF, a
photo or an older .xls file in the documents folder cannot be read: save it as .xlsx or CSV, or
attach it in the chat.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Categorise my longbook

Name: `categorise-my-longbook`

The user says: "Categorise my longbook".

Result: Every commitment without a category gets one. Your AI shows you the ones it guessed, so
you can correct any.

Attachments: none.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Add a month report in my longbook

Name: `add-a-month-report-in-my-longbook`

The user says: "Add September month report in my longbook".

Result: The month's statements recorded, the charges they prove confirmed, and each account's
balance set. longbook draws that month's report, with "Not yet confirmed" beside the total
until every charge in it is confirmed.

Attachments: the bank and card statements that cover the month.

Writes to the longbook: yes; it waits in the app's Changes screen.
