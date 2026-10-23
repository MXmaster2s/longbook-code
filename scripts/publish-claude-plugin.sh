#!/bin/zsh
# Publishes apps/claude-plugin to the public marketplace repository: clones it, replaces its
# files with the generated ones, commits and pushes. Run after the plugin check passes:
# npm run plugin:claude:publish
set -e
cd "$(dirname "$0")/.."
npm run -s plugin:claude:check
REPO="MXmaster2s/longbook-claude-plugin"
WORK="$(mktemp -d)"
gh repo clone "$REPO" "$WORK" -- --quiet
find "$WORK" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R apps/claude-plugin/. "$WORK/"
NAME="$(git config user.name)"
EMAIL="$(git config user.email)"
VERSION="$(node -p "require('./apps/claude-plugin/plugins/longbook/.claude-plugin/plugin.json').version")"
cd "$WORK"
git add -A
if git diff --cached --quiet; then
  echo "marketplace already at $VERSION — nothing to publish."
else
  git -c user.name="$NAME" -c user.email="$EMAIL" commit -q -m "longbook plugin $VERSION"
  git push -q origin HEAD
  echo "published longbook plugin $VERSION to https://github.com/$REPO"
fi
rm -rf "$WORK"
