# Import a bank statement

longbook can read a bank or card statement and turn its lines into charges, so you don't type them in.

## How to import

1. On iPhone, open **Settings**, then **Import a statement**. It is also on the **Reports** screen.
2. Tap **Securely Upload Statement** and choose up to five files at once: PDF, CSV, plain text or Excel, scanned PDFs included.
3. If a PDF is locked, enter its password. The password stays on your device.
4. longbook prepares your longbook, usually in under a minute. A bar fills as it goes, and **longbook Burst**, a small game, is there if you want it. Reading does not depend on the game: if you never press **Play**, the steps open by themselves when it finishes.
5. What was read is saved once, right after reading. If it can't be saved, longbook says so, nothing is written, and **Try Again** saves it without reading the statement again.
6. Then longbook shows what it found, one step for each kind: **Past Expenses**, **People**, **Accounts**, **Commitments**, **Transfers** and **Earnings**. A kind with nothing to show is left out. The row of symbols at the top jumps to any step. **See All** opens every card of a kind. **Skip** goes straight to the end, and **Continue** to the next step.
7. The last screen counts what was saved. **Open Dashboard** opens your longbook on the months the statement covers, and **Import Another Statement** starts the next one.

Payments that repeat become commitments. Every person the statement prints becomes a person, and every account it prints becomes an account: the statement's own account, named from its header even when no number is printed, and the accounts your transfers go to, your own among them. Lines already in your longbook are left out. You need to be signed in to longbook to import.

### Taking something back

- **Undo Import**, on the first step, takes the whole import back: every card it saved, its copy of the statement, and its line in **Past Imports**.
- On **See All** for People, tap a person to remove them, and tap again to keep them. Their charges stay; only the link to them goes.
- After the steps, change anything from its own card. **History** on the **Proposals** screen keeps the import as one change, and can restore the version before it.

### How complete the reading was

**Past Imports** shows the **Import Completeness Score** for each statement: on iPhone in **Settings**, and on Mac in the Settings window under **Statements**. It compares the lines read with the lines in the file, and whether the balance matches.

### Adding the people and accounts it finds

**Add accounts and people found in statements** decides whether an import adds the people and accounts it finds. It's on unless you turn it off: on iPhone in **Settings** under **Import**, and on Mac in the Settings window under **Statements**, where it's called **Add accounts and people found**. With it off, an import adds only the charges and commitments, and each statement's holder.

## What is sent, and what is kept

longbook first reads the statement on your device. When the lines it reads add up to the balances printed, only those lines and the top of the statement go to our server, with long numbers cut to their last four digits, and from there to Anthropic's Claude. Otherwise it sends the file a few pages at a time. If Claude can't answer, the same request goes to OpenAI instead.

- Our server keeps neither the statement nor the charges read from it.
- We only record that an import happened, so we can count your monthly share.
- When the file itself is sent, its pages carry whatever your bank printed, including any account number.

## How many you can import

Every account includes a monthly share of statement reading. longbook Cloud gives you a larger share.

## Use your own AI instead

**Use My Own AI** gives you a prompt for Claude or another AI, which reads the statement and writes into longbook. What it writes waits in **Proposals**. It is not offered during setup; it appears on every import after that.

## If a file is refused

longbook first checks that a file is a statement. A file that isn't, such as a receipt or a screenshot, is refused and nothing is read from it.

## If the charges look wrong

Tap **Undo Import** on the first step and nothing stays in your longbook. If you have already left the steps, restore the version before it from **History** on the **Proposals** screen. Then in Support, tap **Ask a person** to open an email to the team, and tell us the bank's name and what went wrong. Please don't send the statement itself.
