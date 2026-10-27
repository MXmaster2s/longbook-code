// The hosted server's Server Card (MCP SEP-2127): who it is and where to connect, read before
// connecting. Its version and protocols are the ones initialize reports, so the two agree; the
// rest matches the registry entry, server.json, which a test holds it to.
import { RELEASE_VERSION } from '@longbook/core'
import { PROTOCOLS } from './rpc.js'

export const SERVER_CARD = {
  $schema: 'https://static.modelcontextprotocol.io/schemas/v1/server-card.schema.json',
  name: 'app.longbook/mcp',
  title: 'longbook',
  description: 'Your longbook of bills, subscriptions and expenses, for your AI to read and to suggest changes to.',
  version: RELEASE_VERSION,
  websiteUrl: 'https://longbook.app/mcp/',
  repository: { url: 'https://github.com/MXmaster2s/longbook-code', source: 'github', subfolder: 'packages/mcp' },
  icons: [{ src: 'https://longbook.app/apple-touch-icon.png', mimeType: 'image/png', sizes: ['180x180'] }],
  remotes: [{ type: 'streamable-http', url: 'https://longbook.app/mcp', supportedProtocolVersions: PROTOCOLS }],
}
