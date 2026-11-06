# AGENTS.md

This repository is **longbook**: a native SwiftUI app for iPhone and Mac that keeps a memory of
financial commitments in a folder the user owns, an MCP server that lets the user's own AI read
and update that memory, a Supabase backend, and the longbook.app website.

## Start here, every session

1. Read `MEMORY.md`. It holds the current version, what is half done, and decisions worth knowing.
2. Run `git status` and `git log --oneline -10`. If `MEMORY.md` disagrees with the repository, the
   repository is right: correct `MEMORY.md` in the same change.
3. For any task, load the `longbook` skill (`.claude/skills/longbook/SKILL.md`). It routes to a
   reference for each kind of work; read a reference when its work starts, not before.

## Hard rules

1. Work in a git worktree, never in the main checkout. Prepare a new one with
   `./scripts/setup-worktree.sh`.
2. Code comments and commit messages are technical and at most 50 words. Say what changed.
3. longbook is lowercase everywhere; user data is never re-cased.
4. Never bypass a guard (`--no-verify`) and never edit a guard to make a change pass. Fix the content.
5. Stage files by explicit path, never `git add -A`.
6. Never commit a secret, a machine path, or an AI attribution line; `npm run guard:leak` refuses them.
7. No new dependency without asking. Dependencies must be permissively licensed (MIT, Apache-2.0, BSD).
8. The vault contract is versioned: a change bumps the contract revision and updates every carrier
   in the same commit (see `docs/vault-format.md`).
9. Merging, deploying, applying migrations, publishing and store uploads or submissions need the
   maintainer's go-ahead each time. Pushing a branch and opening a pull request is part of the task.

## Build and test

```bash
./scripts/setup-worktree.sh        # npm ci + generate the Xcode project; safe to re-run
npm run typecheck && npm test      # TypeScript
npm run lint:comments && npm run lint:transform && npm run guard:name
(cd packages/swift-core && swift test)
(cd apps/longbook && xcodegen generate)
xcodebuild -project apps/longbook/longbook.xcodeproj -scheme longbook \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project apps/longbook/longbook.xcodeproj -scheme longbook \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

CI runs the full list in `.github/workflows/ci.yml`; run the checks that touch your change before
opening a pull request.

## Where things are

| Path | What |
|---|---|
| `packages/core` | The domain engine in TypeScript: dates, money, selectors, insights, the data-policy scanner |
| `packages/swift-core` | The same data layer in Swift, shared by both app targets (iOS 17+, macOS 14+) |
| `packages/swift-design` | The design system: colour, type, spacing, SwiftUI pieces |
| `packages/mcp` | The MCP server: local over stdio, and the engine behind the hosted one at `longbook.app/mcp` |
| `packages/cards` | HTML cards over the same numbers |
| `supabase/` | Accounts, entitlements, purchases, the hosted MCP and copy, statement reading, report sharing |
| `apps/longbook` | The SwiftUI app: one target for iOS and macOS, plus the widget |
| `apps/longbook-site` | The static website and its edge functions |
| `scripts/` | Build, check, release and deploy scripts (`package.json` lists them) |
| `docs/` | Architecture, vault format, agentic tools, building, releasing, contributing |
