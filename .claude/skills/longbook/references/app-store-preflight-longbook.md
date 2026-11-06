# App Store checks for longbook

Apple's review rules applied to this codebase. Check each line that a change touches.

- **Purchases:** StoreKit 2 in `apps/longbook/Sources/StoreClient.swift`. Prices come from
  `Product.displayPrice` only; `Transaction.updates` and `currentEntitlements` unlock purchases made
  elsewhere; `ownershipType == .familyShared` counts; `AppStore.canMakePayments` is checked; every
  purchase entry point shows its price. `apps/longbook/longbook.storekit` matches App Store Connect
  (both products family-shareable).
- **Server side:** `apple-purchase` validates transactions; `apple-notifications` handles App Store
  Server Notifications V2 (refunds, revokes, family-sharing changes) in order;
  `_shared/family-sharing.ts` decides family access; `apple-account-events` handles Sign in with
  Apple account-delete and consent-revoked events.
- **Refunds:** removing access also shows a message saying what happened. Copy never says Apple
  will refund; Apple decides each request.
- **Account deletion** is in the app (`DeleteAccountSheet.swift`) and warns that a subscription keeps
  billing until cancelled, with a link to manage it.
- **Privacy:** usage data is sent only after the person's choice. `PrivacyInfo.xcprivacy` in
  `apps/longbook/Resources` and `apps/longbook/Widget` lists every collected type and every
  required-reason API (file timestamps C617.1 and 3B52.1); check imports with `nm -u` on the built
  binary. A new data type updates both manifests and `privacy-policy.md` in the same change.
- **Links:** every link the app opens (What's New, Help) exists on longbook.app before the build ships.
- **Direct-download code:** Sparkle, the Polar checkout and licence-key entry are compiled only under
  `DIRECT`. A store build reaches no outside payment page and shows no licence-key field, so
  anything of that kind outside `#if DIRECT` is a rejection risk (guideline 3.1.1).
- **Entitlements:** `apps/longbook/Longbook.entitlements` holds only what the app uses.
- **Listing text and review notes** live in `scripts/asc-listing.mts` (notes under 4,000 bytes,
  labels quoted exactly as the build shows them).
