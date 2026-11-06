# longbook.app — the generated parts of the site

The pages in `apps/longbook-site` are hand-written HTML. This folder holds everything that is
**shared** between them or **generated** for them, and `npm run site:pages` builds it:

| Source here | Becomes |
|---|---|
| `chrome/header.html`, `chrome/header-home.html`, `chrome/footer.html` | the header and footer of every page, between the `chrome:` markers |
| `features/<slug>.md` | `/features/<slug>/` (the page) and `/features/<slug>.md` (its Markdown copy) |
| all of `features/` | `/features/` (the index) and `/features.md` |
| `about.md` | the About longbook block at the end of every feature page |
| `automations.md` | `/automations/` and `/automations.md`: the feature pages it names, each beside its screens, then how to connect an AI |
| `screens.json` | which app screenshot each page shows, with its title and description |

It also writes, from the same sources: a Markdown copy of every listed page (`/faq.md`,
`/index.md`, …), the structured data in the home, FAQ and feature pages, `sitemap.xml`,
`_headers`, and the `features:` block of `_redirects`.
Every page's links to `tokens.css` and `features/features.css` carry the file's content hash
(`?v=…`), because browsers keep a stylesheet for four hours and a new page must never meet an old one.

## Editing a feature page

A feature file has a short frontmatter and fixed sections, in this order: a one-paragraph
summary, `## On the screen`, `## What it does` (two to four `###` blocks), `## Why it exists`, and
an optional `## Questions` (`###` per question). Inline, only `**bold**`, `` `code` `` and links to
another feature (`/features/<slug>/`) or a known page are allowed.

`labels:` lists the app's own words the page quotes. The build fails if the app stops showing one
of them, so a renamed button cannot leave a page describing a screen that no longer exists.

## Commands

- `npm run site:pages` — build everything above. `site:pages:check` verifies instead (CI runs it).
- `npm run site:pages:lint` — check the sources only; writes nothing.
- `npm run site:images` — turn the newest version of each screenshot in `images/screenshots` into
  the JPEGs under `features/img`, with title, description and copyright written into each file.
  macOS only; run it after replacing a screenshot, then `site:pages`.
- `npm run site:og` — render every page's 1200×630 share image from a local copy of the site with
  headless Chrome. Run it last, after `site:pages`.
- `npm run site:pages:test` — the builder's own tests.

A screen with `"source": null` in `screens.json` has no screenshot yet; its page shows an empty
frame until one is added and `site:images` is run.

## Refreshing the screenshots

Every screenshot is taken from the app itself, with made-up data and without using anyone's screen:

1. `npm run demo:vault -- <folder>` writes an invented household, dated around today.
2. **Mac:** build the app unsigned in Debug, then run its binary with `LONGBOOK_VAULT_PATH=<folder>`,
   `LONGBOOK_SNAPSHOT=<out.png>`, `LONGBOOK_SNAPSHOT_HEIGHT=<px>` and `LONGBOOK_SNAPSHOT_SCREEN=<screen>`.
   It draws that screen into a window that never appears, writes the PNG and quits.
3. **iPhone:** use an iPhone 17 Pro simulator in dark mode, with its status bar set to 9:41.
   1. Copy the folder into the app's `Documents/longbook`.
   2. Launch the app with `SIMCTL_CHILD_LONGBOOK_SKIP_AUTH=1` and `SIMCTL_CHILD_LONGBOOK_SNAPSHOT_SCREEN=<screen>`.
   3. Take the picture with `xcrun simctl io <device> screenshot`.
4. Save each picture as the next `-vN` of its file in `images/screenshots`. Then run
   `site:images`, `site:pages` and `site:og`.

How `images/screenshots/ios` and `/mac` are kept:
- **Numbers.** Each number follows the order a person meets the screen. First run, setup and
  reading a statement come first. The iPhone then follows its tabs: Dashboard, Calendar, the add
  button, Reports and More. The Mac follows its sidebar.
- **New screens.** A new screen takes the number of its place, and the screens after it move up.
  Update `screens.json`, `screens.lock.json` and `media-kit/kit.json` in the same change.
- **Older pictures.** The latest version of each current screen stays at the top level. Older
  versions, and screens a redesign replaced, go in `old-versions/`.
- **Where the site looks.** `site:images` reads only the top level of each folder.
- **Store pictures.** The unnumbered files (`dashboard.png` and the others) are the App Store
  set, and stay as they are.

Two captures need care:
- `LONGBOOK_SNAPSHOT_REVIEW` seeds a review by writing into the folder it opens. Give that
  capture a copy of the folder, and take it last.
- The Mac's Data & privacy screen prints the folder's path, so picture it from a neutral path such
  as `~/longbook`, and remove that folder afterwards.
