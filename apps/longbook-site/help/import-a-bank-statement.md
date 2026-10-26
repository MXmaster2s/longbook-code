# Import a bank statement

- Page: https://longbook.app/help/import-a-bank-statement/

longbook can read a bank or card statement and turn its lines into charges, so you don't type them in.

## How to import

1. On iPhone, open **Settings**, then **Import a statement**. It is also on the **Reports** screen.
2. Tap **Securely Upload Statement** and choose up to five files at once: PDF, CSV, plain text or Excel, scanned PDFs included.
3. If a PDF is locked, enter its password. The password stays on your device.
4. Review what was read. It is one list, drawn with the app's own cards: **Commitments**, then **Past expenses**, **People** and **Accounts**, every item ticked. Fix a name, a category or a person, or untick anything. Transfers between your own accounts, card bill payments, money in, and lines already in your longbook start unticked.
5. Tap **Add**, which counts the ticked items. The review closes, and what is recorded shows in **Proposals**, to keep or undo. Only **Add** or **Discard** closes the review.

Payments that repeat are offered as commitments, every one ticked. Every person the statement prints is offered under People, and every account it prints under Accounts: the statement's own account, named from its header even when no number is printed, and the accounts your transfers go to, your own among them. Untick what you don't want. You need to be signed in to longbook to import.

### Adding the people and accounts it finds

**Add accounts and people found in statements** decides whether the people and accounts start ticked. It's on unless you turn it off: on iPhone in **Settings** under **Import**, and on Mac in the Settings window under **Statements**. With it off, they start unticked, and only what you tick is added.

## What is sent, and what is kept

To read a statement, longbook sends it a few pages at a time from your device to our server, and from there to Anthropic's Claude. If Claude can't answer, the same piece goes to OpenAI instead.

- Our server keeps neither the statement nor the charges read from it.
- We only record that an import happened, so we can count your monthly share.
- The pages carry whatever your bank printed, including any account number.

## How many you can import

Every account includes a monthly share of statement reading. longbook Cloud gives you a larger share.

## Use your own AI instead

**Use My Own AI** gives you a prompt for Claude or another AI, which reads the statement and writes into longbook. What it writes waits in **Proposals**.

## If a file is refused

longbook first checks that a file is a statement. A file that isn't, such as a receipt or a screenshot, is refused and nothing is read from it.

## If the charges look wrong

Undo the proposal on the Proposals screen and nothing stays in your longbook. Then in Support, tap **Ask a person** to open an email to the team, and tell us the bank's name and what went wrong. Please don't send the statement itself.

Still have a question? Open **Support** in the app, under **Settings**, then **Help & about**, or write to contact@longbook.app and a person answers.

- [All help articles](https://longbook.app/help.md)
