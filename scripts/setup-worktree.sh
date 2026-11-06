#!/usr/bin/env bash
# Prepares a git worktree for work. Dependencies and the Xcode project are both
# uncommitted, so a worktree made with `git worktree add` starts out unable to build or
# run a single script. Run this once inside it. Safe to re-run.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Every worktree shares one git directory, and that directory lives in the main checkout.
# It is the one reliable way to find that checkout from inside a linked worktree.
common=$(git rev-parse --git-common-dir)
[[ $common = /* ]] || common="$PWD/$common"
main=$(cd "$(dirname "$common")" && pwd)

npm ci

# The agent rulebook is deliberately uncommitted, so a new worktree has none and any
# session started there runs without it. Anyone who has no copy to take is skipped.
if [[ -f $main/CLAUDE.md && ! -e CLAUDE.md ]]; then
  cp "$main/CLAUDE.md" CLAUDE.md
  echo "setup-worktree: took CLAUDE.md from the main checkout"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "setup-worktree: xcodegen is missing — 'brew install xcodegen'" >&2
  exit 1
fi

(cd apps/longbook && xcodegen generate)

echo "setup-worktree: ready"
