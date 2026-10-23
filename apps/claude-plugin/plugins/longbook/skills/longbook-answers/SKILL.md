---
name: longbook-answers
description: >
  Use for requests like "what bills are coming up this week", "what do I pay next", "how much
  did I spend in September", "which premiums renew this year", "what subscriptions renew this
  month", "give me my week in longbook", "What's my next commitment in my longbook", "What is
  coming in my longbook in the next 30 days?", "What is coming in the next 30 days?", even when
  the user does not name longbook. Answers questions about the user's bills, subscriptions,
  payments and spending from their longbook: what is due next or this week, what is coming in
  the next 30 days, what a month cost, and what renews this year. Works through the longbook
  connector (https://longbook.app/mcp).
---

# longbook: Answers

longbook is the user's financial memory: every commitment they pay, its charges past and
planned, their accounts and the people payments are for. Answers questions about the user's
bills, subscriptions, payments and spending from their longbook: what is due next or this week,
what is coming in the next 30 days, what a month cost, and what renews this year. Each prompt
below has a procedure on the longbook server; follow it rather than improvising one.

## How to run one

1. Pick the prompt below that matches what the user asked, in our words or theirs.
2. Call the longbook connector's `read_guide` with the prompt's name, for example
   `read_guide("what-do-i-pay-next")`. It returns the procedure, step by step, and the guide
   chapter it builds on.
3. Follow that procedure and the guide's rules. Never write a card number, a full account
   number, a PIN or a password.
4. If no longbook tools are available, say the longbook connector is needed: in Claude,
   Settings, then Connectors, then Add custom connector, with the address
   https://longbook.app/mcp, signing in with the longbook account. Installing this plugin adds the
   connector too.

## The prompts

### What do I pay next?

Name: `what-do-i-pay-next`

The user says: "What's my next commitment in my longbook", "What do I pay next?".

Result: The next day you owe something, and what is due that day. Nothing in your longbook
changes.

Attachments: none.

Writes to the longbook: no.

### What is coming in the next 30 days?

Name: `what-is-coming-in-the-next-30-days`

The user says: "What is coming in my longbook in the next 30 days?", "What is coming in the
next 30 days?", "What do I owe this month?".

Result: Everything due in the next 30 days, or the period you name, by day, with the total per
currency. Nothing in your longbook changes.

Attachments: none.

Writes to the longbook: no.

### What did I spend in a month?

Name: `what-did-i-spend-in-a-month`

The user says: "What did I spend in July in my longbook?", "What did I spend in July?".

Result: What you spent in that month, and what is not yet confirmed. Through the Mac connection
this comes from longbook's report; otherwise from your charges, including ones nobody has
confirmed yet. Nothing in your longbook changes.

Attachments: none.

Writes to the longbook: no.

### What renews this year?

Name: `what-renews-this-year`

The user says: "What renews this year in my longbook?", "What renews this year?", "Which
premiums are due before March?".

Result: Your yearly, half-yearly and quarterly payments due in the next 12 months, or before
the day you name, in date order. Nothing in your longbook changes.

Attachments: none.

Writes to the longbook: no.

### Make my weekly longbook page

Name: `make-my-weekly-longbook-page`

The user says: "Make my weekly longbook page", "Give me my longbook week".

Result: One page for the week: what is due in the next 7 days, what you spent last week, what
renews in the next 30 days, and anything waiting for you. Nothing in your longbook changes.

Attachments: none.

Writes to the longbook: no.
