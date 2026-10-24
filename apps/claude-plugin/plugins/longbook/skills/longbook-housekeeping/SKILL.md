---
name: longbook-housekeeping
description: >
  Use for requests like "clean up duplicates in my longbook", "fix the weird names in my
  expenses", "give me a morning summary of what's due", "Tidy my longbook", "Reorganise my
  longbook", "Set up a morning brief for my longbook", "Set yourself up for a longbook morning
  brief", even when the user does not name longbook. Tidies the user's longbook (doubled
  charges, bank-style names, odd categories) and sets up a morning brief of what is due. Works
  through the longbook connector (https://longbook.app/mcp).
---

# longbook: Housekeeping

longbook is the user's financial memory: every commitment they pay, its charges past and
planned, their accounts and the people payments are for. Tidies the user's longbook (doubled
charges, bank-style names, odd categories) and sets up a morning brief of what is due. Each
prompt below has a procedure on the longbook server; follow it rather than improvising one.

## How to run one

1. Pick the prompt below that matches what the user asked, in our words or theirs.
2. Call the longbook connector's `read_guide` with the prompt's name, for example
   `read_guide("tidy-my-longbook")`. It returns the procedure, step by step, and the guide
   chapter it builds on.
3. Follow that procedure and the guide's rules. Never write a card number, a full account
   number, a PIN or a password.
4. If no longbook tools are available, say the longbook connector is needed: in Claude,
   Settings, then Connectors, then Add custom connector, with the address
   https://longbook.app/mcp, signing in with the longbook account. Installing this plugin adds the
   connector too.

## The prompts

### Tidy my longbook

Name: `tidy-my-longbook`

The user says: "Tidy my longbook".

Result: Doubled charges, bank-style names and odd categories found, and fixed once you approve
each change.

Attachments: none.

Writes to the longbook: yes; it waits in the app's Proposals screen.

### Reorganise my longbook

Name: `reorganise-my-longbook`

The user says: "Reorganise my longbook".

Result: Your whole longbook, once over: names as you would say them, every row categorised,
people and accounts linked, doubles merged, nothing lost. The whole pass waits in Proposals.

Attachments: none.

Writes to the longbook: yes; it waits in the app's Proposals screen.

### Set up a morning brief

Name: `set-up-a-morning-brief`

The user says: "Set up a morning brief for my longbook", "Set yourself up for a longbook
morning brief".

Result: A short summary every morning of what is due today and in the next 30 days. Nothing in
your longbook changes.

Attachments: none. The user's AI's app must support scheduled tasks.

Needs: scheduled tasks in the AI's app.

Writes to the longbook: no.
