---
description: "Set up a daily longbook email round. Your AI reads your mail every morning at 6 and records the money that moved, so your longbook stays current without you asking."
argument-hint: "[anything to add]"
---

Run longbook's prompt "Set up a daily longbook email round" for the user. What they added: $ARGUMENTS

1. Call the longbook connector's `read_guide` with "set-up-a-daily-longbook-email-round". It
   returns the procedure, step by step, and the guide chapter it builds on.
2. Follow that procedure and the guide's rules.
3. This prompt reads the user's mail through a mail connector; the plugin bundles Gmail. If
   none is signed in, say so and stop.
4. If no longbook tools are available, the longbook connector needs signing in: in Claude Code
   run /mcp and sign in to longbook; in the Claude apps, Settings, then Connectors, then longbook.
   Sign in with the longbook account. Without the plugin, add a custom connector with the address
   https://longbook.app/mcp.
