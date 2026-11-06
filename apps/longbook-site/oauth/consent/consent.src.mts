// The OAuth consent page: a signed-in owner tells longbook whether their AI may read
// the hosted memory. Someone already known here skips straight through — Supabase
// answers a bare redirect for a repeat consent, and this page honours it.
import { createClient } from '@supabase/supabase-js'

// Public by design — an anon key is meant to ship in client code; auth is the boundary.
const SUPABASE_URL = 'https://xbrnijgctmovoqbbmgmb.supabase.co'
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhicm5pamdjdG1vdm9xYmJtZ21iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU3NzQ0NDQsImV4cCI6MjEwMTM1MDQ0NH0.ZamrPyf3UmAmbqzzAcce_Ocb1bKNq19wVxTtaC32a-g'

const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
// Reachable from the console on purpose, for debugging a live sign-in.
;(window as unknown as Record<string, unknown>).longbook = { client }

const params = new URLSearchParams(window.location.search)
const authorizationId = params.get('authorization_id')

const el = (id: string) => document.getElementById(id) as HTMLElement
const show = (state: string) => {
  for (const panel of document.querySelectorAll<HTMLElement>('[data-state]')) {
    panel.hidden = panel.dataset.state !== state
  }
}
const say = (id: string, text: string) => {
  el(id).textContent = text
}
const fail = (message: string, feedback = false) => {
  say('error-text', message)
  el('error-feedback').hidden = !feedback
  show('error')
}

/**
 * The hourly cap on codes is the one failure worth a way to write to us. Auth's own limits name
 * themselves by code; the cap is the server's own sentence and carries no code of its own.
 */
const hourlyLimit = (error: { status?: number; code?: string }): boolean =>
  error.status === 429 && error.code !== 'over_email_send_rate_limit' && error.code !== 'over_request_rate_limit'

const friendly = (message: string): string => {
  if (/otp_expired|expired/i.test(message)) return 'That code has expired. Request a new one and enter it within a few minutes.'
  if (/rate limit|only request this after/i.test(message)) return 'Too many codes requested. Wait a moment, then try again.'
  if (/signup|not allowed/i.test(message)) return 'That email address does not have a longbook account yet. Create one in the app first.'
  return message
}

let email = ''

// Three counts, as the privacy policy describes them: the page opened with a request, and the
// answer. Each carries only the AI's registered name. The site's switch, Global Privacy Control
// and Do Not Track stop them, as does any copy not on longbook.app.
const MEASURE_TOKEN = 'phc_pTXUJ2Qh4fYGu6EmDiwZcAYj6i9htiEQETbYZxApGDaM'
const measured = (): boolean => {
  const signals = navigator as Navigator & { globalPrivacyControl?: boolean; doNotTrack?: string | null }
  if (signals.globalPrivacyControl === true || signals.doNotTrack === '1') return false
  if (location.hostname !== 'longbook.app' && location.hostname !== 'www.longbook.app') return false
  try {
    return localStorage.getItem('longbook.measure') !== 'off'
  } catch {
    return true
  }
}
let aiName = 'other'
const count = (event: 'consent_opened' | 'consent_approved' | 'consent_denied') => {
  if (!measured()) return
  const properties = {
    $cookieless_mode: true,
    $process_person_profile: false,
    $geoip_disable: true,
    $host: 'longbook.app',
    $lib: 'longbook-consent',
    client: aiName,
  }
  const body = JSON.stringify({
    api_key: MEASURE_TOKEN,
    batch: [{ event, distinct_id: '$posthog_cookieless', properties, timestamp: new Date().toISOString() }],
  })
  // keepalive, so an answer still counts while the page leaves for the AI's return address.
  fetch('https://us.i.posthog.com/batch/', { method: 'POST', body, keepalive: true, headers: { 'Content-Type': 'text/plain' } })
    .catch(() => {})
}

// The review account signs in with the fixed code in its directory listing, as test phone numbers
// do elsewhere; the server holds the code and can switch it off. No code is emailed for it.
const REVIEW_ADDRESS = 'review@longbook.app'
const isReview = () => email.toLowerCase() === REVIEW_ADDRESS

async function reviewSignIn(code: string): Promise<string | null> {
  const response = await fetch(`${SUPABASE_URL}/functions/v1/review-sign-in`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', apikey: SUPABASE_ANON_KEY },
    body: JSON.stringify({ email, code }),
  }).catch(() => null)
  if (!response) return 'Check your connection and try again.'
  const body = (await response.json().catch(() => ({}))) as { token_hash?: string; error?: string }
  if (!response.ok || !body.token_hash) return body.error ?? 'That code is not right.'
  const { error } = await client.auth.verifyOtp({ token_hash: body.token_hash, type: 'magiclink' })
  return error ? friendly(error.message) : null
}

async function boot() {
  if (!authorizationId) {
    show('no-request')
    return
  }
  const { data } = await client.auth.getSession()
  if (!data.session) {
    show('signin')
    return
  }
  await loadDetails()
}

async function loadDetails() {
  show('loading')
  const { data, error } = await client.auth.oauth.getAuthorizationDetails(authorizationId!)
  if (error) {
    fail(friendly(error.message))
    return
  }
  if ('authorization_id' in data) {
    const clientName = data.client.name || 'Your AI'
    aiName = (data.client.name ?? '').replace(/[^A-Za-z0-9._ -]/g, '').trim().slice(0, 40) || 'other'
    count('consent_opened')
    say('client-name', clientName)
    say('client-name-2', clientName)
    say('client-target', hostOf(data.redirect_uri))
    say('who', data.user.email)
    show('consent')
    return
  }
  show('leaving')
  window.location.replace(data.redirect_url)
}

const hostOf = (uri: string): string => {
  try {
    return new URL(uri).host
  } catch {
    return uri
  }
}

async function sendCode() {
  email = (el('email') as HTMLInputElement).value.trim()
  if (!email) return
  if (isReview()) {
    say('code-sent-to', email)
    show('code')
    el('code').focus()
    return
  }
  setBusy('send', true)
  const { error } = await client.auth.signInWithOtp({ email, options: { shouldCreateUser: false } })
  setBusy('send', false)
  if (error) {
    fail(friendly(error.message), hourlyLimit(error))
    return
  }
  say('code-sent-to', email)
  show('code')
  el('code').focus()
}

async function verifyCode() {
  const token = (el('code') as HTMLInputElement).value.trim()
  if (!token) return
  setBusy('verify', true)
  if (isReview()) {
    const problem = await reviewSignIn(token)
    setBusy('verify', false)
    if (problem) {
      say('code-error', problem)
      return
    }
    await loadDetails()
    return
  }
  const { error } = await client.auth.verifyOtp({ email, token, type: 'email' })
  setBusy('verify', false)
  if (error) {
    say('code-error', friendly(error.message))
    return
  }
  await loadDetails()
}

async function decide(approve: boolean) {
  setBusy('allow', true)
  setBusy('deny', true)
  const { data, error } = approve
    ? await client.auth.oauth.approveAuthorization(authorizationId!, { skipBrowserRedirect: true })
    : await client.auth.oauth.denyAuthorization(authorizationId!, { skipBrowserRedirect: true })
  if (error) {
    fail(friendly(error.message))
    return
  }
  // The outcome in words, then straight back to the AI that asked. Its callback sets up
  // the connection before it answers, so these words stay on screen while it does.
  show(approve ? 'approved' : 'denied')
  count(approve ? 'consent_approved' : 'consent_denied')
  if (data?.redirect_url) window.location.replace(data.redirect_url)
}

const CONNECT_PROMPT =
  'I am giving you an MCP server. Please help me connect it step by step: ' +
  'https://longbook.app/mcp. It is my longbook financial memory and it is read-only. ' +
  'If your app supports MCP connectors or custom servers, add it there. ' +
  'Sign-in will open in my browser.'

async function copyPrompt() {
  try {
    await navigator.clipboard.writeText(CONNECT_PROMPT)
    say('copy-word', 'Copied. Paste it into any AI.')
  } catch {
    say('copy-word', 'Copying is blocked on this page. Select the text above and copy it manually.')
  }
}

async function switchAccount() {
  // This browser only: the global default would end the account's other sessions too.
  await client.auth.signOut({ scope: 'local' })
  show('signin')
}

function setBusy(id: string, busy: boolean) {
  const button = el(id) as HTMLButtonElement
  button.disabled = busy
}

el('copy-prompt').addEventListener('click', () => void copyPrompt())
el('send').addEventListener('click', () => void sendCode())
el('verify').addEventListener('click', () => void verifyCode())
el('allow').addEventListener('click', () => void decide(true))
el('deny').addEventListener('click', () => void decide(false))
el('switch').addEventListener('click', () => void switchAccount())
el('email').addEventListener('keydown', (e) => {
  if ((e as KeyboardEvent).key === 'Enter') void sendCode()
})
el('code').addEventListener('keydown', (e) => {
  if ((e as KeyboardEvent).key === 'Enter') void verifyCode()
})

void boot()
