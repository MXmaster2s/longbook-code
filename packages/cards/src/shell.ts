// The one HTML shell every card wears: the generated tokens inlined, the app's tone
// steps and type roles as classes, nothing fetched from anywhere. A card is a file.
import { TOKENS_CSS as tokens } from './tokens.js'

export function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
}

// No webfont travels with a card: embedding the variable faces would triple its size.
// Identity is carried by tone, spacing and scale; the face is the host system's.
const BASE = `
* { margin: 0; padding: 0; box-sizing: border-box; }
html { background: var(--lb-canvas); }
body {
  font-family: ui-sans-serif, system-ui, -apple-system, 'Segoe UI', sans-serif;
  color: var(--lb-text-primary);
  padding: var(--lb-space-s3);
}
.panel {
  background: var(--lb-card);
  border: 1px solid var(--lb-hairline);
  border-radius: var(--lb-radius-md);
  padding: var(--lb-space-s4);
  max-width: 640px;
}
.eyebrow {
  font-size: var(--lb-type-eyebrow-size);
  font-weight: var(--lb-type-eyebrow-weight);
  letter-spacing: var(--lb-type-eyebrow-tracking);
  color: var(--lb-text-tertiary);
  margin-bottom: var(--lb-space-s3);
}
.note { font-size: var(--lb-type-footnote-size); color: var(--lb-text-tertiary); }
.amount { font-variant-numeric: tabular-nums; }
.row {
  display: flex; align-items: baseline; gap: var(--lb-space-s2);
  padding: var(--lb-space-s2) 0;
  border-top: 1px solid var(--lb-hairline);
  font-size: var(--lb-type-body-sm-size);
}
.row:first-of-type { border-top: 0; }
.row .name { color: var(--lb-text-primary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.row .when { color: var(--lb-text-tertiary); font-size: var(--lb-type-footnote-size); white-space: nowrap; }
.row .spacer { flex: 1; }
.row .money { color: var(--lb-text-primary); }
.row .paid { color: var(--lb-text-tertiary); font-size: var(--lb-type-tab-label-size); }
`

/** A complete document around one card body. `title` is the tab's name, never shown. */
export function shell(title: string, body: string): string {
  return `<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>${tokens}${BASE}</style>
<body>
${body}
</body>
</html>
`
}

/** The refusal a card renders when the memory can't be read — still a whole file. */
export function messageCard(message: string): string {
  return shell('longbook', `<div class="panel"><p class="note">${escapeHtml(message)}</p></div>`)
}
