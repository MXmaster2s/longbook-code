# Releasing the iOS app

One command archives, exports and uploads a build to App Store Connect, where it becomes a
TestFlight build:

```bash
npm run release:ios
```

Run the pipeline's own audit first. Each line is a requirement and each failure prints the
exact fix:

```bash
npm run release:ios -- --check
```

`--no-upload` stops after the export and leaves the package on disk, for a build you want to
look at before it leaves the machine.

## Both platforms are App Store Connect uploads

The Mac and the iPhone are both signed for Apple to distribute and uploaded to App Store
Connect ([releasing-macos](releasing-macos.md) for the Mac). They share the Apple
Distribution certificate but not an options file: the Mac export also needs the Mac Installer
Distribution certificate and the Mac App Store profile, which `scripts/mas-export-options.plist`
names; `scripts/ios-export-options.plist` names the iOS profile. Both are `app-store-connect`.

Three things every upload has to get right:

1. **A privacy manifest in every bundle.** Apple refuses an upload that uses a required-reason
   API without declaring it. `UserDefaults` is one, and `LongbookCore` uses it — so the widget
   needs its own manifest as well as the app, because an extension is checked as its own
   bundle. Both live beside the code they describe: `Resources/PrivacyInfo.xcprivacy` and
   `Widget/PrivacyInfo.xcprivacy`.
2. **An export-compliance answer.** `ITSAppUsesNonExemptEncryption` is `false` in the app's
   info properties: the app uses HTTPS and the platform's own cryptography, both exempt.
   Without the key, every upload waits on the question being answered by hand.
3. **A build number Apple has not seen.** App Store Connect rejects a repeat, and a rejected
   or replaced build cannot reuse its number. The version is one pair of settings at project
   level, so the app and its extension can never disagree — a mismatch is a rejection.

## The one-time setup

**An App Store Connect API key.** Everything below authenticates with it: the certificate and
the profiles are made through the API with it, and `altool` uploads with it. Create it in App
Store Connect → Users and Access → Integrations → Team keys, with the **App Manager** role,
then:

- put the downloaded `AuthKey_<key id>.p8` at `~/.appstoreconnect/private_keys/`, which is
  where Apple's own tools look. **Nowhere else works**: `xcodebuild` refuses a key under
  `/private` with `must be an absolute path to an existing file` even when the file is plainly
  there and readable, which sends you looking for a missing file rather than a rejected path;
- store the key id in the login keychain as **App Store Connect Key ID**, and the issuer id
  as **Apple App Store Connect Issuer ID**;
- optionally store the App Review contact phone as **App Review Contact Phone**. `asc:listing` reads it
  only to create a review record that does not exist yet; an existing record keeps its own.

The file name and the stored key id must name the same key — a key id with no matching `.p8`
authenticates as nothing, and the failure is a bare 401.

The key is downloadable exactly once. If it is lost, revoke it and make another; there is no
way to fetch it again.

**Then, once a year:**

```bash
npm run asc:provision
```

It creates the Apple Distribution certificate and one App Store profile per bundle id, and
installs the profiles where `xcodebuild` looks. Run it again when the certificate expires; it
reuses anything that already exists.

**Why that command has to exist.** Xcode's automatic signing creates *development*
certificates on demand but never distribution ones, so the first export fails with `No profiles
for 'app.longbook.longbook' were found`. Adding `-allowProvisioningUpdates` does not fix it: it
routes the export through Apple's **cloud signing**, which answers `Cloud signing permission
error` for a key without that entitlement — and then reports the same misleading
"no profiles" line. The export options therefore name the profiles and sign manually, and
`asc:provision` is what puts them there. The names in
`scripts/ios-export-options.plist` and the names that command prints must match.

`xcodegen` regenerates the project from `project.yml` on every release, so nothing else is kept
by hand.

## What the pipeline does

1. `xcodegen generate`, so the project always matches `project.yml`.
2. Archives for `generic/platform=iOS`.
3. **Reads the version back out of the archived app** and refuses if it differs from
   `project.yml`, so a build never reports a version other than the one it was archived as.
4. Exports with `app-store-connect`, `manageAppVersionAndBuildNumber` off so Xcode cannot
   rewrite the number that was just checked.
5. Uploads with `altool`.

Processing on Apple's side takes minutes, sometimes longer, before the build appears in
TestFlight.

## Internal testing, then a public link

**Internal testers** — people on the App Store Connect team — get a build with no review at
all, as soon as it finishes processing. That is the fastest way to put the app on a phone.

**A public TestFlight link needs an external group**, and the first build in one goes through
**Beta App Review**. That review applies the App Store guidelines, so three things have to be
true before it is worth submitting:

- **An account can be deleted from inside the app** (guideline 5.1.1(v)). Sign-in is
  mandatory, so this is not optional.
- **No purchase is offered outside Apple's own** (guideline 3.1.1). The price and the buy
  controls are hidden behind `TrialRibbon.purchasable` for exactly this reason.
- **A subscription states its terms before it is bought** (guideline 3.1.2). The app sells two
  purchases: the one-time licence, made by `npm run asc:iap`, and longbook Cloud, a monthly
  auto-renewable subscription, made by `npm run asc:subscription` (`--check` reads and reports
  without writing; run that first). The Cloud sheet shows the price StoreKit returns, the
  period, what it covers and links to Terms and Privacy, and the listing's description carries
  the Terms of Use link, which `asc:listing` writes.

The external group also needs Test Information: a privacy policy URL, a feedback address, and
sign-in instructions. Reviewers cannot receive a one-time code at someone else's address, so
tell them to use **Continue with Apple**.

## The device family

The app builds iPhone-only (`TARGETED_DEVICE_FAMILY` is `1` on the iOS SDKs; macOS ignores
it). An iPad build is a second layout to design and a second set of screenshots to review,
and nothing is written for that width yet. Widening it later is a settings change and a
design pass, in that order.

## What to test, and the app's own changelog

TestFlight's "What to Test" for a build is the newest entry of
`apps/longbook/Resources/changelog.json`, the same file the app's Check for updates screen shows.
Add the version's entry before the build is cut; `npm run changelog:check` (in CI) refuses a
changelog whose newest entry does not name the version and build `project.yml` builds.
