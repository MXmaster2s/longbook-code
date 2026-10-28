---
title: longbook facts
seo_title: longbook facts for directories and listings
description: Every fact about longbook a directory or listing form asks: descriptions, platforms, pricing, privacy, AI and MCP, features, releases, contact and assets.
lead: The facts a directory or listing form asks about longbook, one per line, ready to copy. Values such as the version, the prices and the features list are filled from their sources each time the site is built.
---

## What longbook is

- Name: longbook
- Name spelling: {{spelling}}
- Tagline: A memory for your financial commitments.
- Short description: longbook remembers your subscriptions, bills, insurance, loans and renewals on iPhone and Mac, keeps them in your own iCloud, and works with your AI.
- Long description:
  longbook is a memory for your financial commitments. It keeps every subscription, insurance premium, loan instalment, rent payment, school fee, card fee and domain renewal: the amount, how often it repeats, the account that pays it and when it is due next. It also keeps the expenses you have already made, so a month's spending can be seen in Reports.

  It is a native app for iPhone and Mac. The next payment stays in view on the iPhone Home Screen widget and in the Mac menu bar, and the Dashboard shows the next thirty days. A calendar puts every payment on its day, twelve months back and twelve months ahead. Every amount stays in its own currency, and each currency is totalled on its own, never converted.

  Everything lives in a longbook folder in your own iCloud Drive, as plain JSON files you own. Apple syncs the folder to every iPhone and Mac on the same iCloud account, and any tool that reads JSON can open it. longbook never connects to your bank, and the format has no field for a card number, a CVV, an expiry, a PIN or a password.

  Getting your records in takes a few minutes. Import a bank or card statement and longbook reads it into charges, repeating payments and people, up to five statements at once, with every line shown for review before it is kept. You can also add a commitment by hand, by voice with Siri, or let your AI do it.

  longbook is built to work with your AI. Through longbook's MCP server, Claude, ChatGPT and other assistants read your longbook and answer what you owe, what renews this year and what a month cost. They can also write into it: reading the receipts, bank alerts and invoices in your email and recording each charge. Nothing your AI writes lands on its own. Every change waits in the Proposals screen with its author recorded, ready to keep, edit or undo.

  For every month with a confirmed charge, longbook draws a report: the total, the split by account, category and person, and every charge. A report can be shared with family as a password-protected link that expires, and their comments come back into the report.

  longbook is a one-time purchase that covers every longbook app on every device you own, with Family Sharing, so everyone in your Apple family gets longbook on their own account. It comes with a {{refund_days}}-day refund and 12 months of longbook Cloud. Cloud is an optional monthly subscription for the few features that need longbook's server: the hosted copy your AI reads from any device, shared reports and more statement reading. Without it, your records, the widget and menu bar, imports within the included share, and an AI on your Mac reading your folder directly all keep working.
- Categories: Finance, Personal finance, Productivity
- App Store category: Finance
- Keywords: {{keywords}}
- Not a bank-linking app: longbook never connects to your bank and never asks for a bank login. Payments are typed in, read from a statement you pick, or added by your AI or Siri.
- Not a budgeting app: longbook sets no budgets, targets or forecasts. It records what you are committed to and totals what goes out.
- Other things it does not do: It does not cancel a subscription for you, convert currencies, or write to Apple Calendar or Google Calendar.

More: [Frequently asked questions](/faq/), [What longbook is and what it costs](/help/what-longbook-is-and-what-it-costs/), [What longbook does not do](/help/what-longbook-does-not-do/), [Why we built longbook](/why-we-built-longbook/)

## Platforms

- Platforms: iPhone and Mac, both native apps
- iPhone: iOS {{ios_min}} or later
- Mac: macOS {{macos_min}} or later, Apple silicon
- Download: [TestFlight beta for Mac and iPhone]({{download}})
- App Store: Coming soon
- Coming soon: {{coming_soon}}
- Languages: English
- Home Screen widget: iPhone
- Menu bar item: Mac
- Sync between devices: Through the user's own iCloud Drive

More: [Download longbook](/download/), [Install with TestFlight](/ios/), [Getting started on iPhone and Mac](/help/getting-started-on-iphone-and-mac/)

## Pricing

- Pricing model: One-time purchase, a lifetime licence. No subscription for the app.
- Launch prices: {{price_tiers}}
- Starting price: {{price_first}}
- What the licence covers: Every longbook app on every compatible device you own, and every future update
- Refund: Within {{refund_days}} days of buying, through Apple
- Free trial: None. The {{refund_days}}-day refund takes its place, and a demo longbook with made-up data can be explored before buying.
- Family Sharing: Yes. Everyone in your Apple family gets longbook on their own account and devices.
- Payment: Through the App Store. Local taxes may apply.
- longbook Cloud: An optional add-on subscription, {{cloud_price}} through the App Store
- longbook Cloud included: The first 12 months come with the purchase, for the buyer's Apple family too
- What longbook Cloud adds: The web connector and access keys, so Claude, ChatGPT and other cloud AI apps reach your longbook from any device; shared reports with a link and a password; more statements read each month

More: [Pricing](/#price), [What is longbook Cloud](/features/what-is-longbook-cloud/), [Refunds, restoring a purchase and Family Sharing](/help/refunds-restoring-a-purchase-and-family-sharing/), [What longbook Cloud adds](/help/what-longbook-cloud-adds/)

## Privacy and data

- Where the data lives: In a longbook folder in the user's own iCloud Drive, as plain JSON files. The main file is `financial_memory.json`.
- Bank login: None. longbook never connects to a bank.
- Card numbers: The format has no field for a full card number, a CVV, an expiry, a PIN or a password, and a save carrying one is refused.
- What leaves the device: Only what the user asks for: a statement being imported, the hosted copy for online AI connectors while AI access is on, shared reports, the account's email and licence status, usage and crash counts, and questions asked in Support with a screenshot when one is attached
- Statements: Read through longbook's server and not kept, neither the file nor the charges
- Hosted copy: Kept only while AI access is on. Turning it off deletes it.
- Selling data: Never. longbook does not see inside a user's longbook.
- AI models: Anthropic's Claude checks and reads imported statements and writes the answers in Support. OpenAI reads a statement only when Anthropic's service cannot answer. Neither trains on the data.
- Website analytics: PostHog in its cookieless mode. No cookie is set, no identifier is kept in the browser, and the IP address is discarded once used. Browsers that send Global Privacy Control or Do Not Track are not measured.
- App analytics: PostHog usage and crash counts, never a name, amount or note. Users can switch it off in Help & about.
- Server hosting: Supabase, {{server_region}}
- Privacy policy: [longbook.app/privacy-policy](/privacy-policy/), in effect since {{privacy_date}}
- Terms of service: [longbook.app/terms](/terms/)

More: [Where your data lives and what leaves your device](/help/where-your-data-lives-and-what-leaves-your-device/), [Keep your longbook in your own iCloud](/features/keep-your-longbook-in-your-own-icloud/), [Cookieless analytics for a personal finance app](/blog/using-cookieless-analytics-for-personal-finance-applications/), [Privacy policy](/privacy-policy/)

## AI and MCP

- Works with: Claude, ChatGPT, and any assistant that supports MCP connectors. On a computer: Claude Code, Claude Desktop, Cursor, VS Code, Codex CLI and Gemini CLI.
- MCP server URL: `{{mcp_url}}`
- Transport: {{mcp_transport}}
- Authentication: Sign in with a longbook account. Needs longbook Cloud.
- MCP tools: {{mcp_tools}}
- Writes: Every change an AI makes waits in the Proposals screen, to keep, edit or undo
- Local server: The npm package `{{npm_package}}`, run with `{{npm_command}}`. Free, with no account and no hosted copy.
- Local transport: stdio
- MCP registry name: `{{registry_name}}`
- Claude plugin: `/plugin marketplace add MXmaster2s/longbook-claude-plugin`, then `/plugin install longbook@longbook`
- Prompts: {{prompts_count}} ready-made prompts, such as "Add my statement" and "What is coming in the next 30 days?"
- Siri and Shortcuts: Siri adds expenses and commitments by voice, and a Shortcuts action records charges from a bank's messages

More: [The MCP server](/mcp), [Automations](/automations/), [Automate longbook with Claude](/features/automate-longbook-with-claude/), [longbook on npm](/features/longbook-npm-package/), [Connect your AI to longbook](/help/connect-your-ai-to-longbook-mcp/)

## Features

{{features}}

More: [All features](/features/), [Upcoming features](/features/upcoming-features/)

## Releases

- Current version: {{version}}
- Build: {{build}}
- Release date: {{release_date}}
- MCP server and npm package version: {{mcp_version}}
- Updates: Every future update is free

More: [Download longbook](/download/), [Blog](/blog/)

## Company and contact

- Maker: {{founder}}, founder of longbook
- Business: Sole proprietor
- Founded: June 2026
- Country: {{country}}
- Website: [longbook.app](https://longbook.app/)
- Email: [contact@longbook.app](mailto:contact@longbook.app)
- X: [@rohthebuilder](https://x.com/rohthebuilder)
- Discord: [discord.gg/28Dtvbx23q](https://discord.gg/28Dtvbx23q)
- Support: [longbook.app/support](/support/), or Support inside the app
- Help: [longbook.app/help](/help/)
- Feature requests: [insigh.to/b/longbook](https://insigh.to/b/longbook)

More: [Contact](/contact/), [Help](/help/), [Media kit](/media-kit/)

## Assets

{{assets}}

More: [Media kit](/media-kit/), [The media kit in Markdown](https://longbook.app/media-kit/index.md), [Every file with its size and checksum](https://longbook.app/media-kit/files.json)

## Listings and badges

- FollowX: [followx.today/b/longbook.app](https://followx.today/b/longbook.app)
- Dodo Payments Index: [index.dodopayments.com/longbook](https://index.dodopayments.com/longbook)
- mcprush: [mcprush.com/longbook/longbook-mcp](https://mcprush.com/longbook/longbook-mcp)
- Wellknown: [wellknown.network/agents/longbook](https://wellknown.network/agents/longbook)
- Indie Hackers: [indiehackers.com/product/longbook](https://www.indiehackers.com/product/longbook)
- Official MCP registry: `{{registry_name}}`
- npm: [npmjs.com/package/{{npm_package}}](https://www.npmjs.com/package/{{npm_package}})

More: [Reviews](/reviews/)
