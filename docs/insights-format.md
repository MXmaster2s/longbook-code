# The insights format (v1)

Insights are short notes the user's AI leaves about longbook's own modules — read from
`insights.json` beside `financial_memory.json`. The app never generates one. Where a note
exists, the module shows a small comment icon; the note appears when the user asks for it.

```json
{
  "version": 1,
  "insights": [
    { "module": "dashboard.this_month",
      "text": "August runs ₹12,000 over July — the travel booking, not a trend.",
      "created_at": "2026-08-07" }
  ]
}
```

- `module` (string, required) — which module the note belongs to, from the ids below.
- `text` (string, required) — plain prose. Say what the numbers can't; don't repeat them.
- `created_at` (ISO day, recommended). Append new entries rather than editing old ones —
  the *last* entry for a module wins.
- The user can dismiss a module's note from the Insights screen. That removes every entry
  for the module from the file, and the icon with it; a fresh entry brings it back.

## Module ids (v1)

| Id | Where it shows |
|---|---|
| `dashboard.next_payment` | The hero card |
| `dashboard.active_commitments` | The count card |
| `dashboard.next_30_days` | The 30-day rail |
| `dashboard.this_month` | The calendar-month panel |
| `dashboard.by_account` | The payment-method donut |
| `dashboard.by_category` | The category tiles |
| `account.<payment_method_id>` | That account's card |
| `member.<family_member_id>` | That member's card |

An id the app doesn't recognise is simply never shown. It is not an error, and it stays in
the file for the version that does.

There are no `reports.*` ids. `reports.summary`, `reports.cash_flow`, `reports.spendings`,
`reports.by_account` and `reports.top_charges` name no module: the Reports screen shows the
reports that are written, so a note has nowhere to sit on it. Words about a report belong
inside the report — a `prose` module, or a `comment` on the module they answer. A note
already written against one of these stays in `insights.json` exactly as written; longbook
does not edit the file to tidy its own vocabulary.

## Honesty rules

- A note reads the vault; it never invents numbers the vault can't back.
- User data quoted in a note is reproduced exactly as typed.
- No note is ever required; silence is a fine answer, and the icon only appears when
  there is something to say.
