#!/bin/zsh
# Deploys the hosted functions this round changed, from the files on disk: the MCP door,
# then the statement reader, then the reorganiser (it carries the door's engine). The access token is read from the keychain into the
# environment and never printed. Run: npm run deploy:servers
set -e
cd "$(dirname "$0")/.."
export SUPABASE_ACCESS_TOKEN="$(security find-generic-password -s 'Supabase Personal-Access Token' -w)"
npm run -s hosted:deploy
npm run -s hosted:verify
npm run -s function:deploy -- statement-extract
npm run -s function:deploy -- reorganise
