// Turns a session row into words a person recognises: the app names its device in its user
// agent, a browser is read for its system and name, a connector is named by its client. Every
// label is short plain text from a known pattern or a trimmed name, never markup.

export interface SessionRow {
  id: string
  created_at: string
  last_active: string | null
  user_agent: string | null
  is_connector: boolean
  client_name: string | null
  total?: number | string | null
}

export type Kind = 'app' | 'connector' | 'browser' | 'other'

export interface DescribedSession {
  id: string
  kind: Kind
  label: string
  detail: string
  signed_in_at: string
  last_active_at: string
  this_device: boolean
}

// "longbook/18 (iPhone; iOS 27.0)": the build, the device, the system. Sessions made before
// the app named its device carry only "longbook/18 CFNetwork/… Darwin/…".
const APP_NAMED = /^longbook\/(\d{1,6}) \((iPhone|iPad|Mac); (iOS|iPadOS|macOS) ([\d.]{1,12})\)/
const APP_PLAIN = /^longbook\/(\d{1,6})\b/

// Control and format characters (line breaks, zero-width marks, right-to-left overrides) and
// angle brackets go; the cut is by code point, so an emoji is never split into a lone half.
const plain = (text: string, max: number): string =>
  Array.from(text.replace(/[\p{Cc}\p{Cf}<>]/gu, ' ').replace(/\s+/g, ' ').trim()).slice(0, max).join('').trim()

function browserSystem(agent: string): string | null {
  if (/iPhone/.test(agent)) return 'iPhone'
  if (/iPad/.test(agent)) return 'iPad'
  if (/Android/.test(agent)) return 'Android'
  if (/Macintosh/.test(agent)) return 'Mac'
  if (/Windows/.test(agent)) return 'Windows'
  if (/Linux/.test(agent)) return 'Linux'
  return null
}

function browserName(agent: string): string | null {
  if (/Edg\//.test(agent)) return 'Edge'
  if (/Firefox\//.test(agent)) return 'Firefox'
  if (/Chrome\//.test(agent) || /CriOS\//.test(agent)) return 'Chrome'
  if (/Safari\//.test(agent)) return 'Safari'
  return null
}

export function describeSession(row: SessionRow, currentId: string | null): DescribedSession {
  const agent = row.user_agent ?? ''
  const base = {
    id: row.id,
    signed_in_at: row.created_at,
    last_active_at: row.last_active ?? row.created_at ?? '',
    this_device: currentId !== null && row.id === currentId,
  }
  if (row.is_connector) {
    const name = plain(row.client_name ?? '', 40)
    return { ...base, kind: 'connector', label: name || 'AI connector', detail: 'AI connector' }
  }
  const named = APP_NAMED.exec(agent)
  if (named) {
    return { ...base, kind: 'app', label: named[2]!, detail: `longbook ${named[1]} · ${named[3]} ${named[4]}` }
  }
  const older = APP_PLAIN.exec(agent)
  if (older) return { ...base, kind: 'app', label: 'longbook app', detail: `longbook ${older[1]}` }
  if (agent.startsWith('Mozilla/')) {
    const system = browserSystem(agent)
    const name = browserName(agent)
    if (system && name) return { ...base, kind: 'browser', label: `${name} on ${system}`, detail: 'Web browser' }
    return { ...base, kind: 'browser', label: name ?? 'Web browser', detail: 'Web browser' }
  }
  return { ...base, kind: 'other', label: 'Another sign-in', detail: '' }
}

/** The session id inside a token the server has already verified. Null when it carries none. */
export function sessionIdOf(jwt: string): string | null {
  const part = jwt.split('.')[1]
  if (!part) return null
  try {
    const text = atob(part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '='))
    const id = (JSON.parse(text) as { session_id?: unknown }).session_id
    return typeof id === 'string' ? id : null
  } catch {
    return null
  }
}

/** True for a token an OAuth client, such as an AI connector, was issued: it names its client. */
export function isConnectorToken(jwt: string): boolean {
  const part = jwt.split('.')[1]
  if (!part) return false
  try {
    const text = atob(part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '='))
    return typeof (JSON.parse(text) as { client_id?: unknown }).client_id === 'string'
  } catch {
    return false
  }
}

/** This device first, then the most recently used. */
export function describeAll(rows: SessionRow[], currentId: string | null): DescribedSession[] {
  return rows
    .map((row) => describeSession(row, currentId))
    .sort((a, b) =>
      a.this_device === b.this_device
        ? (b.last_active_at ?? '').localeCompare(a.last_active_at ?? '')
        : a.this_device ? -1 : 1)
}

/** How many sessions the account has, which may be more than the list carries. */
export function totalOf(rows: SessionRow[]): number {
  const first = Number(rows[0]?.total ?? rows.length)
  return Number.isFinite(first) && first >= rows.length ? first : rows.length
}
