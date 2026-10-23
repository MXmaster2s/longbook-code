---
name: longbook-from-email
description: >
  Use for requests like "find my subscriptions in my email", "find my insurance policies in my
  email", "pull my Amazon orders from Gmail", "add my salary credits from email", "find my EMI
  payments in my mail", "Find subscriptions from my email and add them in my longbook", "Find
  expenses from my email and add them in my longbook", "Find invoices from my email and add
  them in my longbook", "Find insurances from my email and add them in my longbook", even when
  the user does not name longbook. Finds subscriptions, expenses, invoices, insurances,
  purchases, bills, loans and EMIs, travel bookings or money in in the user's email, and adds
  them to their longbook. Works through the longbook connector (https://longbook.app/mcp).
---

# longbook: From your email

longbook is the user's financial memory: every commitment they pay, its charges past and
planned, their accounts and the people payments are for. Finds subscriptions, expenses,
invoices, insurances, purchases, bills, loans and EMIs, travel bookings or money in in the
user's email, and adds them to their longbook. Each prompt below has a procedure on the
longbook server; follow it rather than improvising one.

## How to run one

1. Pick the prompt below that matches what the user asked, in our words or theirs.
2. Call the longbook connector's `read_guide` with the prompt's name, for example
   `read_guide("find-subscriptions-from-my-email")`. It returns the procedure, step by step, and the guide
   chapter it builds on.
3. Follow that procedure and the guide's rules. Never write a card number, a full account
   number, a PIN or a password.
4. If no longbook tools are available, say the longbook connector is needed: in Claude,
   Settings, then Connectors, then Add custom connector, with the address
   https://longbook.app/mcp, signing in with the longbook account. Installing this plugin adds the
   connector too.

## The prompts

### Find subscriptions from my email

Name: `find-subscriptions-from-my-email`

The user says: "Find subscriptions from my email and add them in my longbook".

Result: Your subscriptions found in the last 12 months of your mail: each one with its receipts
as charges, the ones that clearly repeat planned ahead, and trials and price changes as the
mails state them.

Attachments: none. The user's mail must be connected to their AI.

Needs: the user's mail connected to their AI.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Find expenses from my email

Name: `find-expenses-from-my-email`

The user says: "Find expenses from my email and add them in my longbook".

Result: This month's spending from your mail's bank alerts and receipts, each recorded once as
a paid charge.

Attachments: none. The user's mail must be connected to their AI.

Needs: the user's mail connected to their AI.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Find invoices from my email

Name: `find-invoices-from-my-email`

The user says: "Find invoices from my email and add them in my longbook".

Result: The invoices and receipts in the last 12 months of your mail, each recorded once as a
charge, paid or due.

Attachments: none. The user's mail must be connected to their AI.

Needs: the user's mail connected to their AI.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Find insurances from my email

Name: `find-insurances-from-my-email`

The user says: "Find insurances from my email and add them in my longbook".

Result: Your insurance policies found in your mail: each with its premiums as charges, its next
premium planned, and its policy details in its notes.

Attachments: none. The user's mail must be connected to their AI.

Needs: the user's mail connected to their AI.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Find purchases from my email

Name: `find-purchases-from-my-email`

The user says: "Find purchases from my email and add them in my longbook".

Result: Your orders from the last 3 months of your mail, each recorded once as a paid charge
named for what you bought.

Attachments: none. The user's mail must be connected to their AI.

Needs: the user's mail connected to their AI.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Find bills from my email

Name: `find-bills-from-my-email`

The user says: "Find bills from my email and add them in my longbook".

Result: Your bills from the last 3 months of your mail: what you paid recorded, what is due
planned, and each card's monthly bill kept apart from spending.

Attachments: none. The user's mail must be connected to their AI.

Needs: the user's mail connected to their AI.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Find loans and EMIs from my email

Name: `find-loans-and-emis-from-my-email`

The user says: "Find loans and EMIs from my email and add them in my longbook".

Result: Your loans and EMIs found in your mail: each loan with its EMIs as charges, planned
ahead to its end when the mails state it.

Attachments: none. The user's mail must be connected to their AI.

Needs: the user's mail connected to their AI.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Find travel bookings from my email

Name: `find-travel-bookings-from-my-email`

The user says: "Find travel bookings from my email and add them in my longbook".

Result: Your bookings from the last 12 months of your mail: flights, trains, hotels and cabs,
each recorded as a paid charge with where and when.

Attachments: none. The user's mail must be connected to their AI.

Needs: the user's mail connected to their AI.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Find money in from my email

Name: `find-money-in-from-my-email`

The user says: "Find money in from my email and add them in my longbook".

Result: Your salary, refunds, interest and other money in from the last 12 months of your mail,
kept apart from spending.

Attachments: none. The user's mail must be connected to their AI.

Needs: the user's mail connected to their AI.

Writes to the longbook: yes; it waits in the app's Changes screen.
