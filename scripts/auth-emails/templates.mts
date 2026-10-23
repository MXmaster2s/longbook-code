// The two emails Supabase Auth sends when the auth-email function is off, made from the same
// specs the function uses. The double-braced words are Supabase's own placeholders.
import { signInSpec, signUpSpec } from '../../supabase/functions/_shared/auth-emails.ts'
import { render, type Spec } from '../../supabase/functions/_shared/email-shell.ts'

export const CODE = '{{ .Token }}'
export const LINK = '{{ .ConfirmationURL }}'

export interface AuthEmail {
  /** The project setting the template belongs to, without its mailer_ prefix. */
  key: 'confirmation' | 'magic_link'
  file: string
  subject: string
  /** The placeholders the template may hold, in order. */
  placeholders: string[]
  spec: Spec
}

const signUp = signUpSpec(CODE, LINK)
const signIn = signInSpec(CODE)

export const AUTH_EMAILS: AuthEmail[] = [
  { key: 'confirmation', file: 'sign-up.html', subject: signUp.subject, placeholders: [CODE, LINK], spec: signUp },
  { key: 'magic_link', file: 'sign-in.html', subject: signIn.subject, placeholders: [CODE], spec: signIn },
]

export const htmlOf = (email: AuthEmail): string => render(email.spec)
