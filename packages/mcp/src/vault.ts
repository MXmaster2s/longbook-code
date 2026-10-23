// Reads the vault folder this server stands on. The folder IS the product: plain files
// the owner can open. Parsing itself lives in parse.ts, which the hosted server
// shares; this file owns only the filesystem.
import { readFileSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import type { LoadedData } from '@longbook/core'
import { LIBRARY_JSON, LLMS_TXT, SCHEMA_JSON, contractRevisionOf } from '@longbook/core'
import { VaultReadError, parseVault } from './parse.js'

export { VaultReadError, parseVault }

export const DATA_FILE = 'financial_memory.json'
export const SCHEMA_FILE = 'longbook.schema.json'
export const LLMS_FILE = 'llms.txt'
export const LIBRARY_FILE = 'library.json'
export type ContractFile = typeof SCHEMA_FILE | typeof LLMS_FILE | typeof LIBRARY_FILE

const BUNDLED: Record<ContractFile, string> = {
  [SCHEMA_FILE]: SCHEMA_JSON,
  [LLMS_FILE]: LLMS_TXT,
  [LIBRARY_FILE]: LIBRARY_JSON,
}

/**
 * The newer of two copies of a contract file, by the revision line each carries. A copy
 * without a revision is older than any that names one; equal revisions keep the vault's.
 */
export function newerContract(vaultCopy: string | null, bundled: string): string {
  if (vaultCopy === null) return bundled
  const inVault = contractRevisionOf(vaultCopy) ?? -1
  const inBundle = contractRevisionOf(bundled) ?? -1
  return inBundle > inVault ? bundled : vaultCopy
}

/** Where the Mac app keeps the vault when iCloud Drive holds it. */
export function defaultVaultDir(): string {
  return join(homedir(), 'Library', 'Mobile Documents', 'iCloud~app~longbook', 'Documents')
}

/** `--vault <dir>` (or `--vault=<dir>`) wins, then LONGBOOK_VAULT_PATH, then iCloud. */
export function resolveVaultDir(argv: string[] = process.argv, env = process.env): string {
  const inline = argv.find((a) => a.startsWith('--vault='))
  if (inline) return inline.slice('--vault='.length)
  const flag = argv.indexOf('--vault')
  if (flag !== -1) {
    const value = argv[flag + 1]
    // A missing value must refuse loudly — falling through to the default folder
    // would answer from a different vault than the one the flag named.
    if (!value || value.startsWith('-')) {
      throw new VaultReadError('--vault needs a folder path right after it.')
    }
    return value
  }
  if (env.LONGBOOK_VAULT_PATH) return env.LONGBOOK_VAULT_PATH
  return defaultVaultDir()
}

/**
 * Reads the vault fresh whenever the file changed — the app, another device, or the
 * owner's editor may have written it between two tool calls. mtime gates the re-parse.
 */
export class VaultReader {
  private cached: LoadedData | null = null
  private cachedStamp = ''

  constructor(readonly dir: string) {}

  get dataPath(): string {
    return join(this.dir, DATA_FILE)
  }

  load(): LoadedData {
    // Inode and size join mtime in the stamp: the app saves atomically by replacing
    // the file, and two replacements can land inside one timestamp tick.
    let stamp: string
    try {
      const s = statSync(this.dataPath)
      stamp = `${s.ino}:${s.size}:${s.mtimeMs}`
    } catch {
      throw new VaultReadError(
        `No financial memory at ${this.dataPath} — point --vault (or LONGBOOK_VAULT_PATH) at your longbook folder.`,
      )
    }
    if (this.cached && stamp === this.cachedStamp) return this.cached
    const data = parseVault(readFileSync(this.dataPath, 'utf8'))
    this.cached = data
    this.cachedStamp = stamp
    return data
  }

  /**
   * The contract files that travel with every vault, served as MCP resources — the
   * vault's copy or this server's bundled one, whichever names the newer revision, so an
   * older vault never teaches an older curriculum.
   */
  readContractFile(name: ContractFile): string {
    let inVault: string | null
    try {
      inVault = readFileSync(join(this.dir, name), 'utf8')
    } catch {
      inVault = null
    }
    return newerContract(inVault, BUNDLED[name])
  }
}
