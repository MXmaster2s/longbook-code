---
slug: automate-longbook-with-claude
order: 14
group: automate
title: Automate longbook with Claude
seo_title: Connect Claude to your subscriptions and expenses
description: Claude reads your longbook and writes into it through longbook's MCP server: what is due, what was spent, and new charges from statements and email.
card: Claude reads your longbook and keeps it up to date through longbook's MCP server.
platforms: iphone, mac
iphone: iphone-own-ai
mac: mac-mcp-server
aliases: automate-your-longbook-with-your-claude, connect-claude-to-longbook, longbook-mcp-server
related: review-every-change-your-ai-makes, log-expenses-from-gmail, get-insights-about-your-expenses-from-your-ai
labels: Let AI Read My longbook, Set Up Claude Desktop, Copy configuration, Allow suggested changes
---

Claude reads your longbook and writes into it through longbook's MCP server. It answers what is due and what a month cost, and adds the charges it finds.

## On the screen

On iPhone, the statement import's route through Claude: the steps that turn on the longbook MCP server and add the connector in Claude. On Mac, **Automations** with the longbook MCP server on: a hosted copy for Claude on any device, and one-click setup of Claude Desktop on the Mac itself.

## What it does

### Answers from your own records

Claude calls longbook's tools to answer: the next payment, what is due in the next two weeks, spending by category, account or member, and a search across every commitment.

### Writes that wait for you

Claude can add commitments and charges, mark a charge paid, cancel a commitment or leave an insight. Each change is checked against longbook's format and shows in **Changes**, to keep or undo.

### Two ways to connect

On a Mac, **Set Up Claude Desktop** connects Claude to the folder directly, with no hosted copy; what Claude reads goes to Claude as part of the conversation. Anywhere else, Claude connects to `longbook.app/mcp` and reads a hosted copy that only your account can reach.

## Why it exists

The questions people ask about money are rarely the ones an app has a button for. A memory an AI can read answers them in plain words, and one it can write to stays current without typing.

## Questions

### Which AI assistants work with longbook?

Claude, ChatGPT and any other assistant that supports MCP connectors. Claude Desktop on a Mac can also connect to the folder directly. The full setup is on the [Automations page](/automations/).

### Can Claude change my longbook without me knowing?

No. Every change Claude makes shows in Changes with Claude named as its author. Through the hosted connector, a signed-in Claude can only suggest changes, and only after **Allow suggested changes** is turned on in the app.

### What does the hosted copy hold?

A copy of the memory file, uploaded when the MCP server is enabled. It is deleted when the server is switched off, or after ninety days without the app being opened.
