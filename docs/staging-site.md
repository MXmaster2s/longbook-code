# The staging site

`staging.longbook.app` exists so the site can be looked at and argued with before anyone
outside sees it. It serves the same repository as production; only the audience differs.

## Why it is gated, not merely obscure

Every TLS certificate is published to public Certificate Transparency logs, so the hostname
becomes machine-discoverable within minutes of being created — bots scrape those logs
looking for staging sites. A secret URL is therefore not a control. Two things make it
private:

1. **Cloudflare Access** in front of the origin: nothing unauthenticated reaches Netlify.
2. **`guard-staging.ts`**, the backstop: on any host that is not `longbook.app`, every
   response carries `X-Robots-Tag: noindex, nofollow, noarchive, nosnippet` and
   `/robots.txt` answers `Disallow: /`. The guard reads the Host header first and steps
   aside on the live domain, so **production can never inherit a noindex** — the mistake
   that quietly costs a launch its search results.

## One-time setup

**1 · A Netlify site for staging.** Create a second site from the same repository (or
enable branch deploys on the existing one). Keep production's deploy untouched: the point
is that staging can move without the live site moving.

**2 · DNS at Cloudflare.** Add a `CNAME` for `staging` pointing at the Netlify target for
that site, and add `staging.longbook.app` as a custom domain in Netlify so it issues a
certificate.

**3 · Cloudflare Access.** Zero Trust → Access → Applications → Add a self-hosted
application for `staging.longbook.app`, with a policy allowing the addresses that should
get in. Visitors receive a one-time PIN by email; no shared password exists to leak.

Verify all three at once:

```bash
curl -sI https://staging.longbook.app | head -5
```

Before Access is configured, expect `x-robots-tag: noindex…`. After, expect a redirect to
the Cloudflare Access login instead — that is the gate working.

## Deploying to it

Staging is deployed deliberately, never automatically, so what it shows is always something
someone chose to show. Production is deployed the same way and remains its own decision.
