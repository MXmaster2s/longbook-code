---
slug: get-insights-about-your-expenses-from-your-ai
order: 16
group: automate
title: Get insights about your expenses from your AI
seo_title: AI insights on your expenses and subscriptions
description: Claude or ChatGPT reads your longbook and leaves short notes on its dashboard, account and member cards. longbook shows the notes and never writes them.
card: Short notes from your AI, shown beside the dashboard, account or member card each one is about.
platforms: iphone, mac
iphone: iphone-insights
mac: mac-insights
aliases: ai-insights, ai-expense-insights
related: automate-longbook-with-claude, get-spending-insights, review-every-change-your-ai-makes
labels: Insights, Next payment, Spending, Categories
---

Your AI reads your longbook and leaves short notes on the cards they concern. longbook shows each note beside its card and gathers them all on one screen.

## On the screen

**Insights** on iPhone and Mac: every note your AI has left, grouped under Dashboard, Accounts and Members. Each note names the card it sits on and has a cross to remove it.

## What it does

### A note on the card it concerns

A note sits on a dashboard card such as **Next payment**, **Spending** or **Categories**, or on the card of one account or one member. A speech-bubble mark beside the card's title opens it.

### Every note in one place

**Insights** lists every note by area. A note on an account or a member opens the Accounts or Members screen. The cross beside a note removes every note left for that card.

### Notes from your AI alone

longbook never writes a note itself. Notes are kept in a file named insights.json in your longbook folder, and each card shows the latest note left for it.

## Why it exists

A total shows how much; it does not say which charge made the difference, or that a payment moved to another account. An AI that reads the whole record can say so in a sentence. longbook keeps that sentence beside the card it explains.

## Questions

### Does longbook generate insights itself?

No. longbook draws the figures on each card; every note comes from an AI you connect, such as Claude or ChatGPT, through longbook's MCP server. The setup is on [Automate longbook with Claude](/features/automate-longbook-with-claude/).

### Do notes wait in Proposals?

No. A note changes no commitment or charge, so it goes to its card without a review. A note left through the hosted connector at `longbook.app/mcp` reaches its card the next time longbook is open and signed in.

### What if the AI has nothing to say?

Then no mark appears. A card shows the mark only when a note exists for it.
