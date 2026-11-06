# The website

- **Where:** `apps/longbook-site`, a static site with edge functions (`/mcp` and shared reports).
- **Generated vs hand-edited:** `npm run site:pages` builds the stamped pages and the `.md` copies;
  `index.html` and `faq/index.html` are edited directly. `npm run site:pages:check` fails on drift;
  `site:pages:test` and `site:pages:lint` run the page tests and lint.
- **Checks that often bite:** renaming an app label can fail `site:pages:check` (edit the
  `site-content` Markdown and regenerate); `help:articles:check` keeps in-app help and the site in
  step; `site:consent:check` and `site:analytics:check` keep measurement and the privacy policy aligned.
- **Images and films:** `site:images` (needs `sips`), `site:og` (needs Chrome), `site:media` (Swift);
  CI checks them by hash only.
- **Deploy:** `npm run site:deploy`, from a tree that contains everything already live, with the
  maintainer's go-ahead. A deploy from a stale checkout silently removes newer pages.
