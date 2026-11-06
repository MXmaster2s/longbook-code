# Releasing longbook

The full map is `docs/releasing.md` (places, numbers, order); iOS and macOS details are in
`docs/releasing-ios.md` and `docs/releasing-macos.md`.

- **Numbers:** the app's version and build live in `apps/longbook/project.yml`; the release number
  for npm, the plugin and the registry is `1.<rulebook revision>.<patch>` (`release.json`).
  `npm run versions` prints every piece and fails on disagreement.
- **Device builds:** `npm run device:install` records the commit in `apps/longbook/device-builds.json`.
  A build number is reused until it goes to TestFlight; after that the next device build takes N+1.
  TestFlight ships exactly a device-tested build.
- **Changelog:** `apps/longbook/Resources/changelog.json` feeds What's New and the release notes page;
  `npm run changelog:check` fails on a missing entry.
- **Before any release:** `npm run release:doctor`, `npm run release:check`, CI green on main.
- **Order:** devices, then the hosted server, then the website, then npm, registry and plugin, then
  TestFlight and the App Store (`docs/releasing.md`).
- **Mac direct download** (disk image on longbook.app): `npm run release:mac-direct`, described in
  `docs/releasing-macos.md`. Same version and build as the other builds. Publish the exact image that
  was tried on a clean Mac (`--publish-built --sha256 <hex>`), then deploy the website, never the
  other way round. `DIRECT` code (Sparkle, Polar checkout, licence-key entry) must stay out of the
  store builds.
