---
name: longbook-keep-current
description: >
  Use for requests like "add this month's bills from my email", "check my email every morning
  for payments", "add these invoices", "add my new gym membership", "I spent 2,000 on
  groceries", "Add email invoices in my longbook", "Go to longbook.app/mcp and set up a daily
  email round for my longbook, as longbook recommends", "Add document invoices in my longbook",
  "Add a commitment in my longbook", even when the user does not name longbook. Keeps the
  user's longbook current: this month's invoices, bills and money in from their email, a daily
  email round, invoices and receipts kept as files, and a new commitment or expense. Works
  through the longbook connector (https://longbook.app/mcp).
---

# longbook: Keep it current

longbook is the user's financial memory: every commitment they pay, its charges past and
planned, their accounts and the people payments are for. Keeps the user's longbook current:
this month's invoices, bills and money in from their email, a daily email round, invoices and
receipts kept as files, and a new commitment or expense. Each prompt below has a procedure on
the longbook server; follow it rather than improvising one.

## How to run one

1. Pick the prompt below that matches what the user asked, in our words or theirs.
2. Call the longbook connector's `read_guide` with the prompt's name, for example
   `read_guide("add-email-invoices-in-my-longbook")`. It returns the procedure, step by step, and the guide
   chapter it builds on.
3. Follow that procedure and the guide's rules. Never write a card number, a full account
   number, a PIN or a password.
4. If no longbook tools are available, say the longbook connector is needed: in Claude,
   Settings, then Connectors, then Add custom connector, with the address
   https://longbook.app/mcp, signing in with the longbook account. Installing this plugin adds the
   connector too.

## The prompts

### Add email invoices in my longbook

Name: `add-email-invoices-in-my-longbook`

The user says: "Add email invoices in my longbook".

Result: This month's bank alerts, receipts, bills and money in from your mail, each recorded
once, with nothing doubled.

Attachments: none. The user's mail must be connected to their AI.

Needs: the user's mail connected to their AI.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Set up a daily longbook email round

Name: `set-up-a-daily-longbook-email-round`

The user says: "Go to longbook.app/mcp and set up a daily email round for my longbook, as
longbook recommends".

Result: Your AI reads your mail every morning at 6 and records the money that moved, so your
longbook stays current without you asking.

Attachments: none. The user's mail must be connected, and their AI's app must support scheduled
tasks.

Needs: the user's mail connected to their AI, and scheduled tasks in the AI's app.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Add document invoices in my longbook

Name: `add-document-invoices-in-my-longbook`

The user says: "Add document invoices in my longbook".

Result: The invoices, receipts and bills you attach, or keep in the longbook documents folder,
recorded as charges with the file's name in their notes, without doubling what your statements
or mail already recorded.

Attachments: invoices, receipts and bills: attached in the chat, or kept in the longbook
documents folder as a PDF with text, an .xlsx or a CSV. A photo or a scanned receipt can be
read only when attached in the chat.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Add a commitment or an expense

Name: `add-a-commitment-or-an-expense`

The user says: "Add a commitment in my longbook", "Add an expense in my longbook", "Add my new
gym membership to my longbook".

Result: A new commitment planned ahead, or a one-time expense recorded, on the account and for
the person you name.

Attachments: none. A receipt or a sign-up mail helps, if the user has one.

Writes to the longbook: yes; it waits in the app's Changes screen.
