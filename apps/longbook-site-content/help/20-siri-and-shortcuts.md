# Siri and Shortcuts

Siri adds payments to longbook by voice, and says what is due next. A Shortcuts action records charges from your bank's messages.

## Say it to Siri

- **"Add an expense in my longbook"** records a payment you already made.
- **"Add a commitment in my longbook"** adds a one-time payment due on a day.
- **"What do I pay next in my longbook"** names each payment due on the next day anything is owed, with its amount.

Siri asks for the name, the amount and the day. Rupees, dollars, pounds, euros, dirhams and yen keep their currency. Any other amount takes the currency most of your commitments use.

## Charges from bank messages

The **Record a charge from a message** action reads a bank message on your device: the amount, the day, the payee, and the account whose name holds the same last four digits. A credit is recorded as money in. One-time passwords, declined payments and balance alerts record nothing. The same message handed over twice records one charge.

The action reads only the text a shortcut gives it. To run it on its own, build an automation in the Shortcuts app with a Messages or Mail action.

## Questions

### Can Siri add a monthly or yearly commitment?
No. Siri adds a one-time commitment. Set a repeat in the commitment's form in the app.

### Where does Siri write?
To the longbook folder in iCloud Drive, without opening the app. iCloud Drive has to be on. Everything it adds shows in **Proposals** as Siri.
