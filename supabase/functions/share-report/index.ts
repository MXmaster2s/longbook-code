// Serves one shared report: the owner creates a password-protected copy that expires, a viewer
// opens it and leaves comments, the owner pulls comments back or revokes. Creating needs
// longbook Cloud. Every table access here uses the service-role key — the tables carry no
// client policies. Report contents are never logged.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { CLOUD_REQUIRED, hasCloud } from '../_shared/has-cloud.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// Browser-called — needs CORS, including the preflight OPTIONS. Origin stays
// wide open: the boundary is the JWT on owner routes and the password gate on viewer routes.
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
}

// Password vocabulary: short, plain, lowercase. Three words and two digits give about six
// million combinations — plenty for a link that must also be known and dies within a week.
const WORDS = [
  'amber', 'ash', 'birch', 'brook', 'cedar', 'clove', 'coal', 'coral', 'cove', 'dawn',
  'drift', 'dune', 'ember', 'fern', 'flax', 'frost', 'glen', 'hazel', 'iris', 'ivy',
  'kelp', 'lark', 'linen', 'maple', 'mint', 'moss', 'north', 'oak', 'opal', 'pearl',
  'pine', 'plum', 'reed', 'sage', 'salt', 'slate', 'snow', 'teal', 'vale', 'wren',
]

const MIN_HOURS = 1
const MAX_HOURS = 168
const DEFAULT_HOURS = 72

// The address a viewer opens: the site's own page, which asks this function for the report
// through the site's /share-report proxy. The function's host never appears in a message.
const PUBLIC_VIEWER = 'https://longbook.app/r/'

type Service = ReturnType<typeof createClient>
type Share = {
  id: string
  owner_id: string
  report: unknown
  password_hash: string
  password_salt: string
  expires_at: string
}
type ShareGate = { refusal: Response; share?: never } | { refusal?: never; share: Share }
type OwnerGate =
  | { refusal: Response; shareId?: never; expiresAt?: never }
  | { refusal?: never; shareId: string; expiresAt: string }

const refuse = (message: string, status: number) =>
  new Response(message, { status, headers: CORS_HEADERS })
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  })

function randomInt(bound: number): number {
  return crypto.getRandomValues(new Uint32Array(1))[0] % bound
}

function randomHex(bytes: number): string {
  const buf = crypto.getRandomValues(new Uint8Array(bytes))
  return [...buf].map((b) => b.toString(16).padStart(2, '0')).join('')
}

function makePassword(): string {
  const words = [WORDS[randomInt(WORDS.length)], WORDS[randomInt(WORDS.length)], WORDS[randomInt(WORDS.length)]]
  return words.join('-') + '-' + String(randomInt(100)).padStart(2, '0')
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

// Resolves the caller from the Bearer JWT; null means 401.
async function callerFrom(req: Request) {
  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer /, '')
  if (!jwt) return null
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser(jwt)
  return error || !user ? null : user
}

// The gate every viewer route passes: find the share, expire it, check the password. An expired
// row is deleted on touch, not merely refused. Hashes are compared, never raw passwords.
async function openShare(service: Service, id: unknown, password: unknown): Promise<ShareGate> {
  if (typeof id !== 'string' || typeof password !== 'string') {
    return { refusal: refuse('not found', 404) }
  }
  const { data, error } = await service.from('shared_reports').select('*').eq('id', id).maybeSingle()
  if (error || !data) return { refusal: refuse('not found', 404) }
  const share = data as Share
  if (new Date(share.expires_at).getTime() <= Date.now()) {
    await service.from('shared_reports').delete().eq('id', share.id)
    return { refusal: refuse('this link has expired', 410) }
  }
  if ((await sha256Hex(share.password_salt + password)) !== share.password_hash) {
    return { refusal: refuse('wrong password', 403) }
  }
  return { share }
}

// The owner gate for revoke and comment collection: a valid JWT whose user owns the share.
async function ownerShare(req: Request, service: Service, id: unknown): Promise<OwnerGate> {
  const user = await callerFrom(req)
  if (!user) return { refusal: refuse('unauthorized', 401) }
  if (typeof id !== 'string') return { refusal: refuse('not found', 404) }
  const { data, error } = await service
    .from('shared_reports')
    .select('id, owner_id, expires_at')
    .eq('id', id)
    .maybeSingle()
  if (error || !data) return { refusal: refuse('not found', 404) }
  const row = data as { owner_id: string; expires_at: string }
  if (row.owner_id !== user.id) return { refusal: refuse('forbidden', 403) }
  return { shareId: id, expiresAt: row.expires_at }
}

async function handleCreate(req: Request, body: any, service: Service): Promise<Response> {
  const user = await callerFrom(req)
  if (!user) return refuse('unauthorized', 401)
  if (!(await hasCloud(service, user.id))) return json({ error: CLOUD_REQUIRED, code: 'entitlement_required' }, 403)
  if (!body.report || typeof body.report !== 'object') return refuse('report required', 400)
  const requested = Number(body.hours)
  const hours = Number.isFinite(requested)
    ? Math.min(MAX_HOURS, Math.max(MIN_HOURS, requested))
    : DEFAULT_HOURS
  const password = makePassword()
  const salt = randomHex(16)
  const hash = await sha256Hex(salt + password)
  const expiresAt = new Date(Date.now() + hours * 60 * 60 * 1000).toISOString()
  const { data, error } = await service
    .from('shared_reports')
    .insert({
      owner_id: user.id,
      report: body.report,
      password_hash: hash,
      password_salt: salt,
      expires_at: expiresAt,
    })
    .select('id')
    .single()
  if (error || !data) return refuse('could not create share', 500)
  const row = data as { id: string }
  // The owner is emailed that a link exists. The link stands whether or not this is written.
  const title = typeof body.report.title === 'string' ? body.report.title.trim().slice(0, 80) : ''
  const { error: noticeError } = await service.from('account_notices').insert({
    user_id: user.id,
    kind: 'report_shared',
    details: { at: new Date().toISOString(), report: title, expires_at: expiresAt },
  })
  if (noticeError) console.error(`share notice: ${noticeError.message}`)
  return json({
    id: row.id,
    password,
    url: `${PUBLIC_VIEWER}${row.id}`,
    expires_at: expiresAt,
  })
}

async function handleView(body: any, service: Service): Promise<Response> {
  const gate = await openShare(service, body.id, body.password)
  if (gate.refusal) return gate.refusal
  const { data: comments } = await service
    .from('report_comments')
    .select('module_id, author, body, created_at')
    .eq('share_id', gate.share.id)
    .order('created_at', { ascending: true })
  return json({ report: gate.share.report, comments: comments ?? [], expires_at: gate.share.expires_at })
}

async function handleComment(body: any, service: Service): Promise<Response> {
  const gate = await openShare(service, body.id, body.password)
  if (gate.refusal) return gate.refusal
  const moduleId = typeof body.module_id === 'string' ? body.module_id : ''
  const text = typeof body.body === 'string' ? body.body : ''
  const author = typeof body.author === 'string' ? body.author : ''
  if (!moduleId) return refuse('module_id required', 400)
  if (!text.trim() || text.length > 2000) return refuse('body must be 1 to 2000 characters', 400)
  if (author.length > 80) return refuse('author must be 80 characters or fewer', 400)
  // Stored exactly as typed — comments are viewer data and are never trimmed or re-cased.
  const { error } = await service.from('report_comments').insert({
    share_id: gate.share.id,
    module_id: moduleId,
    author: author || null,
    body: text,
  })
  if (error) return refuse('could not save comment', 500)
  return json({ ok: true })
}

async function handleRevoke(req: Request, body: any, service: Service): Promise<Response> {
  const gate = await ownerShare(req, service, body.id)
  if (gate.refusal) return gate.refusal
  const { error } = await service.from('shared_reports').delete().eq('id', gate.shareId)
  if (error) return refuse('could not revoke', 500)
  return json({ ok: true })
}

async function handleComments(req: Request, body: any, service: Service): Promise<Response> {
  const gate = await ownerShare(req, service, body.id)
  if (gate.refusal) return gate.refusal
  const { data: comments } = await service
    .from('report_comments')
    .select('module_id, author, body, created_at')
    .eq('share_id', gate.shareId)
    .order('created_at', { ascending: true })
  return json({ comments: comments ?? [], expires_at: gate.expiresAt })
}

// The id rides as ?id= when the function is called by name, or as the segment after the
// function's own — the shape an older link or a hand-typed address may carry.
function shareIdIn(url: string): string | undefined {
  const here = new URL(url)
  const fromQuery = here.searchParams.get('id')
  if (fromQuery) return fromQuery
  const segments = here.pathname.split('/').filter(Boolean)
  const at = segments.lastIndexOf('share-report')
  return at >= 0 ? segments[at + 1] : undefined
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS_HEADERS })

  if (req.method === 'GET') {
    // The page is the site's; this host answers only JSON. A link that names an id is sent
    // to the page, which asks back here for the report.
    const id = shareIdIn(req.url)
    if (!id) return refuse('not found', 404)
    return Response.redirect(`${PUBLIC_VIEWER}${encodeURIComponent(id)}`, 302)
  }

  if (req.method !== 'POST') return refuse('method not allowed', 405)

  let body: any
  try {
    body = await req.json()
  } catch {
    return refuse('bad json', 400)
  }
  const service = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

  switch (body?.action) {
    case 'create':
      return handleCreate(req, body, service)
    case 'view':
      return handleView(body, service)
    case 'comment':
      return handleComment(body, service)
    case 'revoke':
      return handleRevoke(req, body, service)
    case 'comments':
      return handleComments(req, body, service)
    default:
      return refuse('unknown action', 400)
  }
})
