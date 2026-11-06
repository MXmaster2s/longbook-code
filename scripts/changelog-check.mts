#!/usr/bin/env -S npx tsx
// The newest entry of apps/longbook/Resources/changelog.json must name the version and build
// the project builds, or Check for updates would describe another release. Run: npm run changelog:check.
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { changelogProblems, newestRelease } from './changelog.mts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const project = readFileSync(join(ROOT, 'apps/longbook/project.yml'), 'utf8')
const changelog = readFileSync(join(ROOT, 'apps/longbook/Resources/changelog.json'), 'utf8')
const newest = newestRelease(changelog)
const problems = changelogProblems(project, changelog)

if (problems.length) {
  console.error(`changelog — ${problems.length} problem(s):`)
  for (const p of problems) console.error(`  ${p}`)
  process.exit(1)
}
console.log(`changelog — ${newest.version} (${newest.build}), ${newest.changes.length} changes, matches project.yml.`)
