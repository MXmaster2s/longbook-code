# Building from source

## Prerequisites

- Node.js 20+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — the app's Xcode
  project is generated from `apps/longbook/project.yml` rather than committed
- macOS for the website's images and films: `site:images` uses `sips`, `site:og` needs Google
  Chrome, `site:media` is Swift and `site:fonts` uses Python's fontTools. The pages themselves
  (`site:pages`) build anywhere Node runs, and CI only checks the images by their hashes.

## Working in a worktree

`node_modules/` and the generated Xcode project are both uncommitted, so a worktree made with
`git worktree add` starts out unable to build or run a single script. One command prepares it:

```bash
./scripts/setup-worktree.sh
```

It installs from the lockfile and generates the project, and is safe to re-run.

## The TypeScript side

```bash
npm install
npm run typecheck
npm test
```

## The guards

Run before any commit; CI runs them again:

```bash
npm run lint:comments && npm run lint:transform && npm run guard:name
```

`lint:comments` enforces the 50-word comment ceiling. `lint:transform` blocks CSS re-casing of
product copy. `guard:name` blocks a reserved word. Baselines start empty and only ever shrink.

## The Swift side

`packages/swift-core` is a standalone Swift package — no Xcode project needed to build or test it:

```bash
cd packages/swift-core
swift build
swift test
```

`packages/swift-design` is the design system — colour, type, spacing, and the wrappers every
third-party UI library enters through. It builds and tests the same way, and owns the bundled
typefaces. Its tests assert the contrast, separation, and typography floors, so a token edit that
breaks one fails the build.

## The app

One target builds for both iOS 17+ and macOS 14+, from a generated project:

```bash
cd apps/longbook
xcodegen generate
xcodebuild -project longbook.xcodeproj -scheme longbook -destination 'platform=macOS' build
```

Both packages above are local dependencies of that target rather than copied into it.
`apps/longbook/Widget` is the `LongbookWidget` extension target, generated from the same
`project.yml`.

## Conformance fixtures

`packages/core/tests/fixtures/*.json` are shared test vectors — both `npm test` (TypeScript) and
`swift test` (Swift) load the same files and must agree on every case. Add a case once, in the
fixture; both suites pick it up.
