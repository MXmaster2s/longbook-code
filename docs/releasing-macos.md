# Releasing the macOS app

The Mac ships through the Mac App Store, and only there: the same record, purchase and
review as the iPhone, one build uploaded from this machine.

```bash
npm run release:mas
```

It generates the project, archives the Mac target in Release configuration, exports it as
an installer package signed for Apple to distribute, and uploads it to App Store Connect.
The build then appears in TestFlight for Mac, and a submission sends it to review.
`--check` audits the prerequisites; `--no-upload` stops after the export.

## Prerequisites

Everything the iOS release needs ([releasing-ios](releasing-ios.md)) — the App Store
Connect key in the keychain, the Apple Distribution certificate — plus two things
`npm run asc:provision` makes on the same account: the **Mac Installer Distribution**
certificate the package is signed with, and the **longbook Mac App Store** provisioning
profile `scripts/mas-export-options.plist` names.

## What the store changes

- **The sandbox.** `LongbookMac.entitlements` carries `com.apple.security.app-sandbox`,
  user-selected file access, network access, iCloud and Sign in with Apple. The vault
  folder is reached through the iCloud container or a security-scoped bookmark of the
  folder the reader picked; Claude Desktop's configuration folder is granted once through
  the system's open panel and kept as a bookmark.
- **Updates come from the store.** There is no update engine in the app and no appcast to
  maintain; the Mac's Buy button is StoreKit, the same purchase as the iPhone's.
- **Review.** Every Mac release passes App Review before it reaches anyone.
