# Import a bank statement

- Page: https://longbook.app/help/import-a-bank-statement/

longbook can read a bank or card statement and turn its lines into charges, so you don't type them in.

## How to import

1. On iPhone, open **Settings**, then **Import a statement**. It is also on the **Reports** screen.
2. Tap **Securely Upload Statement** and choose up to five files at once: PDF, CSV, plain text or Excel, scanned PDFs included.
3. If a PDF is locked, enter its password. The password stays on your device.
4. Review every line: fix a name, a category or a person, or untick a line. Transfers between your own accounts and card bill payments start unticked, and lines an earlier statement already recorded are left out.
5. Add them. What is recorded shows in **Proposals**, to keep or undo.

Payments that repeat are offered as commitments, and the people a statement pays are offered as people. You need to be signed in to longbook to import.

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

Undo the proposal on the Proposals screen and nothing stays in your longbook. Then tap **Email us** and tell us the bank's name and what went wrong. Please don't send the statement itself.

Still have a question? Open **Support** in the app, under **Settings**, then **Help & about**, or write to contact@longbook.app and a person answers.

- [All help articles](https://longbook.app/help.md)
