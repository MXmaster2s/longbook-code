// The decisions the deploy makes about the live project's settings, kept free of network calls
// so they can be tested: what differs, whether the code lifetime matches the copy, whether
// anything besides the four settings moved, and whether a saved file can be put back.
export type Config = Record<string, unknown>

/** The emails say a code lasts an hour; the project's mailer_otp_exp is what makes that true. */
export const OTP_SECONDS = 3600

// Set by the project itself whenever a template or subject is customised, never by us.
const DERIVED = ['mailer_subjects_custom_contents', 'mailer_templates_custom_contents']

export const same = (live: unknown, wanted: string): boolean =>
  typeof live === 'string' && live.trimEnd() === wanted.trimEnd()

/** The settings whose live value is not the wanted one, by name, never by content. */
export function differences(live: Config, wanted: Record<string, string>): string[] {
  return Object.entries(wanted).filter(([name, value]) => !same(live[name], value)).map(([name]) => name)
}

export function lifetimeProblem(live: Config): string | null {
  return live.mailer_otp_exp === OTP_SECONDS
    ? null
    : `the emails say a code lasts one hour, but the project's mailer_otp_exp is ${String(live.mailer_otp_exp)} seconds`
}

/** Settings outside `own` whose value differs between two reads, by name. */
export function otherChanges(before: Config, after: Config, own: string[]): string[] {
  const skip = new Set([...own, ...DERIVED])
  return [...new Set([...Object.keys(before), ...Object.keys(after)])]
    .filter((name) => !skip.has(name) && JSON.stringify(before[name]) !== JSON.stringify(after[name]))
    .sort()
}

/** The four settings out of a saved file, or a sentence saying why it cannot be used. */
export function restoreFields(saved: unknown, fields: string[]): Record<string, string> | string {
  if (typeof saved !== 'object' || saved === null) return 'That file is not a saved set of settings.'
  const out: Record<string, string> = {}
  for (const name of fields) {
    const value = (saved as Config)[name]
    if (typeof value !== 'string') return `That file does not hold ${name}.`
    out[name] = value
  }
  return out
}
