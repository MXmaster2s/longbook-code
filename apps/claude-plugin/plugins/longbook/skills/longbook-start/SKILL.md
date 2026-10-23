---
name: longbook-start
description: >
  Use when the user has just installed longbook, asks what longbook can do, or says "help me
  with my longbook", "where do I start with longbook", "what should I do in longbook" or
  "longbook start". Checks the longbook connection, starts setup when the longbook is empty,
  shows every longbook prompt with its slash command, and offers the morning brief, the daily
  email round and the weekly page on a schedule.
---

# longbook: Start here

longbook is the user's financial memory: every commitment they pay, its charges past and
planned, their accounts and the people payments are for. This is the front door: check the
connection, start where the user is, and point to the one prompt that helps most now.

## Steps

1. Call the longbook connector's `whoami`. If no longbook tools are available, the longbook
   connector needs signing in: in Claude Code run /mcp and sign in to longbook; in the Claude
   apps, Settings, then Connectors, then longbook. Sign in with the longbook account. Without the
   plugin, add a custom connector with the address https://longbook.app/mcp. Then stop.
2. If whoami says this connection cannot write, say its how_to_enable sentence: the user
   switches it on in the longbook app.
3. If the longbook holds no commitments yet, offer `/longbook:set-up`: attach bank and card
   statements, ideally the last 12 months. Stop there unless the user wants the list.
4. Otherwise, say in two lines what it holds (commitments, accounts, members) and what is
   waiting: names to fill in from setup, and suggestions the app could not apply.
5. Show the prompts below, by group, each with its slash command. The user can also just ask in
   their own words.
6. Check for a mail connector. If none is signed in, say the email prompts need one: the plugin
   bundles Gmail, signed in with the user's Google account.
7. Offer, and set up only what the user picks, each by its own procedure:
   `/longbook:morning-brief`, `/longbook:email-round` and `/longbook:weekly-page` every Monday.
8. End with the single best next step for this user.

## The prompts

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
