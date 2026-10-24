// Support's emails, in longbook's own look: the code that proves an address, and the
// conversation sent to the team, copied to the person so a reply reaches them both.
import { render, renderText, type Block } from '../_shared/email-shell.ts'

export const SUPPORT_FROM = 'longbook Support <help@longbook.app>'
export const TEAM_INBOX = 'contact@longbook.app'

export interface Said { role: 'user' | 'assistant'; content: string }

export interface Mail { subject: string; html: string; text: string }

export function codeMail(code: string): Mail {
  const spec = {
    subject: `${code} is your longbook Support code`,
    preheader: 'Enter it in Support so we can reply to you by email.',
    title: 'Your Support code',
    blocks: [
      { p: 'Enter this code in longbook Support so the team can reply to you at this address.' } as Block,
      { code } as Block,
      { small: 'It works for ten minutes. If you did not ask for it, you can ignore this email.' } as Block,
    ],
    reason: 'You asked longbook Support to reply to you by email.',
  }
  return { subject: spec.subject, html: render(spec), text: renderText(spec) }
}

/** The conversation as the team reads it: why it came, then every message in turn. */
export function conversationMail(said: Said[], kind: 'reply' | 'review', meta: { email?: string; rating?: string; app?: string }): Mail {
  const first = said.find((s) => s.role === 'user')?.content.replace(/\s+/g, ' ').trim() ?? 'A question'
  const topic = first.length > 60 ? `${first.slice(0, 57)}…` : first
  const rows: [string, string][] = [
    ['Asked for', kind === 'reply' ? 'A reply by email' : 'A review of this conversation'],
    ...(meta.email ? [['Reply to', meta.email] as [string, string]] : []),
    ...(meta.rating ? [['Rating', meta.rating] as [string, string]] : []),
    ...(meta.app ? [['App', meta.app] as [string, string]] : []),
  ]
  const spec = {
    subject: kind === 'reply' ? `Support: ${topic}` : `Support review: ${topic}`,
    preheader: first.slice(0, 120),
    title: kind === 'reply' ? 'A question for the team' : 'A conversation to review',
    subline: kind === 'reply' ? 'Reply to this email and the person who asked receives it.' : 'Sent from Support without an email address.',
    blocks: [
      { details: { title: 'About this conversation', rows } } as Block,
      ...said.map((s) => ({ turn: { who: s.role === 'user' ? 'They asked' : 'longbook Support answered', text: s.content } }) as Block),
    ],
    reason: kind === 'reply' ? 'Sent from longbook Support at the person\'s request, with a copy to them.' : 'Sent from longbook Support at the person\'s request.',
  }
  return { subject: spec.subject, html: render(spec), text: renderText(spec) }
}
