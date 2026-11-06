---
description: "Find insurances from my email. Your insurance policies found in your mail: each with its premiums as charges, its next premium planned, and its policy details in its notes."
argument-hint: "[anything to add]"
---

Run longbook's prompt "Find insurances from my email" for the user. What they added: $ARGUMENTS

1. Call the longbook connector's `read_guide` with "find-insurances-from-my-email". It returns
   the procedure, step by step, and the guide chapter it builds on.
2. Follow that procedure and the guide's rules.
3. This prompt reads the user's mail through a mail connector; the plugin bundles Gmail. If
   none is signed in, say so and stop.
4. If no longbook tools are available, the longbook connector needs signing in: in Claude Code
   run /mcp and sign in to longbook; in the Claude apps, Settings, then Connectors, then longbook.
   Sign in with the longbook account. Without the plugin, add a custom connector with the address
   https://longbook.app/mcp.
