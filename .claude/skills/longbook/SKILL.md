---
name: longbook
description: Use for any work in the longbook repository (app, MCP server, Supabase functions and migrations, website, releases). Routes to the reference for each kind of work and holds the checks a change must pass.
---

# Working on longbook

Read `MEMORY.md` at the repository root first. Then read the one reference below that matches the
work, when that work starts.

| Work | Read |
|---|---|
| Finding your way, adding a file, changing a package | `references/project-structure.md` |
| Any Swift code: views, state, concurrency (read before writing) | `references/swift-code-longbook.md` |
| Any screen, control, sheet, sign-in or copy in the app | `references/apple-hig-longbook.md` |
| Purchases, subscriptions, privacy, sign-in, account deletion, anything Apple reviews | `references/app-store-preflight-longbook.md` |
| Version and build numbers, TestFlight, the changelog, live places | `references/release-longbook.md` |
| The website, its generated pages and edge functions | `references/site-longbook.md` |
| App Store screenshots: capture, frame, upload | `references/store-screenshots-longbook.md` |

## Every change

1. In a worktree (`./scripts/setup-worktree.sh` prepares it).
2. Tests for any logic you change; the Swift side builds for both iOS Simulator and macOS.
   Swift changes follow `references/swift-code-longbook.md` and the PR says what was checked against.
3. The checks your change touches, from `.github/workflows/ci.yml`. Always: `npm run typecheck`,
   `npm test`, `npm run lint:comments`, `npm run guard:name`, `npm run guard:leak -- --staged`.
4. Staged by explicit path; commit message technical, at most 50 words.
5. `MEMORY.md` updated if the change alters state or a decision worth knowing.

## Done when

- The change builds on both targets (for app changes), every check it touches passes locally, the
  pull request is open with a description of what changed and how it was tested, and `MEMORY.md`
  is current.

## Go-ahead

- Pushing a branch and opening a pull request: allowed for the task you were given.
- Merging, deploying (`deploy:servers`, `site:deploy`, `function:deploy`), applying migrations,
  publishing (npm, registry, plugin) and store uploads or submissions: the maintainer, each time.
