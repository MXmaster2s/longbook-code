---
description: "Add a month report in my longbook. The month's statements recorded, the charges they prove confirmed, and each account's balance set."
argument-hint: "[month]"
---

Run longbook's prompt "Add a month report in my longbook" for the user. What they added: $ARGUMENTS

1. Call the longbook connector's `read_guide` with "add-a-month-report-in-my-longbook". It
   returns the procedure, step by step, and the guide chapter it builds on.
2. Follow that procedure and the guide's rules. Use the month the user named above, or the
   month in progress.
3. If no longbook tools are available, the longbook connector needs signing in: in Claude Code
   run /mcp and sign in to longbook; in the Claude apps, Settings, then Connectors, then longbook.
   Sign in with the longbook account. Without the plugin, add a custom connector with the address
   https://longbook.app/mcp.
