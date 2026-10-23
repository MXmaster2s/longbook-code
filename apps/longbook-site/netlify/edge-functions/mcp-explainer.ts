// Both faces of longbook.app/mcp. A browser GET gets the page below; any other GET gets
// the same facts as JSON. POSTs and stream probes fall through to the proxy in
// _redirects. It lives here because the function's platform refuses to serve HTML.
import type { Context } from 'https://edge.netlify.com'
import { ROUTER } from './lib/mcp-router.gen.ts'

const CONNECT_PROMPT =
  'I am giving you an MCP server. Please help me connect it step by step: ' +
  'https://longbook.app/mcp. It is my longbook financial memory. If your app supports ' +
  'MCP connectors or custom servers, add it there. Sign-in will open in my browser.'

// The hosted door takes a statement attached to the chat; the Mac door reads the ones in
// the documents folder, so each gets its own words, both from the prompt catalogue.
const IMPORT_PROMPT = ROUTER.recipes.import_statement.the_owner_says
const IMPORT_PROMPT_MAC = ROUTER.recipes.import_statement.from_the_documents_folder

const escape = (text: string): string =>
  text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

const inline = (text: string): string =>
  escape(text)
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/`([^`]+)`/g, '<code>$1</code>')

// The guide's chapter as a page: paragraphs and lists, bold and code. The chapter's own
// heading is dropped, since the section carries one.
const chapter = (markdown: string): string => {
  const out: string[] = []
  for (const block of markdown.split(/\n\s*\n/)) {
    const lines = block.split('\n').filter((line) => line.trim())
    if (!lines.length || lines[0].startsWith('## ')) continue
    const ordered = /^\d+\.\s/.test(lines[0])
    if (!ordered && !lines[0].startsWith('- ')) {
      out.push(`<p>${inline(lines.map((line) => line.trim()).join(' '))}</p>`)
      continue
    }
    const items: string[] = []
    for (const line of lines) {
      const start = /^(?:\d+\.|-)\s+(.*)$/.exec(line)
      if (start) items.push(start[1])
      else if (items.length) items[items.length - 1] += ` ${line.trim()}`
    }
    const tag = ordered ? 'ol' : 'ul'
    out.push(`<${tag}>${items.map((item) => `<li>${inline(item)}</li>`).join('')}</${tag}>`)
  }
  return out.join('\n')
}

const toolList = (tools: readonly { name: string }[]): string =>
  tools.map((tool) => `<code>${escape(tool.name)}</code>`).join(' ')

const NEEDS: Record<string, string> = {
  mail: 'your mail, connected to your AI',
  scheduler: 'scheduled tasks in your AI’s app',
}

// The catalogue's prompts by group, in its order: the owner's words to copy, and what follows.
const promptGroups = (): string => {
  const groups: { title: string; prompts: (typeof ROUTER.prompts)[number][] }[] = []
  for (const prompt of ROUTER.prompts) {
    const group = groups.find((g) => g.title === prompt.group)
    if (group) group.prompts.push(prompt)
    else groups.push({ title: prompt.group, prompts: [prompt] })
  }
  return groups
    .map((group) => `
    <h3>${escape(group.title)}</h3>
    ${group.prompts.map((prompt) => `
    <span class="prompt">${escape(prompt.phrase)}</span>
    <p class="quiet result">${escape(prompt.result)}${
      prompt.needs.length
        ? ` Needs ${prompt.needs.map((need: string) => escape(NEEDS[need] ?? need)).join(', and ')}.`
        : ''
    }</p>`).join('')}`)
    .join('')
}

const door = (d: (typeof ROUTER.doors)[number]): string => `
  <section class="door">
    <h2>${escape(d.title)}</h2>
    <p>${escape(d.how)}</p>
    <p class="quiet">Reads your memory${d.documents ? ', and the statements in your documents folder' : ''}.
      ${typeof d.writes === 'string' ? `Writes ${escape(d.writes)}.` : 'Does not write.'}</p>
  </section>`

const PAGE = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>longbook — MCP server</title>
<style>
  :root {
    --lb-canvas: #0D1115; --lb-card: #14171D; --lb-chrome: #1C2028; --lb-hairline: #262B34;
    --lb-text-primary: #D3D8DE; --lb-text-secondary: #97A0AB; --lb-text-tertiary: #7F8994;
    --lb-brand-text: #8F82F2;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html { background: var(--lb-canvas); }
  body {
    font-family: ui-sans-serif, system-ui, -apple-system, 'Segoe UI', sans-serif;
    color: var(--lb-text-primary);
    min-height: 100vh; display: grid; place-items: start center; padding: 24px 16px 64px;
  }
  main { width: 100%; max-width: 560px; }
  .wordmark { font-size: 22px; font-weight: 650; letter-spacing: -0.2px; margin-bottom: 20px; }
  .wordmark a { color: inherit; text-decoration: none; }
  h1 { font-size: 19px; font-weight: 600; margin-bottom: 8px; }
  h2 { font-size: 15px; font-weight: 600; margin-bottom: 6px; }
  h3 { font-size: 13px; font-weight: 600; margin-top: 20px; color: var(--lb-text-primary); }
  .result { margin-top: 6px; }
  p { font-size: 14px; line-height: 1.55; color: var(--lb-text-secondary); }
  p + p { margin-top: 8px; }
  section {
    background: var(--lb-card); border: 1px solid var(--lb-hairline);
    border-radius: 16px; padding: 20px; margin-top: 12px;
  }
  .prompt {
    display: block; user-select: all; margin-top: 12px; padding: 12px 14px;
    font-size: 13px; line-height: 1.5; color: var(--lb-text-primary);
    background: var(--lb-chrome); border: 1px solid var(--lb-hairline); border-radius: 12px;
  }
  code {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px;
    color: var(--lb-text-primary); background: var(--lb-chrome);
    border-radius: 6px; padding: 1px 5px; white-space: nowrap;
  }
  .tools { margin-top: 8px; line-height: 2; }
  .recipe p, .recipe li { font-size: 13px; line-height: 1.6; color: var(--lb-text-secondary); }
  .recipe p, .recipe ol, .recipe ul { margin-top: 10px; }
  .recipe ol, .recipe ul { padding-left: 20px; }
  .recipe li + li { margin-top: 6px; }
  .recipe strong { color: var(--lb-text-primary); font-weight: 600; }
  .recipe code { white-space: normal; }
  .quiet { font-size: 13px; color: var(--lb-text-tertiary); }
  .links { margin-top: 8px; font-size: 13px; line-height: 1.9; }
  a { color: var(--lb-brand-text); }
</style>
</head>
<body>
<main>
  <div class="wordmark"><a href="/">longbook</a></div>
  <section>
    <h1>This is an MCP server</h1>
    <p>You have reached the address AI assistants use to reach a longbook financial memory. It is a machine endpoint, so there is nothing to browse — but here is which door is which.</p>
    <p>To connect an AI, paste this into it:</p>
    <span class="prompt">${escape(CONNECT_PROMPT)}</span>
  </section>

  ${ROUTER.doors.map(door).join('\n')}

  <section>
    <h2>What it can do</h2>
    <p class="quiet">Reading</p>
    <p class="tools">${toolList(ROUTER.tools.read)}</p>
    <p class="quiet">Writing — every write lands in the app’s Changes screen, to keep or undo</p>
    <p class="tools">${toolList(ROUTER.tools.write)}</p>
    <p class="quiet">On the owner’s machine only</p>
    <p class="tools">${toolList(ROUTER.tools.local_only)}</p>
  </section>

  <section>
    <h2>What it is for</h2>
    <p>Attach a bank or card statement to the chat with an AI connected to this address, and ask:</p>
    <span class="prompt">${escape(IMPORT_PROMPT)}</span>
    <p class="quiet">Your AI reads the statement in the chat, writes what it finds as one batch, lists the charges that clearly repeat, and asks you about the rest; it sets the repeats once your app has taken in the batch. You review the whole thing in longbook and keep it or undo it.</p>
    <p style="margin-top:12px">On a Mac where the app has set up Claude Desktop, drop a year of statements into the longbook folder instead, and ask:</p>
    <span class="prompt">${escape(IMPORT_PROMPT_MAC)}</span>
    <p class="quiet">That door reads the statements in your documents folder, on your own machine.</p>
  </section>

  <section id="prompts">
    <h2>Prompts</h2>
    <p>Copy one into an AI connected to longbook. Each comes with a procedure your AI follows, step by step, and what it writes waits in the app’s Changes screen for you to keep or undo.</p>
    ${promptGroups()}
    <p class="quiet" style="margin-top:16px">For the AI: <code>read_guide</code> with a prompt’s name or the owner’s words returns its procedure, and <a href="/prompts.json">prompts.json</a> holds them all.</p>
  </section>

  <section id="daily-email-round">
    <h2>${escape(ROUTER.recipes.daily_email_round.title)}</h2>
    <p>Your AI reads yesterday's mail each morning and writes the money it finds into longbook, where it waits in Changes. To set it up, paste this into an AI that has this connector and reads your mail:</p>
    <span class="prompt">${escape(ROUTER.recipes.daily_email_round.the_owner_says)}</span>
    <p class="quiet" style="margin-top:12px">What follows is for the AI. It is the guide's own chapter, also at <code>read_guide "daily-email-round"</code>.</p>
    <div class="recipe">${chapter(ROUTER.recipes.daily_email_round.instructions)}</div>
  </section>

  <section>
    <h2>For the AI reading this</h2>
    <p>Call <code>whoami</code> first: it says who you are, what you may do, what is waiting, and where the schemas live. Then <code>read_guide</code> for the working method.</p>
    <p class="links">
      <a href="/llms.txt">llms.txt</a> — the contract and the working method<br>
      <a href="/schema/longbook.schema.json">longbook.schema.json</a> — the formal schema<br>
      <a href="/library.json">library.json</a> — the tag library, with names and icons<br>
      <a href="/prompts.json">prompts.json</a> — the prompts, each with its procedure
    </p>
    <p class="quiet">Contract revision ${ROUTER.contract_revision}. Same address for JSON: request it without <code>Accept: text/html</code>.</p>
  </section>

  <p class="quiet" style="margin-top:16px">You can disconnect any AI, and revoke any key, from the longbook app. <a href="/">longbook.app</a></p>
</main>
</body>
</html>
`

export default async (request: Request, context: Context) => {
  if (request.method !== 'GET') return context.next()
  const accept = request.headers.get('accept') ?? ''
  // A streamable-HTTP client opens its stream with a GET; that belongs to the function,
  // which answers it honestly rather than being handed a page.
  if (accept.includes('text/event-stream')) return context.next()
  if (accept.includes('text/html')) {
    return new Response(PAGE, { status: 200, headers: { 'Content-Type': 'text/html; charset=utf-8' } })
  }
  return new Response(JSON.stringify(ROUTER, null, 2), {
    status: 200,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'public, max-age=300' },
  })
}

export const config = { path: '/mcp' }
