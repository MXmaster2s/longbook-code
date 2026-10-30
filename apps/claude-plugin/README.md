# longbook for Claude

longbook remembers every commitment you pay: subscriptions, bills, rent, salaries, insurance
and loans, with their charges past and planned. This plugin brings longbook's prompts to Claude
as skills and slash commands, and connects Claude to your longbook. Ask in your own words, or
type a command.

## Install

In Claude Code or the Claude desktop app:

```
/plugin marketplace add MXmaster2s/longbook-claude-plugin
/plugin install longbook@longbook
```

Then sign in to the longbook connector with your longbook account, and to Gmail if you want the
email prompts. Start with `/longbook:start`.

## Commands

**Setting up**

- `/longbook:set-up`: Set up my longbook. Your longbook filled from your statements: every
  charge on record, the names you picked in setup filled in where your statements or your answers
  show them, each account's closing balance set, the charges that clearly repeat planned ahead,
  and the rest set to repeat once you confirm them.
- `/longbook:add-statement`: Add my statement. Every charge on the statement recorded as paid,
  money in kept apart, the account's balance updated, the charges that clearly repeat set to
  continue, and the rest once you confirm them.
- `/longbook:categorise`: Categorise my longbook. Every commitment without a category gets one.
- `/longbook:month-report`: Add a month report in my longbook. The month's statements recorded,
  the charges they prove confirmed, and each account's balance set.

**Keeping it current**

- `/longbook:email-invoices`: Add email invoices in my longbook. This month's bank alerts,
  receipts, bills and money in from your mail, each recorded once, with nothing doubled.
- `/longbook:email-round`: Set up a daily longbook email round. Your AI reads your mail every
  morning at 6 and records the money that moved, so your longbook stays current without you
  asking.
- `/longbook:document-invoices`: Add document invoices in my longbook. The invoices, receipts
  and bills you attach, or keep in the longbook documents folder, recorded as charges with the
  file's name in their notes, without doubling what your statements or mail already recorded.
- `/longbook:add`: Add a commitment or an expense. A new commitment planned ahead, or a
  one-time expense recorded, on the account and for the person you name.

**Reading it**

- `/longbook:whats-next`: What do I pay next? The next day you owe something, and what is due
  that day.
- `/longbook:whats-due`: What is coming in the next 30 days? Everything due in the next 30
  days, or the period you name, by day, with the total per currency.
- `/longbook:month-spend`: What did I spend in a month? What you spent in that month, and what
  is not yet confirmed.
- `/longbook:renewals`: What renews this year? Your yearly, half-yearly and quarterly payments
  due in the next 12 months, or before the day you name, in date order.
- `/longbook:weekly-page`: Make my weekly longbook page. One page for the week: what is due in
  the next 7 days, what you spent last week, what renews in the next 30 days, and anything
  waiting for you.

**Reports**

- `/longbook:report`: Create a report in my longbook. A report over the days, accounts, people
  and categories you choose, on the Reports screen the next time the app is open.
- `/longbook:trip-report`: Make a report of my trip. A report of your trip's spending on the
  Reports screen, filling in as the trip's charges are confirmed.

**Housekeeping**

- `/longbook:tidy`: Tidy my longbook. Doubled charges, bank-style names and odd categories
  found, and fixed once you approve each change.
- `/longbook:reorganise`: Reorganise my longbook. Your whole longbook, once over: names as you
  would say them, every row categorised, people and accounts linked, doubles merged, nothing
  lost.
- `/longbook:morning-brief`: Set up a morning brief. A short summary every morning of what is
  due today and in the next 30 days.

**From your email**

- `/longbook:find-subscriptions`: Find subscriptions from my email. Your subscriptions found in
  the last 12 months of your mail: each one with its receipts as charges, the ones that clearly
  repeat planned ahead, and trials and price changes as the mails state them.
- `/longbook:find-expenses`: Find expenses from my email. This month's spending from your
  mail's bank alerts and receipts, each recorded once as a paid charge.
- `/longbook:find-invoices`: Find invoices from my email. The invoices and receipts in the last
  12 months of your mail, each recorded once as a charge, paid or due.
- `/longbook:find-insurances`: Find insurances from my email. Your insurance policies found in
  your mail: each with its premiums as charges, its next premium planned, and its policy details
  in its notes.
- `/longbook:find-purchases`: Find purchases from my email. Your orders from the last 3 months
  of your mail, each recorded once as a paid charge named for what you bought.
- `/longbook:find-bills`: Find bills from my email. Your bills from the last 3 months of your
  mail: what you paid recorded, what is due planned, and each card's monthly bill kept apart from
  spending.
- `/longbook:find-loans`: Find loans and EMIs from my email. Your loans and EMIs found in your
  mail: each loan with its EMIs as charges, planned ahead to its end when the mails state it.
- `/longbook:find-travel`: Find travel bookings from my email. Your bookings from the last 12
  months of your mail: flights, trains, hotels and cabs, each recorded as a paid charge with
  where and when.
- `/longbook:find-money-in`: Find money in from my email. Your salary, refunds, interest and
  other money in from the last 12 months of your mail, kept apart from spending.

## Skills

- **longbook-setup**: Sets up the user's longbook, their record of subscriptions, bills, rent, salaries, loans and other commitments, from bank and card statements; adds later statements, categorises it, and completes a month so longbook can draw its report.
- **longbook-keep-current**: Keeps the user's longbook current: this month's invoices, bills and money in from their email, a daily email round, invoices and receipts kept as files, and a new commitment or expense.
- **longbook-answers**: Answers questions about the user's bills, subscriptions, payments and spending from their longbook: what is due next or this week, what is coming in the next 30 days, what a month cost, and what renews this year.
- **longbook-reports**: Asks longbook to draw a report over the days, accounts, people or categories the user chooses, or for a trip.
- **longbook-housekeeping**: Tidies the user's longbook (doubled charges, bank-style names, odd categories) and sets up a morning brief of what is due.
- **longbook-from-email**: Finds subscriptions, expenses, invoices, insurances, purchases, bills, loans and EMIs, travel bookings or money in in the user's email, and adds them to their longbook.
- **longbook-start**: checks the connection, starts setup, and shows every prompt.

## What it runs, sends and fetches

The plugin is text only: skills and slash commands that tell Claude what to do. It installs no
hooks, scripts or local servers, runs no code on your machine, and collects no analytics. What
it reaches, it reaches through the two connectors it bundles:

- **longbook** (https://longbook.app/mcp), longbook's own MCP server, signed in with your
  longbook account. It reads the hosted copy of your longbook that the app uploads when you turn
  on its MCP server: your commitments and their charges past and planned, your accounts and
  balances, the people payments are for, your tags and categories, and your reports. Each skill
  and command also fetches its procedure from it with read_guide, so the steps are always the
  server's current ones. What Claude reads through it goes into your conversation with Claude.
- **Writes wait as proposals.** When Claude adds a commitment or a charge, marks one paid,
  cancels one or leaves an insight, the change is sent to longbook as a proposal, and only after
  you turn on Allow proposals in the app. Nothing is in your longbook until you keep it in the
  app's Proposals screen, where you can also undo it. A report request shows on the Reports
  screen instead.
- **Gmail** (https://gmailmcp.googleapis.com/mcp/v1), Google's Gmail MCP server, bundled for
  the email prompts and signed in with your Google account. Only `/longbook:email-invoices`,
  `/longbook:email-round`, `/longbook:find-subscriptions`, `/longbook:find-expenses`,
  `/longbook:find-invoices`, `/longbook:find-insurances`, `/longbook:find-purchases`,
  `/longbook:find-bills`, `/longbook:find-loans`, `/longbook:find-travel` and
  `/longbook:find-money-in` read it: they search and read your mail for payments, bills, receipts
  and money in. No prompt sends, deletes or labels mail. Without a Gmail sign-in every other
  command works.
- **Scheduled tasks.** `/longbook:email-round`, `/longbook:morning-brief` and `/longbook:start`
  (for the weekly page) set up a scheduled task in your Claude app, only when you ask for one,
  and it runs the same prompt through the same connectors.

Statements and files you attach go to Claude in the conversation; what Claude records from them
is sent to longbook as proposals. The plugin sends nothing anywhere else. Privacy:
https://longbook.app/privacy-policy/. Generated from the longbook prompt catalogue (contract
revision 48, version 1.48.0).

## More about longbook

- [longbook.app](https://longbook.app/): the app for Mac and iPhone
- [Automate longbook with Claude](https://longbook.app/features/automate-longbook-with-claude/)
- [Every automation](https://longbook.app/automations/) and [every feature](https://longbook.app/features/)
- [Review every change your AI makes](https://longbook.app/features/review-every-change-your-ai-makes/)
- [Log expenses from Gmail](https://longbook.app/features/log-expenses-from-gmail/)
- [Why we built longbook](https://longbook.app/why-we-built-longbook/)

## License

GPL-3.0, the same licence as longbook. See LICENSE.
