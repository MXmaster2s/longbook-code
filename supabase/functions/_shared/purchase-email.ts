// The confirmation a purchase earns, written once and rendered as HTML and as plain text, so
// the two cannot disagree. Nothing here touches Deno or Node, so the function, its tests and
// the preview script all load this same file.

export interface PurchaseEmailInput {
  email: string
  purchasedAt: Date
  majorVersion: number
  /** Sandbox is TestFlight, or Polar's sandbox: the email says so, and nothing was charged. */
  environment?: string
  /** Who took the payment and sends the receipt: the App Store, or Polar on longbook.app. */
  seller?: 'apple' | 'polar'
}

export interface PurchaseEmail {
  subject: string
  html: string
  text: string
}

const SITE = 'https://longbook.app'
const NEXT_STEP = `${SITE}/automations/`
const APPLE_RECEIPTS = 'https://reportaproblem.apple.com'
const POLAR_RECEIPTS = 'https://polar.sh/ccs/portal'

// The site's own tokens (apps/longbook-site/tokens.css), light first and dark for the mail
// apps that follow the device's appearance.
const LIGHT = {
  canvas: '#F6F4EF', card: '#FFFFFF', sunken: '#EFECE4', hairline: '#DFDACD',
  ink: '#26241F', muted: '#57524A', soft: '#655F55',
  brand: '#6D5AE6', onBrand: '#FBFBFE', link: '#4A3AC8', note: '#ECE9FC',
}
const DARK = {
  canvas: '#0D1115', card: '#14171D', sunken: '#0F1218', hairline: '#262B34',
  ink: '#D3D8DE', muted: '#97A0AB', soft: '#7F8994', link: '#8F82F2', note: '#1D1B33',
}

// Web fonts do not load in most mail apps, so the serif is Georgia and the sans is the system's.
const SERIF = "Georgia, 'Times New Roman', serif"
const SANS = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"

// Mail apps preview the first words of the body. The hidden line ends in enough invisible
// characters that the wordmark and headline never show up behind it.
const PREHEADER_PAD = '&#8199;&#847;'.repeat(45)

const esc = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

function words(input: PurchaseEmailInput) {
  const test = input.environment === 'Sandbox'
  const polar = input.seller === 'polar'
  const version = input.majorVersion
  const date = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' })
    .format(input.purchasedAt)
  return {
    test,
    year: input.purchasedAt.getUTCFullYear(),
    subject: `${test ? '[Test purchase] ' : ''}Your longbook license is now active`,
    preheader: 'Thank you for purchasing longbook. Your one-time license covers iPhone and Mac.',
    title: 'Your longbook one-time license is now active!',
    when: `Purchased version ${version} on ${date}`,
    thanks: 'Thank you for purchasing longbook!',
    body: 'Your purchase is complete and your one-time license is ready. It covers longbook on iPhone and Mac, ' +
      `including every update to version ${version}. Keep this email for your records.`,
    next: 'When you are ready, connect your AI so it can read your commitments and add new ones.',
    button: 'Connect your AI',
    detailsTitle: 'Purchase details',
    details: [
      ['Product', 'longbook one-time license'],
      ['Includes', `iPhone and Mac, updates to version ${version}`],
      ['Account', input.email],
    ] as [string, string][],
    testNote: polar
      ? 'This is a test purchase made in the Polar sandbox. Nothing was charged.'
      : 'This is a test purchase made in TestFlight. Nothing was charged.',
    receipt: polar
      ? 'Polar, which handles payments on longbook.app, emails a receipt for every purchase. You can also find it at'
      : 'Apple emails a receipt for every App Store purchase. You can also find it at',
    receiptUrl: polar ? POLAR_RECEIPTS : APPLE_RECEIPTS,
    receiptSite: polar ? 'polar.sh/ccs/portal' : 'reportaproblem.apple.com',
    help: 'Questions about your purchase? Reply to this email and we will help.',
    why: 'You received this email because a longbook purchase was made with this account.',
  }
}

export function renderPurchaseEmail(input: PurchaseEmailInput): PurchaseEmail {
  const w = words(input)
  const L = LIGHT
  const D = DARK

  const banner = w.test
    ? `<div class="nt lk" style="margin:0 0 24px;padding:12px 16px;background:${L.note};border-radius:10px;font-family:${SANS};font-size:14px;line-height:1.5;color:${L.link};">${esc(w.testNote)}</div>`
    : ''

  const rows = w.details.map(([label, value], i) =>
    `<tr>
<td class="cl ts hr" style="padding:${i ? '10px' : '0'} 12px 10px 0;${i ? `border-top:1px solid ${L.hairline};` : ''}font-family:${SANS};font-size:14px;line-height:1.5;color:${L.soft};vertical-align:top;white-space:nowrap;">${esc(label)}</td>
<td class="cr tk hr" style="padding:${i ? '10px' : '0'} 0 10px;${i ? `border-top:1px solid ${L.hairline};` : ''}font-family:${SANS};font-size:14px;line-height:1.5;font-weight:600;color:${L.ink};text-align:right;vertical-align:top;overflow-wrap:anywhere;word-break:break-word;">${esc(value)}</td>
</tr>`).join('\n')

  const receipt = w.test
    ? ''
    : `<p class="tm" style="margin:0 0 10px;font-family:${SANS};font-size:14px;line-height:1.6;color:${L.muted};">${esc(w.receipt)} <a class="lk" href="${w.receiptUrl}" style="color:${L.link};text-decoration:underline;">${w.receiptSite}</a>.</p>`

  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<meta name="format-detection" content="telephone=no, date=no, address=no, email=no">
<title>${esc(w.subject)}</title>
<style>
  :root { color-scheme: light dark; supported-color-schemes: light dark; }
  body { margin: 0; padding: 0; -webkit-text-size-adjust: 100%; }
  h1, h2 { text-wrap: balance; }
  p { text-wrap: pretty; }
  @media (prefers-color-scheme: dark) {
    .cv { background: ${D.canvas} !important; }
    .cd { background: ${D.card} !important; border-color: ${D.hairline} !important; }
    .bx { background: ${D.sunken} !important; border-color: ${D.hairline} !important; }
    .hr { border-color: ${D.hairline} !important; }
    .nt { background: ${D.note} !important; }
    .tk { color: ${D.ink} !important; }
    .tm { color: ${D.muted} !important; }
    .ts { color: ${D.soft} !important; }
    .lk { color: ${D.link} !important; }
  }
  @media only screen and (max-width: 620px) {
    .wrap { width: 100% !important; }
    .pad { padding: 28px 22px 26px !important; }
    .h1 { font-size: 26px !important; }
    .cl, .cr { display: block !important; width: auto !important; text-align: left !important; white-space: normal !important; }
    .cl { padding-bottom: 0 !important; }
    .cr { border-top: 0 !important; padding-top: 2px !important; }
  }
</style>
</head>
<body class="cv" style="margin:0;padding:0;background:${L.canvas};">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${esc(w.preheader)}${PREHEADER_PAD}</div>
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
${banner}
<h1 class="h1 tk" style="margin:0 0 10px;max-width:460px;font-family:${SERIF};font-size:30px;line-height:1.2;font-weight:500;color:${L.ink};">${esc(w.title).replace('one-time license', '<span style="white-space:nowrap;">one-time license</span>')}</h1>
<p class="ts" style="margin:0 0 28px;font-family:${SANS};font-size:15px;line-height:1.5;color:${L.soft};">${esc(w.when)}</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td class="hr" style="border-top:1px solid ${L.hairline};font-size:1px;line-height:1px;height:1px;">&nbsp;</td></tr></table>
<h2 class="tk" style="margin:28px 0 12px;font-family:${SERIF};font-size:21px;line-height:1.3;font-weight:500;color:${L.ink};">${esc(w.thanks)}</h2>
<p class="tm" style="margin:0 0 14px;font-family:${SANS};font-size:16px;line-height:1.6;color:${L.muted};">${esc(w.body)}</p>
<p class="tm" style="margin:0 0 22px;font-family:${SANS};font-size:16px;line-height:1.6;color:${L.muted};">${esc(w.next)}</p>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 30px;"><tr>
<td bgcolor="${L.brand}" style="background:${L.brand};border-radius:10px;mso-padding-alt:14px 26px;"><a href="${NEXT_STEP}" style="display:inline-block;padding:14px 26px;font-family:${SANS};font-size:16px;line-height:1;font-weight:600;color:${L.onBrand};text-decoration:none;border-radius:10px;">${esc(w.button)}</a></td>
</tr></table>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="bx" style="margin:0 0 26px;background:${L.sunken};border:1px solid ${L.hairline};border-radius:12px;">
<tr><td style="padding:18px 20px 8px;">
<p class="tk" style="margin:0 0 12px;font-family:${SANS};font-size:14px;line-height:1.4;font-weight:600;color:${L.ink};">${esc(w.detailsTitle)}</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
${rows}
</table>
</td></tr>
</table>
${receipt}
<p class="tm" style="margin:0;font-family:${SANS};font-size:14px;line-height:1.6;color:${L.muted};">${esc(w.help)}</p>
</td></tr>
<tr><td class="ts" style="padding:22px 8px 0;text-align:center;font-family:${SANS};font-size:12px;line-height:1.6;color:${L.soft};">
${esc(w.why)}<br>&copy; ${w.year} longbook
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>
`

  const text = [
    w.title,
    w.when,
    '',
    w.thanks,
    '',
    w.body,
    '',
    `${w.next}\n${NEXT_STEP}`,
    '',
    w.detailsTitle,
    ...w.details.map(([label, value]) => `${label}: ${value}`),
    '',
    ...(w.test ? [w.testNote] : [`${w.receipt} ${w.receiptUrl}`]),
    '',
    w.help,
    '',
    '-- ',
    w.why,
    `© ${w.year} longbook`,
    '',
  ].join('\n')

  return { subject: w.subject, html, text }
}
