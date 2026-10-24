#!/usr/bin/env node
// Usage-count names in the app must be fixed snake_case words written in the code. Exit 1 on any
// other name. --coverage lists controls and popups that send nothing; --strict fails on any.
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'

const ROOT = join(import.meta.dirname, '..')
const SOURCES = join(ROOT, 'apps/longbook/Sources')
const NAME = /^[a-z][a-z0-9_]{1,40}$/
const COVERAGE = process.argv.includes('--coverage')
const STRICT = process.argv.includes('--strict')

const swiftFiles = (dir) =>
  readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry)
    if (statSync(path).isDirectory()) return swiftFiles(path)
    return entry.endsWith('.swift') ? [path] : []
  })

const problems = []
const rows = []
for (const path of swiftFiles(SOURCES)) {
  const text = readFileSync(path, 'utf8')
  const file = relative(SOURCES, path)
  // The helpers themselves pass a name along; every other file must give a literal.
  if (file === 'Measure.swift') continue
  for (const m of text.matchAll(/(?:Measure\.(?:used|toggled)|\.measured)\(\s*([^,)\s]*)|measure:\s*("[^"]*")/g)) {
    const given = m[1] ?? m[2]
    const literal = /^"([^"\\]*)"$/.exec(given)
    // A name handed on is fine when it is declared StaticString: the compiler admits only literals.
    if (!literal && new RegExp(`\\b${given}: StaticString\\b`).test(text)) continue
    if (!literal) problems.push(`${file}: a name that is not a plain literal: ${given}`)
    else if (!NAME.test(literal[1])) problems.push(`${file}: "${literal[1]}" is not ${NAME}`)
  }
  if (!COVERAGE) continue
  // A control counts when its own action, before the next control, calls Measure; a popup when
  // the line above it is a .measured modifier. Declarations of helpers are not controls.
  const controls = [...text.matchAll(/(?<![A-Za-z0-9_.])(?:Button\s*[({]|Toggle\s*\()/g)]
    .filter((m) => !/(?:func|struct|var)\s*$/.test(text.slice(Math.max(0, m.index - 40), m.index)))
  const missed = controls.filter((m, i) => {
    const end = Math.min(controls[i + 1]?.index ?? text.length, m.index + 400)
    return !/Measure\.used\(|\.measured\(/.test(text.slice(m.index, end))
  })
  const lines = text.split('\n')
  const popups = lines.filter((line, i) => /^\s*(?:content)?\.(?:sheet|fullScreenCover|popover|alert|confirmationDialog)\(/.test(line)
    && !/\.measured\("/.test(lines[i - 1] ?? ''))
  const lineOf = (index) => text.slice(0, index).split('\n').length
  const left = [...missed.map((m) => `control at line ${lineOf(m.index)}`), ...popups.map((line) => `popup: ${line.trim().slice(0, 60)}`)]
  if (left.length) rows.push({ file, left })
}

if (problems.length) {
  console.error(`telemetry-names — REFUSED:\n${problems.join('\n')}`)
  process.exit(1)
}
console.log('telemetry-names: every name is a fixed snake_case word')
if (COVERAGE) {
  for (const r of rows) for (const what of r.left) console.log(`unmeasured  ${r.file}: ${what}`)
  const total = rows.reduce((n, r) => n + r.left.length, 0)
  console.log(`telemetry-coverage: ${total} controls and popups send nothing, in ${rows.length} files`)
  if (STRICT && total) process.exit(1)
}
