// longbook's prompts as MCP prompts, said once for both doors: the menu entry, and the
// message a client puts in the chat when the owner picks one. The words come from the
// catalogue in @longbook/core; nothing here restates a procedure.
import { CONTRACT_REVISION, PROMPTS, promptGuideKey, promptPhrase } from '@longbook/core'
import type { LongbookPrompt } from '@longbook/core'

export interface McpPromptArgument {
  name: string
  description: string
  required: boolean
}

export interface McpPrompt {
  name: string
  title: string
  description: string
  arguments?: McpPromptArgument[]
}

// A type, not an interface: the SDK's result type carries an index signature.
export type McpPromptMessage = {
  description: string
  messages: { role: 'user'; content: { type: 'text'; text: string } }[]
}

export const MONTH_ARGUMENT_DESCRIPTION =
  'The month the owner means, by name, such as "October". Left out, the month in progress.'

const MONTH_ARGUMENT: McpPromptArgument = { name: 'month', description: MONTH_ARGUMENT_DESCRIPTION, required: false }

/** One menu entry: the prompt's id as its name, and a month argument where its words name a month. */
export const mcpPrompt = (prompt: LongbookPrompt): McpPrompt => ({
  name: prompt.id,
  title: prompt.title,
  description: prompt.result,
  ...(prompt.template ? { arguments: [MONTH_ARGUMENT] } : {}),
})

/** The prompt menu both doors list, in the catalogue's order. */
export const MCP_PROMPTS: McpPrompt[] = PROMPTS.map(mcpPrompt)

const MONTHS = /^(january|february|march|april|may|june|july|august|september|october|november|december)$/i
const MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
  'October', 'November', 'December']

/** "october" reads "October"; anything else stays as the client sent it. */
const monthName = (words: string): string =>
  MONTHS.test(words) ? words[0]!.toUpperCase() + words.slice(1).toLowerCase() : words

/**
 * The owner's words as one user message, then longbook's procedure, then where the method
 * lives in full. Without a month, a month prompt names the one in progress, by UTC unless
 * the caller passes its own calendar. Null for an unknown name.
 */
export function mcpPromptMessage(
  name: string,
  month?: unknown,
  today: Date = new Date(),
  monthOf: (day: Date) => number = (day) => day.getUTCMonth(),
): McpPromptMessage | null {
  const prompt = PROMPTS.find((p) => p.id === name)
  if (!prompt) return null
  const named = typeof month === 'string' && month.trim() ? monthName(month.trim()) : MONTH_NAMES[monthOf(today)]
  const lines = [
    promptPhrase(prompt, named),
    '',
    "longbook's procedure for this, to follow step by step with every rule in its guide:",
    ...prompt.procedure,
  ]
  if (prompt.chapter) {
    lines.push('', `The method in full: read_guide("${prompt.chapter}")`)
  }
  lines.push('', `Pass guide_key "${promptGuideKey(prompt, CONTRACT_REVISION)}" with every write this procedure makes.`)
  return {
    description: prompt.result,
    messages: [{ role: 'user', content: { type: 'text', text: lines.join('\n') } }],
  }
}
