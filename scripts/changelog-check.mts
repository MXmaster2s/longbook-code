#!/usr/bin/env -S npx tsx
// The newest entry of apps/longbook/Resources/changelog.json must name the version and build
// the project builds, or Check for updates would describe another release. Run: npm run changelog:check.
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { newestRelease } from './changelog.mts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const project = readFileSync(join(ROOT, 'apps/longbook/project.yml'), 'utf8')
const version = /MARKETING_VERSION: "([^"]+)"/.exec(project)?.[1]
const build = /CURRENT_PROJECT_VERSION: "(\d+)"/.exec(project)?.[1]
const newest = newestRelease(readFileSync(join(ROOT, 'apps/longbook/Resources/changelog.json'), 'utf8'))

const problems: string[] = []
if (newest.version !== version) problems.push(`changelog names ${newest.version}, project.yml builds ${version}`)
if (String(newest.build) !== build) problems.push(`changelog names build ${newest.build}, project.yml builds ${build}`)
if (!/^\d{4}-\d{2}-\d{2}$/.test(newest.date)) problems.push(`the newest entry's date "${newest.date}" is not a day`)
const long = newest.changes.filter((c) => c.length > 300)
if (long.length) problems.push(`${long.length} change(s) run past 300 characters`)
if (newest.changes.join(' ').length > 4000) problems.push('the notes run past TestFlight\'s 4000 characters')

if (problems.length) {
  console.error(`changelog — ${problems.length} problem(s):`)
  for (const p of problems) console.error(`  ${p}`)
  process.exit(1)
}
console.log(`changelog — ${newest.version} (${newest.build}), ${newest.changes.length} changes, matches project.yml.`)
