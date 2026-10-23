# Releasing longbook

longbook lives in several places at once. This page names each one, the number it carries, and
the order a change reaches them. `npm run versions` prints the same table for the repo;
`npm run versions:live` also asks every live place.

## The numbers

**The rulebook revision** (now 40). The rulebook is longbook's `llms.txt` and the files beside it
(`library.json`, the schema, `prompts.json`): what every AI is taught about a longbook folder.
It lives in `scripts/gen-vault-contract.mts` as `CONTRACT_REVISION`. Every place below states
which revision it follows.

**The release number** (now 1.40.2): `1.<rulebook revision>.<patch>`, with the patch in
`release.json`. Everything built from the same code carries it together, so none can fall behind:

- the npm package `@longbook/mcp`
- its MCP registry entry `app.longbook/mcp`
- the longbook plugin for Claude
- the version both MCP servers report to an AI

Raise the patch for a fix that leaves the rulebook alone. A new rulebook revision starts the
patch at 0 again. Then run `npm run release` and `npm run plugin:claude`.

**The app's own number** (1.3.6, build 31), in `apps/longbook/project.yml`, because Apple
requires one. Help & about shows it with the rulebook it follows and the commit it was built
from. One build number is one exact app: `npm run device:install` refuses a number already on
the iPhone or the Mac, and `apps/longbook/device-builds.json` records the commit each number was
made from. `npm run versions` fails if the app changes after a number was installed and the
number was not raised.

## The places

| Place | What it is | How it is updated |
|---|---|---|
| The app on the owner's iPhone and Mac | The product, with its own copy of the rulebook and of the local MCP server | `npm run device:install` |
| The hosted MCP server, `longbook.app/mcp` | The connector every AI signs in to; reads the hosted copy, writes as proposals | `npm run deploy:servers` |
| The website, `longbook.app` | Pages, `llms.txt`, `prompts.json`, and the `/mcp` page | `npm run site:deploy` |
| npm, `@longbook/mcp` | The local MCP server for anyone without the Mac app: `npx -y @longbook/mcp@latest` | `npm run npm:publish` |
| The MCP registry, `app.longbook/mcp` | The public listing of both: the hosted address and the npm package | `npm run registry:publish` |
| The longbook plugin for Claude | Commands and skills for Claude Code and Cowork; points at the hosted server | `npm run plugin:claude:publish` |
| TestFlight, later the App Store | The app for everyone else | `npm run release:ios`, `npm run release:mas` |

## The order

1. **The app on the owner's iPhone and Mac.** He checks it there before anything else goes out.
   If the change needs something new from the hosted server, deploy the server at this step
   too, and say so.
2. **The hosted MCP server.**
3. **The website.**
4. **npm**, then **the MCP registry** (the registry only lists versions npm already has).
5. **The plugin for Claude.**
6. **TestFlight**, on the owner's word. After launch this step is App Review and release.

Then `npm run versions:live`: every row should match.

## The rule for rulebook changes

A new revision may add — a tool, a field, a chapter, a prompt — but never remove or rename
what an older app or AI relies on, because the hosted server is updated before every app is.
A change that has to break something needs a new major version, decided on purpose.
