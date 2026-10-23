---
slug: longbook-npm-package
order: 22
group: automate
title: Use your longbook in any AI app on your computer
seo_title: longbook on npm: your expenses in any AI app
description: One npx command runs longbook's MCP server on your own computer, so Cursor, VS Code, Claude Code and other AI apps read your longbook, free and private.
card: One command lets Cursor, VS Code, Claude Code and other AI apps on your computer read your longbook, free and private.
platforms: mac
mac: mac-mcp-server
aliases: npm, npx, longbook-mcp-npm, local-mcp-server, longbook-mcp-package
related: automate-longbook-with-claude, keep-your-longbook-in-your-own-icloud, review-every-change-your-ai-makes
labels: Set Up Claude Desktop, Copy configuration
film: A 30-second film of longbook on npm
---

Want the AI app you already have open all day to know what you owe this month? Run longbook's MCP server on your own computer with one command, and Cursor, VS Code, Claude Code or any other MCP app reads your longbook folder directly. Add it in your AI app and consider it done.

`npx -y @longbook/mcp@latest`

## On the screen

On Mac, **Automations** with the longbook MCP server. The server built into the app is the same one this package runs: on a Mac without the app's setup, on Windows, on Linux, in any app that starts MCP servers.

## What it does

### Works in the AI apps you already use

Cursor, VS Code with GitHub Copilot, Claude Code, Claude Desktop, Codex CLI, Gemini CLI and any other app that starts MCP servers take the same line. Each app's settings are on the [Automations page](/automations/).

### Free and private

It reads the files in your longbook folder on the computer it runs on. Nothing goes to longbook's server: there is no hosted copy, no account to sign in to and no longbook Cloud to pay for, and it works offline.

### The same answers and the same rules

It is the server the Mac app runs. It answers what is due, what renews and what a month cost, reads the statements in your documents folder. Every change it makes is written to your folder at once and shows in **Changes** with the AI's name on it, to keep or undo.

### Any computer that has your folder

On a Mac it finds your longbook in iCloud Drive by itself. On Windows or Linux, point it at the folder with `--vault`, for example the longbook folder iCloud for Windows keeps in sync.

## Why it exists

Want your longbook one question away in the editor, terminal or assistant you already work in, without a copy of it on anyone's server? A server on your own computer reads the files where they are. longbook's folder is plain files you own, so the server that reads it is free and open source, and anyone can check what it does.

## Questions

### Do I need longbook Cloud?

No. longbook Cloud is for the hosted connector at `longbook.app/mcp`, which works from any device, including iPhone and claude.ai. This package works only on the computer it runs on, and is free.

### Do I need the longbook app?

Yes. The server reads a longbook folder, which the longbook app creates. Your AI's changes take effect in the folder straight away, and you review them, keeping or undoing each one, in longbook on your Mac or iPhone.

### Is it free?

The server is free and open source, and nothing in it checks for a licence, so technically you can use longbook through it for free, forever. longbook is a one-time purchase with a 7-day refund, $38 for the first 100 buyers, and one person makes it. If you are at home in a terminal, please consider buying the licence anyway: it is what keeps longbook getting better. [Why we built longbook](/why-we-built-longbook/).

### What does my computer need?

Node.js 18 or later, the same as most MCP servers. `npx` comes with it, downloads the newest release when your AI app starts the server, and keeps nothing else installed.

### How do I add it to my AI app?

Add a server named longbook with the command `npx` and the arguments `-y` and `@longbook/mcp@latest`, then restart the app. On Windows or Linux, add `--vault` and your longbook folder's path. The [Automations page](/automations/) has the exact settings for each app, and the code is on [npm](https://www.npmjs.com/package/@longbook/mcp).
