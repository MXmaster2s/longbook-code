#!/usr/bin/env -S npx tsx
// The database's own invariants, asserted against the live project. Row-level security
// decides which ROW a caller may touch, never which column; and EXECUTE is granted by
// default. Both have to be checked rather than assumed.
// Run: npm run guard:rls (needs SUPABASE_ACCESS_TOKEN, like hosted:deploy).
import { readFileSync, existsSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const PROJECT_REF = 'xbrnijgctmovoqbbmgmb'

function token(): string {
  const env = process.env.SUPABASE_ACCESS_TOKEN
  if (env) return env.trim()
  const cli = join(homedir(), '.supabase/access-token')
  if (existsSync(cli)) return readFileSync(cli, 'utf8').trim()
  console.error('No Supabase access token. Set SUPABASE_ACCESS_TOKEN, or run: npx supabase login')
  process.exit(1)
}

async function ask(query: string): Promise<Record<string, unknown>[]> {
  const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  })
  if (!res.ok) {
    console.error(`query failed (${res.status}): ${await res.text()}`)
    process.exit(1)
  }
  return (await res.json()) as Record<string, unknown>[]
}

interface Check {
  what: string
  query: string
  /** Rows coming back are violations; each is printed. */
}

// Every function anon or authenticated may call, and why. Anything else is a mistake —
// this is the check that would have caught waitlist_rate_bump the day it shipped.
const CALLABLE = [
  'mcp_memory_for_key', // the hosted server redeems keys with the publishable key
  'mcp_propose_for_key',
  'mcp_propose_for_user', // authenticated only; anon gets nothing from it
  'mcp_memory_for_user', // authenticated only; the signed-in read door in one hop
  'mcp_rate_check',
  'mcp_count', // the hosted server's daily usage count; writes only for a live key or signed-in caller
  'mcp_count_detail', // the same, by door, surface and tool name
  'has_cloud', // the one Cloud rule; a signed-in caller is answered for its own account alone
]


/** Every column a signed-in client may touch, and how. A table absent here exposes no
 *  column at all, and a column added later fails until it is declared — the guard states
 *  what a client sees, rather than trusting that migrations meant what they said. */
const EXPOSED: { t: string; p: string; c: string[] }[] = [
  { t: 'access_keys', p: 'INSERT', c: ['created_at', 'expires_at', 'id', 'key_hash', 'last_used_at', 'name', 'revoked_at', 'scopes', 'user_id'] },
  { t: 'access_keys', p: 'SELECT', c: ['created_at', 'expires_at', 'id', 'last_used_at', 'name', 'revoked_at', 'scopes', 'user_id'] },
  { t: 'access_keys', p: 'UPDATE', c: ['name', 'revoked_at'] },
  { t: 'cloud_subscriptions', p: 'SELECT', c: ['auto_renew', 'expires_at', 'status', 'user_id'] },
  { t: 'entitlements', p: 'SELECT', c: ['major_version', 'polar_order_id', 'purchased_at', 'status', 'user_id'] },
  { t: 'hosted_memories', p: 'INSERT', c: ['memory', 'pushed_at', 'user_id', 'web_propose'] },
  { t: 'hosted_memories', p: 'SELECT', c: ['memory', 'pushed_at', 'user_id', 'web_propose'] },
  { t: 'hosted_memories', p: 'UPDATE', c: ['memory', 'pushed_at', 'user_id', 'web_propose'] },
  { t: 'mcp_pending_writes', p: 'SELECT', c: ['applied_at', 'client', 'created_at', 'failed_at', 'failure', 'id', 'idempotency_key', 'key_id', 'kind', 'origin', 'payload', 'source_ref', 'user_id'] },
  { t: 'mcp_pending_writes', p: 'UPDATE', c: ['applied_at', 'failed_at', 'failure'] },
  { t: 'profiles', p: 'SELECT', c: ['created_at', 'email', 'id', 'trial_started_at'] },
  { t: 'structures', p: 'INSERT', c: ['created_at', 'icon', 'kind', 'name', 'name_key', 'source', 'template', 'updated_at', 'user_id'] },
  { t: 'structures', p: 'SELECT', c: ['created_at', 'icon', 'kind', 'name', 'name_key', 'source', 'template', 'updated_at', 'user_id'] },
  { t: 'structures', p: 'UPDATE', c: ['created_at', 'icon', 'kind', 'name', 'name_key', 'source', 'template', 'updated_at', 'user_id'] },
]

const exposedSql = EXPOSED.map(
  (e) =>
    `(table_name='${e.t}' and privilege_type='${e.p}' and column_name in (${e.c
      .map((c) => `'${c}'`)
      .join(',')}))`,
).join('\n                 or ')

const CHECKS: Check[] = [
  {
    what: 'every table in public has row-level security enabled',
    query: `select c.relname as table_name from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname='public' and c.relkind='r' and not c.relrowsecurity`,
  },
  {
    what: 'no table in public lets anon write',
    query: `select table_name, privilege_type from information_schema.table_privileges
            where table_schema='public' and grantee='anon'
              and privilege_type in ('INSERT','UPDATE','DELETE')`,
  },
  {
    what: 'the tables the app only ever reads carry no write grant',
    query: `select table_name, grantee, privilege_type from information_schema.table_privileges
            where table_schema='public' and grantee in ('anon','authenticated')
              and table_name in ('entitlements','profiles','cloud_subscriptions')
              and privilege_type in ('INSERT','UPDATE','DELETE')`,
  },
  {
    what: 'entitlements, profiles and cloud_subscriptions have no write POLICY either',
    query: `select c.relname as table_name, p.polname as policy from pg_policy p
            join pg_class c on c.oid = p.polrelid
            where c.relname in ('entitlements','profiles','cloud_subscriptions') and p.polcmd <> 'r'`,
  },
  {
    what: 'the Cloud grant table is unreachable by any client role',
    query: `select table_name::text, grantee::text, privilege_type::text from information_schema.table_privileges
            where table_schema='public' and grantee in ('anon','authenticated')
              and table_name='cloud_grants'
            union all
            select c.relname::text, 'policy', p.polname::text from pg_policy p join pg_class c on c.oid = p.polrelid
            where c.relname='cloud_grants'`,
  },
  {
    // The hosted copy is pushed and refreshed only with longbook Cloud; reads and the revoke stay open.
    what: 'the hosted copy is pushed and refreshed only with Cloud',
    query: `select p.polname as policy, p.polcmd as command from pg_policy p
            join pg_class c on c.oid = p.polrelid
            where c.relname='hosted_memories' and p.polcmd in ('a','w')
              and coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') not like '%has_cloud%'`,
  },
  {
    // One rule, read in every place that gates on it: the two doors, the filing, the nightly expiry.
    what: 'the hosted doors, the proposal filing and the copy expiry read the Cloud rule',
    query: `select want.proname || ' does not read ' || want.rule as problem
            from (values ('mcp_memory_for_key', 'has_cloud'), ('mcp_memory_for_user', 'has_cloud'),
                         ('mcp_file_proposal', 'has_cloud'), ('expire_hosted_copies', 'cloud_until')) as want(proname, rule)
            left join pg_proc p on p.proname = want.proname
              and p.pronamespace = 'public'::regnamespace and p.prosrc like '%' || want.rule || '%'
            where p.oid is null`,
  },
  {
    what: 'the web orders table is unreachable by any client role',
    query: `select table_name::text, grantee::text, privilege_type::text from information_schema.table_privileges
            where table_schema='public' and grantee in ('anon','authenticated')
              and table_name='web_orders'
            union all
            select c.relname::text, 'policy', p.polname::text from pg_policy p join pg_class c on c.oid = p.polrelid
            where c.relname='web_orders'`,
  },
  {
    what: 'the share tables are unreachable by any client role',
    query: `select table_name, grantee, privilege_type from information_schema.table_privileges
            where table_schema='public' and grantee in ('anon','authenticated')
              and table_name in ('shared_reports','report_comments')`,
  },
  {
    what: 'the hosted server usage counts are unreachable by any client role',
    query: `select table_name::text, grantee::text, privilege_type::text from information_schema.table_privileges
            where table_schema='public' and grantee in ('anon','authenticated')
              and table_name in ('mcp_daily_counts','mcp_daily_surfaces','mcp_daily_tools')
            union all
            select c.relname::text, 'policy', p.polname::text from pg_policy p join pg_class c on c.oid = p.polrelid
            where c.relname in ('mcp_daily_counts','mcp_daily_surfaces','mcp_daily_tools')`,
  },
  {
    what: 'the sign-in code counter is unreachable by any client role',
    query: `select table_name::text, grantee::text, privilege_type::text from information_schema.table_privileges
            where table_schema='public' and grantee in ('anon','authenticated')
              and table_name='auth_email_sends'
            union all
            select c.relname::text, 'policy', p.polname::text from pg_policy p join pg_class c on c.oid = p.polrelid
            where c.relname='auth_email_sends'`,
  },
  {
    what: 'a key hash is never readable or updatable by a client — it IS the credential',
    // INSERT is the exception and the point: minting writes a hash the client can never
    // read back, so a stolen session cannot walk away with a permanent anonymous key.
    query: `select grantee, privilege_type from information_schema.column_privileges
            where table_schema='public' and table_name='access_keys' and column_name='key_hash'
              and grantee in ('anon','authenticated') and privilege_type in ('SELECT','UPDATE')`,
  },
  {
    what: 'a client may write only a key name and its revocation stamp',
    query: `select grantee, column_name from information_schema.column_privileges
            where table_schema='public' and table_name='access_keys'
              and grantee in ('anon','authenticated') and privilege_type='UPDATE'
              and column_name not in ('name','revoked_at')`,
  },
  {
    what: 'revocation stays one-way',
    query: `select 'missing trigger' as problem where not exists (
              select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
              where c.relname='access_keys' and not t.tgisinternal
                and t.tgname='access_keys_revocation_is_final')`,
  },
  {
    what: 'a client may stamp a proposal only with its outcome',
    query: `select grantee, column_name from information_schema.column_privileges
            where table_schema='public' and table_name='mcp_pending_writes'
              and grantee in ('anon','authenticated') and privilege_type='UPDATE'
              and column_name not in ('applied_at','failed_at','failure')`,
  },
  {
    what: 'proposals arrive only through the definer function, never a direct insert',
    query: `select 'insert policy exists' as problem from pg_policy p join pg_class c on c.oid=p.polrelid
            where c.relname='mcp_pending_writes' and p.polcmd='a'
            union all
            select 'insert grant exists' from information_schema.table_privileges
            where table_schema='public' and table_name='mcp_pending_writes'
              and grantee in ('anon','authenticated') and privilege_type='INSERT'`,
  },
  {
    what: 'every UPDATE policy pins the new row to the same owner as the old one',
    query: `select c.relname as table_name, p.polname as policy from pg_policy p
            join pg_class c on c.oid = p.polrelid join pg_namespace n on n.oid=c.relnamespace
            where n.nspname='public' and p.polcmd='w' and p.polwithcheck is null`,
  },
  {
    what: 'no function in public is callable by a client unless it is on the list',
    query: `select p.proname, pg_get_function_identity_arguments(p.oid) as args
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname='public'
              and (has_function_privilege('anon', p.oid, 'EXECUTE')
                or has_function_privilege('authenticated', p.oid, 'EXECUTE'))
              and p.proname not in (${CALLABLE.map((n) => `'${n}'`).join(', ')})`,
  },
  {
    what: 'a signed-in client touches only the declared columns, and anon touches none',
    query: `select grantee, table_name, privilege_type, column_name
            from information_schema.column_privileges
            where table_schema='public' and grantee in ('anon','authenticated')
              and privilege_type in ('SELECT','INSERT','UPDATE')
              and not (grantee='authenticated' and (${exposedSql}))`,
  },
  {
    what: 'no client role holds TRUNCATE, TRIGGER or REFERENCES anywhere',
    // TRUNCATE is the sharp one: it ignores row-level security, so the grant reads as
    // "may empty every user's rows". Unreachable through the API today, and still wrong.
    query: `select table_name, grantee, privilege_type from information_schema.table_privileges
            where table_schema='public' and grantee in ('anon','authenticated')
              and privilege_type in ('TRUNCATE','TRIGGER','REFERENCES')`,
  },
  {
    what: 'a client deletes only where the app deletes: its hosted copy, its filed proposal',
    query: `select table_name, grantee from information_schema.table_privileges
            where table_schema='public' and grantee in ('anon','authenticated')
              and privilege_type='DELETE'
              and not (grantee='authenticated' and table_name in ('hosted_memories','mcp_pending_writes'))`,
  },
  {
    // The privacy policy promises the ninety days; this is the job that keeps the promise.
    what: 'the nightly expiry of hosted copies and proposals is scheduled and active',
    query: `select 'expire-hosted-copies is missing or inactive' as problem
            where not exists (select 1 from cron.job where jobname='expire-hosted-copies' and active)`,
  },
  {
    // The privacy policy promises shares are deleted on expiry; this job keeps that promise.
    what: 'the nightly expiry of shared reports is scheduled and active',
    query: `select 'expire-shared-reports is missing or inactive' as problem
            where not exists (select 1 from cron.job where jobname='expire-shared-reports' and active)`,
  },
  {
    // The policy promises what a sign-in notice copied is removed; the tidy job keeps that promise,
    // and the other two send the notices at all.
    what: 'the account notice jobs are scheduled and active, and the last runs did not fail',
    query: `select j.jobname || ' is missing or inactive' as problem
            from (values ('account-notices-scan'), ('account-notices-send'), ('account-notices-tidy')) as want(jobname)
            left join cron.job j on j.jobname = want.jobname and j.active
            where j.jobid is null
            union all
            select d.jobid::text || ' last failed: ' || left(coalesce(d.return_message, ''), 120)
            from cron.job_run_details d
            join cron.job j on j.jobid = d.jobid and j.jobname like 'account-notices-%'
            where d.runid = (select max(d2.runid) from cron.job_run_details d2 where d2.jobid = d.jobid)
              and d.status = 'failed'`,
  },
]

let failures = 0
for (const check of CHECKS) {
  const rows = await ask(check.query)
  if (rows.length === 0) {
    console.log(`  ok   ${check.what}`)
    continue
  }
  failures += 1
  console.log(` FAIL  ${check.what}`)
  for (const row of rows) console.log(`         ${JSON.stringify(row)}`)
}

console.log(
  failures === 0
    ? `\nrls guard — clean (${CHECKS.length} invariants).`
    : `\nrls guard — ${failures} of ${CHECKS.length} invariants broken. Row-level security gates rows, not columns.`,
)
process.exit(failures === 0 ? 0 : 1)
