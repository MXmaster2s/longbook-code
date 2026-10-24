// The look of longbook's emails: the purchase email's design made general, in the site's own
// tokens. A test keeps both in step with apps/longbook-site/tokens.css. Pure code, so the
// function, the sign-in email generator and the tests share it.

export type Block =
  | { p: string }
  | { small: string }
  | { code: string }
  | { link: { lead: string; label: string; href: string } }
  | { details: { title: string; rows: [string, string][] } }
  /** One message of a conversation: who said it, then what they said, line breaks kept. */
  | { turn: { who: string; text: string } }

export interface Spec {
  subject: string
  preheader: string
  title: string
  /** A quieter line under the title, such as when something happened. */
  subline?: string
  /** A rule under the title and subline, before the blocks. */
  divider?: boolean
  blocks: Block[]
  reason: string
}

const SITE = 'https://longbook.app'

export const LIGHT = {
  canvas: '#F6F4EF', card: '#FFFFFF', sunken: '#EFECE4', hairline: '#DFDACD',
  ink: '#26241F', muted: '#57524A', soft: '#655F55', onBrand: '#FBFBFE', link: '#4A3AC8',
}
export const DARK = {
  canvas: '#0D1115', card: '#14171D', sunken: '#0F1218', hairline: '#262B34',
  ink: '#D3D8DE', muted: '#97A0AB', soft: '#7F8994', link: '#8F82F2',
}

// Web fonts do not load in most mail apps, so the serif is Georgia and the sans is the system's.
const SERIF = "Georgia, 'Times New Roman', serif"
const SANS = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"
const MONO = 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace'

// Mail apps preview the first words of the body; this many invisible characters keep the
// wordmark and headline out of that preview.
const PREHEADER_PAD = '&#8199;&#847;'.repeat(45)

const esc = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

const L = LIGHT
const D = DARK

function block(b: Block): string {
  if ('p' in b) {
    return `<p class="tm" style="margin:0 0 16px;font-family:${SANS};font-size:16px;line-height:1.6;color:${L.muted};">${esc(b.p)}</p>`
  }
  if ('small' in b) {
    return `<p class="tm" style="margin:0 0 10px;font-family:${SANS};font-size:14px;line-height:1.6;color:${L.muted};">${esc(b.small)}</p>`
  }
  if ('code' in b) {
    return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td style="padding:6px 0 24px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="bx" style="background:${L.sunken};border:1px solid ${L.hairline};border-radius:12px;"><tr><td align="center" class="co tk" style="padding:22px 12px;font-family:${MONO};font-size:34px;line-height:1;font-weight:600;letter-spacing:7px;color:${L.ink};">${esc(b.code)}</td></tr></table></td></tr></table>`
  }
  if ('turn' in b) {
    return `<p class="ts" style="margin:0 0 4px;font-family:${SANS};font-size:13px;line-height:1.4;font-weight:600;color:${L.soft};">${esc(b.turn.who)}</p>` +
      `<p class="tk" style="margin:0 0 18px;font-family:${SANS};font-size:15px;line-height:1.6;color:${L.ink};white-space:pre-wrap;">${esc(b.turn.text)}</p>`
  }
  if ('link' in b) {
    return `<p class="tm" style="margin:0 0 20px;font-family:${SANS};font-size:14px;line-height:1.6;color:${L.muted};">${esc(b.link.lead)} <a class="lk" href="${esc(b.link.href)}" style="color:${L.link};text-decoration:underline;">${esc(b.link.label)}</a></p>`
  }
  const rows = b.details.rows.map(([label, value], i) =>
    `<tr>
<td class="cl ts hr" style="padding:${i ? '10px' : '0'} 12px 10px 0;${i ? `border-top:1px solid ${L.hairline};` : ''}font-family:${SANS};font-size:14px;line-height:1.5;color:${L.soft};vertical-align:top;white-space:nowrap;">${esc(label)}</td>
<td class="cr tk hr" style="padding:${i ? '10px' : '0'} 0 10px;${i ? `border-top:1px solid ${L.hairline};` : ''}font-family:${SANS};font-size:14px;line-height:1.5;font-weight:600;color:${L.ink};text-align:right;vertical-align:top;overflow-wrap:anywhere;word-break:break-word;">${esc(value)}</td>
</tr>`).join('\n')
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td style="padding:0 0 26px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="bx" style="background:${L.sunken};border:1px solid ${L.hairline};border-radius:12px;">
<tr><td style="padding:18px 20px 8px;">
<p class="tk" style="margin:0 0 12px;font-family:${SANS};font-size:14px;line-height:1.4;font-weight:600;color:${L.ink};">${esc(b.details.title)}</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
${rows}
</table>
</td></tr>
</table></td></tr></table>`
}

export function render(spec: Spec): string {
  const hasDetails = spec.blocks.some((b) => 'details' in b)
  const hasRules = hasDetails || !!spec.divider
  const subline = spec.subline
    ? `\n<p class="ts" style="margin:0 0 ${spec.divider ? '28px' : '22px'};font-family:${SANS};font-size:15px;line-height:1.5;color:${L.soft};">${esc(spec.subline)}</p>`
    : ''
  const divider = spec.divider
    ? `\n<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td class="hr" style="border-top:1px solid ${L.hairline};font-size:1px;line-height:1px;height:1px;">&nbsp;</td></tr></table>\n<div style="height:24px;line-height:24px;font-size:0;">&nbsp;</div>`
    : ''
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<meta name="format-detection" content="telephone=no, date=no, address=no, email=no">
<title>${esc(spec.subject)}</title>
<style>
  :root { color-scheme: light dark; supported-color-schemes: light dark; }
  body { margin: 0; padding: 0; -webkit-text-size-adjust: 100%; }
  h1 { text-wrap: balance; }
  p { text-wrap: pretty; }
  @media (prefers-color-scheme: dark) {
    .cv { background: ${D.canvas} !important; }
    .cd { background: ${D.card} !important; border-color: ${D.hairline} !important; }
    .bx { background: ${D.sunken} !important; border-color: ${D.hairline} !important; }${hasRules ? `\n    .hr { border-color: ${D.hairline} !important; }` : ''}
    .tk { color: ${D.ink} !important; }
    .tm { color: ${D.muted} !important; }
    .ts { color: ${D.soft} !important; }
    .lk { color: ${D.link} !important; }
  }
  @media only screen and (max-width: 620px) {
    .wrap { width: 100% !important; }
    .pad { padding: 28px 22px 26px !important; }
    .h1 { font-size: 26px !important; }
    .co { font-size: 30px !important; letter-spacing: 5px !important; }${hasDetails ? `
    .cl, .cr { display: block !important; width: auto !important; text-align: left !important; white-space: normal !important; }
    .cl { padding-bottom: 0 !important; }
    .cr { border-top: 0 !important; padding-top: 2px !important; }` : ''}
  }
</style>
</head>
<body class="cv" style="margin:0;padding:0;background:${L.canvas};">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${esc(spec.preheader)}${PREHEADER_PAD}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="cv" style="background:${L.canvas};">
<tr><td align="center" style="padding:32px 16px 40px;">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" class="wrap" style="width:600px;max-width:100%;">
<tr><td style="padding:0 4px 20px;">
<table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
<td style="vertical-align:middle;padding-right:9px;"><img src="${SITE}/mark-52.png" width="26" height="26" alt="" style="display:block;border:0;width:26px;height:26px;"></td>
<td class="tk" style="vertical-align:middle;font-family:${SERIF};font-size:22px;line-height:1;font-weight:500;color:${L.ink};">longbook</td>
</tr></table>
</td></tr>
<tr><td class="cd pad" style="padding:40px 40px 34px;background:${L.card};border:1px solid ${L.hairline};border-radius:16px;">
<h1 class="h1 tk" style="margin:0 0 ${spec.subline ? '10px' : '22px'};max-width:460px;font-family:${SERIF};font-size:30px;line-height:1.2;font-weight:500;color:${L.ink};">${esc(spec.title)}</h1>${subline}${divider}
${spec.blocks.map(block).join('\n')}
</td></tr>
<tr><td class="ts" style="padding:22px 8px 0;text-align:center;font-family:${SANS};font-size:12px;line-height:1.6;color:${L.soft};">
${esc(spec.reason)}
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>
`
}

/** The same words as plain text, for the mail apps and readers that want no markup. */
export function renderText(spec: Spec): string {
  const lines = (b: Block): string[] => {
    if ('p' in b) return [b.p, '']
    if ('small' in b) return [b.small, '']
    if ('code' in b) return [b.code, '']
    if ('link' in b) return [`${b.link.lead} ${b.link.href}`, '']
    if ('turn' in b) return [`${b.turn.who}:`, b.turn.text, '']
    return [b.details.title, ...b.details.rows.map(([label, value]) => `${label}: ${value}`), '']
  }
  return [spec.title, ...(spec.subline ? [spec.subline] : []), '', ...spec.blocks.flatMap(lines), '-- ', spec.reason, ''].join('\n')
}
