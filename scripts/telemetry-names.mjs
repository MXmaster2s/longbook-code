#!/usr/bin/env node
// Usage-count names in the app must be fixed snake_case words written in the code. Exit 1 on any
// other name. --coverage lists each file's controls and popups that send nothing; --strict fails on them.
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
  for (const m of text.matchAll(/(?:Measure\.(?:used|toggled)|\.measured)\(\s*([^,)\s]*)/g)) {
    const literal = /^"([^"\\]*)"$/.exec(m[1])
    if (!literal) problems.push(`${file}: a name that is not a plain literal: ${m[1]}`)
    else if (!NAME.test(literal[1])) problems.push(`${file}: "${literal[1]}" is not ${NAME}`)
  }
  if (!COVERAGE) continue
  const controls = [...text.matchAll(/(?<![A-Za-z0-9_.])(?:Button\s*[({]|Toggle\s*\()/g)].length
  const measuredControls = [...text.matchAll(/Measure\.used\(|\.measured\("[^"]*"\)/g)].length
  const popups = [...text.matchAll(/\.(?:sheet|fullScreenCover|popover|alert|confirmationDialog)\(/g)].length
  const measuredPopups = [...text.matchAll(/\.measured\("[^"]*", \./g)].length
  const left = Math.max(0, controls - measuredControls) + Math.max(0, popups - measuredPopups)
  if (left) rows.push({ file, controls, measuredControls, popups, measuredPopups, left })
}

if (problems.length) {
  console.error(`telemetry-names — REFUSED:\n${problems.join('\n')}`)
  process.exit(1)
}
console.log('telemetry-names: every name is a fixed snake_case word')
if (COVERAGE) {
  rows.sort((a, b) => b.left - a.left)
  for (const r of rows) {
    console.log(`${String(r.left).padStart(4)} unmeasured  ${r.file}  (controls ${r.measuredControls}/${r.controls}, popups ${r.measuredPopups}/${r.popups})`)
  }
  const total = rows.reduce((n, r) => n + r.left, 0)
  console.log(`telemetry-coverage: ${total} controls and popups send nothing, in ${rows.length} files`)
  if (STRICT && total) process.exit(1)
}
