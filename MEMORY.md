# MEMORY.md

The project's technical state, for anyone working in this repository. One dated line each, newest
first. Changed through pull requests like any file. Procedures belong in
`.claude/skills/longbook/`, not here.

## Now

- App 1.5.0, build 67 (`apps/longbook/project.yml`). Release number 1.50.0: rulebook revision 50, patch 0 (`release.json`).
- Mac direct download live since 2026-11-04: GitHub release `mac-1.5.0-67`, appcast at longbook.app/appcast.xml, sale through Polar (`supabase/functions/polar-*`).
- iPhone beta on TestFlight is 1.5.0 (66); the App Store and Mac App Store submissions have not started.
- Targets: iOS 17.0 and macOS 14.0 from one SwiftUI target; Swift 5.10 language mode; iPad runs in compatibility mode only.

## Decisions

- 2026-11-05 · Agent entry files added: `CLAUDE.md` imports `AGENTS.md`; skills live in `.claude/skills/longbook/`.
- 2026-11-03 · Family Sharing: family copies of the licence and Cloud subscription are honoured by the server (`supabase/functions/_shared/family-sharing.ts`).
- 2026-11-03 · Sign in with Apple server-to-server events are handled by `apple-account-events`.
- 2026-10-30 · A transfer is only between accounts the user owns; card bills are charges (rulebook revision 50).

## Half done

- Polar checkout code (`PolarFunctions`) is still compiled into store builds, unreachable; gate it with `#if DIRECT` before any store submission.
- No in-app nudge for a new Mac version yet; Sparkle's own check is on by default.
