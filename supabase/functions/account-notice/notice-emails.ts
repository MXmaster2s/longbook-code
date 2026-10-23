// The four emails a person gets about their account: a sign-in, the hosted copy on or off, a
// report shared. Each says only what was recorded when it happened. Nothing here touches Deno or
// Node, so the function and its tests share it.
import { render, renderText, type Block, type Spec } from '../_shared/email-shell.ts'

export const KINDS = ['signin', 'mcp_on', 'mcp_off', 'report_shared'] as const
export type Kind = (typeof KINDS)[number]
export const isKind = (kind: string): kind is Kind => (KINDS as readonly string[]).includes(kind)

export interface Notice {
  subject: string
  html: string
  text: string
}

type Details = Record<string, unknown>

const text = (value: unknown, max: number): string =>
  // Control characters out, so nothing recorded can break a line of the email.
  typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max) : ''

/** "29 September 2026 at 18:29 UTC", the same on every runtime. */
export function when(value: unknown, fallback: string): string {
  const date = new Date(typeof value === 'string' ? value : fallback)
  const at = Number.isNaN(date.getTime()) ? new Date(fallback) : date
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: 'UTC' })
      .formatToParts(at).map((p) => [p.type, p.value]),
  )
  return `${parts.day} ${parts.month} ${parts.year} at ${parts.hour}:${parts.minute} UTC`
}

/**
 * What a session's device string reveals. The app calls itself "longbook/<build>" and says nothing
 * else that tells an iPhone from a Mac, so that is all this claims. Browsers name themselves.
 */
export function describeDevice(userAgent: unknown): string | null {
  const ua = text(userAgent, 300)
  if (!ua) return null
  const app = /^longbook\/(\d{1,6})\b/.exec(ua)
  if (app) return `longbook app, build ${app[1]}`
  const browser = /\bEdg\//.test(ua) ? 'Edge'
    : /\bOPR\//.test(ua) ? 'Opera'
    : /\bFirefox\//.test(ua) ? 'Firefox'
    : /\b(Chrome|CriOS)\//.test(ua) ? 'Chrome'
    : /\bSafari\//.test(ua) ? 'Safari'
    : null
  const system = /\biPhone\b/.test(ua) ? 'iPhone'
    : /\biPad\b/.test(ua) ? 'iPad'
    : /\bAndroid\b/.test(ua) ? 'Android'
    : /\bMacintosh\b|\bMac OS X\b/.test(ua) ? 'a Mac'
    : /\bWindows\b/.test(ua) ? 'Windows'
    : /\bLinux\b|\bX11\b/.test(ua) ? 'Linux'
    : null
  if (browser && system) return `${browser} on ${system}`
  return browser ?? system ?? 'Another app or script'
}

const address = (value: unknown): string | null => {
  const ip = text(value, 45)
  return /^\d{1,3}(\.\d{1,3}){3}$/.test(ip) || (/^[0-9a-fA-F:]+$/.test(ip) && ip.includes(':')) ? ip : null
}

const methodName = (value: unknown): string | null =>
  value === 'otp' || value === 'magiclink' ? 'Email code' : value === 'oauth' ? 'Google or Apple' : null

const row = (label: string, value: string | null): [string, string][] => (value ? [[label, value]] : [])

function specFor(kind: Kind, d: Details, fallback: string): Spec {
  const at = when(d.at, fallback)
  if (kind === 'signin') {
    // The time is the subline already; what is left is only what the sign-in recorded.
    const rows = [...row('Method', methodName(d.method)), ...row('App or browser', describeDevice(d.user_agent)), ...row('IP address', address(d.ip))]
    const card: Block[] = rows.length ? [{ details: { title: 'Sign-in details', rows } }] : []
    return {
      subject: 'A new sign-in to your longbook account',
      preheader: 'Your account was signed in. If that was you, there is nothing to do.',
      title: 'New sign-in to your account',
      subline: at,
      divider: true,
      blocks: [
        { p: 'Your longbook account was signed in. If that was you, there is nothing to do.' },
        ...card,
        { small: 'If it was not you, reply to this email and we will help you secure your account.' },
      ],
      reason: 'You received this email because your longbook account was signed in.',
    }
  }
  if (kind === 'mcp_on') {
    return {
      subject: 'longbook’s MCP server is on',
      preheader: 'A copy of your memory file is now stored with your account so your AI can read it.',
      title: 'Your MCP server is on',
      subline: `Turned on ${at}`,
      divider: true,
      blocks: [
        { p: 'Any AI you connect can now read your longbook through a hosted copy. A copy of your memory file is stored with your account so your AI can read it. It is replaced when you save, and deleted when you turn the server off or after 90 days without opening longbook.' },
        { details: { title: 'MCP server', rows: [['Address', 'https://longbook.app/mcp'], ['Hosted copy', 'On']] } },
        { small: 'If you did not turn this on, open longbook and turn it off. That deletes the hosted copy.' },
      ],
      reason: 'You received this email because the MCP server was turned on for your longbook account.',
    }
  }
  if (kind === 'mcp_off') {
    return {
      subject: 'longbook’s MCP server is off',
      preheader: 'The hosted copy of your memory file was deleted.',
      title: 'Your MCP server is off',
      subline: `Turned off ${at}`,
      divider: true,
      blocks: [
        { p: 'The hosted copy of your memory file was deleted, so nothing is hosted for your AI to read. Your own files in iCloud were not touched.' },
        { p: 'Keys you created stay valid until you revoke them, even with the server off. They have nothing to read until you turn it back on, and you can revoke them then.' },
        { small: 'If you did not turn this off, open longbook and turn it back on.' },
      ],
      reason: 'You received this email because the MCP server was turned off for your longbook account.',
    }
  }
  const expires = typeof d.expires_at === 'string' ? when(d.expires_at, fallback) : null
  const shared: Block[] = [
    { p: 'You created a password-protected link to a report. Anyone with the link and the password can open it without a longbook account and leave comments.' },
    { details: { title: 'Share details', rows: [...row('Report', text(d.report, 80) || null), ...row('Link expires', expires)] } },
    { small: 'longbook keeps no copy of the password and never emails it. You can end the link sooner with Stop sharing on the report.' },
    { small: 'If you did not share a report, reply to this email and we will help.' },
  ]
  return {
    subject: 'You shared a report from longbook',
    preheader: 'A password-protected link to your report is live.',
    title: 'Your report has a live link',
    subline: `Shared ${at}`,
    divider: true,
    blocks: shared.filter((b) => !('details' in b) || b.details.rows.length > 0),
    reason: 'You received this email because a report was shared from your longbook account.',
  }
}

/** The email for one recorded event, or null when the kind is not one of the four. */
export function renderNotice(kind: string, details: unknown, recordedAt: string): Notice | null {
  if (!isKind(kind)) return null
  const spec = specFor(kind, details && typeof details === 'object' ? (details as Details) : {}, recordedAt)
  return { subject: spec.subject, html: render(spec), text: renderText(spec) }
}
