# Frequently asked questions

> What longbook is, what it remembers, where the data lives, how an AI connects, and how the $38 lifetime license and its 7-day refund work.

- Page: https://longbook.app/faq/

### What is longbook?

longbook is a memory for your financial commitments. It remembers them and reminds you on time, on your iPhone and your Mac. Everything is stored in your own iCloud, and it is open for your AI to talk to — so Claude or ChatGPT always knows what you are committed to. Health insurance, car insurance, rent, EMIs, school fees, subscriptions, credit card fees, domain renewals: if it costs money and comes back, it goes in longbook.

### What can it remember?

Your financial commitments — premiums, rent, instalments, school fees, subscriptions, credit card payment dates — and the expenses you have already made, which appear in the Reports section of the app. Your AI can write into it too: anything it finds in your emails, or anywhere else you point it, longbook remembers and reminds you about. For a quick glance there is an iPhone widget and a Mac menu bar item.

### Which devices does it run on?

Mac and iPhone, both native apps. macOS 14 or later, iOS 17 or later. One purchase covers both, and they read the same folder, so a change on one shows up on the other.

### Where is my data stored?

In a file called financial_memory.json, inside your longbook folder in your own iCloud. It is a plain, structured JSON file, readable by any version of longbook, by other apps, and by your AI. The folder also carries a schema and a guide — longbook.schema.json and llms.txt — so your AI knows exactly how to read it and write into it.

### Is there a longbook account?

Yes. Your longbook.app account connects your AI to the longbook MCP, so your AI can read and write your commitments even when you are talking to it from your iPhone. It also carries your license, and the report links you share with family.

### How do I connect Claude or ChatGPT?

longbook connects as a custom connector: https://longbook.app/mcp, added in Claude or ChatGPT and signed in with the longbook account. That address is longbook's MCP server — in a browser it explains itself: the tools your AI can call, and a worked example. On a Mac, the app can also connect Claude to your folder directly, with one click in Settings.

### How do expenses from Gmail get in?

Your AI does it. Connected to your Gmail, it checks the payments from the last month and updates your longbook. It reads the emails, understands how to write into your longbook folder, and files each expense. The next time you open the app, every change is waiting in the Proposals section for you to keep or undo.

### What if my AI gets something wrong inside my longbook?

Every change your AI makes appears in the Proposals section of the app, with its author on it, and longbook keeps the history of your past versions. Undoing the change or restoring an earlier version is one tap.

### Does longbook connect to my bank?

No — longbook does not need to. It keeps the reminders, the financial commitments and the expenses you record, and holds them in plain view. That is the whole job, done from the records in your own folder.

### Can I share my expense report with my family members?

Yes. A report is shared as a link and a password longbook generates; you pass both on — a secure way to share expenses, from any browser. Your family members can comment inside the report too, and your AI can read those comments and update your longbook when you tell it to.

### What do I get with the licence?

The iPhone app and the Mac app now, and the iPad, Apple Watch, iPhone Duo and Android apps as they arrive, with the iOS widget and the Mac menu bar item, your AI reading and editing your longbook folder on a Mac, and every update. It is one purchase, not a subscription. At launch the first 100 buyers pay $38, the next 250 pay $98, and everyone after pays $149. longbook Cloud, for the features that run on longbook’s server, is a separate $4 a month.

### Can I try longbook before paying?

longbook is bought before you use it, with a 7-day refund instead of a trial. Within 7 days of buying, tap Request a Refund in Account and Apple refunds you. Before buying, you can look around a demo longbook with made-up data, and every license includes 12 months of longbook Cloud.

### Is longbook open source?

Yes — longbook is licensed under GPL-3.0. Its source code is public on GitHub at [github.com/MXmaster2s/longbook-code](https://github.com/MXmaster2s/longbook-code): anyone can read it, build it and send a pull request. The work is coordinated on the community Discord.

### How do I contact longbook?

Email: contact@longbook.app. X: [@rohthebuilder](https://x.com/rohthebuilder). The [community Discord](https://discord.gg/28Dtvbx23q) carries feature requests and the roadmap. Feature suggestions also land on the [feedback board](https://insigh.to/b/longbook), and developers start at [Work on the source](https://longbook.app/source).
