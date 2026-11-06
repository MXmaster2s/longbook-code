---
description: "Create a report in my longbook. A report over the days, accounts, people and categories you choose, on the Reports screen the next time the app is open."
argument-hint: "[anything to add]"
---

Run longbook's prompt "Create a report in my longbook" for the user. What they added: $ARGUMENTS

1. Call the longbook connector's `read_guide` with "create-a-report-in-my-longbook". It returns
   the procedure, step by step, and the guide chapter it builds on.
2. Follow that procedure and the guide's rules.
3. If no longbook tools are available, the longbook connector needs signing in: in Claude Code
   run /mcp and sign in to longbook; in the Claude apps, Settings, then Connectors, then longbook.
   Sign in with the longbook account. Without the plugin, add a custom connector with the address
   https://longbook.app/mcp.
