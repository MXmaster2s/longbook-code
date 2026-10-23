// What the two server bundles share: the workspace packages as esbuild aliases, so a
// bundle takes the core beside it, and the revision read that says when it did not.
import { join } from 'node:path'

/**
 * The workspace packages by name, each at its own source under root. Without this a
 * worktree whose node_modules links to another checkout bundles that checkout's core.
 */
export function workspaceAliases(root: string): Record<string, string> {
  return {
    '@longbook/core': join(root, 'packages/core/src/index.ts'),
    '@longbook/cards': join(root, 'packages/cards/src/index.ts'),
  }
}

/**
 * Every contract revision an artifact carries, with esbuild's line continuations and the
 * chunked constants' joins removed first so no marker is read across a break.
 */
export function contractRevisions(text: string): number[] {
  const joined = text.replace(/\\\n/g, '').replace(/" \+\n {2}"/g, '')
  const found = new Set<number>()
  for (const m of joined.matchAll(/contract revision (\d+)|\\?"contract_revision\\?":\s*(\d+)/g)) {
    found.add(Number(m[1] ?? m[2]))
  }
  return [...found].sort((a, b) => a - b)
}

/** Null when the artifact carries exactly the expected revision; otherwise what it carries. */
export function revisionDrift(text: string, expected: number): string | null {
  const carried = contractRevisions(text)
  if (carried.length === 1 && carried[0] === expected) return null
  return `embeds contract revision ${carried.join(' and ') || 'none'}, packages/core is at ${expected}`
}
