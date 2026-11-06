// The emails Supabase Auth asks for: the code for a new address, the code for a returning one,
// and a plain one for anything else. Auth's own templates and the auth-email function are both
// made from here, so the two paths send the same email.
import type { Spec } from './email-shell.ts'

export const SIGN_UP_SUBJECT = 'Your longbook sign-up code'
export const SIGN_IN_SUBJECT = 'Your longbook sign-in code'

export function signUpSpec(code: string, link: string | null): Spec {
  return {
    subject: SIGN_UP_SUBJECT,
    preheader: 'Enter this code in longbook to finish creating your account.',
    title: 'Your sign-up code',
    blocks: [
      { p: 'Enter this code in longbook to finish creating your account. It works once, expires in one hour, and only the newest code works.' },
      { code },
      ...(link ? [{ link: { lead: 'Prefer a link?', label: 'Confirm email address', href: link } }] : []),
      { small: 'Do not share this code with anyone. longbook will never ask you for it.' },
      { small: 'If you did not try to create a longbook account, ignore this email. The address stays unconfirmed unless the code is entered or the link is opened.' },
    ],
    reason: 'You received this email because this address was used to create a longbook account.',
  }
}

export function signInSpec(code: string): Spec {
  return {
    subject: SIGN_IN_SUBJECT,
    preheader: 'Enter this code in longbook to finish signing in.',
    title: 'Your sign-in code',
    blocks: [
      { p: 'Enter this code in longbook to finish signing in. It works once, expires in one hour, and only the newest code works.' },
      { code },
      { small: 'Do not share this code with anyone. longbook will never ask you for it.' },
      { small: 'If you did not ask to sign in, ignore this email. Nobody can sign in without the code.' },
    ],
    reason: 'You received this email because a sign-in code was requested for this address.',
  }
}

/** Any other email Auth asks for, which longbook has no flow of its own for: the code if there is one. */
export function otherSpec(code: string | null): Spec {
  return code
    ? {
      subject: 'Your longbook code',
      preheader: 'Enter this code in longbook to continue.',
      title: 'Your longbook code',
      blocks: [
        { p: 'Enter this code in longbook to continue. It works once and expires in one hour.' },
        { code },
        { small: 'Do not share this code with anyone. longbook will never ask you for it.' },
        { small: 'If you did not ask for a code, ignore this email.' },
      ],
      reason: 'You received this email because a code was requested for this address.',
    }
    : {
      subject: 'A change to your longbook account',
      preheader: 'Your longbook account was updated.',
      title: 'Your account was updated',
      blocks: [
        { p: 'A change was made to your longbook account. If that was you, there is nothing to do.' },
        { small: 'If it was not you, reply to this email and we will help you secure your account.' },
      ],
      reason: 'You received this email because your longbook account was updated.',
    }
}
