#!/usr/bin/env node
// Blocks a reserved word from entering the tree. Exit 1 on any hit.
import { execSync } from 'node:child_process'

const word = Buffer.from('cmVuZXdseQ==', 'base64').toString()
let out = ''
try {
  out = execSync(`git grep -Il -i -e ${word} -- . ':!scripts/name-guard.mjs'`, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  }).trim()
} catch {
  // git grep exits 1 when nothing matches — that is the clean case.
}

if (out) {
  console.error(`name-guard — REFUSED. Reserved word present in:\n${out}`)
  process.exit(1)
}
console.log('name-guard: clean')
