// The hosted MCP server: the memory over Streamable HTTP, one user per row. Reads answer
// from the copy the app pushed. Writes are PROPOSALS — nothing here rewrites the memory;
// one waits in mcp_pending_writes until the owner's app applies it, for review there.
// Dispatch lives in engine.mjs, generated from packages/mcp.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { LLMS_TXT, RateLimiter, RpcFailure, SCHEMA_JSON, SERVER_CARD, failureBody, handleRpc, parseHints, parseVault } from './engine.mjs'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
// The public face: longbook.app proxies here, and the advertised identity is the
// longbook address. The direct Supabase URL keeps answering for connections that
// already saved it.
const PUBLIC_URL = 'https://longbook.app/mcp'

// Thirty calls a minute per user. This in-memory counter is the isolate's cheap
// first answer; the durable count lives in Postgres (mcp_rate), asked once per
// surviving request, so parallel isolates and cold starts refill nobody's minute.
const limiter = new RateLimiter(30, 60_000)

// Open origin, same as share-report: the boundary is the bearer token, not the origin.
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, mcp-protocol-version, mcp-session-id',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  // Without this a browser client cannot read the challenge that tells it where to sign
  // in, nor the session id — allow-origin alone hides both from JS.
  'Access-Control-Expose-Headers': 'WWW-Authenticate, Mcp-Session-Id',
}
const JSON_HEADERS = { ...CORS_HEADERS, 'Content-Type': 'application/json' }

/** RFC 9728 resource metadata: names the auth server an MCP client should talk to. */
const RESOURCE_METADATA = {
  resource: PUBLIC_URL,
  authorization_servers: [`${SUPABASE_URL}/auth/v1`],
  bearer_methods_supported: ['header'],
}

/** The Server Card (MCP SEP-2127) at <server>/server-card: public, cacheable, revalidated by ETag. */
const CARD_BODY = JSON.stringify(SERVER_CARD)
const CARD_TAG = `"${Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(CARD_BODY))))
  .slice(0, 8).map((b) => b.toString(16).padStart(2, '0')).join('')}"`
const CARD_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET',
  'Access-Control-Allow-Headers': 'Content-Type, If-None-Match',
  'Access-Control-Expose-Headers': 'ETag',
  'Cache-Control': 'public, max-age=3600',
  ETag: CARD_TAG,
}

const tooMany = (retryAfterSeconds: number) =>
  new Response(failureBody('rate_limited', 'Too many requests. Give it a moment.', { retry_after: retryAfterSeconds }), {
    status: 429,
    headers: { ...JSON_HEADERS, 'Retry-After': String(retryAfterSeconds) },
  })

const unauthorized = (
  code: 'unauthorized' | 'key_revoked' | 'key_expired' = 'unauthorized',
  message = 'Sign in to reach your hosted memory.',
) =>
  new Response(failureBody(code, message), {
    status: 401,
    headers: {
      ...JSON_HEADERS,
      // Only where signing in is actually the answer. A key that was revoked or has
      // expired is not an OAuth problem, and a scheduled run has no browser to send.
      ...(code === 'unauthorized'
        ? { 'WWW-Authenticate': `Bearer resource_metadata="${PUBLIC_URL}/.well-known/oauth-protected-resource"` }
        : {}),
    },
  })

/** Where the owner turns writing on: the Automations screen, More on iPhone, Settings on the Mac. */
const AUTOMATIONS_SCREEN = 'the Automations screen (More on iPhone, Settings on the Mac)'

/** What each refusal from the database means, said once, for either door. */
const REFUSALS: Record<string, string> = {
  insufficient_scope:
    `This connection may read, not suggest changes. In the longbook app, open ${AUTOMATIONS_SCREEN} — the box "Let signed-in AIs suggest changes", or a key with "Read and suggest changes".`,
  key_expired: 'This key has expired. Make a new one in the longbook app.',
  key_revoked: 'This key was revoked in the longbook app.',
  not_found:
    'There is no hosted copy of this memory to propose against. Turn the MCP server switch on in the longbook app first.',
  queue_full:
    'The owner already has 100 suggestions waiting for review. Stop, and tell them to open longbook and review what is there.',
  payload_too_large: 'This call is too large to file. Split the batch and send it again.',
  unauthorized: 'This connection is not signed in.',
  entitlement_required:
    'This account has no longbook Cloud subscription, which the hosted memory needs. Stop, and tell the owner: longbook Cloud is subscribed to in the longbook app, under Account. On a Mac, Claude Desktop or Claude Code can instead use the longbook folder in iCloud, or the local server, at no charge.',
}

/** The hosted memory behind longbook Cloud: a handshake crosses, anything that reads it does not. */
const cloudRequired = () =>
  new Response(failureBody('entitlement_required', REFUSALS.entitlement_required!), {
    status: 403,
    headers: JSON_HEADERS,
  })

/** The AI's name as its requests introduce it, so the review says "Claude" rather
 *  than which door it came through. Unknown agents keep their first word. */
const clientName = (userAgent: string | null): string | null => {
  const ua = (userAgent ?? '').trim()
  if (!ua) return null
  const lower = ua.toLowerCase()
  if (lower.includes('claude') || lower.includes('anthropic')) return 'Claude'
  if (lower.includes('chatgpt') || lower.includes('openai')) return 'ChatGPT'
  if (lower.includes('gemini')) return 'Gemini'
  if (lower.includes('cursor')) return 'Cursor'
  const word = ua.split(/[\s/;(]/)[0] ?? ''
  return word.length >= 2 ? word.slice(0, 40) : null
}

/** Files one proposal through whichever definer function names this caller. */
// deno-lint-ignore no-explicit-any
const file = async (client: any, fn: string, who: Record<string, unknown>, proposal: {
  kind: string
  payload: unknown
  idempotency_key?: string
  source_ref?: string
}, agent: string | null = null) => {
  const { data: filed, error: fileError } = await client.rpc(fn, {
    ...who,
    p_kind: proposal.kind,
    p_payload: proposal.payload,
    p_source_ref: proposal.source_ref ?? null,
    p_idempotency_key: proposal.idempotency_key ?? null,
    p_client: agent,
  })
  const row = Array.isArray(filed) ? filed[0] : filed
  if (fileError || !row) {
    throw new RpcFailure('upstream_error', 'The proposal could not be filed. Try again in a moment.')
  }
  if (row.error) {
    throw new RpcFailure(
      row.error,
      REFUSALS[row.error] ?? 'This proposal was refused.',
      row.error === 'insufficient_scope' ? { scope: 'memory:propose' } : {},
    )
  }
  return { entry_id: row.entry_id, created: row.created, pending_count: row.pending_count }
}

const sha256Hex = async (text: string): Promise<string> => {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

/** How many messages in one body, single or batched, carry this method. A tools/call is a
 *  tool call; an initialize opens a connection. */
/** The name a client gives itself in initialize's clientInfo, and the names of the tools a
 *  body calls with how often. Names only: never an argument. */
const surfaceOf = (body: unknown): string | null => {
  for (const m of Array.isArray(body) ? body : [body]) {
    const name = (m as { method?: unknown; params?: { clientInfo?: { name?: unknown } } } | null)
    if (name?.method === 'initialize' && typeof name.params?.clientInfo?.name === 'string') return name.params.clientInfo.name
  }
  return null
}
const toolsCalled = (body: unknown): Record<string, number> => {
  const out: Record<string, number> = {}
  for (const m of Array.isArray(body) ? body : [body]) {
    const call = m as { method?: unknown; params?: { name?: unknown } } | null
    if (call?.method === 'tools/call' && typeof call.params?.name === 'string') {
      out[call.params.name] = (out[call.params.name] ?? 0) + 1
    }
  }
  return out
}

const messages = (body: unknown, method: string): number =>
  (Array.isArray(body) ? body : [body]).filter(
    (m) => typeof m === 'object' && m !== null && (m as { method?: unknown }).method === method,
  ).length

/** The methods a connection opens with, and the prompt menu, which is longbook's own
 *  words. None of them reads the memory, so the door can answer them without carrying it
 *  across. */
const HANDSHAKE = new Set(['initialize', 'ping', 'tools/list', 'resources/list', 'prompts/list', 'prompts/get'])

/** Whether any message in the body is more than a handshake: a tools/call, a resources/read,
 *  or a method this list does not know, which is given the memory to be safe. */
const needsMemory = (body: unknown): boolean =>
  (Array.isArray(body) ? body : [body]).some((m) => {
    const method = typeof m === 'object' && m !== null ? (m as { method?: unknown }).method : undefined
    return !(typeof method === 'string' && (HANDSHAKE.has(method) || method.startsWith('notifications/')))
  })

/** What the signed-in door answers: the memory when the body needs it, who this is, and
 *  whether the owner lets this connection suggest changes. A door that left the memory
 *  behind still carries the to_fill_in names, so initialize can say them. */
interface UserDoor {
  data: ReturnType<typeof parseVault> | null
  identity: Record<string, unknown>
  mayPropose: boolean
  toFillIn?: { id: string; name: string }[]
  /** The hints setup kept, carried the same way; absent while the database does not send them. */
  hints?: ReturnType<typeof parseHints>
  /** False when the account has no longbook Cloud; the database kept the memory back. */
  cloud?: boolean
}

/** The to_fill_in rows as the memory's parser keeps them: an id and a name, nothing less. */
const placeholders = (raw: unknown): { id: string; name: string }[] =>
  (Array.isArray(raw) ? raw : [])
    .filter((r): r is { id: string; name: string } =>
      typeof r === 'object' && r !== null && typeof r.id === 'string' && typeof r.name === 'string' && r.name.trim() !== '')
    .map((r) => ({ id: r.id, name: r.name }))

/** The signed-in identity, one shape whichever door built it. */
const userIdentity = (
  signedInAs: string,
  mayPropose: boolean,
  pushedAt: unknown,
  inbox: { pending: number; failed: unknown[]; failedCount: number },
): Record<string, unknown> => ({
  server: 'longbook (hosted)',
  signed_in_as: signedInAs,
  scopes: mayPropose ? ['memory:read', 'memory:propose'] : ['memory:read'],
  hosted_copy: pushedAt != null ? { pushed_at: pushedAt } : null,
  pending_for_review: inbox.pending,
  // Named on purpose: a proposal that could not be applied must not be invisible to the
  // agent that filed it. The newest 20 ride along with their reasons.
  failed_to_apply: inbox.failed,
  failed_to_apply_count: inbox.failedCount,
  rate_limit: { calls_per_minute: 30 },
  note: mayPropose
    ? 'Signed in as the owner. Changes you write are suggestions: they wait for the owner\'s app and land in its Proposals screen, to keep or undo.'
    : 'A signed-in AI reads the hosted copy. The owner has not turned on suggestions from the web.',
})

const memoryUnreadable = () =>
  new Response(failureBody('upstream_error', 'The hosted memory could not be read. Try again.'), {
    status: 500,
    headers: JSON_HEADERS,
  })

/** The signed-in door in one hop: mcp_memory_for_user answers the rate verdict, who this is,
 *  the owner's switch, the inbox, and the memory only when the body needs it, all from the
 *  caller's own JWT. Null while the database does not have the function yet. */
// deno-lint-ignore no-explicit-any
const oneHopUserDoor = async (supabase: any, withMemory: boolean): Promise<UserDoor | Response | null> => {
  const { data: rows, error, status } = await supabase.rpc('mcp_memory_for_user', { p_with_memory: withMemory })
  if (error?.code === 'PGRST202') return null
  // The token itself, or the role it carries, was refused before the function ran.
  if (status === 401 || status === 403) return unauthorized()
  if (error) return memoryUnreadable()
  const row = Array.isArray(rows) ? rows[0] : rows
  // A token without a subject answers no row.
  if (!row) return unauthorized()
  if (row.allowed === false) return tooMany(row.retry_after ?? 60)
  const mayPropose = row.web_propose === true
  return {
    data: row.memory ? parseVault(JSON.stringify(row.memory)) : null,
    identity: userIdentity(String(row.email), mayPropose, row.pushed_at, {
      pending: row.pending_count ?? 0,
      failed: Array.isArray(row.failed) ? row.failed : [],
      failedCount: row.failed_count ?? 0,
    }),
    mayPropose,
    toFillIn: placeholders(row.to_fill_in),
    hints: parseHints(row.hints),
    cloud: row.cloud !== false,
  }
}

/** The door of before, five round trips, kept for a function deployed ahead of the
 *  migration that adds the one-hop function. */
// deno-lint-ignore no-explicit-any
const fiveHopUserDoor = async (supabase: any, bearer: string): Promise<UserDoor | Response> => {
  const { data: userData } = await supabase.auth.getUser(bearer)
  if (!userData?.user) return unauthorized()

  const gate = limiter.allow(userData.user.id, Date.now())
  if (!gate.allowed) return tooMany(gate.retryAfterSeconds)
  // The durable floor. The subject is the caller's own JWT, read inside the
  // function. Errors fail open: this is a limiter, not the lock on the door.
  const { data: verdict } = await supabase.rpc('mcp_rate_check')
  const v = Array.isArray(verdict) ? verdict[0] : verdict
  if (v?.allowed === false) return tooMany(v.retry_after ?? 60)

  // One read per request: the row the caller's own JWT can see, nothing more.
  const { data: row, error } = await supabase
    .from('hosted_memories')
    .select('memory,pushed_at,web_propose')
    .maybeSingle()
  if (error) return memoryUnreadable()
  const mayPropose = row?.web_propose === true
  // The inbox as the owner's own JWT sees it: unapplied rows, pending ones first (the
  // queue is capped at 100), then failed ones newest first. One select.
  const { data: inbox } = await supabase
    .from('mcp_pending_writes')
    .select('id,kind,failure,created_at,failed_at,applied_at,source_ref')
    .is('applied_at', null)
    .order('failed_at', { ascending: false, nullsFirst: true })
    .limit(220)
  const unapplied: Record<string, unknown>[] = Array.isArray(inbox) ? inbox : []
  const failedRows = unapplied.filter((r) => r.failed_at != null)
  // The exact number of failures, however many the inbox page carried.
  const { count: failedTotal } = await supabase
    .from('mcp_pending_writes')
    .select('id', { count: 'exact', head: true })
    .is('applied_at', null)
    .not('failed_at', 'is', null)
  return {
    data: row ? parseVault(JSON.stringify(row.memory)) : null,
    identity: userIdentity(userData.user.email ?? userData.user.id, mayPropose, row?.pushed_at ?? null, {
      pending: unapplied.length - failedRows.length,
      failed: failedRows.slice(0, 20).map((r) => ({
        entry_id: r.id,
        kind: r.kind,
        reason: r.failure,
        created_at: r.created_at,
        failed_at: r.failed_at,
        source_ref: r.source_ref ?? null,
      })),
      failedCount: failedTotal ?? failedRows.length,
    }),
    mayPropose,
  }
}

/** Adds one request's connections, tool calls and filed proposals to the day's count for that
 *  AI application (mcp_count), then by door, surface and tool name (mcp_count_detail). Nothing
 *  identifying is stored. A failure is swallowed, and the
 *  runtime finishes the write after the answer when it can. */
const tally = async (
  // deno-lint-ignore no-explicit-any
  client: any,
  args: { p_key_hash: string | null; p_client: string; p_calls: number; p_edits: number; p_connections: number },
  detail: { p_door: 'oauth' | 'key'; p_surface: string | null; p_tools: Record<string, number> },
) => {
  if (args.p_calls === 0 && args.p_edits === 0 && args.p_connections === 0) return
  const work = (async () => {
    try {
      await client.rpc('mcp_count', args)
      // The same request by door, by the name the client gives itself, and by tool name.
      await client.rpc('mcp_count_detail', {
        p_key_hash: args.p_key_hash,
        p_client: args.p_client,
        p_door: detail.p_door,
        p_surface: detail.p_surface,
        p_connections: args.p_connections,
        p_tools: detail.p_tools,
      })
    } catch {
      // A count never changes an answer.
    }
  })()
  const runtime = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } }).EdgeRuntime
  if (typeof runtime?.waitUntil === 'function') {
    try {
      runtime.waitUntil(work)
      return
    } catch {
      // Fall through and wait for it here.
    }
  }
  await work
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url)
  if (url.pathname.endsWith('/server-card')) {
    if (req.method === 'OPTIONS') return new Response(null, { headers: CARD_HEADERS })
    if (req.method !== 'GET') return new Response(null, { status: 405, headers: { ...CARD_HEADERS, Allow: 'GET' } })
    if (req.headers.get('if-none-match') === CARD_TAG) return new Response(null, { status: 304, headers: CARD_HEADERS })
    return new Response(CARD_BODY, { headers: { ...CARD_HEADERS, 'Content-Type': 'application/mcp-server-card+json' } })
  }
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS_HEADERS })
  if (req.method === 'GET' && url.pathname.endsWith('/.well-known/oauth-protected-resource')) {
    return new Response(JSON.stringify(RESOURCE_METADATA), { headers: JSON_HEADERS })
  }
  // A person in a browser sees a real page at longbook.app/mcp — served by the site
  // layer, because this platform's gateway forces text/plain and a sandbox CSP on any
  // HTML a function answers. Every non-POST here gets the JSON contract instead.
  if (req.method !== 'POST') {
    return new Response(failureBody('validation_failed', 'POST one JSON-RPC message'), {
      status: 405,
      headers: { ...JSON_HEADERS, Allow: 'POST, OPTIONS' },
    })
  }

  const bearer = req.headers.get('authorization')?.replace(/^Bearer /i, '') ?? ''
  if (!bearer) return unauthorized()

  // The body before the doors, so the door knows whether this request needs the memory
  // at all before it asks the database for anything.
  let body: unknown
  try {
    body = await req.json()
  } catch {
    return new Response(
      JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'parse error' } }),
      { status: 400, headers: JSON_HEADERS },
    )
  }

  // Two doors, one room. OAuth clients carry a Supabase JWT; keyed clients carry a
  // personal access key (lbk_…), redeemed by hash through a definer function. Either
  // way the answer is one owner's memory, and no service role exists here at all.
  const anon = () =>
    createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    })

  let data: ReturnType<typeof parseVault> | null = null
  // The to_fill_in names when a handshake left the memory behind; data says them otherwise.
  let toFillIn: { id: string; name: string }[] | undefined
  let hints: ReturnType<typeof parseHints> | undefined
  let identity: Record<string, unknown> = {}
  // Set only for a key carrying memory:propose; its absence is what makes a connection
  // read-only — the write tools never even appear in tools/list.
  let propose: ((proposal: { kind: string; payload: unknown; idempotency_key?: string; source_ref?: string }) => unknown) | undefined
  let keyHash = ''
  // The client the day's count goes through: set only once a door has let the caller in.
  let counter: ReturnType<typeof anon> | null = null
  // Whether this body reads the memory: a handshake crosses either door without it, and
  // without longbook Cloud; anything more is refused when the account has none.
  const wantsMemory = needsMemory(body)

  if (bearer.startsWith('lbk_')) {
    keyHash = await sha256Hex(bearer)
    const gate = limiter.allow(`lbk:${keyHash}`, Date.now())
    if (!gate.allowed) return tooMany(gate.retryAfterSeconds)
    const { data: rows, error } = await anon().rpc('mcp_memory_for_key', { p_key_hash: keyHash })
    const match = Array.isArray(rows) ? rows[0] : rows
    if (error || !match) return unauthorized('key_revoked', 'This key is not valid — it may have been revoked in the longbook app.')
    if (match.expired === true) {
      return unauthorized('key_expired', `This key expired on ${String(match.expires_at).slice(0, 10)}. Make a new one in the longbook app.`)
    }
    // The durable verdict rode back with the redemption — one Postgres row per key.
    if (match.allowed === false) return tooMany(match.retry_after ?? 60)
    if (match.cloud === false && wantsMemory) return cloudRequired()

    const scopes: string[] = Array.isArray(match.scopes) ? match.scopes : ['memory:read']
    data = match.memory ? parseVault(JSON.stringify(match.memory)) : null
    identity = {
      server: 'longbook (hosted)',
      key_name: match.key_name,
      scopes,
      expires_at: match.expires_at ?? null,
      hosted_copy: match.memory ? { pushed_at: match.pushed_at } : null,
      pending_for_review: match.pending_count ?? 0,
      // Named on purpose: a proposal that could not be applied must not be invisible
      // to the agent that filed it. The newest 20 ride along with their reasons.
      failed_to_apply: Array.isArray(match.failed) ? match.failed : [],
      failed_to_apply_count: match.failed_count ?? 0,
      rate_limit: { calls_per_minute: 30, resets_in: match.retry_after ?? 60 },
    }
    if (scopes.includes('memory:propose')) {
      propose = (proposal) => file(anon(), 'mcp_propose_for_key', { p_key_hash: keyHash }, proposal, clientName(req.headers.get('user-agent')))
    }
    counter = anon()
  } else {
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${bearer}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    // One hop, and a handshake crosses without the memory. The five-hop door answers only
    // while the one-hop function is not in the database yet.
    const door = (await oneHopUserDoor(supabase, wantsMemory)) ?? (await fiveHopUserDoor(supabase, bearer))
    if (door instanceof Response) return door
    if (door.cloud === false && wantsMemory) return cloudRequired()
    data = door.data
    toFillIn = door.toFillIn
    hints = door.hints
    identity = door.identity
    // The owner's own switch, read from their own row. Off is enforced in the database
    // too — this only decides whether the door is offered.
    if (door.mayPropose) propose = (proposal) => file(supabase, 'mcp_propose_for_user', {}, proposal, clientName(req.headers.get('user-agent')))
    counter = supabase
  }

  const viaKey = bearer.startsWith('lbk_')
  // The same door, counting each proposal filed as new (created is true).
  let edits = 0
  const offered = propose
  const filing = offered
    ? async (proposal: Parameters<typeof offered>[0]) => {
        const filed = await offered(proposal)
        if ((filed as { created?: unknown } | null)?.created === true) edits += 1
        return filed
      }
    : undefined
  const ctx = {
    loadData: () => data,
    toFillIn: () => toFillIn ?? [],
    hints: () => hints ?? [],
    llmsText: () => LLMS_TXT,
    schemaText: () => SCHEMA_JSON,
    identity: () => identity,
    writeMode: 'proposal' as const,
    whyReadOnly: () =>
      viaKey
        ? 'This key may read, not suggest changes.'
        : 'This is a signed-in web connection, and suggestions from the web are switched off.',
    howToEnable: () =>
      viaKey
        ? `In the longbook app, open ${AUTOMATIONS_SCREEN} and make a key with "Read and suggest changes".`
        : `In the longbook app, open ${AUTOMATIONS_SCREEN} — the box "Let signed-in AIs suggest changes".`,
    ...(filing ? { propose: filing } : {}),
  }
  let response: Response
  if (Array.isArray(body)) {
    const answers = []
    for (const message of body) {
      const one = await handleRpc(message, ctx)
      if (one !== null) answers.push(one)
    }
    response = answers.length === 0
      ? new Response(null, { status: 202, headers: CORS_HEADERS })
      : new Response(JSON.stringify(answers), { headers: JSON_HEADERS })
  } else {
    const answer = await handleRpc(body, ctx)
    response = answer === null
      ? new Response(null, { status: 202, headers: CORS_HEADERS })
      : new Response(JSON.stringify(answer), { headers: JSON_HEADERS })
  }
  if (counter) {
    await tally(counter, {
      p_key_hash: viaKey ? keyHash : null,
      p_client: clientName(req.headers.get('user-agent')) ?? 'other',
      p_calls: messages(body, 'tools/call'),
      p_edits: edits,
      p_connections: messages(body, 'initialize'),
    }, {
      p_door: viaKey ? 'key' : 'oauth',
      p_surface: surfaceOf(body),
      p_tools: toolsCalled(body),
    })
  }
  return response
})
