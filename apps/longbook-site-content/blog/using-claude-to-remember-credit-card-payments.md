---
slug: using-claude-to-remember-credit-card-payments
title: Using Claude to remember your credit card payments
seo_title: Track credit card bills with Claude and longbook
description: Claude reads your card statement emails every morning and records each bill in longbook as a transfer, so the due date shows on iPhone and Mac without alerts.
card: Claude reads your card bill emails every morning and records them in longbook. The due date waits on iPhone and Mac.
lead: Want to know when your credit card bill is due, without another alert from the bank, the card app and your payments app? This is how to have Claude read your card emails every morning and record each bill in longbook, so the next due date waits on your iPhone and Mac until you look.
date: 2026-10-15
updated: 2026-10-16
image: /blog/media/card-payments/share.jpg
image_alt: Using Claude to remember your credit card payments, on the longbook blog
---

A credit card bill arrives as an email. It holds the two facts you need: the total due and the due date. The bank also alerts you, the card app reminds you and a payments app does the same. Each one is a notification you did not choose, and the one that matters is easy to swipe away.

longbook sends no notifications. It shows the next payment where you already look: the dashboard, the Home Screen widget on iPhone and the menu bar on Mac. What it needs is the bill, without you typing it. That is the job we give to Claude.

Here is the whole setup, in the order you would do it.

## Step 1: Connect Claude to your longbook and your mail

You need three things in Claude: the longbook connector, a mail connector such as Gmail, and scheduled tasks. In longbook, switch on **Enable longbook MCP server** on the Automations screen and tick **Let signed-in AIs suggest changes**.

longbook itself never connects to your mailbox. Claude reads your mail through its own connector and writes to longbook through the longbook one. The setup is on [Automate longbook with Claude](/features/automate-longbook-with-claude/).

## Step 2: Paste one line into Claude

The **Claude Automation** card on the Automations screen holds a one-line prompt and **Copy the prompt**.

![The Claude Automation card on longbook's iPhone Automations screen, with its one-line prompt and a Copy the prompt button](/blog/media/card-payments/automations.jpg "Automations on iPhone. The Claude Automation card holds the prompt to paste.")

The prompt reads: “Go to longbook.app/mcp and set yourself up for a daily longbook email round, as longbook recommends.” Paste it into Claude with the longbook and mail connectors on. Claude creates a scheduled task for 6 every morning, in your time zone, and runs the first round at once, so you see what a morning looks like.

If your Claude has no scheduled tasks, it says so, and you can ask it to run a round whenever you like. The [Gmail feature page](/features/log-expenses-from-gmail/) shows the round in full.

## Step 3: Start with the last three months

A new longbook has no bills in it yet. Before the daily round, ask Claude: **Find bills from my email and add them in my longbook.**

Claude searches the last three months of your mail for electricity, water, gas, phone, internet and rent bills, and for credit card statements. What you paid is recorded, what is due is planned, and each card's monthly bill is kept apart from spending. It then asks you, in one message, about anything it could not place.

## Step 4: See what Claude does with a card statement

A card statement is the email the daily round cares about most. Claude records it like this:

- **One statement is one card bill.** It is named for the card and the month it falls due, such as "Coral card bill, October 2026".
- **It is recorded for the total due**, on that card, unpaid, at its due date.
- **It is a transfer, never spending.** The purchases on the card are your spending. The bill is money moving from your bank account to the card. longbook shows the bill but never adds it to spending, so nothing is counted twice.
- **A payment marks it paid.** When the bank's confirmation arrives, Claude marks that month's card bill paid.
- **A bill already recorded for that month is corrected, never added twice.** Claude reads what longbook already holds before it writes.

One-time passwords, sign-in alerts and offers are skipped. The last four digits of a card are used only to match the bill to the right card. Claude never writes a card number, a one-time password or a tax id.

![Part of longbook's iPhone Calendar for September 2026, with the 24th selected and a card bill of 9,830 rupees listed as a paid transfer](/blog/media/card-payments/calendar.jpg "A card bill in the Calendar, on the day it was due: marked as a transfer, and paid.")

## Step 5: Review what Claude added

Every row waits in **Proposals** with Claude named as its writer. **Keep all** accepts the round as it stands and **Undo all** writes back the state from before it. Before that, any row can be edited or deleted. Open longbook after a round and the new rows are there.

![The top of longbook's iPhone Proposals screen, with its tabs, the Keep all and Undo all buttons and the first charge Claude suggested](/blog/media/card-payments/changes.jpg "Proposals on iPhone: what Claude added, waiting to keep or undo.")

On a Mac, Proposals also keeps a history, so an earlier version of your longbook can be written back.

![The top of longbook's Mac Proposals screen, with its tabs, the Keep all and Undo all buttons and the charges Claude suggested](/blog/media/card-payments/mac-changes.jpg "Proposals on Mac, with the same Keep all and Undo all.")

Claude reads the mail it can see. A bill that never reached your inbox is not found, and a statement that Claude misreads shows up here, where you can fix it. [Every change your AI makes](/features/review-every-change-your-ai-makes/) is reviewed before you keep it.

## Step 6: See the next due date, without an alert

Once the card bill is in, it appears where you already look.

:::film /features/media/get-spending-insights.mp4
A 25-second film of longbook's Coming up row on iPhone and Mac: the next thirty charges and transfers in date order, a card bill among them, ending on the longbook logo.
Coming up, the row on the dashboard that holds the next due date. It is shown here on iPhone and on Mac.
:::

- The **dashboard** shows the next commitment and the next 30 days.
- The [Calendar](/features/calendar-view-of-your-expenses/) marks each bill on its day.
- On iPhone, the [Home Screen widget](/features/add-longbook-widget-to-your-iphone/) shows the next day something is due. A card bill due that day shows on its own line and stays out of the total.
- On Mac, the [menu bar](/features/see-your-next-payment-in-the-mac-menu-bar/) shows the total due on the next payment day and how many days away it is. A card bill is listed separately, with its own amount.

**Coming up**, on the dashboard, lists the next thirty charges and transfers in date order. A card bill is one of the transfers: it shows with its due date and total, and it is never added to what you spent.

All of it reads the longbook folder in [your own iCloud](/features/keep-your-longbook-in-your-own-icloud/). A bill Claude adds on one device shows on the other once iCloud has synced it.

## What stays with you

Claude reads your mail through its own connector, under your agreement with Claude. longbook never connects to a mailbox and never sees your mail.

From each bill, Claude takes only what the bill needs: the amount and currency, the day, a plain name, a category, the last four digits to match a card, and a reference to the email it came from. It never writes a card number.

There are two ways to connect. On a Mac, **Set up Claude Desktop** connects Claude to the folder directly, with no hosted copy, and what Claude reads goes to Claude as part of the conversation. Anywhere else, Claude connects to `longbook.app/mcp` and reads a hosted copy that only your account can reach. The hosted copy, and what it keeps, is described in the [privacy policy](/privacy-policy/).

If you would rather start from a bank statement than from email, [here is what longbook does with one](/blog/using-ai-for-statements-to-data/).

If something here is wrong, or you want a step explained further, write to [contact@longbook.app](mailto:contact@longbook.app).
