# Releasing the macOS app

The Mac ships two ways from the same code: the Mac App Store (this page, up to "The direct
download" below) and a notarised disk image on longbook.app. The store build is the same record,
purchase and review as the iPhone, one build uploaded from this machine.

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
- **Updates come from the store.** The store build has no update engine and no appcast; the
  Mac's Buy button is StoreKit, the same purchase as the iPhone's. The direct download below
  is a separate build (the `longbook-direct` scheme, `DIRECT` compilation condition) that
  updates itself.
- **Review.** Every Mac release passes App Review before it reaches anyone.

## The direct download

The disk image on longbook.app is the same app built by the `longbook-direct` scheme and signed
with Developer ID. Sparkle checks `longbook.app/appcast.xml` for updates, Buy opens a Polar
checkout in the browser, and a licence key can be entered in the app. Those parts are compiled
only when `DIRECT` is set; the store builds contain none of them.

```bash
npm run release:mac-direct -- --check       # audit the prerequisites
npm run release:mac-direct -- --no-publish  # build, notarise and test the image by hand
npm run release:mac-direct -- --publish-built --sha256 <hex>   # publish that exact image
```

- **Order:** the disk image is built and tried on a clean Mac first. Publishing creates the GitHub
  release (`mac-<version>-<build>`, assets `longbook.dmg` and `longbook-<version>-<build>.dmg`)
  and the appcast entry. The website is deployed after the release exists, so the Download
  button never points at nothing.
- **Same number everywhere:** a direct release carries the version and build of the iPhone and
  store builds, and the build must be the one recorded as device-tested in
  `apps/longbook/device-builds.json`.
- **Server side:** `polar-checkout`, `polar-claim` and `polar-webhook` in `supabase/functions`
  make the sale and the licence; their secrets are set in Supabase, never in this repository.
- Before a release, walk it through on a clean Mac: install, first run, purchase, the server
  records and the emails.
