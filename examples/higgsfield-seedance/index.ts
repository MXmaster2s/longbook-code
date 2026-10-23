#!/usr/bin/env -S npx tsx
// One Seedance 2.5 text-to-video generation through Higgsfield's official SDK. Billable.
// HF_CREDENTIALS (key-id:key-secret) comes from the environment, or else from .env.local at the
// repository root, which Git ignores. The key is never printed.
// Run: npm run higgsfield:seedance
import { resolve } from 'node:path'
import {
  APIError,
  AuthenticationError,
  NotEnoughCreditsError,
  TimeoutError,
  createHiggsfieldClient,
} from '@higgsfield/client/v2'

const MODEL = 'bytedance/seedance-2.5/text-to-video'
const INPUT = {
  prompt: 'A cinematic scene at sunset',
  duration: 5,
  resolution: '720p',
  aspect_ratio: '16:9',
}
const MAX_WAIT_MINUTES = 20
const ENV_FILE = resolve(__dirname, '../../.env.local')

// Final statuses that mean no video. The SDK's wait never stops on "canceled", which is missing
// from its status type, so a canceled request usually ends as the timeout instead.
const NOT_GENERATED: Record<string, string> = {
  nsfw: 'was blocked by content moderation',
  failed: 'failed',
  canceled: 'was canceled',
  completed: 'completed without a video URL',
}
const CHECK_DASHBOARD =
  'Higgsfield may have accepted and billed the request, and it may still finish: check the Higgsfield dashboard before running this again.'

class SetupError extends Error {}

// Set just before the billable request goes out.
let sent = false

function readCredentials(): string {
  // The HTTP libraries under the SDK print request headers, key included, when these are on.
  if (process.env.DEBUG || process.env.NODE_DEBUG) {
    throw new SetupError('Unset DEBUG and NODE_DEBUG first: their output would include the key')
  }
  // .env.local never overrides a variable that is already set, even to nothing.
  if (!process.env.HF_CREDENTIALS?.trim()) {
    delete process.env.HF_CREDENTIALS
    if (typeof process.loadEnvFile !== 'function') {
      throw new SetupError(`Reading .env.local needs Node 20.12 or newer; this is ${process.version}`)
    }
    try {
      process.loadEnvFile(ENV_FILE)
    } catch (error) {
      // A missing file is reported below, as the missing variable.
      if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error
    }
  }
  const credentials = process.env.HF_CREDENTIALS?.trim()
  if (!credentials) {
    throw new SetupError('HF_CREDENTIALS is not set. Add HF_CREDENTIALS=key-id:key-secret to .env.local')
  }
  if (!/^[^:\s]+:[^:\s]+$/.test(credentials)) {
    throw new SetupError('HF_CREDENTIALS must be key-id:key-secret: two parts joined by one colon')
  }
  return credentials
}

async function main(): Promise<void> {
  const client = createHiggsfieldClient({
    credentials: readCredentials(),
    // A video can take longer than the SDK's five-minute default.
    maxPollTime: MAX_WAIT_MINUTES * 60_000,
    // Submitting is billable: retrying a submit whose reply was lost could pay for a second video.
    maxRetries: 0,
  })

  console.log(`Submitting ${MODEL} with ${JSON.stringify(INPUT)}`)
  console.log(`Waiting up to ${MAX_WAIT_MINUTES} minutes for the video…`)
  sent = true
  const result = await client.subscribe(MODEL, { input: INPUT, withPolling: true })

  const status: string = result.status
  const url = result.video?.url
  if (status === 'completed' && url) {
    console.log(`Completed. Request ${result.request_id}`)
    console.log(`Video URL: ${url}`)
    return
  }
  process.exitCode = 1
  const request = result.request_id ? `request ${result.request_id}` : 'the request'
  const outcome = NOT_GENERATED[status]
  if (outcome) console.error(`Not generated: ${request} ${outcome}.`)
  else console.error(`Outcome unknown: ${request} stopped at status "${status}". ${CHECK_DASHBOARD}`)
}

// Only an error's name and message are printed: a raw HTTP error carries the request headers,
// and with them the key.
function describe(error: unknown): string {
  if (error instanceof SetupError) return error.message
  if (error instanceof AuthenticationError) return 'Higgsfield rejected HF_CREDENTIALS (HTTP 401)'
  if (error instanceof NotEnoughCreditsError) {
    return 'HTTP 403. The SDK reports every 403 as not enough credits, but a firewall or proxy blocking api.higgsfield.ai answers 403 too'
  }
  if (error instanceof TimeoutError) return `no result within ${MAX_WAIT_MINUTES} minutes`
  if (error instanceof APIError) return `Higgsfield API error (HTTP ${error.statusCode}): ${error.message}`
  if (error instanceof Error) return `${error.name}: ${error.message}`
  return 'an unknown error'
}

main().catch((error: unknown) => {
  process.exitCode = 1
  // A 4xx is a refusal. Any other failure once the request is out (a timeout, a 5xx, a dropped
  // connection) can come after Higgsfield accepted it.
  const refused =
    error instanceof AuthenticationError || (error instanceof APIError && (error.statusCode ?? 500) < 500)
  if (!sent || refused) console.error(`Not generated: ${describe(error)}.`)
  else console.error(`Outcome unknown: ${describe(error)}. ${CHECK_DASHBOARD}`)
})
