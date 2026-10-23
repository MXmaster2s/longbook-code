# Contributing

longbook is GPL-3.0. Copyright © 2026 Rohit Kundliwal.

## The licence grant

By submitting a contribution you license it under GPL-3.0 **and** grant the maintainer a
perpetual, irrevocable right to relicense it — including distributing builds containing it
through app stores whose terms are incompatible with unmodified GPL, and offering the work under
other licence terms. This keeps the project distributable on the App Store while staying GPL in
source. If you cannot accept this, open an issue instead of a pull request — reports and ideas
need no grant.

## Dependency policy

Third-party dependencies must be permissively licensed (MIT, Apache-2.0, BSD). No copyleft
dependencies, including GPL: the maintainer cannot extend the app-store grant to code he does not
own.

## The rules that keep the data correct

- The vault contract in [vault format](vault-format.md) is versioned; a change to it bumps the
  contract revision and updates every carrier in the same commit.
- The memory never holds secrets: no fields for card numbers, CVVs, expiries, PINs, or
  credentials, and validators refuse pattern-matched secrets in free text. Changes that weaken
  this are declined.
- Per-currency totals are never blended; multi-month amounts are never amortised; insights say
  nothing rather than guess.

## The rules that keep the repo readable

- Code comments and commit messages: technical, and at most 50 words. Say what changed.
- Brand casing binds all copy: longbook is lowercase everywhere; user data is never re-cased.
- Never bypass the guards (`--no-verify`) and never edit a guard to make a change pass.
