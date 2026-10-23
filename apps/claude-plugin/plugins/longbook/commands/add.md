---
description: "Add a commitment or an expense. A new commitment planned ahead, or a one-time expense recorded, on the account and for the person you name."
argument-hint: "[anything to add]"
---

Run longbook's prompt "Add a commitment or an expense" for the user. What they added: $ARGUMENTS

1. Call the longbook connector's `read_guide` with "add-a-commitment-or-an-expense". It returns
   the procedure, step by step, and the guide chapter it builds on.
2. Follow that procedure and the guide's rules.
3. If no longbook tools are available, the longbook connector needs signing in: in Claude Code
   run /mcp and sign in to longbook; in the Claude apps, Settings, then Connectors, then longbook.
   Sign in with the longbook account. Without the plugin, add a custom connector with the address
   https://longbook.app/mcp.
