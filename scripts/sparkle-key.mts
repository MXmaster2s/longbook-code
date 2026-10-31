// The public half of Sparkle's Ed25519 key, from the private seed generate_keys stores.
import { createPrivateKey, createPublicKey } from 'node:crypto'

const PKCS8_ED25519 = Buffer.from('302e020100300506032b657004220420', 'hex')
const SPKI_PREFIX_LENGTH = 12

/** The base64 public key for a base64 seed, or null when the input is not a 32-byte seed. */
export const sparklePublicKey = (seed: string): string | null => {
  const bytes = Buffer.from(seed.trim(), 'base64')
  if (bytes.length !== 32) return null
  const key = createPrivateKey({ key: Buffer.concat([PKCS8_ED25519, bytes]), format: 'der', type: 'pkcs8' })
  return createPublicKey(key).export({ format: 'der', type: 'spki' }).subarray(SPKI_PREFIX_LENGTH).toString('base64')
}
