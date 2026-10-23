---
description: "Set up my longbook. Your longbook filled from your statements: every charge on record, the names you picked in setup filled in where your statements or your answers show them, each account's closing balance set, the charges that clearly repeat planned ahead, and the rest set to repeat once you confirm them."
argument-hint: "[anything to add]"
---

Run longbook's prompt "Set up my longbook" for the user. What they added: $ARGUMENTS

1. Call the longbook connector's `read_guide` with "set-up-my-longbook". It returns the
   procedure, step by step, and the guide chapter it builds on.
2. Follow that procedure and the guide's rules.
3. If no longbook tools are available, the longbook connector needs signing in: in Claude Code
   run /mcp and sign in to longbook; in the Claude apps, Settings, then Connectors, then longbook.
   Sign in with the longbook account. Without the plugin, add a custom connector with the address
   https://longbook.app/mcp.
