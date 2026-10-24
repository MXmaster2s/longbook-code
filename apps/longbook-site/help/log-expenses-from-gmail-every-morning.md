# Log expenses from Gmail every morning

- Page: https://longbook.app/help/log-expenses-from-gmail-every-morning/

Claude can read your mail every morning and record what it finds in longbook. Each entry waits in **Proposals**.

## What it needs

- a longbook account with **Let AI Read My longbook** and **Allow proposals** turned on in **AI Connections**
- Claude with the longbook connector, a mail connector such as Gmail, and scheduled tasks

Without scheduled tasks, Claude can run the same round when you ask.

## Set it up

In the app, open **AI Connections**, find **Claude automation**, and tap **Copy Prompt**. Paste it into Claude. Claude schedules itself for 6am each day and runs the first round at once.

## What each round does

It reads the last day of mail for bank and card alerts, receipts, bills that are due, money in, renewal notices and card statements.

- A payment for a commitment longbook already holds becomes that commitment's charge.
- A card bill is recorded as a transfer, kept out of spending.
- One-time passwords, sign-in alerts and offers are skipped.
- Each entry keeps a reference to its email.

## Questions

### Does longbook read my email?

No. Claude reads it through its own mail connector and writes to longbook through the longbook connector. longbook never connects to a mailbox.

### Can the same payment be recorded twice?

The round checks what longbook already holds and skips an email whose amount and day are already recorded. Anything that slips through shows in **Proposals**, to undo.

Still have a question? Open **Support** in the app, under **Settings**, then **Help & about**, or write to contact@longbook.app and a person answers.

- [All help articles](https://longbook.app/help.md)
