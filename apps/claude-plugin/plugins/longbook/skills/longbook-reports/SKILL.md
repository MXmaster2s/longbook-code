---
name: longbook-reports
description: >
  Use for requests like "make a report of my Goa trip", "a report of what we spent on the kids
  this quarter", "create a report for my business card", "Create a report in my longbook",
  "Make a report of my Goa trip in my longbook", even when the user does not name longbook.
  Asks longbook to draw a report over the days, accounts, people or categories the user
  chooses, or for a trip. Works through the longbook connector (https://longbook.app/mcp).
---

# longbook: Reports

longbook is the user's financial memory: every commitment they pay, its charges past and
planned, their accounts and the people payments are for. Asks longbook to draw a report over
the days, accounts, people or categories the user chooses, or for a trip. Each prompt below has
a procedure on the longbook server; follow it rather than improvising one.

## How to run one

1. Pick the prompt below that matches what the user asked, in our words or theirs.
2. Call the longbook connector's `read_guide` with the prompt's name, for example
   `read_guide("create-a-report-in-my-longbook")`. It returns the procedure, step by step, and the guide
   chapter it builds on.
3. Follow that procedure and the guide's rules. Never write a card number, a full account
   number, a PIN or a password.
4. If no longbook tools are available, say the longbook connector is needed: in Claude,
   Settings, then Connectors, then Add custom connector, with the address
   https://longbook.app/mcp, signing in with the longbook account. Installing this plugin adds the
   connector too.

## The prompts

### Create a report in my longbook

Name: `create-a-report-in-my-longbook`

The user says: "Create a report in my longbook".

Result: A report over the days, accounts, people and categories you choose, on the Reports
screen the next time the app is open. It counts confirmed charges only.

Attachments: none.

Writes to the longbook: yes; it waits in the app's Changes screen.

### Make a report of my trip

Name: `make-a-report-of-my-trip`

The user says: "Make a report of my Goa trip in my longbook", "Make a report of my Goa trip".

Result: A report of your trip's spending on the Reports screen, filling in as the trip's
charges are confirmed.

Attachments: none.

Writes to the longbook: yes; it waits in the app's Changes screen.
