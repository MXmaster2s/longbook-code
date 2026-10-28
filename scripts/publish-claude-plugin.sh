#!/bin/zsh
# Offers apps/claude-plugin to the public plugin repo as a release-<version> branch and pull
# request; merging publishes. The directory re-scans main on every push, so a changed plugin
# needs a new version (patch in release.json). Run: npm run plugin:claude:publish
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"
npm run -s plugin:claude:check
REPO="MXmaster2s/longbook-claude-plugin"
MANIFEST="plugins/longbook/.claude-plugin/plugin.json"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
gh repo clone "$REPO" "$WORK" -- --quiet
VERSION="$(node -p "require('./apps/claude-plugin/$MANIFEST').version")"
LIVE="$(node -p "try { require('$WORK/$MANIFEST').version } catch { '' }")"
BRANCH="release-$VERSION"
NAME="$(git config user.name)"
EMAIL="$(git config user.email)"
cd "$WORK"
git switch -q -c "$BRANCH"
find "$WORK" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$ROOT/apps/claude-plugin/." "$WORK/"
git add -A
if git diff --cached --quiet; then
  echo "marketplace already at $VERSION — nothing to publish."
  exit 0
fi
if [[ "$VERSION" == "$LIVE" ]]; then
  echo "the plugin changed but its version is still $VERSION: raise patch in release.json first." >&2
  exit 1
fi
git -c user.name="$NAME" -c user.email="$EMAIL" commit -q -m "longbook plugin $VERSION"
git push -q -u origin "$BRANCH"
gh pr create --repo "$REPO" --base main --head "$BRANCH" --title "longbook plugin $VERSION" \
  --body "The longbook plugin at $VERSION (was ${LIVE:-none}), generated from longbook-code. Merging publishes it to the Claude plugin directory."
