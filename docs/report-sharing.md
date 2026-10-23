# Report sharing (v1)

A shared report is one report JSON (see [report-format.md](report-format.md)), copied out of
the vault at the moment of sharing and held by the share server until the link dies. The
server never sees the vault — not the files, not the history, not the other reports. It holds
exactly the one report the owner chose to share, and nothing arrives except by that choice.

Sharing is for people outside longbook. A share is a link plus a password: the link opens a
viewer page drawn like the app's report screen, the password unlocks the report, and the
viewer may leave one comment per module — a text box behind a comment icon. The owner later
pulls the comments back into the vault.

## The flow

1. The owner's app calls `create` with the report JSON and gets back `{id, password, url,
   expires_at}`. The url is `https://longbook.app/r/<id>` — the site proxies it to the
   function. The password is returned once and never again.
2. The owner passes the url and the password along, ideally on separate channels.
3. The viewer opens the url, types the password, reads, and comments.
4. The owner calls `comments` to collect what was said — then `revoke`, or just lets the
   clock run out.

## The actions

The viewer page is the site's own, `longbook.app/r/<share id>`; it reads the id from its
address and talks to the Edge Function through the site's `/share-report` proxy. A `GET` on
the function with an id redirects there. Every other call is a `POST` whose JSON body carries
an `action`:

- `create` — requires `Authorization: Bearer <user jwt>`. Body `{report, hours}`; `hours`
  clamps to 1..168 and defaults to 72. Replies `{id, password, url, expires_at}`.
- `view` — body `{id, password}`. Replies `{report, comments, expires_at}`. `404` unknown
  link, `410` expired, `403` wrong password. The page says each of these in its own words,
  chosen by the status; the server's plain-text reason is never shown.
- `comment` — body `{id, password, module_id, author, body}`. `body` is required, at most
  2000 characters; `author` is optional, at most 80; both are stored exactly as typed.
  Replies `{ok: true}`.
- `revoke` — requires the owner's jwt. Body `{id}`. Deletes the share. Replies `{ok: true}`.
- `comments` — requires the owner's jwt. Body `{id}`. Replies `{comments}`, each with
  `{module_id, author, body, created_at}`.

Comments carry the module's `id`; a module without one gets `module-<index>` from its
position in the report. A drawn report writes no module `id`, so in practice every comment
is keyed by position, and `ReportReader.mergeViewerComments` finds the module that way.

## What the viewer draws

`apps/longbook-site/r/index.html` is one static page: an inline stylesheet built on the
site's `tokens.css`, and an inline script. The script is generated — `npm run site:viewer`
bundles `r/viewer.src.mts` (the page) and `r/report-view.mts` (the words and numbers, with no
page in them) and writes the bundle between the `viewer:begin` and `viewer:end` markers,
with `tokens.css` linked by content hash. CI runs `site:viewer:check`, so a hand edit inside
the markers fails. Every string reaches the page through text nodes, never markup.

It draws what the app's report screen draws (`ReportDetailView.swift`), by the rules in
[report-format.md](report-format.md):

- **Header** — the report's title; its days ("1–31 August 2026", "28 September – 3 October
  2026", a single day as "1 October 2026"), else "Written 7 August 2026"; then the scope line
  ("Accounts: HDFC, Cash · Members: Rohit"). The subtitle is never shown.
- **Sections** — each module's title as a heading over its card.
- **Total expenses** — the first money stat as the figure, other-currency sums beside it
  ("+$20"), the change ("▲ 9.6% vs June", coloured by `delta_is_good`), and every other stat
  on one line ("3 charges · 1 not yet confirmed · Money in ₹1,50,000").
- **Accounts** (any donut not titled "Categories") — an inline-SVG ring with the top slice's
  share and "From <name>" at its centre, and a legend: swatch, name, share, amount. A slice
  in another currency is listed with a hollow swatch and no share.
- **Categories** — a scrolling strip of tiles: the category's ink, its name, amount and share.
- **All charges** — searched and narrowed by category, account, member and currency from the
  rows alone; each row a card with the category's ink, its name, date, category, member and
  account, and the amount. Rows the owner took out follow under "Removed from this report",
  faded; ids in `hidden_ids` are listed nowhere.
- `bars`, `prose` and an unknown type still render, so an older shared file reads; a version
  1 file reads too.
- A footer: "Shared from longbook" and when the link expires.

Every module carries the owner's pulled-back note under its card and a comment box below
that. The Removed block belongs to the charge list's module and has no box of its own, so
the keys stay `id` or `module-<index>`. The page follows the viewer's system appearance
unless they chose one on longbook.app, and its colours, type and radii are the site's tokens.

The page holds its own copy of four things the app owns: the money format (`fmtMoney`), the
`0.004`-of-a-turn shave that parts two arcs, the share format ("62%", "4.5%"), and the "first
letter up" rule gated on a module titled exactly `"Categories"`. A change to any of them in
the app is a change here too, or the two surfaces stop matching. The ring's inks come from
`--lb-data-0` to `--lb-data-11` and `--lb-neutral-fold` in `tokens.css`.

## The password

Three short words and two digits, hyphen-joined — `ember-salt-pine-47`. It is generated
server-side, returned once from `create`, and stored only as a salted SHA-256 hash. There is
no reset and no reminder: a lost password means revoke and share again.

## Expiry and revoke

A link lives 72 hours: the app asks for that, and the function clamps any `hours` it is given
to 1..168. Expiry is not a soft state: the first touch past the deadline deletes the row.
`revoke` is the same deletion on demand. Either way the report, its password hash, and every comment are gone.
A dead link holds nothing.

## What the server holds

One row per share: the report JSON, the password hash and salt, the owner's id, the
deadline. Comments sit in a second table beside it. Both tables have row level security
enabled with no client policies at all — nothing reads or writes them except the Edge
Function, with the service-role key. There is no path from this server back into a vault,
because a vault was never given to it.
