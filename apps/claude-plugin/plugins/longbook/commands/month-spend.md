---
description: "What did I spend in a month? What you spent in that month, and what is not yet confirmed."
argument-hint: "[month]"
---

Run longbook's prompt "What did I spend in a month?" for the user. What they added: $ARGUMENTS

1. Call the longbook connector's `read_guide` with "what-did-i-spend-in-a-month". It returns
   the procedure, step by step, and the guide chapter it builds on.
2. Follow that procedure and the guide's rules. Use the month the user named above, or the
   month in progress.
3. If no longbook tools are available, the longbook connector needs signing in: in Claude Code
   run /mcp and sign in to longbook; in the Claude apps, Settings, then Connectors, then longbook.
   Sign in with the longbook account. Without the plugin, add a custom connector with the address
   https://longbook.app/mcp.
